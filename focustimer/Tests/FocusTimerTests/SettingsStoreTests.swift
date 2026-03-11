import XCTest
@testable import FocusTimer

final class SettingsStoreTests: XCTestCase {
    func testLoadReturnsDefaultAndPersistsWhenStoreIsEmpty() {
        let (store, defaults, suiteName) = TestSettingsFactory.makeSettingsStore()
        defer { TestSettingsFactory.tearDownSuite(defaults: defaults, suiteName: suiteName) }

        let loaded = store.load()

        XCTAssertEqual(loaded, .default)
        XCTAssertNotNil(defaults.string(forKey: TestSettingsFactory.storageKey))
    }

    func testSaveAndLoadRoundTrip() {
        let expected = FocusSettings(
            focusMinutes: 45,
            breakMinutes: 10,
            sessionTitle: "Deep Work",
            sessionEmoji: "💻",
            sessionAccentHex: "#89BDD0",
            subTasks: [
                FocusTask(emoji: "🧠", title: "Plan", durationMinutes: 10, accentHex: "#ECEBFC", isDone: false),
                FocusTask(emoji: "⌨️", title: "Execute", durationMinutes: 35, accentHex: "#ECEBFC", isDone: false)
            ],
            subTaskTimersEnabled: true
        )

        let (store, defaults, suiteName) = TestSettingsFactory.makeSettingsStore()
        defer { TestSettingsFactory.tearDownSuite(defaults: defaults, suiteName: suiteName) }

        store.save(expected)
        let loaded = store.load()

        XCTAssertEqual(loaded, expected)
    }

    func testLoadFallsBackToDefaultForCorruptedPayload() {
        let (store, defaults, suiteName) = TestSettingsFactory.makeSettingsStore()
        defer { TestSettingsFactory.tearDownSuite(defaults: defaults, suiteName: suiteName) }

        defaults.set("not-json", forKey: TestSettingsFactory.storageKey)

        let loaded = store.load()

        XCTAssertEqual(loaded, .default)
        XCTAssertNotEqual(defaults.string(forKey: TestSettingsFactory.storageKey), "not-json")
    }

    func testCloudSnapshotNewerThanLocalReplacesLocalData() {
        let (defaults, suiteName) = TestSettingsFactory.makeDefaultsSuite()
        defer { TestSettingsFactory.tearDownSuite(defaults: defaults, suiteName: suiteName) }

        let cloud = MockSettingsCloudSync()
        let store = SettingsStore(defaults: defaults, cloudSync: cloud)

        let local = FocusSettings(
            focusMinutes: 20,
            breakMinutes: 5,
            sessionTitle: "Local",
            sessionEmoji: "💻",
            sessionAccentHex: "#89BDD0",
            subTasks: [],
            subTaskTimersEnabled: false
        )
        store.save(local)

        let remote = FocusSettings(
            focusMinutes: 30,
            breakMinutes: 10,
            sessionTitle: "Cloud",
            sessionEmoji: "🧺",
            sessionAccentHex: "#A9D1D6",
            subTasks: [],
            subTaskTimersEnabled: false
        )

        let fetchExpectation = expectation(description: "Cloud fetch requested")
        fetchExpectation.assertForOverFulfill = false
        cloud.onFetch = {
            fetchExpectation.fulfill()
        }

        let updateExpectation = expectation(description: "External settings callback invoked")
        store.onExternalSettingsChange = { settings in
            XCTAssertEqual(settings.sessionTitle, "Cloud")
            updateExpectation.fulfill()
        }

        store.synchronizeFromCloudNow()
        wait(for: [fetchExpectation], timeout: 1.5)
        cloud.completeNextFetch(
            with: .success(
                SettingsSyncSnapshot(
                    settings: remote,
                    updatedAt: Date().addingTimeInterval(120)
                )
            )
        )

        wait(for: [updateExpectation], timeout: 1.5)
        XCTAssertEqual(store.load().sessionTitle, "Cloud")
    }

    func testSavePushesSettingsSnapshotToCloudLayer() {
        let (defaults, suiteName) = TestSettingsFactory.makeDefaultsSuite()
        defer { TestSettingsFactory.tearDownSuite(defaults: defaults, suiteName: suiteName) }

        let cloud = MockSettingsCloudSync()
        let store = SettingsStore(defaults: defaults, cloudSync: cloud)

        let saveExpectation = expectation(description: "Cloud save invoked")
        cloud.onSave = { snapshot in
            if snapshot.settings.sessionTitle == "Push me" {
                saveExpectation.fulfill()
            }
        }

        store.save(
            FocusSettings(
                focusMinutes: 40,
                breakMinutes: 8,
                sessionTitle: "Push me",
                sessionEmoji: "📝",
                sessionAccentHex: "#6A66DA",
                subTasks: [],
                subTaskTimersEnabled: false
            )
        )

        wait(for: [saveExpectation], timeout: 1.5)
    }

    func testRapidSavesAreCoalescedIntoSingleCloudPush() {
        let (defaults, suiteName) = TestSettingsFactory.makeDefaultsSuite()
        defer { TestSettingsFactory.tearDownSuite(defaults: defaults, suiteName: suiteName) }

        let cloud = MockSettingsCloudSync()
        let store = SettingsStore(defaults: defaults, cloudSync: cloud, cloudPushDebounceInterval: 0.2)
        let lock = NSLock()
        var savedTitles: [String] = []

        let firstSaveExpectation = expectation(description: "Cloud save invoked")
        cloud.onSave = { snapshot in
            lock.lock()
            savedTitles.append(snapshot.settings.sessionTitle)
            let shouldFulfill = savedTitles.count == 1
            lock.unlock()
            if shouldFulfill {
                firstSaveExpectation.fulfill()
            }
        }

        store.save(Self.settings(title: "First"))
        store.save(Self.settings(title: "Second"))
        store.save(Self.settings(title: "Final"))

        wait(for: [firstSaveExpectation], timeout: 2.0)
        Thread.sleep(forTimeInterval: 0.45)

        lock.lock()
        let recordedCount = savedTitles.count
        let latestTitle = savedTitles.last
        lock.unlock()

        XCTAssertEqual(recordedCount, 1)
        XCTAssertEqual(latestTitle, "Final")
    }

    func testOlderCloudSnapshotKeepsLocalAndRepushesLocalState() {
        let (defaults, suiteName) = TestSettingsFactory.makeDefaultsSuite()
        defer { TestSettingsFactory.tearDownSuite(defaults: defaults, suiteName: suiteName) }

        let cloud = MockSettingsCloudSync()
        let store = SettingsStore(defaults: defaults, cloudSync: cloud, cloudPushDebounceInterval: 0.1)
        let local = Self.settings(title: "Local latest")
        store.save(local)

        let fetchExpectation = expectation(description: "Cloud fetch requested")
        cloud.onFetch = {
            fetchExpectation.fulfill()
        }

        let repushExpectation = expectation(description: "Local snapshot pushed back to cloud")
        cloud.onSave = { snapshot in
            if snapshot.settings.sessionTitle == "Local latest" {
                repushExpectation.fulfill()
            }
        }

        store.synchronizeFromCloudNow()
        wait(for: [fetchExpectation], timeout: 1.5)
        cloud.completeNextFetch(
            with: .success(
                SettingsSyncSnapshot(
                    settings: Self.settings(title: "Remote stale"),
                    updatedAt: Date().addingTimeInterval(-120)
                )
            )
        )

        wait(for: [repushExpectation], timeout: 1.5)
        XCTAssertEqual(store.load().sessionTitle, "Local latest")
    }

    private static func settings(title: String) -> FocusSettings {
        FocusSettings(
            focusMinutes: 40,
            breakMinutes: 8,
            sessionTitle: title,
            sessionEmoji: "📝",
            sessionAccentHex: "#6A66DA",
            subTasks: [],
            subTaskTimersEnabled: false
        )
    }
}

private final class MockSettingsCloudSync: SettingsCloudSyncing {
    private var pendingFetchCompletions: [(Result<SettingsSyncSnapshot?, Error>) -> Void] = []
    private let lock = NSLock()
    var onFetch: (() -> Void)?
    var onSave: ((SettingsSyncSnapshot) -> Void)?

    func fetchSnapshot(completion: @escaping (Result<SettingsSyncSnapshot?, Error>) -> Void) {
        lock.lock()
        pendingFetchCompletions.append(completion)
        lock.unlock()
        onFetch?()
    }

    func saveSnapshot(_ snapshot: SettingsSyncSnapshot, completion: @escaping (Result<Void, Error>) -> Void) {
        onSave?(snapshot)
        completion(.success(()))
    }

    func completeNextFetch(with result: Result<SettingsSyncSnapshot?, Error>) {
        lock.lock()
        guard !pendingFetchCompletions.isEmpty else {
            lock.unlock()
            return
        }
        let completion = pendingFetchCompletions.removeFirst()
        lock.unlock()
        completion(result)
    }
}
