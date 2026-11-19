import SwiftUI

/// List backgrounds, modeled on To Do's color themes plus gradient "scenes"
/// standing in for its photo backgrounds.
struct Theme: Identifiable, Equatable {
    let key: String
    let name: String
    let colors: [Color]
    /// Color used for checkmarks, stars and buttons inside the list.
    let accent: Color
    var isScene: Bool { colors.count > 1 }
    var id: String { key }

    static func hex(_ v: UInt32) -> Color {
        Color(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
    }

    static let blue = Theme(key: "blue", name: "Blue", colors: [hex(0x3E69E4)], accent: hex(0x3E69E4))
    static let purple = Theme(key: "purple", name: "Purple", colors: [hex(0x8764B8)], accent: hex(0x8764B8))
    static let rose = Theme(key: "rose", name: "Rose", colors: [hex(0xC4314B)], accent: hex(0xC4314B))
    static let orange = Theme(key: "orange", name: "Orange", colors: [hex(0xCA5010)], accent: hex(0xCA5010))
    static let green = Theme(key: "green", name: "Green", colors: [hex(0x498205)], accent: hex(0x498205))
    static let teal = Theme(key: "teal", name: "Teal", colors: [hex(0x038387)], accent: hex(0x038387))
    static let gray = Theme(key: "gray", name: "Gray", colors: [hex(0x69797E)], accent: hex(0x69797E))
    static let pink = Theme(key: "pink", name: "Pink", colors: [hex(0xE3008C)], accent: hex(0xE3008C))

    static let sunrise = Theme(key: "sunrise", name: "Sunrise", colors: [hex(0xF7B267), hex(0xF4845F), hex(0x7B4B94)], accent: hex(0xD9643A))
    static let ocean = Theme(key: "ocean", name: "Ocean", colors: [hex(0x8EC5FC), hex(0x3E7CB1), hex(0x1B3A5C)], accent: hex(0x2F6EA8))
    static let forest = Theme(key: "forest", name: "Forest", colors: [hex(0xA8C66C), hex(0x4F7942), hex(0x1E3D2F)], accent: hex(0x3F7A3A))
    static let dusk = Theme(key: "dusk", name: "Dusk", colors: [hex(0xFBC2EB), hex(0x8A6FDF), hex(0x2E2A5E)], accent: hex(0x6E55C9))
    static let meadow = Theme(key: "meadow", name: "Meadow", colors: [hex(0xD4E9A8), hex(0x7FB77E), hex(0x2F7E79)], accent: hex(0x2F7E79))
    static let desert = Theme(key: "desert", name: "Desert", colors: [hex(0xF6D6A8), hex(0xD9895B), hex(0x8C4A3B)], accent: hex(0xB4613D))
    static let mist = Theme(key: "mist", name: "Mist", colors: [hex(0xD7DDE8), hex(0x8E9EAB), hex(0x4B5A69)], accent: hex(0x4B5A69))
    static let night = Theme(key: "night", name: "Night", colors: [hex(0x355C7D), hex(0x2A3A5E), hex(0x0F1A2E)], accent: hex(0x3B6FB6))

    static let colorThemes: [Theme] = [blue, purple, rose, orange, green, teal, gray, pink]
    static let sceneThemes: [Theme] = [sunrise, ocean, forest, dusk, meadow, desert, mist, night]
    static let all: [Theme] = colorThemes + sceneThemes

    static func named(_ key: String?) -> Theme {
        all.first { $0.key == key } ?? .blue
    }

    @ViewBuilder var background: some View {
        if isScene {
            ZStack {
                LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom)
                // Soft hills, so a scene reads as a picture rather than a flat gradient.
                GeometryReader { geo in
                    let w = geo.size.width, h = geo.size.height
                    Path { p in
                        p.move(to: CGPoint(x: 0, y: h * 0.72))
                        p.addQuadCurve(to: CGPoint(x: w, y: h * 0.66), control: CGPoint(x: w * 0.45, y: h * 0.56))
                        p.addLine(to: CGPoint(x: w, y: h))
                        p.addLine(to: CGPoint(x: 0, y: h))
                    }
                    .fill(Color.black.opacity(0.12))
                    Path { p in
                        p.move(to: CGPoint(x: 0, y: h * 0.82))
                        p.addQuadCurve(to: CGPoint(x: w, y: h * 0.8), control: CGPoint(x: w * 0.7, y: h * 0.7))
                        p.addLine(to: CGPoint(x: w, y: h))
                        p.addLine(to: CGPoint(x: 0, y: h))
                    }
                    .fill(Color.black.opacity(0.14))
                }
            }
        } else {
            colors[0]
        }
    }
}

/// Icons and colors for the built-in smart lists, as in To Do.
enum SmartList: String, CaseIterable, Identifiable {
    case myDay, important, planned, all, completed, tasks
    var id: String { rawValue }

    var title: String {
        switch self {
        case .myDay: return "My Day"
        case .important: return "Important"
        case .planned: return "Planned"
        case .all: return "All"
        case .completed: return "Completed"
        case .tasks: return "Tasks"
        }
    }

    var systemImage: String {
        switch self {
        case .myDay: return "sun.max"
        case .important: return "star"
        case .planned: return "calendar"
        case .all: return "infinity"
        case .completed: return "checkmark.circle"
        case .tasks: return "house"
        }
    }

    var iconColor: Color {
        switch self {
        case .myDay: return Theme.hex(0x6E7A86)
        case .important: return Theme.hex(0xD83B6A)
        case .planned: return Theme.hex(0x0E8A7D)
        case .all: return Theme.hex(0x8764B8)
        case .completed: return Theme.hex(0x498205)
        case .tasks: return Theme.hex(0x3E69E4)
        }
    }

    var defaultTheme: Theme {
        switch self {
        case .myDay: return .meadow
        case .important: return .rose
        case .planned: return .teal
        case .all: return .purple
        case .completed: return .green
        case .tasks: return .blue
        }
    }
}
