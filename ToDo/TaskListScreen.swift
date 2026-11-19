import CoreData
import SwiftUI

/// The screen for any list: a smart list (My Day, Important, Planned, …),
/// the built-in Tasks list, or one of your own lists.
struct TaskListScreen: View {
    let smart: SmartList?
    @ObservedObject var list: TaskList
    private let isCustomList: Bool

    @FetchRequest private var tasks: FetchedResults<TodoTask>
    @AppStorage(SettingsKey.starredToTop) private var starredToTop = true
    @AppStorage(SettingsKey.confirmDelete) private var confirmDelete = true
    @State private var themeVersion = 0
    @State private var prompt: TextPrompt?
    @State private var showThemes = false
    @State private var showSuggestions = false
    @State private var confirmDeleteList = false
    @State private var pendingDelete: TodoTask?
    @State private var sharingError: String?
    @Environment(\.dismiss) private var dismiss

    /// For smart lists, `list` is a throwaway placeholder that is never saved.
    init(smart: SmartList?, list: TaskList?) {
        self.smart = list == nil ? (smart ?? .tasks) : nil
        self.isCustomList = list != nil
        self.list = list ?? TaskList.placeholder
        _tasks = FetchRequest(
            entity: NSEntityDescription.entity(forEntityName: "TodoTask", in: Persistence.shared.viewContext)!,
            sortDescriptors: [NSSortDescriptor(key: "order", ascending: true)],
            predicate: TaskQuery.predicate(smart: list == nil ? (smart ?? .tasks) : nil, list: list),
            animation: .default
        )
    }

    // MARK: Settings stored on the list, or per smart list on this device

    private var title: String {
        isCustomList ? ListTitle(list.displayName).text : (smart?.title ?? "Tasks")
    }

    private var theme: Theme {
        _ = themeVersion
        if isCustomList { return list.theme }
        let s = smart ?? .tasks
        return UserDefaults.standard.string(forKey: SettingsKey.smartTheme(s)).map(Theme.named) ?? s.defaultTheme
    }

    private var sort: TaskSort {
        _ = themeVersion
        if isCustomList { return list.sort }
        let s = smart ?? .tasks
        return TaskSort(rawValue: UserDefaults.standard.string(forKey: SettingsKey.smartSort(s)) ?? "") ?? .custom
    }

    private var ascending: Bool {
        _ = themeVersion
        if isCustomList { return list.sortAscending }
        return !UserDefaults.standard.bool(forKey: SettingsKey.smartSort(smart ?? .tasks) + ".desc")
    }

    private var showCompleted: Bool {
        _ = themeVersion
        if isCustomList { return list.showCompleted }
        return UserDefaults.standard.bool(forKey: SettingsKey.smartShowCompleted(smart ?? .tasks))
    }

    private var supportsCompletedSection: Bool {
        isCustomList || smart == .myDay || smart == .tasks
    }

    private var canReorder: Bool {
        sort == .custom && (isCustomList || smart == .tasks)
    }

    private var isSharedList: Bool { isCustomList && Persistence.shared.isShared(list) }
    private var isParticipant: Bool { isCustomList && Persistence.shared.isInSharedStore(list) }

    // MARK: Sorted tasks

    private var openTasks: [TodoTask] {
        sort.sorted(tasks.filter { !$0.isCompleted }, ascending: ascending, importantFirst: starredToTop)
    }

    private var completedTasks: [TodoTask] {
        tasks.filter(\.isCompleted).sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }
    }

    // MARK: Body

    var body: some View {
        ZStack {
            theme.background.ignoresSafeArea()
            List {
                header
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 10, trailing: 16))

                if smart == .planned {
                    plannedSections
                } else if smart == .completed {
                    rows(completedTasks)
                } else {
                    rows(openTasks, movable: canReorder)
                    if supportsCompletedSection, !completedTasks.isEmpty {
                        completedHeader
                        if showCompleted { rows(completedTasks) }
                    }
                }

                if tasks.isEmpty { emptyState }

                Color.clear.frame(height: 20)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .environment(\.defaultMinListRowHeight, 0)
        }
        .safeAreaInset(edge: .bottom) {
            if smart != .completed {
                AddTaskBar(context: TaskContext(list: isCustomList ? list : nil, smart: smart), accent: theme.accent)
            }
        }
        .tint(.white)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .principal) { Text("") }
            ToolbarItemGroup(placement: .topBarTrailing) {
                if smart == .myDay {
                    Button { showSuggestions = true } label: { Image(systemName: "lightbulb") }
                        .accessibilityLabel("Suggestions")
                }
                if isCustomList, !isParticipant {
                    Button { startSharing() } label: {
                        Image(systemName: isSharedList ? "person.2.fill" : "person.crop.circle.badge.plus")
                    }
                    .accessibilityLabel("Share list")
                }
                optionsMenu
            }
        }
        .sheet(isPresented: $showThemes) {
            ThemePicker(selected: theme) { picked in
                if isCustomList { list.themeKey = picked.key; Actions.save() }
                else { UserDefaults.standard.set(picked.key, forKey: SettingsKey.smartTheme(smart ?? .tasks)) }
                themeVersion += 1
            }
        }
        .sheet(isPresented: $showSuggestions) { SuggestionsView() }
        .textPrompt($prompt)
        .confirmationDialog(isParticipant ? "Leave “\(title)”?" : "“\(title)” will be permanently deleted.",
                            isPresented: $confirmDeleteList, titleVisibility: .visible) {
            Button(isParticipant ? "Leave list" : "Delete list", role: .destructive) {
                dismiss()
                let l = list
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { Actions.delete(l) }
            }
        }
        .confirmationDialog("“\(pendingDelete?.displayTitle ?? "")” will be permanently deleted.",
                            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
                            titleVisibility: .visible) {
            Button("Delete task", role: .destructive) {
                if let t = pendingDelete { Actions.delete(t) }
                pendingDelete = nil
            }
        }
        .alert("Couldn't share", isPresented: Binding(get: { sharingError != nil }, set: { if !$0 { sharingError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(sharingError ?? "") }
    }

    // MARK: Pieces

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                if isCustomList, let emoji = ListTitle(list.displayName).emoji {
                    Text(emoji).font(.system(size: 30))
                }
                Text(title)
                    .font(.system(size: 32, weight: .bold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.15), radius: 2, y: 1)
                    .onTapGesture { if isCustomList { rename() } }
            }
            if smart == .myDay {
                Text(DateLabel.header(Date()))
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.9))
            }
            if isCustomList, let people = Persistence.shared.participantSummary(for: list) {
                Label(isParticipant ? "Shared with you" : "Shared with \(people)", systemImage: "person.2")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.9))
            }
        }
    }

    @ViewBuilder
    private func rows(_ items: [TodoTask], movable: Bool = false) -> some View {
        ForEach(items) { task in
            TaskRow(task: task, accent: theme.accent,
                    showListName: !isCustomList && smart != .tasks,
                    showMyDay: smart != .myDay)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 2, leading: 12, bottom: 2, trailing: 12))
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: confirmDelete ? nil : ButtonRole.destructive) {
                        if confirmDelete { pendingDelete = task } else { Actions.delete(task) }
                    } label: { Label("Delete", systemImage: "trash") }
                        .tint(.red)
                }
                .swipeActions(edge: .leading, allowsFullSwipe: true) {
                    Button { Actions.toggleMyDay(task) } label: {
                        Label(task.isInMyDay ? "Remove from My Day" : "Add to My Day",
                              systemImage: task.isInMyDay ? "sun.max.trianglebadge.exclamationmark" : "sun.max")
                    }
                    .tint(Theme.hex(0x3E69E4))
                }
        }
        .onMove(perform: movable ? { from, to in reorder(items, from: from, to: to) } : nil)
    }

    private func reorder(_ items: [TodoTask], from: IndexSet, to: Int) {
        var arr = items
        arr.move(fromOffsets: from, toOffset: to)
        for (i, t) in arr.enumerated() { t.order = Double(i) }
        Actions.save()
    }

    private var completedHeader: some View {
        Button {
            withAnimation {
                if isCustomList { list.showCompleted.toggle(); Actions.save() }
                else {
                    let key = SettingsKey.smartShowCompleted(smart ?? .tasks)
                    UserDefaults.standard.set(!UserDefaults.standard.bool(forKey: key), forKey: key)
                    themeVersion += 1
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: showCompleted ? "chevron.down" : "chevron.right")
                    .font(.caption.bold())
                Text("Completed")
                Text("\(completedTasks.count)").foregroundStyle(.white.opacity(0.8))
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Capsule().fill(Color.black.opacity(0.22)))
        }
        .buttonStyle(.borderless)
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 14, leading: 14, bottom: 6, trailing: 14))
    }

    @ViewBuilder private var plannedSections: some View {
        let buckets = PlannedBucket.group(openTasks)
        ForEach(buckets, id: \.bucket) { group in
            Text(group.bucket.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 14, leading: 16, bottom: 4, trailing: 16))
            rows(group.tasks)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: smart?.systemImage ?? "checklist")
                .font(.system(size: 44, weight: .light))
            Text(emptyText)
                .font(.subheadline)
                .multilineTextAlignment(.center)
        }
        .foregroundStyle(.white.opacity(0.9))
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    private var emptyText: String {
        switch smart {
        case .myDay: return "Focus on your day\nGet things done with My Day, a list that refreshes every day."
        case .important: return "Try starring some tasks to see them here."
        case .planned: return "Tasks with due dates or reminders show up here."
        case .completed: return "Completed tasks show up here."
        default: return "Tasks you add show up here."
        }
    }

    private var optionsMenu: some View {
        Menu {
            Menu {
                Picker("Sort by", selection: Binding(get: { sort }, set: setSort)) {
                    ForEach(TaskSort.allCases.filter { $0 != .myDay || smart != .myDay }) { s in
                        Label(s.label, systemImage: s.systemImage).tag(s)
                    }
                }
                if sort != .custom {
                    Divider()
                    Button { toggleDirection() } label: {
                        Label(ascending ? "Reverse order" : "Original order", systemImage: "arrow.up.arrow.down")
                    }
                }
            } label: { Label("Sort by", systemImage: "arrow.up.arrow.down") }

            Button { showThemes = true } label: { Label("Change theme", systemImage: "paintpalette") }

            if isCustomList {
                Button { rename() } label: { Label("Rename list", systemImage: "pencil") }
                if !isParticipant {
                    Button { startSharing() } label: {
                        Label(isSharedList ? "Manage sharing" : "Share list", systemImage: "person.crop.circle.badge.plus")
                    }
                }
            }
            if supportsCompletedSection {
                Button {
                    if isCustomList { list.showCompleted.toggle(); Actions.save() }
                    else {
                        let key = SettingsKey.smartShowCompleted(smart ?? .tasks)
                        UserDefaults.standard.set(!showCompleted, forKey: key)
                        themeVersion += 1
                    }
                } label: {
                    Label(showCompleted ? "Hide completed tasks" : "Show completed tasks",
                          systemImage: showCompleted ? "eye.slash" : "eye")
                }
            }
            if isCustomList {
                Divider()
                Button(role: .destructive) { confirmDeleteList = true } label: {
                    Label(isParticipant ? "Leave list" : "Delete list", systemImage: isParticipant ? "rectangle.portrait.and.arrow.right" : "trash")
                }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .accessibilityLabel("List options")
    }

    private func setSort(_ s: TaskSort) {
        if isCustomList { list.sortKey = s.rawValue; list.sortAscending = s != .importance && s != .creationDate; Actions.save() }
        else { UserDefaults.standard.set(s.rawValue, forKey: SettingsKey.smartSort(smart ?? .tasks)) }
        themeVersion += 1
    }

    private func toggleDirection() {
        if isCustomList { list.sortAscending.toggle(); Actions.save() }
        else {
            let key = SettingsKey.smartSort(smart ?? .tasks) + ".desc"
            UserDefaults.standard.set(!UserDefaults.standard.bool(forKey: key), forKey: key)
        }
        themeVersion += 1
    }

    private func rename() {
        prompt = TextPrompt(title: "Rename list", text: list.displayName, actionTitle: "Save") { name in
            list.name = name
            Actions.save()
        }
    }

    private func startSharing() {
        Task { @MainActor in
            do {
                let (share, container) = try await Persistence.shared.share(list)
                SharingPresenter.present(share: share, container: container, title: list.displayName)
            } catch {
                sharingError = "Make sure you're signed in to iCloud. (\(error.localizedDescription))"
            }
        }
    }
}

extension TaskList {
    /// Stand-in object for smart-list screens; inserted into no context.
    static let placeholder: TaskList = {
        let entity = ManagedModel.shared.entitiesByName["TaskList"]!
        return TaskList(entity: entity, insertInto: nil)
    }()
}

enum PlannedBucket: Int, CaseIterable, Comparable {
    case earlier, today, tomorrow, thisWeek, later

    static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }

    var title: String {
        switch self {
        case .earlier: return "Earlier"
        case .today: return "Today"
        case .tomorrow: return "Tomorrow"
        case .thisWeek: return "This week"
        case .later: return "Later"
        }
    }

    static func of(_ task: TodoTask) -> PlannedBucket {
        guard let date = task.dueDate ?? task.reminderDate else { return .later }
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let day = cal.startOfDay(for: date)
        let diff = cal.dateComponents([.day], from: today, to: day).day ?? 0
        switch diff {
        case ..<0: return .earlier
        case 0: return .today
        case 1: return .tomorrow
        case 2...7: return .thisWeek
        default: return .later
        }
    }

    struct Group {
        let bucket: PlannedBucket
        let tasks: [TodoTask]
    }

    static func group(_ tasks: [TodoTask]) -> [Group] {
        let dict = Dictionary(grouping: tasks, by: { of($0) })
        return dict.keys.sorted().map { key in
            Group(bucket: key, tasks: dict[key]!.sorted { ($0.dueDate ?? $0.reminderDate ?? .distantFuture) < ($1.dueDate ?? $1.reminderDate ?? .distantFuture) })
        }
    }
}
