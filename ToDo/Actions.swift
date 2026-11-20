import CoreData
import SwiftUI
import UIKit

enum SettingsKey {
    static let userName = "userName"
    static let addToTop = "addToTop"
    static let starredToTop = "starredToTop"
    static let playSound = "playSound"
    static let confirmDelete = "confirmDelete"
    static let showDueToday = "showDueTodayInMyDay"
    static func showSmart(_ s: SmartList) -> String { "show.\(s.rawValue)" }
    static func smartTheme(_ s: SmartList) -> String { "theme.\(s.rawValue)" }
    static func smartSort(_ s: SmartList) -> String { "sort.\(s.rawValue)" }
    static func smartShowCompleted(_ s: SmartList) -> String { "showCompleted.\(s.rawValue)" }

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            addToTop: true,
            starredToTop: true,
            playSound: true,
            confirmDelete: true,
            showDueToday: false,
            showSmart(.important): true,
            showSmart(.planned): true,
            showSmart(.all): false,
            showSmart(.completed): false,
            showSmart(.myDay): true,
            showSmart(.tasks): true,
            smartShowCompleted(.myDay): true,
            smartShowCompleted(.tasks): true,
        ])
    }
}

/// Where a new task should go and what it starts with, based on the list it
/// was typed into.
struct TaskContext {
    var list: TaskList?
    var smart: SmartList?
}

@MainActor
enum Actions {
    static var ctx: NSManagedObjectContext { Persistence.shared.viewContext }

    // MARK: Tasks

    @discardableResult
    static func addTask(title: String, context: TaskContext, due: Date? = nil, reminder: Date? = nil,
                        recurrence: Recurrence? = nil, myDay: Bool = false) -> TodoTask? {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let task = TodoTask(context: ctx)
        Persistence.shared.assign(task, alongside: context.list)
        task.id = UUID()
        task.title = trimmed
        task.createdAt = Date()
        task.list = context.list
        task.order = newOrder(in: context.list)
        task.dueDate = due
        task.reminderDate = reminder
        task.recurrence = recurrence
        switch context.smart {
        case .myDay: task.myDayDate = Date()
        case .important: task.isImportant = true
        case .planned: if task.dueDate == nil { task.dueDate = Calendar.current.startOfDay(for: Date()) }
        default: break
        }
        if myDay { task.myDayDate = Date() }
        if recurrence != nil, task.dueDate == nil, task.reminderDate == nil {
            task.dueDate = Calendar.current.startOfDay(for: Date())
        }
        save()
        return task
    }

    static func newOrder(in list: TaskList?) -> Double {
        let req = NSFetchRequest<TodoTask>(entityName: "TodoTask")
        req.predicate = list.map { NSPredicate(format: "list == %@", $0) } ?? NSPredicate(format: "list == nil")
        let orders = ((try? ctx.fetch(req)) ?? []).map(\.order)
        if UserDefaults.standard.bool(forKey: SettingsKey.addToTop) {
            return (orders.min() ?? 0) - 1
        }
        return (orders.max() ?? 0) + 1
    }

    static func toggleComplete(_ task: TodoTask) {
        withAnimation(.easeInOut(duration: 0.25)) {
            task.isCompleted.toggle()
            task.completedAt = task.isCompleted ? Date() : nil
            if task.isCompleted {
                Feedback.completed()
                if let rec = task.recurrence { spawnNextOccurrence(of: task, recurrence: rec) }
            }
        }
        save()
    }

    /// Like To Do: completing a repeating task leaves it completed and creates
    /// the next one with its dates moved forward.
    private static func spawnNextOccurrence(of task: TodoTask, recurrence rec: Recurrence) {
        let next = TodoTask(context: ctx)
        Persistence.shared.assign(next, alongside: task.list ?? task)
        next.id = UUID()
        next.title = task.title
        next.note = task.note
        next.isImportant = task.isImportant
        next.list = task.list
        next.createdAt = Date()
        next.order = task.order
        next.recurrence = rec
        let cal = Calendar.current
        if let due = task.dueDate {
            var nextDue = rec.next(after: due)
            // Skip occurrences already in the past.
            while nextDue < cal.startOfDay(for: Date()) { nextDue = rec.next(after: nextDue) }
            next.dueDate = nextDue
            if let rem = task.reminderDate {
                let delta = nextDue.timeIntervalSince(due)
                next.reminderDate = rem.addingTimeInterval(delta)
            }
        } else if let rem = task.reminderDate {
            var nextRem = rec.next(after: rem)
            while nextRem < Date() { nextRem = rec.next(after: nextRem) }
            next.reminderDate = nextRem
        }
        for step in task.sortedSteps {
            let s = TaskStep(context: ctx)
            Persistence.shared.assign(s, alongside: next.list ?? task)
            s.id = UUID()
            s.title = step.title
            s.order = step.order
            s.createdAt = Date()
            s.task = next
        }
        task.recurrence = nil
    }

    static func toggleImportant(_ task: TodoTask) {
        withAnimation { task.isImportant.toggle() }
        save()
    }

    static func toggleMyDay(_ task: TodoTask) {
        withAnimation { task.myDayDate = task.isInMyDay ? nil : Date() }
        save()
    }

    static func delete(_ task: TodoTask) {
        withAnimation { ctx.delete(task) }
        save()
    }

    static func move(_ task: TodoTask, to list: TaskList?) {
        guard task.list != list else { return }
        let sourceStore = task.objectID.persistentStore
        let targetStore = list?.objectID.persistentStore ?? Persistence.shared.privateStore
        if sourceStore == targetStore {
            task.list = list
            task.order = newOrder(in: list)
        } else {
            // Objects can't move between iCloud stores, so copy and delete.
            let copy = TodoTask(context: ctx)
            Persistence.shared.assign(copy, alongside: list)
            for key in ["id", "title", "note", "isCompleted", "completedAt", "isImportant", "dueDate",
                        "reminderDate", "myDayDate", "repeatFrequency", "repeatInterval", "repeatWeekdays",
                        "createdAt", "msID"] {
                copy.setValue(task.value(forKey: key), forKey: key)
            }
            copy.list = list
            copy.order = newOrder(in: list)
            for step in task.sortedSteps {
                let s = TaskStep(context: ctx)
                Persistence.shared.assign(s, alongside: list)
                s.id = UUID(); s.title = step.title; s.isCompleted = step.isCompleted
                s.order = step.order; s.createdAt = step.createdAt; s.task = copy
            }
            ctx.delete(task)
        }
        save()
    }

    // MARK: Steps

    static func addStep(_ title: String, to task: TodoTask) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let step = TaskStep(context: ctx)
        Persistence.shared.assign(step, alongside: task)
        step.id = UUID()
        step.title = trimmed
        step.createdAt = Date()
        step.order = (task.sortedSteps.map(\.order).max() ?? 0) + 1
        step.task = task
        save()
    }

    static func toggleStep(_ step: TaskStep) {
        withAnimation { step.isCompleted.toggle() }
        if step.isCompleted { Feedback.tap() }
        save()
    }

    static func promote(_ step: TaskStep) {
        guard let task = step.task else { return }
        addTask(title: step.displayTitle, context: TaskContext(list: task.list))
        ctx.delete(step)
        save()
    }

    // MARK: Lists & groups

    static func newList(name: String) -> TaskList {
        let list = TaskList(context: ctx)
        Persistence.shared.assign(list, alongside: nil)
        list.id = UUID()
        list.name = name
        list.createdAt = Date()
        list.themeKey = Theme.blue.key
        list.sortKey = TaskSort.custom.rawValue
        list.showCompleted = true
        list.sortAscending = true
        list.order = (allLists().map(\.order).max() ?? 0) + 1
        save()
        return list
    }

    static func allLists() -> [TaskList] {
        let req = NSFetchRequest<TaskList>(entityName: "TaskList")
        return (try? ctx.fetch(req)) ?? []
    }

    static func allGroups() -> [ListGroup] {
        let req = NSFetchRequest<ListGroup>(entityName: "ListGroup")
        req.sortDescriptors = [NSSortDescriptor(key: "order", ascending: true)]
        return (try? ctx.fetch(req)) ?? []
    }

    static func newGroup(name: String) -> ListGroup {
        let g = ListGroup(context: ctx)
        Persistence.shared.assign(g, alongside: nil)
        g.id = UUID()
        g.name = name
        g.createdAt = Date()
        g.isExpanded = true
        g.order = (allGroups().map(\.order).max() ?? 0) + 1
        save()
        return g
    }

    static func delete(_ list: TaskList) {
        if Persistence.shared.isInSharedStore(list) {
            Persistence.shared.leaveShared(list)
        } else {
            ctx.delete(list)
        }
        save()
    }

    /// Recreates a list whose iCloud share got stuck: copies the list and all its
    /// tasks and steps into a fresh unshared list, then clears out the broken share.
    @discardableResult
    static func resetSharing(_ list: TaskList) -> TaskList? {
        guard let share = Persistence.shared.existingShare(for: list) else { return nil }
        let copy = TaskList(context: ctx)
        Persistence.shared.assign(copy, alongside: nil)
        for key in ["name", "emoji", "themeKey", "sortKey", "sortAscending", "showCompleted", "groupID",
                    "order", "createdAt", "msID"] {
            copy.setValue(list.value(forKey: key), forKey: key)
        }
        copy.id = UUID()
        for task in (list.tasks as? Set<TodoTask>) ?? [] {
            let t = TodoTask(context: ctx)
            Persistence.shared.assign(t, alongside: nil)
            for key in ["title", "note", "isCompleted", "completedAt", "isImportant", "dueDate", "reminderDate",
                        "myDayDate", "repeatFrequency", "repeatInterval", "repeatWeekdays", "createdAt", "order", "msID"] {
                t.setValue(task.value(forKey: key), forKey: key)
            }
            t.id = UUID()
            t.list = copy
            for step in task.sortedSteps {
                let s = TaskStep(context: ctx)
                Persistence.shared.assign(s, alongside: nil)
                s.id = UUID(); s.title = step.title; s.isCompleted = step.isCompleted
                s.order = step.order; s.createdAt = step.createdAt; s.task = t
            }
        }
        // Keep the old list out of the way locally until the purge removes it.
        list.msID = nil
        save()
        Persistence.shared.purgeShare(share, fallback: list.objectID)
        return copy
    }

    static func ungroupAndDelete(_ group: ListGroup) {
        for list in allLists() where list.groupID == group.id { list.groupID = nil }
        ctx.delete(group)
        save()
    }

    static func save() {
        Persistence.shared.save()
        Reminders.scheduleSoon()
    }
}

extension TaskStep {
    var displayTitle: String { title ?? "" }
}

// MARK: - Fetching tasks for a screen

enum TaskQuery {
    static func predicate(smart: SmartList?, list: TaskList?) -> NSPredicate {
        if let list { return NSPredicate(format: "list == %@", list) }
        let cal = Calendar.current
        let start = cal.startOfDay(for: Date())
        let end = cal.date(byAdding: .day, value: 1, to: start)!
        switch smart {
        case .myDay:
            if UserDefaults.standard.bool(forKey: SettingsKey.showDueToday) {
                return NSPredicate(format: "(myDayDate >= %@ AND myDayDate < %@) OR (dueDate >= %@ AND dueDate < %@)",
                                   start as NSDate, end as NSDate, start as NSDate, end as NSDate)
            }
            return NSPredicate(format: "myDayDate >= %@ AND myDayDate < %@", start as NSDate, end as NSDate)
        case .important: return NSPredicate(format: "isImportant == YES AND isCompleted == NO")
        case .planned: return NSPredicate(format: "(dueDate != nil OR reminderDate != nil) AND isCompleted == NO")
        case .all: return NSPredicate(format: "isCompleted == NO")
        case .completed: return NSPredicate(format: "isCompleted == YES")
        case .tasks, .none: return NSPredicate(format: "list == nil")
        }
    }

    static func count(smart: SmartList) -> Int {
        let req = NSFetchRequest<TodoTask>(entityName: "TodoTask")
        let base = predicate(smart: smart, list: nil)
        req.predicate = smart == .completed ? base :
            NSCompoundPredicate(andPredicateWithSubpredicates: [base, NSPredicate(format: "isCompleted == NO")])
        return (try? Persistence.shared.viewContext.count(for: req)) ?? 0
    }
}

// MARK: - Haptics and sound

@MainActor
enum Feedback {
    static func tap() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    static func completed() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        if UserDefaults.standard.bool(forKey: SettingsKey.playSound) { Sound.playComplete() }
    }
}
