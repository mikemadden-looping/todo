import CoreData
import SwiftUI

enum Destination: Hashable {
    case smart(SmartList)
    case list(NSManagedObjectID)
}

struct RootView: View {
    @State private var selection: Destination?
    @State private var path: [TaskRoute] = []
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.managedObjectContext) private var ctx

    var body: some View {
        NavigationSplitView {
            SidebarView(selection: $selection, open: open)
        } detail: {
            NavigationStack(path: $path) {
                detailRoot
                    .navigationDestination(for: TaskRoute.self) { route in
                        if let task = try? ctx.existingObject(with: route.id) as? TodoTask {
                            TaskDetailView(task: task)
                        }
                    }
            }
        }
        .onChange(of: selection) { _, _ in path = [] }
        .onAppear {
            if sizeClass == .regular, selection == nil { selection = .smart(.myDay) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .openTask)) { note in
            guard let id = note.object as? String, let uuid = UUID(uuidString: id) else { return }
            let req = NSFetchRequest<TodoTask>(entityName: "TodoTask")
            req.predicate = NSPredicate(format: "id == %@", uuid as CVarArg)
            if let task = try? ctx.fetch(req).first { open(task) }
        }
    }

    @ViewBuilder private var detailRoot: some View {
        switch selection {
        case .smart(let s):
            TaskListScreen(smart: s, list: nil).id(selection)
        case .list(let id):
            if let list = try? ctx.existingObject(with: id) as? TaskList, !list.isDeleted {
                TaskListScreen(smart: nil, list: list).id(selection)
            } else {
                placeholder
            }
        case .none:
            placeholder
        }
    }

    private var placeholder: some View {
        ZStack {
            Theme.blue.background.ignoresSafeArea()
            Image(systemName: "checkmark.circle")
                .font(.system(size: 60, weight: .light))
                .foregroundStyle(.white.opacity(0.7))
        }
    }

    /// Shows a task's list and then the task itself (used by search and reminders).
    func open(_ task: TodoTask) {
        let dest: Destination = task.list.map { .list($0.objectID) } ?? .smart(.tasks)
        if selection != dest {
            selection = dest
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { path = [TaskRoute(id: task.objectID)] }
        } else {
            path = [TaskRoute(id: task.objectID)]
        }
    }
}
