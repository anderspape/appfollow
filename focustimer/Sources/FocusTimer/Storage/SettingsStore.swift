import Foundation

#if canImport(CloudKit)
import CloudKit
#endif

struct SettingsSyncSnapshot: Equatable {
    var settings: FocusSettings
    var updatedAt: Date
}

protocol SettingsCloudSyncing {
    func fetchSnapshot(completion: @escaping (Result<SettingsSyncSnapshot?, Error>) -> Void)
    func saveSnapshot(_ snapshot: SettingsSyncSnapshot, completion: @escaping (Result<Void, Error>) -> Void)
}

final class SettingsStore {
    private let defaults: UserDefaults
    private let cloudSync: SettingsCloudSyncing?
    private let cloudPushDebounceInterval: TimeInterval
    private let storageKey = "focus_timer.settings.v1"
    private let updatedAtKey = "focus_timer.settings.updated_at.v1"
    private let minCloudPullInterval: TimeInterval = 20

    private let cloudQueue = DispatchQueue(label: "focus_timer.settings.cloud")
    private var lastCloudPullAt: Date?
    private var isCloudPushInFlight = false
    private var pendingCloudPushSnapshot: SettingsSyncSnapshot?
    private var pendingCloudPushWorkItem: DispatchWorkItem?

    var onExternalSettingsChange: ((FocusSettings) -> Void)?

    init(
        defaults: UserDefaults = .standard,
        cloudSync: SettingsCloudSyncing? = nil,
        cloudPushDebounceInterval: TimeInterval = 0.45
    ) {
        self.defaults = defaults
        self.cloudPushDebounceInterval = max(0.05, cloudPushDebounceInterval)

        #if canImport(CloudKit)
        let defaultCloudSync: SettingsCloudSyncing? = CloudSyncRuntime.isAppBundle ? CloudKitSettingsSync() : nil
        #else
        let defaultCloudSync: SettingsCloudSyncing? = nil
        #endif

        self.cloudSync = cloudSync ?? defaultCloudSync
        synchronizeFromCloudNow()
    }

    func load() -> FocusSettings {
        synchronizeFromCloudIfNeeded()

        if let local = readFromDefaults() {
            return local
        }

        save(.default)
        return .default
    }

    func save(_ settings: FocusSettings) {
        let snapshot = SettingsSyncSnapshot(settings: settings, updatedAt: Date())
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
                        if let localSnapshot = self.localSnapshotIfAvailable() {
                            self.pushSnapshotToCloud(localSnapshot)
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

    private func mergeRemoteSnapshot(_ remoteSnapshot: SettingsSyncSnapshot) {
        let local = localSnapshotIfAvailable()
        let skewTolerance: TimeInterval = 0.5

        if local == nil || remoteSnapshot.updatedAt.timeIntervalSince(local!.updatedAt) > skewTolerance {
            persistLocalSnapshot(remoteSnapshot)
            DispatchQueue.main.async { [weak self] in
                self?.onExternalSettingsChange?(remoteSnapshot.settings)
            }
            return
        }

        if let local, local.updatedAt.timeIntervalSince(remoteSnapshot.updatedAt) > skewTolerance {
            pushSnapshotToCloud(local)
        }
    }

    private func localSnapshotIfAvailable() -> SettingsSyncSnapshot? {
        guard let settings = readFromDefaults() else { return nil }
        let updatedAt = storedUpdatedAt() ?? .distantPast
        return SettingsSyncSnapshot(settings: settings, updatedAt: updatedAt)
    }

    private func storedUpdatedAt() -> Date? {
        guard let timestamp = defaults.object(forKey: updatedAtKey) as? TimeInterval else { return nil }
        return Date(timeIntervalSince1970: timestamp)
    }

    private func readFromDefaults() -> FocusSettings? {
        guard let payload = defaults.string(forKey: storageKey) else { return nil }
        return decode(payload)
    }

    private func persistLocalSnapshot(_ snapshot: SettingsSyncSnapshot) {
        guard let payload = encode(snapshot.settings) else { return }
        defaults.set(payload, forKey: storageKey)
        defaults.set(snapshot.updatedAt.timeIntervalSince1970, forKey: updatedAtKey)
    }

    private func pushSnapshotToCloud(_ snapshot: SettingsSyncSnapshot) {
        guard let cloudSync else { return }

        cloudQueue.async { [weak self] in
            guard let self else { return }
            self.pendingCloudPushSnapshot = snapshot
            self.scheduleCloudPushIfNeeded(cloudSync: cloudSync)
        }
    }

    private func scheduleCloudPushIfNeeded(cloudSync: SettingsCloudSyncing) {
        pendingCloudPushWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.performCloudPushIfNeeded(cloudSync: cloudSync)
        }
        pendingCloudPushWorkItem = workItem
        cloudQueue.asyncAfter(deadline: .now() + cloudPushDebounceInterval, execute: workItem)
    }

    private func performCloudPushIfNeeded(cloudSync: SettingsCloudSyncing) {
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

    private func encode(_ settings: FocusSettings) -> String? {
        StorageJSONCodec.encode(settings)
    }

    private func decode(_ payload: String) -> FocusSettings? {
        StorageJSONCodec.decode(FocusSettings.self, from: payload)
    }
}

#if canImport(CloudKit)
private final class CloudKitSettingsSync: SettingsCloudSyncing {
    private let database: CKDatabase
    private let recordID = CKRecord.ID(recordName: "settings")
    private let recordType = "FocusTimerSettings"
    private let settingsField = "settingsPayload"
    private let updatedAtField = "updatedAt"

    init(container: CKContainer = .default()) {
        self.database = container.privateCloudDatabase
    }

    func fetchSnapshot(completion: @escaping (Result<SettingsSyncSnapshot?, Error>) -> Void) {
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

            guard let payload = record[settingsField] as? String,
                  let settings = StorageJSONCodec.decode(FocusSettings.self, from: payload)
            else {
                completion(.success(nil))
                return
            }

            let updatedAt = (record[updatedAtField] as? Date) ?? .distantPast
            completion(.success(SettingsSyncSnapshot(settings: settings, updatedAt: updatedAt)))
        }
    }

    func saveSnapshot(_ snapshot: SettingsSyncSnapshot, completion: @escaping (Result<Void, Error>) -> Void) {
        guard let payload = StorageJSONCodec.encode(snapshot.settings)
        else {
            completion(.success(()))
            return
        }

        let record = CKRecord(recordType: recordType, recordID: recordID)
        record[settingsField] = payload as CKRecordValue
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
