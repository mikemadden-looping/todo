#if DEBUG
import CoreData
import Foundation

/// Sample data for the screenshot workflow (launch argument `-seedDemo YES`).
@MainActor
enum DemoData {
    static var isEnabled: Bool { UserDefaults.standard.bool(forKey: "seedDemo") }

    static func seed() {
        let ctx = Persistence.shared.viewContext
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        func day(_ n: Int) -> Date { cal.date(byAdding: .day, value: n, to: today)! }

        let groceries = Actions.newList(name: "🛒 Groceries")
        groceries.themeKey = "green"
        let house = Actions.newList(name: "House projects")
        house.themeKey = "orange"
        let trip = Actions.newList(name: "✈️ London trip")
        trip.themeKey = "ocean"
        let school = Actions.newList(name: "School")
        school.themeKey = "purple"
        let group = Actions.newGroup(name: "Family")
        trip.groupID = group.id
        school.groupID = group.id

        func add(_ title: String, _ list: TaskList?, myDay: Bool = false, important: Bool = false,
                 due: Date? = nil, reminder: Date? = nil, rec: Recurrence? = nil, steps: [(String, Bool)] = [],
                 note: String? = nil, done: Bool = false) {
            let t = Actions.addTask(title: title, context: TaskContext(list: list), due: due, reminder: reminder,
                                    recurrence: rec, myDay: myDay)!
            t.isImportant = important
            t.note = note
            if done { t.isCompleted = true; t.completedAt = Date() }
            for (s, d) in steps {
                Actions.addStep(s, to: t)
                if d { t.sortedSteps.last?.isCompleted = true }
            }
        }

        add("Milk", groceries, myDay: true)
        add("Eggs", groceries)
        add("Challah for Friday", groceries, important: true, due: day(1))
        add("Apples", groceries, done: true)
        add("Coffee beans", groceries)

        add("Call the roofer about the estimate", house, myDay: true, important: true, due: day(-1))
        add("Replace HVAC filter", house, due: day(3), rec: Recurrence(frequency: .monthly))
        add("Plant garlic in the raised beds", house, steps: [("Buy seed garlic", true), ("Amend soil", false), ("Mulch", false)])

        add("Book train tickets", trip, due: day(10), note: "Check off-peak times")
        add("Renew passport photos", trip, important: true)

        add("Sign permission slip", school, myDay: true, due: day(0), reminder: cal.date(bySettingHour: 18, minute: 0, second: 0, of: today))
        add("Science fair poster supplies", school, due: day(5))

        add("Pick up dry cleaning", nil, myDay: true, reminder: cal.date(byAdding: .hour, value: 3, to: Date()))
        add("Water the plants", nil, myDay: true, rec: Recurrence(frequency: .weekly, weekdays: [1, 4]), done: false)
        add("Return library books", nil, due: day(2))
        add("Schedule dentist appointment", nil, important: true)
        add("Pay the water bill", nil, myDay: true, done: true)

        UserDefaults.standard.set("Mike Madden", forKey: SettingsKey.userName)
        try? ctx.save()
    }
}
#endif
