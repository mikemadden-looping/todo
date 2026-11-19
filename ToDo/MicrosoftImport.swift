import AuthenticationServices
import CoreData
import CryptoKit
import SwiftUI
import UIKit

/// One-time import of lists and tasks from Microsoft To Do through Microsoft Graph.
/// Sign-in uses OAuth with PKCE in a system web sheet; the app never sees the password,
/// and the access token is kept only in memory for the import.
enum MicrosoftGraph {
    static let redirectURI = "todoimport://auth"
    static let scopes = "Tasks.Read offline_access"
    static let authority = "https://login.microsoftonline.com/common/oauth2/v2.0"

    static var configuredClientID: String? {
        guard let id = Bundle.main.object(forInfoDictionaryKey: "MSClientID") as? String,
              !id.isEmpty, !id.contains("$(") else { return nil }
        return id
    }

    struct GraphError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    // MARK: Sign-in

    @MainActor
    static func signIn(clientID: String) async throws -> String {
        let verifier = randomString(64)
        let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64URL
        var comps = URLComponents(string: "\(authority)/authorize")!
        comps.queryItems = [
            .init(name: "client_id", value: clientID),
            .init(name: "response_type", value: "code"),
            .init(name: "redirect_uri", value: redirectURI),
            .init(name: "response_mode", value: "query"),
            .init(name: "scope", value: scopes),
            .init(name: "code_challenge", value: challenge),
            .init(name: "code_challenge_method", value: "S256"),
            .init(name: "prompt", value: "select_account"),
        ]
        let callback = try await WebAuth.run(url: comps.url!, scheme: "todoimport")
        let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
        if let err = items.first(where: { $0.name == "error_description" })?.value ?? items.first(where: { $0.name == "error" })?.value {
            throw GraphError(message: err)
        }
        guard let code = items.first(where: { $0.name == "code" })?.value else {
            throw GraphError(message: "Microsoft didn't return a sign-in code.")
        }

        var req = URLRequest(url: URL(string: "\(authority)/token")!)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let form: [String: String] = [
            "client_id": clientID,
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": redirectURI,
            "code_verifier": verifier,
            "scope": scopes,
        ]
        req.httpBody = form.map { "\($0.key)=\($0.value.formEncoded)" }.joined(separator: "&").data(using: .utf8)
        let (data, _) = try await URLSession.shared.data(for: req)
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        guard let token = json["access_token"] as? String else {
            throw GraphError(message: (json["error_description"] as? String) ?? "Couldn't get an access token.")
        }
        return token
    }

    private static func randomString(_ n: Int) -> String {
        let chars = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        return String((0..<n).map { _ in chars.randomElement()! })
    }

    // MARK: Graph calls

    static func getAll(_ url: String, token: String) async throws -> [[String: Any]] {
        var results: [[String: Any]] = []
        var next: String? = url
        while let u = next, let reqURL = URL(string: u) {
            var req = URLRequest(url: reqURL)
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            let (data, response) = try await URLSession.shared.data(for: req)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
            if status == 429 || status == 503 {
                let wait = Double((response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Retry-After") ?? "") ?? 3
                try await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
                continue
            }
            guard (200..<300).contains(status) else {
                let msg = ((json["error"] as? [String: Any])?["message"] as? String) ?? "HTTP \(status)"
                throw GraphError(message: msg)
            }
            results += (json["value"] as? [[String: Any]]) ?? []
            next = json["@odata.nextLink"] as? String
        }
        return results
    }

    // MARK: Parsing helpers

    /// Graph dates look like {"dateTime": "2026-11-20T05:00:00.0000000", "timeZone": "UTC"}.
    static func date(_ value: Any?) -> Date? {
        guard let obj = value as? [String: Any], let s = obj["dateTime"] as? String else { return nil }
        let tzName = obj["timeZone"] as? String ?? "UTC"
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        f.timeZone = TimeZone(identifier: tzName == "UTC" ? "UTC" : tzName) ?? TimeZone(identifier: "UTC")
        return f.date(from: String(s.prefix(19)))
    }

    static func isoDate(_ value: Any?) -> Date? {
        guard let s = value as? String else { return nil }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: s) ?? ISO8601DateFormatter().date(from: s)
    }

    static func recurrence(_ value: Any?) -> Recurrence? {
        guard let rec = value as? [String: Any], let pattern = rec["pattern"] as? [String: Any],
              let type = pattern["type"] as? String else { return nil }
        let interval = max(1, pattern["interval"] as? Int ?? 1)
        let names = ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"]
        let days = Set(((pattern["daysOfWeek"] as? [String]) ?? []).compactMap { names.firstIndex(of: $0.lowercased()).map { $0 + 1 } })
        switch type {
        case "daily": return Recurrence(frequency: .daily, interval: interval)
        case "weekly":
            if interval == 1, days == [2, 3, 4, 5, 6] { return Recurrence(frequency: .weekdays) }
            return Recurrence(frequency: .weekly, interval: interval, weekdays: days)
        case "absoluteMonthly", "relativeMonthly": return Recurrence(frequency: .monthly, interval: interval)
        case "absoluteYearly", "relativeYearly": return Recurrence(frequency: .yearly, interval: interval)
        default: return nil
        }
    }

    static func plainText(_ body: Any?) -> String? {
        guard let b = body as? [String: Any], var content = b["content"] as? String else { return nil }
        if (b["contentType"] as? String)?.lowercased() == "html" {
            content = content.replacingOccurrences(of: "<br>", with: "\n", options: .caseInsensitive)
                .replacingOccurrences(of: "</p>", with: "\n", options: .caseInsensitive)
                .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
                .replacingOccurrences(of: "&nbsp;", with: " ")
                .replacingOccurrences(of: "&amp;", with: "&")
                .replacingOccurrences(of: "&lt;", with: "<")
                .replacingOccurrences(of: "&gt;", with: ">")
        }
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

// MARK: - Importer

@MainActor
final class MicrosoftImporter: ObservableObject {
    enum Phase: Equatable {
        case idle, signingIn, importing(String), done(String), failed(String)
    }

    @Published var phase: Phase = .idle
    var includeCompleted = true

    func run(clientID: String) async {
        phase = .signingIn
        do {
            let token = try await MicrosoftGraph.signIn(clientID: clientID)
            phase = .importing("Reading your lists…")
            let summary = try await importAll(token: token)
            phase = .done(summary)
        } catch let e as ASWebAuthenticationSessionError where e.code == .canceledLogin {
            phase = .idle
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    private func importAll(token: String) async throws -> String {
        let ctx = Persistence.shared.viewContext
        let graphLists = try await MicrosoftGraph.getAll("https://graph.microsoft.com/v1.0/me/todo/lists", token: token)

        let existingLists = Dictionary(Actions.allLists().compactMap { l in l.msID.map { ($0, l) } }, uniquingKeysWith: { a, _ in a })
        let taskReq = NSFetchRequest<TodoTask>(entityName: "TodoTask")
        taskReq.predicate = NSPredicate(format: "msID != nil")
        let existingTaskIDs = Set(((try? ctx.fetch(taskReq)) ?? []).compactMap(\.msID))

        var listCount = 0, taskCount = 0, skipped = 0
        var nextListOrder = (Actions.allLists().map(\.order).max() ?? 0) + 1
        let themes = Theme.colorThemes

        for (index, gl) in graphLists.enumerated() {
            guard let gid = gl["id"] as? String else { continue }
            let wellKnown = gl["wellknownListName"] as? String ?? "none"
            if wellKnown == "flaggedEmails" { continue }
            let name = gl["displayName"] as? String ?? "Untitled list"
            phase = .importing("Importing “\(name)” (\(index + 1) of \(graphLists.count))…")

            // To Do's default "Tasks" list maps to this app's Tasks list.
            var list: TaskList?
            if wellKnown != "defaultList" {
                if let existing = existingLists[gid] {
                    list = existing
                } else {
                    let l = TaskList(context: ctx)
                    Persistence.shared.assign(l, alongside: nil)
                    l.id = UUID()
                    l.name = name
                    l.msID = gid
                    l.createdAt = Date()
                    l.themeKey = themes[listCount % themes.count].key
                    l.sortKey = TaskSort.custom.rawValue
                    l.sortAscending = true
                    l.showCompleted = true
                    l.order = nextListOrder
                    nextListOrder += 1
                    list = l
                    listCount += 1
                }
            }

            let base = "https://graph.microsoft.com/v1.0/me/todo/lists/\(gid)/tasks"
            var graphTasks: [[String: Any]]
            var expanded = true
            do {
                graphTasks = try await MicrosoftGraph.getAll("\(base)?$expand=checklistItems&$top=100", token: token)
            } catch {
                expanded = false
                graphTasks = try await MicrosoftGraph.getAll("\(base)?$top=100", token: token)
            }

            for (i, gt) in graphTasks.enumerated() {
                guard let tid = gt["id"] as? String else { continue }
                if existingTaskIDs.contains(tid) { skipped += 1; continue }
                let completed = (gt["status"] as? String) == "completed"
                if completed && !includeCompleted { continue }

                let t = TodoTask(context: ctx)
                Persistence.shared.assign(t, alongside: list)
                t.id = UUID()
                t.msID = tid
                t.title = gt["title"] as? String ?? ""
                t.note = MicrosoftGraph.plainText(gt["body"])
                t.isCompleted = completed
                t.completedAt = completed ? (MicrosoftGraph.date(gt["completedDateTime"]) ?? Date()) : nil
                t.isImportant = (gt["importance"] as? String) == "high"
                if let due = MicrosoftGraph.date(gt["dueDateTime"]) {
                    t.dueDate = Calendar.current.startOfDay(for: due)
                }
                if (gt["isReminderOn"] as? Bool) == true {
                    t.reminderDate = MicrosoftGraph.date(gt["reminderDateTime"])
                }
                if !completed { t.recurrence = MicrosoftGraph.recurrence(gt["recurrence"]) }
                t.createdAt = MicrosoftGraph.isoDate(gt["createdDateTime"]) ?? Date()
                t.order = Double(i)
                t.list = list
                taskCount += 1

                var items = gt["checklistItems"] as? [[String: Any]]
                if items == nil, !expanded {
                    items = try? await MicrosoftGraph.getAll("\(base)/\(tid)/checklistItems", token: token)
                }
                for (j, item) in (items ?? []).enumerated() {
                    let s = TaskStep(context: ctx)
                    Persistence.shared.assign(s, alongside: list)
                    s.id = UUID()
                    s.title = item["displayName"] as? String ?? ""
                    s.isCompleted = (item["isChecked"] as? Bool) ?? false
                    s.order = Double(j)
                    s.createdAt = MicrosoftGraph.isoDate(item["createdDateTime"]) ?? Date()
                    s.task = t
                }
            }
            Actions.save()
        }

        var summary = "Imported \(taskCount) task\(taskCount == 1 ? "" : "s") in \(listCount) new list\(listCount == 1 ? "" : "s")."
        if skipped > 0 { summary += " Skipped \(skipped) already imported." }
        return summary
    }
}

struct MicrosoftImportView: View {
    @StateObject private var importer = MicrosoftImporter()
    @AppStorage("msClientID") private var savedClientID = ""
    @State private var includeCompleted = true

    private var clientID: String { MicrosoftGraph.configuredClientID ?? savedClientID }

    var body: some View {
        Form {
            Section {
                Text("Sign in with the Microsoft account you use in To Do. Your lists, tasks, steps, notes, due dates, reminders and repeat settings are copied here. Lists shared with you in To Do are copied as your own lists. Running it again skips tasks already imported.")
                    .font(.subheadline)
                Toggle("Include completed tasks", isOn: $includeCompleted)
            }
            if MicrosoftGraph.configuredClientID == nil {
                Section {
                    TextField("Application (client) ID", text: $savedClientID)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.system(.body, design: .monospaced))
                } header: {
                    Text("Azure app ID")
                } footer: {
                    Text("From the app registration described in the README (redirect URI \(MicrosoftGraph.redirectURI)).")
                }
            }
            Section {
                Button {
                    importer.includeCompleted = includeCompleted
                    Task { await importer.run(clientID: clientID.trimmingCharacters(in: .whitespaces)) }
                } label: {
                    HStack {
                        Text("Sign in and import")
                        Spacer()
                        if case .signingIn = importer.phase { ProgressView() }
                        if case .importing = importer.phase { ProgressView() }
                    }
                }
                .disabled(clientID.trimmingCharacters(in: .whitespaces).isEmpty || isBusy)
            }
            switch importer.phase {
            case .importing(let msg):
                Section { Text(msg).foregroundStyle(.secondary) }
            case .done(let msg):
                Section { Label(msg, systemImage: "checkmark.circle.fill").foregroundStyle(.green) }
            case .failed(let msg):
                Section { Label(msg, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red) }
            default:
                EmptyView()
            }
        }
        .navigationTitle("Import from To Do")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var isBusy: Bool {
        switch importer.phase {
        case .signingIn, .importing: return true
        default: return false
        }
    }
}

// MARK: - ASWebAuthenticationSession wrapper

@MainActor
private final class WebAuth: NSObject, ASWebAuthenticationPresentationContextProviding {
    private static var current: WebAuth?
    private var session: ASWebAuthenticationSession?

    static func run(url: URL, scheme: String) async throws -> URL {
        let auth = WebAuth()
        current = auth
        defer { current = nil }
        return try await withCheckedThrowingContinuation { cont in
            let s = ASWebAuthenticationSession(url: url, callbackURLScheme: scheme) { callback, error in
                if let callback { cont.resume(returning: callback) }
                else { cont.resume(throwing: error ?? MicrosoftGraph.GraphError(message: "Sign-in failed.")) }
            }
            s.presentationContextProvider = auth
            s.prefersEphemeralWebBrowserSession = true
            auth.session = s
            s.start()
        }
    }

    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            return scenes.flatMap(\.windows).first { $0.isKeyWindow } ?? ASPresentationAnchor()
        }
    }
}

private extension Data {
    var base64URL: String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

private extension String {
    var formEncoded: String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return addingPercentEncoding(withAllowedCharacters: allowed) ?? self
    }
}
