import CloudKit
import CoreData
import Foundation
import os

/// Core Data stack that syncs through iCloud. There are two stores:
/// the private store holds everything you own (including lists you share with
/// others), and the shared store holds lists other people shared with you.
final class Persistence {
    #if DEBUG
    static let shared = Persistence(inMemory: UserDefaults.standard.bool(forKey: "seedDemo"))
    #else
    static let shared = Persistence()
    #endif

    let container: NSPersistentCloudKitContainer
    private(set) var privateStore: NSPersistentStore?
    private(set) var sharedStore: NSPersistentStore?
    let cloudContainerID: String
    private let log = Logger(subsystem: "todo", category: "persistence")

    var viewContext: NSManagedObjectContext { container.viewContext }
    var ckContainer: CKContainer { CKContainer(identifier: cloudContainerID) }

    init(inMemory: Bool = false) {
        cloudContainerID = (Bundle.main.object(forInfoDictionaryKey: "CloudKitContainerID") as? String)
            .flatMap { $0.contains("$(") ? nil : $0 } ?? "iCloud.com.mikemadden.todo"

        container = NSPersistentCloudKitContainer(name: "ToDo", managedObjectModel: ManagedModel.shared)

        let baseURL = NSPersistentContainer.defaultDirectoryURL()
        let privateDesc = NSPersistentStoreDescription(url: baseURL.appendingPathComponent("private.sqlite"))
        let sharedDesc = NSPersistentStoreDescription(url: baseURL.appendingPathComponent("shared.sqlite"))

        for desc in [privateDesc, sharedDesc] {
            desc.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
            desc.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
        }

        let privateOptions = NSPersistentCloudKitContainerOptions(containerIdentifier: cloudContainerID)
        privateOptions.databaseScope = .private
        privateDesc.cloudKitContainerOptions = privateOptions

        let sharedOptions = NSPersistentCloudKitContainerOptions(containerIdentifier: cloudContainerID)
        sharedOptions.databaseScope = .shared
        sharedDesc.cloudKitContainerOptions = sharedOptions

        if inMemory {
            // Throwaway local stores with no iCloud, for screenshots.
            let tmp = FileManager.default.temporaryDirectory
            for (desc, name) in [(privateDesc, "demo-private"), (sharedDesc, "demo-shared")] {
                let url = tmp.appendingPathComponent("\(name).sqlite")
                for suffix in ["", "-wal", "-shm"] {
                    try? FileManager.default.removeItem(at: URL(fileURLWithPath: url.path + suffix))
                }
                desc.url = url
                desc.cloudKitContainerOptions = nil
            }
        }

        container.persistentStoreDescriptions = [privateDesc, sharedDesc]
        container.loadPersistentStores { [log] desc, error in
            if let error {
                log.error("Store failed to load: \(error.localizedDescription)")
            }
        }

        for store in container.persistentStoreCoordinator.persistentStores {
            let name = store.url?.lastPathComponent ?? ""
            if name.hasSuffix("private.sqlite") { privateStore = store }
            if name.hasSuffix("shared.sqlite") { sharedStore = store }
        }

        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        container.viewContext.transactionAuthor = "app"
        try? container.viewContext.setQueryGenerationFrom(.current)

        #if DEBUG
        // In a Debug build run from Xcode (CloudKit's Development environment),
        // push the record types to CloudKit so they can be deployed to
        // Production in the CloudKit Console. See README, "One-time iCloud setup".
        if !inMemory, ProcessInfo.processInfo.environment["INIT_CLOUDKIT_SCHEMA"] == "1" {
            do {
                try container.initializeCloudKitSchema(options: [])
                log.info("CloudKit schema initialized")
            } catch {
                log.error("initializeCloudKitSchema failed: \(error.localizedDescription)")
            }
        }
        #endif
    }

    func save() {
        let ctx = viewContext
        guard ctx.hasChanges else { return }
        do { try ctx.save() } catch {
            log.error("Save failed: \(error.localizedDescription)")
            ctx.rollback()
        }
    }

    /// Puts a newly inserted object in the same store as `peer` (for example a
    /// task added to a list someone shared with you goes in the shared store).
    func assign(_ object: NSManagedObject, alongside peer: NSManagedObject?) {
        let store = peer?.objectID.persistentStore ?? privateStore
        if let store, object.objectID.isTemporaryID {
            viewContext.assign(object, to: store)
        }
    }

    // MARK: Sharing

    func isInSharedStore(_ object: NSManagedObject) -> Bool {
        guard let sharedStore else { return false }
        return object.objectID.persistentStore == sharedStore
    }

    func existingShare(for list: TaskList) -> CKShare? {
        guard !list.objectID.isTemporaryID else { return nil }
        return (try? container.fetchShares(matching: [list.objectID]))?[list.objectID]
    }

    func isShared(_ list: TaskList) -> Bool {
        isInSharedStore(list) || existingShare(for: list) != nil
    }

    func canEdit(_ object: NSManagedObject) -> Bool {
        container.canUpdateRecord(forManagedObjectWith: object.objectID)
    }

    enum ShareProblem: LocalizedError {
        case stuck, notUploaded, noLink
        var errorDescription: String? {
            switch self {
            case .stuck: return "This list's sharing got stuck in iCloud. Use Reset sharing, then share again."
            case .notUploaded: return "This list hasn't finished uploading to iCloud yet. Try again in a minute."
            case .noLink: return "iCloud created the share but didn't return a link."
            }
        }
    }

    /// True when a share exists locally but iCloud never saved it (no link).
    func hasStuckShare(_ list: TaskList) -> Bool {
        guard !isInSharedStore(list), let share = existingShare(for: list) else { return false }
        return share.url == nil
    }

    /// Waits until the list has been uploaded, so sharing doesn't race the first upload.
    @MainActor
    func waitUntilUploaded(_ list: TaskList, timeout: TimeInterval = 30) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if !list.objectID.isTemporaryID, container.record(for: list.objectID) != nil { return true }
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }
        return false
    }

    @MainActor
    func share(_ list: TaskList) async throws -> (CKShare, CKContainer) {
        if let share = existingShare(for: list) {
            if share.url == nil { throw ShareProblem.stuck }
            return (share, ckContainer)
        }
        guard await waitUntilUploaded(list) else { throw ShareProblem.notUploaded }
        let (_, share, ck) = try await container.share([list], to: nil)
        share[CKShare.SystemFieldKey.title] = list.displayName as CKRecordValue
        if share.url == nil {
            // The link can arrive a moment after the save.
            for _ in 0..<5 {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if let fresh = existingShare(for: list), fresh.url != nil { return (fresh, ck) }
            }
            throw ShareProblem.noLink
        }
        return (share, ck)
    }

    /// Creates (or returns) the share for a list; used by the share sheet's
    /// preparation step.
    @MainActor
    func makeShare(listID: NSManagedObjectID) async throws -> CKShare {
        guard let list = try viewContext.existingObject(with: listID) as? TaskList else {
            throw CocoaError(.coderValueNotFound)
        }
        do {
            let (share, _) = try await share(list)
            return share
        } catch {
            SyncMonitor.shared.recordShareError(error)
            throw error
        }
    }

    func accept(_ metadata: CKShare.Metadata) {
        guard let sharedStore else { return }
        container.acceptShareInvitations(from: [metadata], into: sharedStore) { [log] _, error in
            if let error { log.error("Accepting share failed: \(error.localizedDescription)") }
        }
    }

    func persistUpdatedShare(_ share: CKShare) {
        guard let store = privateStore else { return }
        container.persistUpdatedShare(share, in: store) { [log] _, error in
            if let error { log.error("Persisting share failed: \(error.localizedDescription)") }
        }
    }

    /// Clears a share's zone. If iCloud can't (for example the zone never
    /// existed on the server), `fallback` is deleted locally instead.
    func purgeShare(_ share: CKShare, fallback: NSManagedObjectID? = nil) {
        guard let store = privateStore else { return }
        container.purgeObjectsAndRecordsInZone(with: share.recordID.zoneID, in: store) { [log] _, error in
            guard let error else { return }
            log.error("Purging share failed: \(error.localizedDescription)")
            Task { @MainActor in
                SyncMonitor.shared.recordShareError(error)
                if let id = fallback, let obj = try? self.viewContext.existingObject(with: id), !obj.isDeleted {
                    self.viewContext.delete(obj)
                    self.save()
                }
            }
        }
    }

    /// Leaves a list someone else shared with you.
    func leaveShared(_ list: TaskList) {
        guard let share = (try? container.fetchShares(matching: [list.objectID]))?[list.objectID],
              let store = sharedStore else { return }
        container.purgeObjectsAndRecordsInZone(with: share.recordID.zoneID, in: store) { [log] _, error in
            if let error { log.error("Leaving share failed: \(error.localizedDescription)") }
        }
    }

    func participantSummary(for list: TaskList) -> String? {
        guard let share = existingShare(for: list) else { return nil }
        let others = share.participants.filter { $0 != share.currentUserParticipant }
        let names = others.compactMap { p -> String? in
            if let c = p.userIdentity.nameComponents {
                return PersonNameComponentsFormatter.localizedString(from: c, style: .short)
            }
            return p.userIdentity.lookupInfo?.emailAddress
        }
        return names.isEmpty ? nil : names.joined(separator: ", ")
    }
}
