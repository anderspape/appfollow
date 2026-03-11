import XCTest
@testable import FocusTimer

final class TaskLibraryStoreTests: XCTestCase {
    func testSaveAndLoadRoundTrip() {
        let (defaults, suiteName) = TestSettingsFactory.makeDefaultsSuite()
        defer { TestSettingsFactory.tearDownSuite(defaults: defaults, suiteName: suiteName) }

        let store = TaskLibraryStore(defaults: defaults)
        let templates = [
            TaskTemplate(
                title: "Laundry",
                emoji: "🧺",
                accentHex: "#A9D1D6",
                focusMinutes: 25,
                subTasks: [
                    FocusTask(emoji: "🧺", title: "Sort", durationMinutes: 10, accentHex: "#A9D1D6", isDone: false)
                ],
                subTaskTimersEnabled: true
            ),
            TaskTemplate(
                title: "Deep work",
                emoji: "💼",
                accentHex: "#89BDD0",
                focusMinutes: 45
            )
        ]

        store.save(templates)
        let loaded = store.load()

        XCTAssertEqual(loaded.count, 2)
        XCTAssertEqual(loaded[0].title, "Laundry")
        XCTAssertEqual(loaded[0].subTasks.count, 1)
        XCTAssertEqual(loaded[1].focusMinutes, 45)
    }

    func testLoadReturnsEmptyForMissingOrInvalidPayload() {
        let (defaults, suiteName) = TestSettingsFactory.makeDefaultsSuite()
        defer { TestSettingsFactory.tearDownSuite(defaults: defaults, suiteName: suiteName) }

        let store = TaskLibraryStore(defaults: defaults)
        XCTAssertTrue(store.load().isEmpty)

        defaults.set("{not valid json", forKey: "focus_timer.task_library.v1")
        XCTAssertTrue(store.load().isEmpty)
    }

    func testSaveAndLoadSavedPremadeIDsRoundTrip() {
        let (defaults, suiteName) = TestSettingsFactory.makeDefaultsSuite()
        defer { TestSettingsFactory.tearDownSuite(defaults: defaults, suiteName: suiteName) }

        let store = TaskLibraryStore(defaults: defaults)
        let ids: Set<String> = ["premade-work-deep-work", "premade-admin-inbox-zero"]

        store.saveSavedPremadeTemplateIDs(ids)
        let loaded = store.loadSavedPremadeTemplateIDs()

        XCTAssertEqual(loaded, ids)
    }

    func testCloudSnapshotNewerThanLocalReplacesLocalData() {
        let (defaults, suiteName) = TestSettingsFactory.makeDefaultsSuite()
        defer { TestSettingsFactory.tearDownSuite(defaults: defaults, suiteName: suiteName) }

        let cloud = MockTaskLibraryCloudSync()
        let store = TaskLibraryStore(defaults: defaults, cloudSync: cloud)

        let localTemplates = [
            TaskTemplate(title: "Local task", emoji: "💼", accentHex: "#89BDD0", focusMinutes: 25)
        ]
        store.save(localTemplates)

        let remoteTemplates = [
            TaskTemplate(title: "Cloud task", emoji: "🧺", accentHex: "#A9D1D6", focusMinutes: 40)
        ]
        let remoteIDs: Set<String> = ["premade-cloud-1"]

        let updatedExpectation = expectation(description: "Receives external cloud update")
        let fetchExpectation = expectation(description: "Cloud fetch requested")
        fetchExpectation.assertForOverFulfill = false
        cloud.onFetch = {
            fetchExpectation.fulfill()
        }
        store.onExternalLibraryChange = { templates, ids in
            XCTAssertEqual(templates.first?.title, "Cloud task")
            XCTAssertEqual(ids, remoteIDs)
            updatedExpectation.fulfill()
        }

        store.synchronizeFromCloudNow()
        wait(for: [fetchExpectation], timeout: 1.5)
        cloud.completeNextFetch(
            with: .success(
                TaskLibrarySyncSnapshot(
                    templates: remoteTemplates,
                    savedPremadeTemplateIDs: remoteIDs,
                    updatedAt: Date().addingTimeInterval(120)
                )
            )
        )

        wait(for: [updatedExpectation], timeout: 1.5)
        XCTAssertEqual(store.load().first?.title, "Cloud task")
        XCTAssertEqual(store.loadSavedPremadeTemplateIDs(), remoteIDs)
    }

    func testSavePushesSnapshotToCloudLayer() {
        let (defaults, suiteName) = TestSettingsFactory.makeDefaultsSuite()
        defer { TestSettingsFactory.tearDownSuite(defaults: defaults, suiteName: suiteName) }

        let cloud = MockTaskLibraryCloudSync()
        let store = TaskLibraryStore(defaults: defaults, cloudSync: cloud)

        let saveExpectation = expectation(description: "Cloud save invoked")
        cloud.onSave = { snapshot in
            if snapshot.templates.first?.title == "Push me" {
                saveExpectation.fulfill()
            }
        }

        store.save([TaskTemplate(title: "Push me", emoji: "📝", accentHex: "#6A66DA", focusMinutes: 20)])

        wait(for: [saveExpectation], timeout: 1.5)
    }

    func testRapidLibrarySavesAreCoalescedIntoSingleCloudPush() {
        let (defaults, suiteName) = TestSettingsFactory.makeDefaultsSuite()
        defer { TestSettingsFactory.tearDownSuite(defaults: defaults, suiteName: suiteName) }

        let cloud = MockTaskLibraryCloudSync()
        let store = TaskLibraryStore(defaults: defaults, cloudSync: cloud, cloudPushDebounceInterval: 0.2)
        let lock = NSLock()
        var pushedTitles: [String] = []

        let firstPushExpectation = expectation(description: "Cloud save invoked")
        cloud.onSave = { snapshot in
            let title = snapshot.templates.first?.title ?? ""
            lock.lock()
            pushedTitles.append(title)
            let shouldFulfill = pushedTitles.count == 1
            lock.unlock()
            if shouldFulfill {
                firstPushExpectation.fulfill()
            }
        }

        store.save([TaskTemplate(title: "First", emoji: "1️⃣", accentHex: "#89BDD0", focusMinutes: 15)])
        store.save([TaskTemplate(title: "Second", emoji: "2️⃣", accentHex: "#89BDD0", focusMinutes: 20)])
        store.save([TaskTemplate(title: "Final", emoji: "3️⃣", accentHex: "#89BDD0", focusMinutes: 25)])

        wait(for: [firstPushExpectation], timeout: 2.0)
        Thread.sleep(forTimeInterval: 0.45)

        lock.lock()
        let pushCount = pushedTitles.count
        let latest = pushedTitles.last
        lock.unlock()

        XCTAssertEqual(pushCount, 1)
        XCTAssertEqual(latest, "Final")
    }
}

private final class MockTaskLibraryCloudSync: TaskLibraryCloudSyncing {
    private var pendingFetchCompletions: [(Result<TaskLibrarySyncSnapshot?, Error>) -> Void] = []
    private let lock = NSLock()
    var onFetch: (() -> Void)?
    var onSave: ((TaskLibrarySyncSnapshot) -> Void)?

    func fetchSnapshot(completion: @escaping (Result<TaskLibrarySyncSnapshot?, Error>) -> Void) {
        lock.lock()
        pendingFetchCompletions.append(completion)
        lock.unlock()
        onFetch?()
    }

    func saveSnapshot(_ snapshot: TaskLibrarySyncSnapshot, completion: @escaping (Result<Void, Error>) -> Void) {
        onSave?(snapshot)
        completion(.success(()))
    }

    func completeNextFetch(with result: Result<TaskLibrarySyncSnapshot?, Error>) {
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
