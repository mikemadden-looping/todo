import CoreData
import SwiftUI

struct SidebarView: View {
    @Binding var selection: Destination?
    let open: (TodoTask) -> Void

    @FetchRequest(sortDescriptors: [NSSortDescriptor(key: "order", ascending: true)])
    private var lists: FetchedResults<TaskList>
    @FetchRequest(sortDescriptors: [NSSortDescriptor(key: "order", ascending: true)])
    private var groups: FetchedResults<ListGroup>
    @FetchRequest(sortDescriptors: [])
    private var allTasks: FetchedResults<TodoTask>

    @AppStorage(SettingsKey.userName) private var userName = ""
    @AppStorage(SettingsKey.showSmart(.important)) private var showImportant = true
    @AppStorage(SettingsKey.showSmart(.planned)) private var showPlanned = true
    @AppStorage(SettingsKey.showSmart(.all)) private var showAll = false
    @AppStorage(SettingsKey.showSmart(.completed)) private var showCompletedList = false
    @AppStorage(SettingsKey.showDueToday) private var showDueToday = false

    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var search = ""
    @State private var prompt: TextPrompt?
    @State private var showSettings = false
    @State private var listToDelete: TaskList?

    private var visibleSmartLists: [SmartList] {
        var s: [SmartList] = [.myDay]
        if showImportant { s.append(.important) }
        if showPlanned { s.append(.planned) }
        if showAll { s.append(.all) }
        if showCompletedList { s.append(.completed) }
        s.append(.tasks)
        return s
    }

    var body: some View {
        List(selection: $selection) {
            if search.isEmpty {
                profileRow
                Section {
                    ForEach(visibleSmartLists) { s in
                        NavigationLink(value: Destination.smart(s)) {
                            SidebarRow(icon: .symbol(s.systemImage, s.iconColor), title: s.title, count: count(for: s))
                        }
                    }
                }
                Section {
                    ForEach(topLevelItems, id: \.self) { item in
                        switch item {
                        case .list(let list): listRow(list)
                        case .group(let group): groupRow(group)
                        }
                    }
                    .onMove(perform: moveTopLevel)
                }
            } else {
                SearchResults(text: search, open: open)
            }
        }
        .sidebarStyle(compact: sizeClass == .compact)
        .navigationTitle("Lists")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .automatic), prompt: "Search")
        .safeAreaInset(edge: .bottom) { bottomBar }
        .textPrompt($prompt)
        .sheet(isPresented: $showSettings) { SettingsView() }
        .confirmationDialog(listToDelete.map { Persistence.shared.isInSharedStore($0) ? "Leave “\($0.displayName)”?" : "“\($0.displayName)” will be permanently deleted." } ?? "",
                            isPresented: Binding(get: { listToDelete != nil }, set: { if !$0 { listToDelete = nil } }),
                            titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                if let l = listToDelete {
                    if selection == .list(l.objectID) { selection = nil }
                    Actions.delete(l)
                }
                listToDelete = nil
            }
        }
    }

    // MARK: Rows

    private var profileRow: some View {
        Button { showSettings = true } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(Theme.blue.accent.gradient)
                    Text(initials).font(.subheadline.bold()).foregroundStyle(.white)
                }
                .frame(width: 40, height: 40)
                VStack(alignment: .leading, spacing: 1) {
                    Text(userName.isEmpty ? "Your name" : userName)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text("Settings").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "gearshape").foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }

    private var initials: String {
        let parts = userName.split(separator: " ").prefix(2).compactMap(\.first)
        return parts.isEmpty ? "☀︎" : String(parts).uppercased()
    }

    private func listRow(_ list: TaskList) -> some View {
        let t = ListTitle(list.displayName)
        let shared = Persistence.shared.isShared(list)
        return NavigationLink(value: Destination.list(list.objectID)) {
            SidebarRow(icon: t.emoji.map { .emoji($0) } ?? .symbol("list.bullet", list.theme.accent),
                       title: t.text, count: openCount(list), shared: shared)
        }
        .contextMenu {
            Button { rename(list) } label: { Label("Rename list", systemImage: "pencil") }
            if !groups.isEmpty {
                Menu {
                    Button { list.groupID = nil; Actions.save() } label: {
                        if list.groupID == nil { Label("No group", systemImage: "checkmark") } else { Text("No group") }
                    }
                    ForEach(groups) { g in
                        Button { list.groupID = g.id; Actions.save() } label: {
                            if list.groupID == g.id { Label(g.displayName, systemImage: "checkmark") } else { Text(g.displayName) }
                        }
                    }
                } label: { Label("Move to group", systemImage: "folder") }
            }
            Button(role: .destructive) { listToDelete = list } label: {
                Label(Persistence.shared.isInSharedStore(list) ? "Leave list" : "Delete list", systemImage: "trash")
            }
        }
    }

    @ViewBuilder private func groupRow(_ group: ListGroup) -> some View {
        let members = lists.filter { $0.groupID == group.id }
        DisclosureGroup(isExpanded: Binding(get: { group.isExpanded }, set: { group.isExpanded = $0; Actions.save() })) {
            ForEach(members) { listRow($0) }
                .onMove { from, to in
                    var arr = members
                    arr.move(fromOffsets: from, toOffset: to)
                    for (i, l) in arr.enumerated() { l.order = Double(i) }
                    Actions.save()
                }
            if members.isEmpty {
                Text("Long-press a list and choose Move to group")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } label: {
            Label {
                Text(group.displayName)
            } icon: {
                Image(systemName: "rectangle.stack").foregroundStyle(.secondary)
            }
            .contextMenu {
                Button {
                    prompt = TextPrompt(title: "Rename group", text: group.displayName, actionTitle: "Save") {
                        group.name = $0; Actions.save()
                    }
                } label: { Label("Rename group", systemImage: "pencil") }
                Button(role: .destructive) { Actions.ungroupAndDelete(group) } label: {
                    Label("Ungroup lists", systemImage: "rectangle.stack.badge.minus")
                }
            }
        }
    }

    private var bottomBar: some View {
        HStack {
            Button {
                prompt = TextPrompt(title: "New list", text: "", actionTitle: "Create list") { name in
                    let list = Actions.newList(name: name)
                    selection = .list(list.objectID)
                }
            } label: {
                Label("New list", systemImage: "plus")
                    .font(.body.weight(.medium))
            }
            Spacer()
            Button {
                prompt = TextPrompt(title: "New group", text: "", actionTitle: "Create group") { name in
                    _ = Actions.newGroup(name: name)
                }
            } label: {
                Image(systemName: "rectangle.stack.badge.plus")
            }
            .accessibilityLabel("New group")
        }
        .foregroundStyle(Theme.blue.accent)
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.bar)
    }

    // MARK: Data

    private enum Item: Hashable {
        case list(TaskList), group(ListGroup)
        var order: Double {
            switch self {
            case .list(let l): return l.order
            case .group(let g): return g.order
            }
        }
    }

    private var topLevelItems: [Item] {
        let groupIDs = Set(groups.compactMap(\.id))
        let loose = lists.filter { $0.groupID == nil || !groupIDs.contains($0.groupID!) }.map(Item.list)
        return (loose + groups.map(Item.group)).sorted { $0.order < $1.order }
    }

    private func openCount(_ list: TaskList) -> Int {
        allTasks.filter { $0.list == list && !$0.isCompleted }.count
    }

    private func count(for s: SmartList) -> Int {
        let cal = Calendar.current
        let open = allTasks.filter { !$0.isCompleted }
        switch s {
        case .myDay:
            return open.filter { $0.isInMyDay || (showDueToday && $0.dueDate.map(cal.isDateInToday) == true) }.count
        case .important: return open.filter(\.isImportant).count
        case .planned: return open.filter { $0.dueDate != nil || $0.reminderDate != nil }.count
        case .all: return open.count
        case .completed: return 0
        case .tasks: return open.filter { $0.list == nil }.count
        }
    }

    /// Drag to reorder the lists and groups shown at the top level.
    private func moveTopLevel(from: IndexSet, to: Int) {
        var items = topLevelItems
        items.move(fromOffsets: from, toOffset: to)
        for (i, item) in items.enumerated() {
            switch item {
            case .list(let l): l.order = Double(i)
            case .group(let g): g.order = Double(i)
            }
        }
        Actions.save()
    }

    private func rename(_ list: TaskList) {
        prompt = TextPrompt(title: "Rename list", text: list.displayName, actionTitle: "Save") {
            list.name = $0; Actions.save()
        }
    }
}

struct SidebarRow: View {
    enum Icon {
        case symbol(String, Color)
        case emoji(String)
    }

    let icon: Icon
    let title: String
    let count: Int
    var shared = false

    var body: some View {
        HStack(spacing: 12) {
            Group {
                switch icon {
                case let .symbol(name, color):
                    Image(systemName: name).foregroundStyle(color).font(.system(size: 18))
                case .emoji(let e):
                    Text(e).font(.system(size: 18))
                }
            }
            .frame(width: 26)
            Text(title).foregroundStyle(.primary)
            if shared {
                Image(systemName: "person.2").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if count > 0 {
                Text("\(count)").foregroundStyle(.secondary).font(.subheadline)
            }
        }
        .padding(.vertical, 2)
    }
}

/// Search across task titles, notes and steps.
struct SearchResults: View {
    let text: String
    let open: (TodoTask) -> Void
    @FetchRequest private var results: FetchedResults<TodoTask>

    init(text: String, open: @escaping (TodoTask) -> Void) {
        self.text = text
        self.open = open
        _results = FetchRequest(
            entity: NSEntityDescription.entity(forEntityName: "TodoTask", in: Persistence.shared.viewContext)!,
            sortDescriptors: [NSSortDescriptor(key: "isCompleted", ascending: true),
                              NSSortDescriptor(key: "createdAt", ascending: false)],
            predicate: NSPredicate(format: "title CONTAINS[cd] %@ OR note CONTAINS[cd] %@ OR ANY steps.title CONTAINS[cd] %@",
                                   text, text, text)
        )
    }

    var body: some View {
        if results.isEmpty {
            Text("No results for “\(text)”").foregroundStyle(.secondary)
        }
        ForEach(results) { task in
            Button { open(task) } label: {
                HStack(spacing: 12) {
                    Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(task.isCompleted ? (task.list?.theme.accent ?? Theme.blue.accent) : .secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(task.displayTitle)
                            .strikethrough(task.isCompleted)
                            .foregroundStyle(.primary)
                        Text(task.list.map { ListTitle($0.displayName).text } ?? "Tasks")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if task.isImportant { Image(systemName: "star.fill").foregroundStyle(.secondary) }
                }
            }
            .buttonStyle(.plain)
        }
    }
}

private extension View {
    /// Plain white list on iPhone like To Do; a real sidebar on iPad and Mac.
    @ViewBuilder func sidebarStyle(compact: Bool) -> some View {
        if compact { listStyle(.plain) } else { listStyle(.sidebar) }
    }
}
