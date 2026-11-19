import CoreData
import SwiftUI

enum TaskDetailViewField: Hashable { case title, newStep, note, step(NSManagedObjectID) }

struct TaskDetailView: View {
    @ObservedObject var task: TodoTask
    @Environment(\.dismiss) private var dismiss
    @AppStorage(SettingsKey.confirmDelete) private var confirmDelete = true
    @State private var newStep = ""
    @State private var confirmingDelete = false
    @FocusState private var focus: TaskDetailViewField?

    private var accent: Color { task.list?.theme.accent ?? Theme.blue.accent }

    var body: some View {
        Group {
            if task.managedObjectContext == nil || task.isDeleted {
                Color(.systemGroupedBackground)
            } else {
                content
            }
        }
        .navigationTitle(task.list.map { ListTitle($0.displayName).text } ?? "Tasks")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(nil, for: .navigationBar)
        .tint(accent)
        .onDisappear { Actions.save() }
    }

    private var content: some View {
        ScrollView {
            VStack(spacing: 10) {
                titleCard
                myDayCard
                datesCard
                listCard
                noteCard
            }
            .padding(12)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Color(.systemGroupedBackground))
        .safeAreaInset(edge: .bottom) { footer }
        .toolbar {
            ToolbarItem(placement: .keyboard) {
                HStack { Spacer(); Button("Done") { focus = nil; Actions.save() } }
            }
        }
        .confirmationDialog("“\(task.displayTitle)” will be permanently deleted.", isPresented: $confirmingDelete,
                            titleVisibility: .visible) {
            Button("Delete task", role: .destructive) { deleteTask() }
        }
    }

    // MARK: Title and steps

    private var titleCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                CheckCircle(isOn: task.isCompleted, accent: accent, size: 24) { Actions.toggleComplete(task) }
                    .padding(.top, 3)
                TextField("Task name", text: Binding(get: { task.title ?? "" }, set: { task.title = $0 }), axis: .vertical)
                    .font(.title3.weight(.semibold))
                    .strikethrough(task.isCompleted)
                    .focused($focus, equals: .title)
                    .submitLabel(.done)
                    .onSubmit { Actions.save() }
                StarButton(isOn: task.isImportant, accent: accent) { Actions.toggleImportant(task) }
                    .padding(.top, 3)
            }
            .padding(14)

            ForEach(task.sortedSteps) { step in
                StepRow(step: step, accent: accent, focus: $focus, field: .step(step.objectID))
                Divider().padding(.leading, 48)
            }

            HStack(spacing: 12) {
                Image(systemName: "plus")
                    .foregroundStyle(accent)
                    .frame(width: 24)
                TextField(task.sortedSteps.isEmpty ? "Add step" : "Next step", text: $newStep)
                    .foregroundStyle(accent)
                    .focused($focus, equals: .newStep)
                    .submitLabel(.next)
                    .onSubmit {
                        Actions.addStep(newStep, to: task)
                        newStep = ""
                        focus = .newStep
                    }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
        }
        .card()
    }

    // MARK: My Day

    private var myDayCard: some View {
        DetailRow(icon: "sun.max", text: task.isInMyDay ? "Added to My Day" : "Add to My Day",
                  active: task.isInMyDay, accent: accent,
                  onClear: task.isInMyDay ? { Actions.toggleMyDay(task) } : nil)
            .contentShape(Rectangle())
            .onTapGesture { if !task.isInMyDay { Actions.toggleMyDay(task) } }
            .card()
    }

    // MARK: Reminder, due date, repeat

    private var datesCard: some View {
        VStack(spacing: 0) {
            ReminderMenu(date: binding(\.reminderDate)) {
                DetailRow(icon: "bell", text: task.reminderDate.map { "Remind me at \($0.formatted(date: .omitted, time: .shortened))" } ?? "Remind me",
                          subtitle: task.reminderDate.map { DateLabel.day($0) },
                          active: task.reminderDate != nil, accent: accent,
                          onClear: task.reminderDate != nil ? { task.reminderDate = nil; Actions.save() } : nil)
            }
            Divider().padding(.leading, 48)
            DueDateMenu(date: binding(\.dueDate)) {
                DetailRow(icon: "calendar", text: task.dueDate.map { "Due \(DateLabel.day($0))" } ?? "Add due date",
                          active: task.dueDate != nil, accent: task.isOverdue ? .red : accent,
                          onClear: task.dueDate != nil ? { task.dueDate = nil; Actions.save() } : nil)
            }
            Divider().padding(.leading, 48)
            RepeatMenu(recurrence: Binding(get: { task.recurrence }, set: { newValue in
                task.recurrence = newValue
                if newValue != nil, task.dueDate == nil, task.reminderDate == nil { task.dueDate = QuickDates.today }
                Actions.save()
            })) {
                DetailRow(icon: "repeat", text: task.recurrence?.label ?? "Repeat",
                          active: task.recurrence != nil, accent: accent,
                          onClear: task.recurrence != nil ? { task.recurrence = nil; Actions.save() } : nil)
            }
        }
        .card()
    }

    private func binding(_ kp: ReferenceWritableKeyPath<TodoTask, Date?>) -> Binding<Date?> {
        Binding(get: { task[keyPath: kp] }, set: { task[keyPath: kp] = $0; Actions.save() })
    }

    // MARK: List

    private var listCard: some View {
        Menu {
            MoveToListMenuItems(task: task)
        } label: {
            DetailRow(icon: "list.bullet", text: task.list.map { ListTitle($0.displayName).text } ?? "Tasks",
                      subtitle: "List", active: false, accent: accent, onClear: nil)
        }
        .card()
    }

    // MARK: Note

    private var noteCard: some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: Binding(get: { task.note ?? "" }, set: { task.note = $0 }))
                .focused($focus, equals: .note)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 110)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
            if (task.note ?? "").isEmpty {
                Text("Add note")
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 15)
                    .padding(.vertical, 14)
                    .allowsHitTesting(false)
            }
        }
        .card()
    }

    // MARK: Footer

    private var footer: some View {
        HStack {
            Spacer()
            Text(footerText)
                .font(.footnote)
                .foregroundStyle(.secondary)
            Spacer()
            Button {
                if confirmDelete { confirmingDelete = true } else { deleteTask() }
            } label: {
                Image(systemName: "trash").font(.body)
            }
            .foregroundStyle(.secondary)
            .accessibilityLabel("Delete task")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.bar)
    }

    private var footerText: String {
        if task.isCompleted, let done = task.completedAt { return "Completed \(DateLabel.day(done))" }
        if let created = task.createdAt {
            return Calendar.current.isDateInToday(created) ? "Created today" : "Created \(DateLabel.day(created))"
        }
        return ""
    }

    private func deleteTask() {
        dismiss()
        let t = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { Actions.delete(t) }
    }
}

private struct StepRow: View {
    @ObservedObject var step: TaskStep
    let accent: Color
    var focus: FocusState<TaskDetailViewField?>.Binding
    let field: TaskDetailViewField

    var body: some View {
        HStack(spacing: 12) {
            CheckCircle(isOn: step.isCompleted, accent: accent, size: 20) { Actions.toggleStep(step) }
                .frame(width: 24)
            TextField("Step", text: Binding(get: { step.title ?? "" }, set: { step.title = $0 }))
                .strikethrough(step.isCompleted)
                .foregroundStyle(step.isCompleted ? .secondary : .primary)
                .focused(focus, equals: field)
                .onSubmit { Actions.save() }
            Menu {
                Button { Actions.promote(step) } label: { Label("Promote to task", systemImage: "arrow.up.square") }
                Button(role: .destructive) {
                    Persistence.shared.viewContext.delete(step)
                    Actions.save()
                } label: { Label("Delete step", systemImage: "trash") }
            } label: {
                Image(systemName: "ellipsis")
                    .foregroundStyle(.secondary)
                    .frame(width: 30, height: 30)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }
}

struct DetailRow: View {
    let icon: String
    let text: String
    var subtitle: String? = nil
    let active: Bool
    let accent: Color
    let onClear: (() -> Void)?

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 17))
                .frame(width: 24)
                .foregroundStyle(active ? accent : Color.secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(text)
                    .foregroundStyle(active ? accent : Color.secondary)
                if let subtitle {
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if let onClear {
                Button(action: onClear) {
                    Image(systemName: "xmark").font(.footnote).foregroundStyle(.secondary)
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Remove")
            }
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 52)
        .contentShape(Rectangle())
    }
}

struct MoveToListMenuItems: View {
    @ObservedObject var task: TodoTask

    var body: some View {
        Button { Actions.move(task, to: nil) } label: {
            Label("Tasks", systemImage: task.list == nil ? "checkmark" : "house")
        }
        ForEach(Actions.allLists().sorted { $0.order < $1.order }) { list in
            Button { Actions.move(task, to: list) } label: {
                if task.list == list { Label(list.displayName, systemImage: "checkmark") } else { Text(list.displayName) }
            }
        }
    }
}

extension View {
    func card() -> some View {
        background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
