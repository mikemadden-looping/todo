import AVFoundation
import CoreData
import UIKit
import UserNotifications

/// Reminders are local notifications. Because tasks sync between devices, each
/// device reschedules its notifications from the data whenever it changes.
@MainActor
enum Reminders {
    static let categoryID = "TASK_REMINDER"
    static let completeAction = "COMPLETE"
    private static var pending: DispatchWorkItem?

    static func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    static func registerCategories() {
        let complete = UNNotificationAction(identifier: completeAction, title: "Mark as completed", options: [])
        let cat = UNNotificationCategory(identifier: categoryID, actions: [complete], intentIdentifiers: [], options: [])
        UNUserNotificationCenter.current().setNotificationCategories([cat])
    }

    static func scheduleSoon() {
        pending?.cancel()
        let work = DispatchWorkItem { Task { @MainActor in reschedule() } }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: work)
    }

    static func reschedule() {
        let center = UNUserNotificationCenter.current()
        let req = NSFetchRequest<TodoTask>(entityName: "TodoTask")
        req.predicate = NSPredicate(format: "isCompleted == NO AND reminderDate > %@", Date() as NSDate)
        req.sortDescriptors = [NSSortDescriptor(key: "reminderDate", ascending: true)]
        req.fetchLimit = 60 // iOS keeps at most 64 pending notifications per app
        let tasks = (try? Persistence.shared.viewContext.fetch(req)) ?? []

        center.removeAllPendingNotificationRequests()
        for task in tasks {
            guard let date = task.reminderDate, let id = task.id else { continue }
            let content = UNMutableNotificationContent()
            content.title = task.displayTitle
            content.body = task.list?.displayName ?? "Tasks"
            content.sound = .default
            content.categoryIdentifier = categoryID
            content.userInfo = ["taskID": id.uuidString]
            let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
            center.add(UNNotificationRequest(identifier: id.uuidString, content: content, trigger: trigger))
        }
    }

    static func complete(taskID: String) {
        guard let uuid = UUID(uuidString: taskID) else { return }
        let req = NSFetchRequest<TodoTask>(entityName: "TodoTask")
        req.predicate = NSPredicate(format: "id == %@", uuid as CVarArg)
        if let task = try? Persistence.shared.viewContext.fetch(req).first, !task.isCompleted {
            Actions.toggleComplete(task)
        }
    }
}

enum Sound {
    private static var player: AVAudioPlayer?

    static func playComplete() {
        guard let url = Bundle.main.url(forResource: "complete", withExtension: "wav") else { return }
        try? AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
        player = try? AVAudioPlayer(contentsOf: url)
        player?.volume = 0.6
        player?.play()
    }
}
