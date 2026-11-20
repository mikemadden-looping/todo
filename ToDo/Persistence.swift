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

    func share(_ list: TaskList) async throws -> (CKShare, CKContainer) {
        if let share = existingShare(for: list) { return (share, ckContainer) }
        let (_, share, ck) = try await container.share([list], to: nil)
        share[CKShare.SystemFieldKey.title] = list.displayName as CKRecordValue
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

    func purgeShare(_ share: CKShare) {
        guard let store = privateStore else { return }
        container.purgeObjectsAndRecordsInZone(with: share.recordID.zoneID, in: store) { [log] _, error in
            if let error { log.error("Purging share failed: \(error.localizedDescription)") }
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
