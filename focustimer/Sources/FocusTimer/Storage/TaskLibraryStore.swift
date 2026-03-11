import Foundation

#if canImport(CloudKit)
import CloudKit
#endif

struct TaskLibrarySyncSnapshot: Equatable {
    var templates: [TaskTemplate]
    var savedPremadeTemplateIDs: Set<String>
    var updatedAt: Date

    var isEmpty: Bool {
        templates.isEmpty && savedPremadeTemplateIDs.isEmpty
    }
}

protocol TaskLibraryCloudSyncing {
    func fetchSnapshot(completion: @escaping (Result<TaskLibrarySyncSnapshot?, Error>) -> Void)
    func saveSnapshot(_ snapshot: TaskLibrarySyncSnapshot, completion: @escaping (Result<Void, Error>) -> Void)
}

final class TaskLibraryStore {
    private let defaults: UserDefaults
    private let cloudSync: TaskLibraryCloudSyncing?
    private let cloudPushDebounceInterval: TimeInterval
    private let storageKey = "focus_timer.task_library.v1"
    private let savedPremadeIDsKey = "focus_timer.task_library.saved_premade_ids.v1"
    private let updatedAtKey = "focus_timer.task_library.updated_at.v1"
    private let minCloudPullInterval: TimeInterval = 20

    private let cloudQueue = DispatchQueue(label: "focus_timer.task_library.cloud")
    private var lastCloudPullAt: Date?
    private var isCloudPushInFlight = false
    private var pendingCloudPushSnapshot: TaskLibrarySyncSnapshot?
    private var pendingCloudPushWorkItem: DispatchWorkItem?

    var onExternalLibraryChange: (([TaskTemplate], Set<String>) -> Void)?

    init(
        defaults: UserDefaults = .standard,
        cloudSync: TaskLibraryCloudSyncing? = nil,
        cloudPushDebounceInterval: TimeInterval = 0.45
    ) {
        self.defaults = defaults
        self.cloudPushDebounceInterval = max(0.05, cloudPushDebounceInterval)

        #if canImport(CloudKit)
        let defaultCloudSync: TaskLibraryCloudSyncing? = CloudSyncRuntime.isAppBundle ? CloudKitTaskLibrarySync() : nil
        #else
        let defaultCloudSync: TaskLibraryCloudSyncing? = nil
        #endif

        self.cloudSync = cloudSync ?? defaultCloudSync
        synchronizeFromCloudNow()
    }

    func load() -> [TaskTemplate] {
        synchronizeFromCloudIfNeeded()
        return localSnapshot().templates
    }

    func save(_ templates: [TaskTemplate]) {
        var snapshot = localSnapshot()
        snapshot.templates = templates
        snapshot.updatedAt = Date()
        persistLocalSnapshot(snapshot)
        pushSnapshotToCloud(snapshot)
    }

    func loadSavedPremadeTemplateIDs() -> Set<String> {
        synchronizeFromCloudIfNeeded()
        return localSnapshot().savedPremadeTemplateIDs
    }

    func saveSavedPremadeTemplateIDs(_ ids: Set<String>) {
        var snapshot = localSnapshot()
        snapshot.savedPremadeTemplateIDs = normalizedIDs(ids)
        snapshot.updatedAt = Date()
        persistLocalSnapshot(snapshot)
        pushSnapshotToCloud(snapshot)
    }

    func synchronizeFromCloudNow() {
        synchronizeFromCloud(force: true)
    }

    private func synchronizeFromCloudIfNeeded() {
        synchronizeFromCloud(force: false)
    }

    private func synchronizeFromCloud(force: Bool) {
        guard let cloudSync else { return }

        cloudQueue.async { [weak self] in
            guard let self else { return }

            let now = Date()
            if !force,
               let lastCloudPullAt,
               now.timeIntervalSince(lastCloudPullAt) < minCloudPullInterval
            {
                return
            }
            lastCloudPullAt = now

            cloudSync.fetchSnapshot { [weak self] result in
                guard let self else { return }
                switch result {
                case .success(let remoteSnapshot):
                    guard let remoteSnapshot else {
                        let local = self.localSnapshot()
                        if !local.isEmpty {
                            self.pushSnapshotToCloud(local)
                        }
                        return
                    }
                    self.mergeRemoteSnapshot(remoteSnapshot)
                case .failure:
                    break
                }
            }
        }
    }

    private func mergeRemoteSnapshot(_ remoteSnapshot: TaskLibrarySyncSnapshot) {
        let local = localSnapshot()
        let skewTolerance: TimeInterval = 0.5

        if remoteSnapshot.updatedAt.timeIntervalSince(local.updatedAt) > skewTolerance {
            persistLocalSnapshot(remoteSnapshot)
            DispatchQueue.main.async { [weak self] in
                self?.onExternalLibraryChange?(remoteSnapshot.templates, remoteSnapshot.savedPremadeTemplateIDs)
            }
            return
        }

        if local.updatedAt.timeIntervalSince(remoteSnapshot.updatedAt) > skewTolerance {
            pushSnapshotToCloud(local)
        }
    }

    private func localSnapshot() -> TaskLibrarySyncSnapshot {
        let templates = decodeTemplates(defaults.string(forKey: storageKey))
        let savedPremadeTemplateIDs = decodeSavedIDs(defaults.string(forKey: savedPremadeIDsKey))
        let updatedAt = storedUpdatedAt(fallbackTemplates: templates)

        return TaskLibrarySyncSnapshot(
            templates: templates,
            savedPremadeTemplateIDs: savedPremadeTemplateIDs,
            updatedAt: updatedAt
        )
    }

    private func storedUpdatedAt(fallbackTemplates: [TaskTemplate]) -> Date {
        if let timestamp = defaults.object(forKey: updatedAtKey) as? TimeInterval {
            return Date(timeIntervalSince1970: timestamp)
        }
        return fallbackTemplates.map(\.updatedAt).max() ?? .distantPast
    }

    private func persistLocalSnapshot(_ snapshot: TaskLibrarySyncSnapshot) {
        if let payload = encodeTemplates(snapshot.templates) {
            defaults.set(payload, forKey: storageKey)
        } else {
            defaults.removeObject(forKey: storageKey)
        }

        if let payload = encodeSavedIDs(snapshot.savedPremadeTemplateIDs) {
            defaults.set(payload, forKey: savedPremadeIDsKey)
        } else {
            defaults.removeObject(forKey: savedPremadeIDsKey)
        }

        defaults.set(snapshot.updatedAt.timeIntervalSince1970, forKey: updatedAtKey)
    }

    private func pushSnapshotToCloud(_ snapshot: TaskLibrarySyncSnapshot) {
        guard let cloudSync else { return }

        cloudQueue.async { [weak self] in
            guard let self else { return }
            self.pendingCloudPushSnapshot = snapshot
            self.scheduleCloudPushIfNeeded(cloudSync: cloudSync)
        }
    }

    private func scheduleCloudPushIfNeeded(cloudSync: TaskLibraryCloudSyncing) {
        pendingCloudPushWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.performCloudPushIfNeeded(cloudSync: cloudSync)
        }
        pendingCloudPushWorkItem = workItem
        cloudQueue.asyncAfter(deadline: .now() + cloudPushDebounceInterval, execute: workItem)
    }

    private func performCloudPushIfNeeded(cloudSync: TaskLibraryCloudSyncing) {
        guard !isCloudPushInFlight, let snapshot = pendingCloudPushSnapshot else { return }

        pendingCloudPushSnapshot = nil
        isCloudPushInFlight = true
        cloudSync.saveSnapshot(snapshot) { [weak self] _ in
            guard let self else { return }
            self.cloudQueue.async { [weak self] in
                guard let self else { return }
                self.isCloudPushInFlight = false
                if self.pendingCloudPushSnapshot != nil {
                    self.scheduleCloudPushIfNeeded(cloudSync: cloudSync)
                }
            }
        }
    }

    private func encodeTemplates(_ templates: [TaskTemplate]) -> String? {
        StorageJSONCodec.encode(templates)
    }

    private func decodeTemplates(_ payload: String?) -> [TaskTemplate] {
        StorageJSONCodec.decode([TaskTemplate].self, from: payload) ?? []
    }

    private func encodeSavedIDs(_ ids: Set<String>) -> String? {
        let normalized = Array(normalizedIDs(ids)).sorted()
        return StorageJSONCodec.encode(normalized)
    }

    private func decodeSavedIDs(_ payload: String?) -> Set<String> {
        let decoded = StorageJSONCodec.decode([String].self, from: payload) ?? []
        return normalizedIDs(Set(decoded))
    }

    private func normalizedIDs(_ ids: Set<String>) -> Set<String> {
        Set(ids.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })
    }
}

#if canImport(CloudKit)
private final class CloudKitTaskLibrarySync: TaskLibraryCloudSyncing {
    private let database: CKDatabase
    private let recordID = CKRecord.ID(recordName: "task-library")
    private let recordType = "FocusTimerTaskLibrary"
    private let templatesField = "templatesPayload"
    private let savedIDsField = "savedPremadeIDsPayload"
    private let updatedAtField = "updatedAt"

    init(container: CKContainer = .default()) {
        self.database = container.privateCloudDatabase
    }

    func fetchSnapshot(completion: @escaping (Result<TaskLibrarySyncSnapshot?, Error>) -> Void) {
        database.fetch(withRecordID: recordID) { [weak self] record, error in
            if let ckError = error as? CKError, ckError.code == .unknownItem {
                completion(.success(nil))
                return
            }

            if let error {
                completion(.failure(error))
                return
            }

            guard let self, let record else {
                completion(.success(nil))
                return
            }

            let templatesPayload = record[templatesField] as? String
            let savedIDsPayload = record[savedIDsField] as? String
            let updatedAt = (record[updatedAtField] as? Date) ?? .distantPast

            guard let templatesPayload,
                  let templates = StorageJSONCodec.decode([TaskTemplate].self, from: templatesPayload)
            else {
                completion(.success(nil))
                return
            }

            let savedIDs: Set<String>
            if let decoded: [String] = StorageJSONCodec.decode([String].self, from: savedIDsPayload) {
                savedIDs = Set(decoded.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })
            } else {
                savedIDs = []
            }

            completion(
                .success(
                    TaskLibrarySyncSnapshot(
                        templates: templates,
                        savedPremadeTemplateIDs: savedIDs,
                        updatedAt: updatedAt
                    )
                )
            )
        }
    }

    func saveSnapshot(_ snapshot: TaskLibrarySyncSnapshot, completion: @escaping (Result<Void, Error>) -> Void) {
        guard let templatesPayload = StorageJSONCodec.encode(snapshot.templates),
              let savedIDsPayload = StorageJSONCodec.encode(Array(snapshot.savedPremadeTemplateIDs).sorted())
        else {
            completion(.success(()))
            return
        }

        let record = CKRecord(recordType: recordType, recordID: recordID)
        record[templatesField] = templatesPayload as CKRecordValue
        record[savedIDsField] = savedIDsPayload as CKRecordValue
        record[updatedAtField] = snapshot.updatedAt as CKRecordValue

        let operation = CKModifyRecordsOperation(recordsToSave: [record], recordIDsToDelete: nil)
        operation.savePolicy = .changedKeys
        operation.modifyRecordsResultBlock = { result in
            switch result {
            case .success:
                completion(.success(()))
            case .failure(let error):
                completion(.failure(error))
            }
        }
        database.add(operation)
    }

}
#endif
