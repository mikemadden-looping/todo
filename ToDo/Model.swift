import CoreData
import Foundation

// MARK: - Managed object classes
//
// The Core Data model is built in code (see `ManagedModel.shared`) so there is
// no .xcdatamodeld to keep in sync. Every attribute is optional or has a
// default and every relationship has an inverse, which CloudKit requires.

@objc(TaskList)
final class TaskList: NSManagedObject, Identifiable {
    @NSManaged var id: UUID?
    @NSManaged var name: String?
    @NSManaged var emoji: String?
    @NSManaged var themeKey: String?
    @NSManaged var sortKey: String?
    @NSManaged var sortAscending: Bool
    @NSManaged var showCompleted: Bool
    @NSManaged var groupID: UUID?
    @NSManaged var order: Double
    @NSManaged var createdAt: Date?
    @NSManaged var msID: String?
    @NSManaged var tasks: NSSet?

    var displayName: String { (name?.isEmpty == false ? name : nil) ?? "Untitled list" }
    var theme: Theme { Theme.named(themeKey) }
    var sort: TaskSort { TaskSort(rawValue: sortKey ?? "") ?? .custom }

    var openTaskCount: Int {
        (tasks as? Set<TodoTask>)?.filter { !$0.isCompleted }.count ?? 0
    }
}

@objc(TodoTask)
final class TodoTask: NSManagedObject, Identifiable {
    @NSManaged var id: UUID?
    @NSManaged var title: String?
    @NSManaged var note: String?
    @NSManaged var isCompleted: Bool
    @NSManaged var completedAt: Date?
    @NSManaged var isImportant: Bool
    @NSManaged var dueDate: Date?
    @NSManaged var reminderDate: Date?
    @NSManaged var myDayDate: Date?
    @NSManaged var repeatFrequency: String?
    @NSManaged var repeatInterval: Int16
    @NSManaged var repeatWeekdays: String?
    @NSManaged var createdAt: Date?
    @NSManaged var order: Double
    @NSManaged var msID: String?
    @NSManaged var list: TaskList?
    @NSManaged var steps: NSSet?

    var displayTitle: String { title ?? "" }

    var isInMyDay: Bool {
        guard let d = myDayDate else { return false }
        return Calendar.current.isDateInToday(d)
    }

    var sortedSteps: [TaskStep] {
        ((steps as? Set<TaskStep>) ?? []).sorted {
            $0.order == $1.order ? ($0.createdAt ?? .distantPast) < ($1.createdAt ?? .distantPast) : $0.order < $1.order
        }
    }

    var recurrence: Recurrence? {
        get {
            guard let f = repeatFrequency, let freq = Recurrence.Frequency(rawValue: f) else { return nil }
            let days = (repeatWeekdays ?? "").split(separator: ",").compactMap { Int($0) }
            return Recurrence(frequency: freq, interval: max(1, Int(repeatInterval)), weekdays: Set(days))
        }
        set {
            repeatFrequency = newValue?.frequency.rawValue
            repeatInterval = Int16(newValue?.interval ?? 1)
            if let days = newValue?.weekdays, !days.isEmpty {
                repeatWeekdays = days.sorted().map(String.init).joined(separator: ",")
            } else {
                repeatWeekdays = nil
            }
        }
    }

    var isOverdue: Bool {
        guard let due = dueDate, !isCompleted else { return false }
        return due < Calendar.current.startOfDay(for: Date())
    }
}

@objc(TaskStep)
final class TaskStep: NSManagedObject, Identifiable {
    @NSManaged var id: UUID?
    @NSManaged var title: String?
    @NSManaged var isCompleted: Bool
    @NSManaged var order: Double
    @NSManaged var createdAt: Date?
    @NSManaged var task: TodoTask?
}

@objc(ListGroup)
final class ListGroup: NSManagedObject, Identifiable {
    @NSManaged var id: UUID?
    @NSManaged var name: String?
    @NSManaged var order: Double
    @NSManaged var isExpanded: Bool
    @NSManaged var createdAt: Date?

    var displayName: String { (name?.isEmpty == false ? name : nil) ?? "Untitled group" }
}

// MARK: - Sorting

enum TaskSort: String, CaseIterable, Identifiable {
    case custom, importance, dueDate, myDay, alphabetical, creationDate
    var id: String { rawValue }

    var label: String {
        switch self {
        case .custom: return "Custom order"
        case .importance: return "Importance"
        case .dueDate: return "Due date"
        case .myDay: return "Added to My Day"
        case .alphabetical: return "Alphabetically"
        case .creationDate: return "Creation date"
        }
    }

    var systemImage: String {
        switch self {
        case .custom: return "line.3.horizontal"
        case .importance: return "star"
        case .dueDate: return "calendar"
        case .myDay: return "sun.max"
        case .alphabetical: return "arrow.up.arrow.down"
        case .creationDate: return "calendar.badge.plus"
        }
    }

    func sorted(_ tasks: [TodoTask], ascending: Bool, importantFirst: Bool) -> [TodoTask] {
        let base: [TodoTask]
        switch self {
        case .custom:
            base = tasks.sorted { $0.order == $1.order ? ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) : $0.order < $1.order }
        case .importance:
            base = tasks.sorted { a, b in
                a.isImportant != b.isImportant ? (ascending ? !a.isImportant : a.isImportant) : a.order < b.order
            }
        case .dueDate:
            base = tasks.sorted { a, b in
                switch (a.dueDate, b.dueDate) {
                case let (x?, y?): return ascending ? x < y : x > y
                case (_?, nil): return true
                case (nil, _?): return false
                default: return a.order < b.order
                }
            }
        case .myDay:
            base = tasks.sorted { a, b in
                a.isInMyDay != b.isInMyDay ? (ascending ? a.isInMyDay : !a.isInMyDay) : a.order < b.order
            }
        case .alphabetical:
            base = tasks.sorted {
                let r = $0.displayTitle.localizedStandardCompare($1.displayTitle) == .orderedAscending
                return ascending ? r : !r
            }
        case .creationDate:
            base = tasks.sorted {
                let x = $0.createdAt ?? .distantPast, y = $1.createdAt ?? .distantPast
                return ascending ? x < y : x > y
            }
        }
        guard importantFirst, self != .importance else { return base }
        return base.filter(\.isImportant) + base.filter { !$0.isImportant }
    }
}

// MARK: - Recurrence

struct Recurrence: Equatable {
    enum Frequency: String, CaseIterable, Identifiable {
        case daily, weekdays, weekly, monthly, yearly
        var id: String { rawValue }
        var unit: String {
            switch self {
            case .daily, .weekdays: return "day"
            case .weekly: return "week"
            case .monthly: return "month"
            case .yearly: return "year"
            }
        }
    }

    var frequency: Frequency
    var interval: Int = 1
    /// Calendar weekday numbers (1 = Sunday … 7 = Saturday), used with `.weekly`.
    var weekdays: Set<Int> = []

    var label: String {
        if frequency == .weekdays { return "Weekdays" }
        if interval == 1 && (frequency != .weekly || weekdays.count <= 1) {
            switch frequency {
            case .daily: return "Daily"
            case .weekly: return "Weekly"
            case .monthly: return "Monthly"
            case .yearly: return "Yearly"
            case .weekdays: return "Weekdays"
            }
        }
        var s = interval == 1 ? "Every \(frequency.unit)" : "Every \(interval) \(frequency.unit)s"
        if frequency == .weekly, !weekdays.isEmpty {
            let symbols = Calendar.current.shortWeekdaySymbols
            s += " on " + weekdays.sorted().map { symbols[$0 - 1] }.joined(separator: ", ")
        }
        return s
    }

    /// The next occurrence strictly after `date`.
    func next(after date: Date, calendar cal: Calendar = .current) -> Date {
        switch frequency {
        case .daily:
            return cal.date(byAdding: .day, value: interval, to: date) ?? date
        case .weekdays:
            var d = cal.date(byAdding: .day, value: 1, to: date) ?? date
            while cal.isDateInWeekend(d) { d = cal.date(byAdding: .day, value: 1, to: d) ?? d }
            return d
        case .weekly:
            guard !weekdays.isEmpty else {
                return cal.date(byAdding: .weekOfYear, value: interval, to: date) ?? date
            }
            var d = date
            for _ in 0..<7 {
                d = cal.date(byAdding: .day, value: 1, to: d) ?? d
                let wd = cal.component(.weekday, from: d)
                if wd == cal.firstWeekday, interval > 1 {
                    d = cal.date(byAdding: .weekOfYear, value: interval - 1, to: d) ?? d
                }
                if weekdays.contains(cal.component(.weekday, from: d)) { return d }
            }
            return cal.date(byAdding: .weekOfYear, value: interval, to: date) ?? date
        case .monthly:
            return cal.date(byAdding: .month, value: interval, to: date) ?? date
        case .yearly:
            return cal.date(byAdding: .year, value: interval, to: date) ?? date
        }
    }
}

// MARK: - Model description

enum ManagedModel {
    static let shared: NSManagedObjectModel = build()

    private static func attr(_ name: String, _ type: NSAttributeType, default value: Any? = nil) -> NSAttributeDescription {
        let a = NSAttributeDescription()
        a.name = name
        a.attributeType = type
        a.isOptional = true
        if let value { a.defaultValue = value }
        return a
    }

    private static func build() -> NSManagedObjectModel {
        let list = NSEntityDescription()
        list.name = "TaskList"
        list.managedObjectClassName = NSStringFromClass(TaskList.self)

        let task = NSEntityDescription()
        task.name = "TodoTask"
        task.managedObjectClassName = NSStringFromClass(TodoTask.self)

        let step = NSEntityDescription()
        step.name = "TaskStep"
        step.managedObjectClassName = NSStringFromClass(TaskStep.self)

        let group = NSEntityDescription()
        group.name = "ListGroup"
        group.managedObjectClassName = NSStringFromClass(ListGroup.self)

        // Relationships
        let listTasks = NSRelationshipDescription()
        let taskList = NSRelationshipDescription()
        listTasks.name = "tasks"
        listTasks.destinationEntity = task
        listTasks.minCount = 0
        listTasks.maxCount = 0
        listTasks.deleteRule = .cascadeDeleteRule
        listTasks.isOptional = true
        taskList.name = "list"
        taskList.destinationEntity = list
        taskList.minCount = 0
        taskList.maxCount = 1
        taskList.deleteRule = .nullifyDeleteRule
        taskList.isOptional = true
        listTasks.inverseRelationship = taskList
        taskList.inverseRelationship = listTasks

        let taskSteps = NSRelationshipDescription()
        let stepTask = NSRelationshipDescription()
        taskSteps.name = "steps"
        taskSteps.destinationEntity = step
        taskSteps.minCount = 0
        taskSteps.maxCount = 0
        taskSteps.deleteRule = .cascadeDeleteRule
        taskSteps.isOptional = true
        stepTask.name = "task"
        stepTask.destinationEntity = task
        stepTask.minCount = 0
        stepTask.maxCount = 1
        stepTask.deleteRule = .nullifyDeleteRule
        stepTask.isOptional = true
        taskSteps.inverseRelationship = stepTask
        stepTask.inverseRelationship = taskSteps

        list.properties = [
            attr("id", .UUIDAttributeType),
            attr("name", .stringAttributeType),
            attr("emoji", .stringAttributeType),
            attr("themeKey", .stringAttributeType),
            attr("sortKey", .stringAttributeType),
            attr("sortAscending", .booleanAttributeType, default: true),
            attr("showCompleted", .booleanAttributeType, default: true),
            attr("groupID", .UUIDAttributeType),
            attr("order", .doubleAttributeType, default: 0.0),
            attr("createdAt", .dateAttributeType),
            attr("msID", .stringAttributeType),
            listTasks,
        ]

        task.properties = [
            attr("id", .UUIDAttributeType),
            attr("title", .stringAttributeType),
            attr("note", .stringAttributeType),
            attr("isCompleted", .booleanAttributeType, default: false),
            attr("completedAt", .dateAttributeType),
            attr("isImportant", .booleanAttributeType, default: false),
            attr("dueDate", .dateAttributeType),
            attr("reminderDate", .dateAttributeType),
            attr("myDayDate", .dateAttributeType),
            attr("repeatFrequency", .stringAttributeType),
            attr("repeatInterval", .integer16AttributeType, default: 1),
            attr("repeatWeekdays", .stringAttributeType),
            attr("createdAt", .dateAttributeType),
            attr("order", .doubleAttributeType, default: 0.0),
            attr("msID", .stringAttributeType),
            taskList,
            taskSteps,
        ]

        step.properties = [
            attr("id", .UUIDAttributeType),
            attr("title", .stringAttributeType),
            attr("isCompleted", .booleanAttributeType, default: false),
            attr("order", .doubleAttributeType, default: 0.0),
            attr("createdAt", .dateAttributeType),
            stepTask,
        ]

        group.properties = [
            attr("id", .UUIDAttributeType),
            attr("name", .stringAttributeType),
            attr("order", .doubleAttributeType, default: 0.0),
            attr("isExpanded", .booleanAttributeType, default: true),
            attr("createdAt", .dateAttributeType),
        ]

        let model = NSManagedObjectModel()
        model.entities = [list, task, step, group]
        return model
    }
}
