import CoreData
import SwiftUI

struct TaskRoute: Hashable {
    let id: NSManagedObjectID
}

/// One task, drawn as a white card like To Do.
struct TaskRow: View {
    @ObservedObject var task: TodoTask
    let accent: Color
    var showListName = false
    var showMyDay = true

    var body: some View {
        HStack(spacing: 12) {
            CheckCircle(isOn: task.isCompleted, accent: accent) {
                Actions.toggleComplete(task)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(task.displayTitle)
                    .font(.body)
                    .strikethrough(task.isCompleted, color: .secondary)
                    .foregroundStyle(task.isCompleted ? .secondary : .primary)
                    .lineLimit(3)
                if !details.isEmpty {
                    detailLine
                }
            }
            Spacer(minLength: 4)
            StarButton(isOn: task.isImportant, accent: accent) {
                Actions.toggleImportant(task)
            }
        }
        .padding(.vertical, 11)
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(.systemBackground).opacity(task.isCompleted ? 0.85 : 1))
                .shadow(color: .black.opacity(0.08), radius: 1, y: 1)
        )
        .background(NavigationLink(value: TaskRoute(id: task.objectID)) { EmptyView() }.opacity(0))
        .contentShape(Rectangle())
        .contextMenu { TaskContextMenu(task: task) }
    }

    private enum Detail: Hashable {
        case myDay, list(String), steps(Int, Int), due(Date), reminder, repeats, note
    }

    private var details: [Detail] {
        var d: [Detail] = []
        if showMyDay, task.isInMyDay { d.append(.myDay) }
        if showListName { d.append(.list(task.list.map { ListTitle($0.displayName).text } ?? "Tasks")) }
        let steps = task.sortedSteps
        if !steps.isEmpty { d.append(.steps(steps.filter(\.isCompleted).count, steps.count)) }
        if let due = task.dueDate { d.append(.due(due)) }
        if task.reminderDate != nil, !task.isCompleted { d.append(.reminder) }
        if task.recurrence != nil { d.append(.repeats) }
        if let note = task.note, !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { d.append(.note) }
        return d
    }

    private var detailLine: some View {
        let items = details
        return HStack(spacing: 5) {
            ForEach(Array(items.enumerated()), id: \.offset) { i, item in
                if i > 0 { Text("•").foregroundStyle(.tertiary) }
                detailView(item)
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }

    @ViewBuilder private func detailView(_ d: Detail) -> some View {
        switch d {
        case .myDay:
            Label("My Day", systemImage: "sun.max").labelStyle(.titleAndIcon)
        case .list(let name):
            Text(name)
        case let .steps(done, total):
            Text("\(done) of \(total)")
        case .due(let date):
            let overdue = task.isOverdue
            let today = Calendar.current.isDateInToday(date)
            Label(overdue ? "Overdue, \(DateLabel.day(date))" : DateLabel.day(date), systemImage: "calendar")
                .foregroundStyle(task.isCompleted ? Color.secondary : (overdue ? Color.red : (today ? accent : Color.secondary)))
        case .reminder:
            Image(systemName: "bell")
        case .repeats:
            Image(systemName: "repeat")
        case .note:
            Image(systemName: "note.text")
        }
    }
}

struct TaskContextMenu: View {
    @ObservedObject var task: TodoTask

    var body: some View {
        Button { Actions.toggleMyDay(task) } label: {
            Label(task.isInMyDay ? "Remove from My Day" : "Add to My Day", systemImage: task.isInMyDay ? "sun.max.trianglebadge.exclamationmark" : "sun.max")
        }
        Button { Actions.toggleImportant(task) } label: {
            Label(task.isImportant ? "Remove importance" : "Mark as important", systemImage: task.isImportant ? "star.slash" : "star")
        }
        Button { Actions.toggleComplete(task) } label: {
            Label(task.isCompleted ? "Mark as not completed" : "Mark as completed", systemImage: task.isCompleted ? "circle" : "checkmark.circle")
        }
        Divider()
        Button { task.dueDate = QuickDates.today; Actions.save() } label: {
            Label("Due today", systemImage: "calendar.day.timeline.left")
        }
        Button { task.dueDate = QuickDates.tomorrow; Actions.save() } label: {
            Label("Due tomorrow", systemImage: "calendar.badge.clock")
        }
        if task.dueDate != nil {
            Button { task.dueDate = nil; Actions.save() } label: {
                Label("Remove due date", systemImage: "calendar.badge.minus")
            }
        }
        Divider()
        MoveToListMenu(task: task)
        Divider()
        Button(role: .destructive) { Actions.delete(task) } label: {
            Label("Delete task", systemImage: "trash")
        }
    }
}

struct MoveToListMenu: View {
    @ObservedObject var task: TodoTask

    var body: some View {
        Menu {
            Button { Actions.move(task, to: nil) } label: {
                Label("Tasks", systemImage: task.list == nil ? "checkmark" : "house")
            }
            ForEach(Actions.allLists().sorted { $0.order < $1.order }) { list in
                Button { Actions.move(task, to: list) } label: {
                    if task.list == list {
                        Label(list.displayName, systemImage: "checkmark")
                    } else {
                        Text(list.displayName)
                    }
                }
            }
        } label: {
            Label("Move task to…", systemImage: "arrow.right.doc.on.clipboard")
        }
    }
}
