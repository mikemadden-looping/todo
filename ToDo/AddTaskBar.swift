import SwiftUI

/// The "+ Add a task" bar at the bottom of a list. Tapping it opens a text
/// field with buttons for a due date, reminder and repeat, as in To Do.
struct AddTaskBar: View {
    let context: TaskContext
    let accent: Color

    @State private var expanded = false
    @State private var text = ""
    @State private var due: Date?
    @State private var reminder: Date?
    @State private var recurrence: Recurrence?
    @FocusState private var focused: Bool

    var body: some View {
        Group {
            if expanded { editor } else { collapsed }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
        .animation(.easeInOut(duration: 0.2), value: expanded)
    }

    private var collapsed: some View {
        Button {
            expanded = true
            DispatchQueue.main.async { focused = true }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "plus")
                    .font(.system(size: 18, weight: .medium))
                Text("Add a task")
                Spacer()
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .frame(height: 50)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .background(Color.black.opacity(0.18), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .environment(\.colorScheme, .dark)
        }
        .buttonStyle(.plain)
    }

    private var editor: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Circle()
                    .strokeBorder(Color.secondary.opacity(0.7), lineWidth: 1.5)
                    .frame(width: 22, height: 22)
                TextField("Add a task", text: $text)
                    .focused($focused)
                    .submitLabel(.done)
                    .onSubmit(submit)
                if !text.trimmingCharacters(in: .whitespaces).isEmpty {
                    Button(action: submit) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 26))
                            .foregroundStyle(accent)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Add task")
                }
            }
            .padding(.horizontal, 14)
            .frame(height: 50)

            Divider()

            HStack(spacing: 8) {
                DueDateMenu(date: $due) {
                    chip(icon: "calendar", text: due.map { "Due \(DateLabel.day($0))" }, active: due != nil)
                }
                ReminderMenu(date: $reminder) {
                    chip(icon: "bell", text: reminder.map { DateLabel.dayAndTime($0) }, active: reminder != nil)
                }
                RepeatMenu(recurrence: $recurrence) {
                    chip(icon: "repeat", text: recurrence?.label, active: recurrence != nil)
                }
                Spacer()
                Button("Done") { collapse() }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(accent)
                    .buttonStyle(.borderless)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .shadow(color: .black.opacity(0.15), radius: 6, y: 2)
        .tint(accent)
        .onChange(of: focused) { _, isFocused in
            if !isFocused, text.isEmpty, due == nil, reminder == nil, recurrence == nil {
                expanded = false
            }
        }
    }

    private func chip(icon: String, text: String?, active: Bool) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
            if let text { Text(text).lineLimit(1) }
        }
        .font(.footnote)
        .foregroundStyle(active ? accent : Color.secondary)
        .padding(.horizontal, text == nil ? 8 : 10)
        .padding(.vertical, 6)
        .background(Capsule().fill(active ? accent.opacity(0.12) : Color(.secondarySystemFill)))
    }

    private func submit() {
        if Actions.addTask(title: text, context: context, due: due, reminder: reminder, recurrence: recurrence) != nil {
            Feedback.tap()
        }
        text = ""
        due = nil
        reminder = nil
        recurrence = nil
        focused = true
    }

    private func collapse() {
        if !text.trimmingCharacters(in: .whitespaces).isEmpty { submit() }
        focused = false
        expanded = false
    }
}
