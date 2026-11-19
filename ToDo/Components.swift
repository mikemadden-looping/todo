import SwiftUI

// MARK: - Check circle

struct CheckCircle: View {
    let isOn: Bool
    let accent: Color
    var size: CGFloat = 22
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .strokeBorder(isOn ? accent : Color.secondary.opacity(0.7), lineWidth: 1.5)
                    .background(Circle().fill(isOn ? accent : Color.clear))
                if isOn {
                    Image(systemName: "checkmark")
                        .font(.system(size: size * 0.5, weight: .bold))
                        .foregroundStyle(.white)
                        .transition(.scale)
                }
            }
            .frame(width: size, height: size)
            .contentShape(Rectangle().inset(by: -10))
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(isOn ? "Mark as not completed" : "Mark as completed")
    }
}

struct StarButton: View {
    let isOn: Bool
    let accent: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: isOn ? "star.fill" : "star")
                .font(.system(size: 18))
                .foregroundStyle(isOn ? accent : Color.secondary)
                .contentShape(Rectangle().inset(by: -10))
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(isOn ? "Remove importance" : "Mark as important")
    }
}

// MARK: - List names with a leading emoji
//
// As in To Do, a list whose name starts with an emoji uses that emoji as its icon.

struct ListTitle {
    let emoji: String?
    let text: String

    init(_ name: String) {
        if let first = name.first, first.isEmoji {
            emoji = String(first)
            let rest = name.dropFirst().trimmingCharacters(in: .whitespaces)
            text = rest.isEmpty ? name : rest
        } else {
            emoji = nil
            text = name
        }
    }
}

extension Character {
    var isEmoji: Bool {
        guard let scalar = unicodeScalars.first else { return false }
        return scalar.properties.isEmojiPresentation || (scalar.properties.isEmoji && unicodeScalars.count > 1)
    }
}

// MARK: - Date labels

enum DateLabel {
    static func day(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return "Today" }
        if cal.isDateInTomorrow(date) { return "Tomorrow" }
        if cal.isDateInYesterday(date) { return "Yesterday" }
        let sameYear = cal.component(.year, from: date) == cal.component(.year, from: Date())
        return date.formatted(sameYear ? .dateTime.weekday(.abbreviated).month(.abbreviated).day()
                                       : .dateTime.weekday(.abbreviated).month(.abbreviated).day().year())
    }

    static func dayAndTime(_ date: Date) -> String {
        "\(day(date)) at \(date.formatted(date: .omitted, time: .shortened))"
    }

    static func header(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.wide).month(.wide).day())
    }
}

// MARK: - Quick date choices (same options as To Do)

enum QuickDates {
    static var cal: Calendar { .current }
    static var today: Date { cal.startOfDay(for: Date()) }
    static var tomorrow: Date { cal.date(byAdding: .day, value: 1, to: today)! }
    static var nextMonday: Date {
        cal.nextDate(after: today, matching: DateComponents(weekday: 2), matchingPolicy: .nextTime) ?? tomorrow
    }

    static func at(_ hour: Int, on day: Date) -> Date {
        cal.date(bySettingHour: hour, minute: 0, second: 0, of: day) ?? day
    }

    static var laterToday: Date {
        let inThree = Date().addingTimeInterval(3 * 3600)
        let comps = cal.dateComponents([.year, .month, .day, .hour], from: inThree)
        return cal.date(from: comps) ?? inThree
    }
}

struct DueDateMenu<Label: View>: View {
    @Binding var date: Date?
    @ViewBuilder var label: () -> Label
    @State private var picking = false

    var body: some View {
        Menu {
            Button { date = QuickDates.today } label: {
                SwiftUI.Label("Today", systemImage: "calendar.day.timeline.left")
            }
            Button { date = QuickDates.tomorrow } label: {
                SwiftUI.Label("Tomorrow", systemImage: "calendar.badge.clock")
            }
            Button { date = QuickDates.nextMonday } label: {
                SwiftUI.Label("Next week", systemImage: "calendar")
            }
            Button { picking = true } label: {
                SwiftUI.Label("Pick a date", systemImage: "calendar.badge.plus")
            }
            if date != nil {
                Divider()
                Button(role: .destructive) { date = nil } label: {
                    SwiftUI.Label("Remove due date", systemImage: "trash")
                }
            }
        } label: { label() }
        .sheet(isPresented: $picking) {
            DatePickSheet(title: "Due date", initial: date ?? QuickDates.tomorrow, withTime: false) { picked in
                date = Calendar.current.startOfDay(for: picked)
            }
        }
    }
}

struct ReminderMenu<Label: View>: View {
    @Binding var date: Date?
    @ViewBuilder var label: () -> Label
    @State private var picking = false

    var body: some View {
        Menu {
            Button { set(QuickDates.laterToday) } label: {
                SwiftUI.Label("Later today (\(QuickDates.laterToday.formatted(date: .omitted, time: .shortened)))", systemImage: "clock")
            }
            Button { set(QuickDates.at(9, on: QuickDates.tomorrow)) } label: {
                SwiftUI.Label("Tomorrow (9:00 AM)", systemImage: "clock.arrow.circlepath")
            }
            Button { set(QuickDates.at(9, on: QuickDates.nextMonday)) } label: {
                SwiftUI.Label("Next week (Mon, 9:00 AM)", systemImage: "calendar")
            }
            Button { picking = true } label: {
                SwiftUI.Label("Pick a date & time", systemImage: "calendar.badge.clock")
            }
            if date != nil {
                Divider()
                Button(role: .destructive) { date = nil } label: {
                    SwiftUI.Label("Remove reminder", systemImage: "trash")
                }
            }
        } label: { label() }
        .sheet(isPresented: $picking) {
            DatePickSheet(title: "Remind me", initial: date ?? QuickDates.at(9, on: QuickDates.tomorrow), withTime: true) { picked in
                set(picked)
            }
        }
    }

    private func set(_ d: Date) {
        Reminders.requestAuthorization()
        date = d
    }
}

struct RepeatMenu<Label: View>: View {
    @Binding var recurrence: Recurrence?
    @ViewBuilder var label: () -> Label
    @State private var custom = false

    var body: some View {
        Menu {
            Button("Daily") { recurrence = Recurrence(frequency: .daily) }
            Button("Weekdays") { recurrence = Recurrence(frequency: .weekdays) }
            Button("Weekly") {
                recurrence = Recurrence(frequency: .weekly, weekdays: [Calendar.current.component(.weekday, from: Date())])
            }
            Button("Monthly") { recurrence = Recurrence(frequency: .monthly) }
            Button("Yearly") { recurrence = Recurrence(frequency: .yearly) }
            Button("Custom…") { custom = true }
            if recurrence != nil {
                Divider()
                Button("Never repeat", role: .destructive) { recurrence = nil }
            }
        } label: { label() }
        .sheet(isPresented: $custom) {
            CustomRepeatSheet(initial: recurrence ?? Recurrence(frequency: .weekly, weekdays: [Calendar.current.component(.weekday, from: Date())])) {
                recurrence = $0
            }
        }
    }
}

struct DatePickSheet: View {
    let title: String
    @State var selection: Date
    let withTime: Bool
    let onSave: (Date) -> Void
    @Environment(\.dismiss) private var dismiss

    init(title: String, initial: Date, withTime: Bool, onSave: @escaping (Date) -> Void) {
        self.title = title
        _selection = State(initialValue: initial)
        self.withTime = withTime
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                DatePicker(title, selection: $selection, displayedComponents: withTime ? [.date, .hourAndMinute] : [.date])
                    .datePickerStyle(.graphical)
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { onSave(selection); dismiss() }.bold()
                }
            }
        }
        .presentationDetents([.large, .medium])
    }
}

struct CustomRepeatSheet: View {
    @State var rec: Recurrence
    let onSave: (Recurrence) -> Void
    @Environment(\.dismiss) private var dismiss

    init(initial: Recurrence, onSave: @escaping (Recurrence) -> Void) {
        var r = initial
        if r.frequency == .weekdays { r = Recurrence(frequency: .weekly, interval: 1, weekdays: [2, 3, 4, 5, 6]) }
        _rec = State(initialValue: r)
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Repeat every") {
                    Stepper(value: $rec.interval, in: 1...99) {
                        Text("\(rec.interval)")
                    }
                    Picker("Unit", selection: $rec.frequency) {
                        Text(rec.interval == 1 ? "day" : "days").tag(Recurrence.Frequency.daily)
                        Text(rec.interval == 1 ? "week" : "weeks").tag(Recurrence.Frequency.weekly)
                        Text(rec.interval == 1 ? "month" : "months").tag(Recurrence.Frequency.monthly)
                        Text(rec.interval == 1 ? "year" : "years").tag(Recurrence.Frequency.yearly)
                    }
                    .pickerStyle(.segmented)
                }
                if rec.frequency == .weekly {
                    Section("On") {
                        HStack {
                            ForEach(1...7, id: \.self) { wd in
                                let on = rec.weekdays.contains(wd)
                                Button {
                                    if on { rec.weekdays.remove(wd) } else { rec.weekdays.insert(wd) }
                                } label: {
                                    Text(Calendar.current.veryShortWeekdaySymbols[wd - 1])
                                        .font(.subheadline.bold())
                                        .frame(width: 34, height: 34)
                                        .background(Circle().fill(on ? Color.accentColor : Color(.secondarySystemFill)))
                                        .foregroundStyle(on ? .white : .primary)
                                }
                                .buttonStyle(.borderless)
                                .frame(maxWidth: .infinity)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Repeat")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { onSave(rec); dismiss() }.bold()
                }
            }
        }
        .presentationDetents([.medium])
    }
}

// MARK: - Text prompt (rename, new list, new group)

struct TextPrompt: Identifiable {
    let id = UUID()
    let title: String
    var text: String
    let actionTitle: String
    let onSave: (String) -> Void
}

extension View {
    func textPrompt(_ prompt: Binding<TextPrompt?>) -> some View {
        modifier(TextPromptModifier(prompt: prompt))
    }
}

private struct TextPromptModifier: ViewModifier {
    @Binding var prompt: TextPrompt?
    @State private var text = ""

    func body(content: Content) -> some View {
        content
            .alert(prompt?.title ?? "", isPresented: Binding(get: { prompt != nil }, set: { if !$0 { prompt = nil } })) {
                TextField("Name", text: $text)
                Button("Cancel", role: .cancel) { prompt = nil }
                Button(prompt?.actionTitle ?? "Save") {
                    let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !t.isEmpty { prompt?.onSave(t) }
                    prompt = nil
                }
            }
            .onChange(of: prompt?.id) { _, _ in text = prompt?.text ?? "" }
    }
}
