import CoreData
import SwiftUI

/// Records what iCloud sync and sharing are doing, so problems show up in
/// Settings → Sync status instead of failing silently.
@MainActor
final class SyncMonitor: ObservableObject {
    static let shared = SyncMonitor()

    struct Entry: Identifiable {
        let id = UUID()
        let date: Date
        let kind: String
        let succeeded: Bool
        let detail: String?
    }

    @Published private(set) var entries: [Entry] = []

    private init() {
        NotificationCenter.default.addObserver(
            forName: NSPersistentCloudKitContainer.eventChangedNotification, object: nil, queue: .main
        ) { note in
            guard let event = note.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey]
                    as? NSPersistentCloudKitContainer.Event, event.endDate != nil else { return }
            let kind: String
            switch event.type {
            case .setup: kind = "Setup"
            case .import: kind = "Download"
            case .export: kind = "Upload"
            @unknown default: kind = "Sync"
            }
            let store = event.storeIdentifier == Persistence.shared.sharedStore?.identifier ? " (shared)" : ""
            let detail = event.error.map(SyncMonitor.describe)
            MainActor.assumeIsolated {
                SyncMonitor.shared.add(Entry(date: event.endDate ?? Date(), kind: kind + store,
                                             succeeded: event.succeeded, detail: detail))
            }
        }
    }

    func add(_ entry: Entry) {
        entries.insert(entry, at: 0)
        if entries.count > 40 { entries.removeLast(entries.count - 40) }
    }

    func recordShareError(_ error: Error) {
        add(Entry(date: Date(), kind: "Share", succeeded: false, detail: Self.describe(error)))
    }

    nonisolated static func describe(_ error: Error) -> String {
        let ns = error as NSError
        var parts = ["\(ns.domain) \(ns.code): \(ns.localizedDescription)"]
        if let underlying = ns.userInfo[NSUnderlyingErrorKey] as? NSError {
            parts.append("Underlying: \(underlying.domain) \(underlying.code): \(underlying.localizedDescription)")
        }
        if let partial = ns.userInfo["CKPartialErrors"] as? [AnyHashable: NSError] {
            for (_, e) in partial.prefix(3) {
                parts.append("Partial: \(e.domain) \(e.code): \(e.localizedDescription)")
            }
        }
        return parts.joined(separator: "\n")
    }
}

struct SyncStatusView: View {
    @ObservedObject private var monitor = SyncMonitor.shared

    var body: some View {
        List {
            if monitor.entries.isEmpty {
                Text("Nothing yet. Make a change, or leave the app and come back, then check again.")
                    .foregroundStyle(.secondary)
            }
            ForEach(monitor.entries) { e in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Image(systemName: e.succeeded ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(e.succeeded ? .green : .red)
                        Text(e.kind).bold()
                        Spacer()
                        Text(e.date.formatted(date: .omitted, time: .standard))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if let d = e.detail {
                        Text(d).font(.caption.monospaced()).textSelection(.enabled)
                    }
                }
            }
        }
        .navigationTitle("Sync status")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !monitor.entries.isEmpty {
                ShareLink(item: monitor.entries.map {
                    "\($0.date.formatted()) \($0.kind) \($0.succeeded ? "OK" : "FAILED")\n\($0.detail ?? "")"
                }.joined(separator: "\n\n")) {
                    Image(systemName: "square.and.arrow.up")
                }
            }
        }
    }
}
