import CloudKit
import CoreData
import SwiftUI
import UIKit

// MARK: - Theme picker

struct ThemePicker: View {
    let selected: Theme
    let onPick: (Theme) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Color").font(.headline)
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: 4), spacing: 14) {
                        ForEach(Theme.colorThemes) { t in swatch(t, circle: true) }
                    }
                    Text("Scene").font(.headline).padding(.top, 6)
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4), spacing: 12) {
                        ForEach(Theme.sceneThemes) { t in swatch(t, circle: false) }
                    }
                }
                .padding(20)
            }
            .navigationTitle("Theme")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func swatch(_ t: Theme, circle: Bool) -> some View {
        Button { onPick(t) } label: {
            ZStack {
                if circle {
                    Circle().fill(t.colors[0]).frame(width: 52, height: 52)
                } else {
                    t.background
                        .frame(height: 70)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                if t == selected {
                    Image(systemName: "checkmark")
                        .font(.headline.bold())
                        .foregroundStyle(.white)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(t.name)
    }
}

// MARK: - My Day suggestions (the lightbulb)

struct SuggestionsView: View {
    @Environment(\.dismiss) private var dismiss
    @FetchRequest(sortDescriptors: [NSSortDescriptor(key: "createdAt", ascending: false)],
                  predicate: NSPredicate(format: "isCompleted == NO"))
    private var open: FetchedResults<TodoTask>

    var body: some View {
        NavigationStack {
            List {
                section("Overdue", overdue)
                section("Due today", dueToday)
                section("Upcoming", upcoming)
                section("Earlier in My Day", earlier)
                section("Recently added", recent)
                if overdue.isEmpty && dueToday.isEmpty && upcoming.isEmpty && earlier.isEmpty && recent.isEmpty {
                    ContentUnavailableView("No suggestions", systemImage: "lightbulb",
                                           description: Text("Tasks with due dates and recent tasks show up here."))
                }
            }
            .navigationTitle("Suggestions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }

    private var candidates: [TodoTask] { open.filter { !$0.isInMyDay } }
    private var today: Date { Calendar.current.startOfDay(for: Date()) }

    private var overdue: [TodoTask] { candidates.filter { $0.isOverdue } }
    private var dueToday: [TodoTask] { candidates.filter { $0.dueDate.map(Calendar.current.isDateInToday) == true } }
    private var upcoming: [TodoTask] {
        let week = Calendar.current.date(byAdding: .day, value: 7, to: today)!
        return candidates.filter { d in
            guard let due = d.dueDate else { return false }
            return due >= Calendar.current.date(byAdding: .day, value: 1, to: today)! && due < week
        }.sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }
    }
    private var earlier: [TodoTask] {
        candidates.filter { t in t.myDayDate.map { $0 < today } == true && t.dueDate == nil }
    }
    private var recent: [TodoTask] {
        let cutoff = Date().addingTimeInterval(-3 * 86400)
        let shown = Set((overdue + dueToday + upcoming + earlier).map(\.objectID))
        return candidates.filter { ($0.createdAt ?? .distantPast) > cutoff && !shown.contains($0.objectID) }.prefix(15).map { $0 }
    }

    @ViewBuilder private func section(_ title: String, _ items: [TodoTask]) -> some View {
        if !items.isEmpty {
            Section(title) {
                ForEach(items) { task in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(task.displayTitle)
                            HStack(spacing: 6) {
                                Text(task.list.map { ListTitle($0.displayName).text } ?? "Tasks")
                                if let due = task.dueDate {
                                    Text("•")
                                    Label(DateLabel.day(due), systemImage: "calendar")
                                        .foregroundStyle(task.isOverdue ? .red : .secondary)
                                }
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button {
                            Actions.toggleMyDay(task)
                        } label: {
                            Image(systemName: "plus").font(.title3)
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Add to My Day")
                    }
                }
            }
        }
    }
}

// MARK: - Settings

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(SettingsKey.userName) private var userName = ""
    @AppStorage(SettingsKey.addToTop) private var addToTop = true
    @AppStorage(SettingsKey.starredToTop) private var starredToTop = true
    @AppStorage(SettingsKey.playSound) private var playSound = true
    @AppStorage(SettingsKey.confirmDelete) private var confirmDelete = true
    @AppStorage(SettingsKey.showDueToday) private var showDueToday = false
    @AppStorage(SettingsKey.showSmart(.important)) private var showImportant = true
    @AppStorage(SettingsKey.showSmart(.planned)) private var showPlanned = true
    @AppStorage(SettingsKey.showSmart(.all)) private var showAll = false
    @AppStorage(SettingsKey.showSmart(.completed)) private var showCompleted = false
    @State private var iCloudStatus = "Checking…"

    var body: some View {
        NavigationStack {
            Form {
                Section("Your name") {
                    TextField("Name", text: $userName)
                        .textContentType(.name)
                }
                Section("General") {
                    Toggle("Add new tasks on top", isOn: $addToTop)
                    Toggle("Move starred tasks to top", isOn: $starredToTop)
                    Toggle("Play completion sound", isOn: $playSound)
                    Toggle("Confirm before deleting", isOn: $confirmDelete)
                    Toggle("Show tasks due today in My Day", isOn: $showDueToday)
                }
                Section("Smart lists") {
                    Toggle("Important", isOn: $showImportant)
                    Toggle("Planned", isOn: $showPlanned)
                    Toggle("All", isOn: $showAll)
                    Toggle("Completed", isOn: $showCompleted)
                }
                Section {
                    NavigationLink {
                        MicrosoftImportView()
                    } label: {
                        Label("Import from Microsoft To Do", systemImage: "square.and.arrow.down")
                    }
                } footer: {
                    Text("Copies your lists, tasks, steps, notes, due dates, reminders and repeats from your Microsoft account.")
                }
                Section {
                    LabeledContent("iCloud sync", value: iCloudStatus)
                    NavigationLink("Sync status") { SyncStatusView() }
                } footer: {
                    Text("Tasks sync to your other devices signed in to the same iCloud account. Share a list from its person button.")
                }
                Section {
                    LabeledContent("Version", value: appVersion)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .task { await checkICloud() }
        }
    }

    private var appVersion: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "\(v) (\(b))"
    }

    private func checkICloud() async {
        do {
            let status = try await Persistence.shared.ckContainer.accountStatus()
            switch status {
            case .available: iCloudStatus = "On"
            case .noAccount: iCloudStatus = "Not signed in to iCloud"
            case .restricted: iCloudStatus = "Restricted"
            case .temporarilyUnavailable: iCloudStatus = "Temporarily unavailable"
            default: iCloudStatus = "Unknown"
            }
        } catch {
            iCloudStatus = "Unavailable"
        }
    }
}

// MARK: - Sharing (UICloudSharingController)

@MainActor
enum SharingPresenter {
    private static var delegate: SharingDelegate?

    static func present(share: CKShare, container: CKContainer, title: String) {
        let controller = UICloudSharingController(share: share, container: container)
        controller.availablePermissions = [.allowReadWrite, .allowPrivate]
        let d = SharingDelegate(title: title)
        delegate = d
        controller.delegate = d
        guard let top = topViewController() else { return }
        if let pop = controller.popoverPresentationController {
            pop.sourceView = top.view
            pop.sourceRect = CGRect(x: top.view.bounds.maxX - 60, y: 60, width: 1, height: 1)
        }
        top.present(controller, animated: true)
    }

    static func invite(list: TaskList) {
        let ck = Persistence.shared.ckContainer
        let title = list.displayName
        let provider = NSItemProvider()
        if let share = Persistence.shared.existingShare(for: list) {
            provider.registerCKShare(share, container: ck, allowedSharingOptions: .standard)
        } else {
            let id = list.objectID
            provider.registerCKShare(container: ck, allowedSharingOptions: .standard) {
                try await Persistence.shared.makeShare(listID: id)
            }
        }
        let config = UIActivityItemsConfiguration(itemProviders: [provider])
        config.metadataProvider = { key in
            key == .title ? title : nil
        }
        let controller = UIActivityViewController(activityItemsConfiguration: config)
        guard let top = topViewController() else { return }
        if let pop = controller.popoverPresentationController {
            pop.sourceView = top.view
            pop.sourceRect = CGRect(x: top.view.bounds.maxX - 60, y: 60, width: 1, height: 1)
        }
        top.present(controller, animated: true)
    }

    private static func topViewController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive } ??
            UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        var vc = scene?.windows.first { $0.isKeyWindow }?.rootViewController ?? scene?.windows.first?.rootViewController
        while let presented = vc?.presentedViewController { vc = presented }
        return vc
    }
}

final class SharingDelegate: NSObject, UICloudSharingControllerDelegate {
    let title: String
    init(title: String) { self.title = title }

    func itemTitle(for csc: UICloudSharingController) -> String? { title }

    func cloudSharingController(_ csc: UICloudSharingController, failedToSaveShareWithError error: Error) {}

    func cloudSharingControllerDidSaveShare(_ csc: UICloudSharingController) {
        if let share = csc.share { Persistence.shared.persistUpdatedShare(share) }
    }

    func cloudSharingControllerDidStopSharing(_ csc: UICloudSharingController) {
        // The list stays in your iCloud; only the share is removed.
    }
}
