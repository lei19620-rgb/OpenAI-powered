import SwiftData
import XCTest
@testable import SimpleStudy

@MainActor
final class AlarmManagementTests: XCTestCase {
    private func alarm(id: UUID = UUID()) -> SystemAlarmSnapshot {
        .init(id: id, state: .scheduled, fireDate: Date().addingTimeInterval(3600))
    }

    private func todo(in context: ModelContext) throws -> TodoRecord {
        let todo = TodoRecord(title: "Scheduled reminder", triggerKind: .scheduledTime,
                              scheduledAt: Date().addingTimeInterval(3600))
        var action = TodoAction(kind: .scheduleAlarm, phase: .activation,
                                parameters: .init(alarmTarget: .allAuthorizedDevices))
        action.state = .succeeded
        todo.actions = [action]
        context.insert(todo)
        try context.save()
        return todo
    }

    private func register(_ alarm: SystemAlarmSnapshot, todo: TodoRecord, in context: ModelContext,
                          deviceID: String? = nil) throws -> AlarmRegistrationRecord {
        let record = AlarmRegistrationRecord(todoID: todo.id, deviceID: deviceID ?? DeviceIdentity.id, deviceKind: "iPhone",
                                             fireDate: todo.originalScheduledAt)
        record.alarmID = alarm.id
        record.state = .scheduled
        todo.alarmState = .scheduled
        context.insert(record)
        try context.save()
        return record
    }

    func testMissingRegistrationIsVisibleAndCanCancelOnlyThatAlarm() async throws {
        let first = alarm(), second = alarm()
        let client = FakeSystemAlarmClient([first, second])
        let engine = TodoActionEngine(alarmClient: client)
        engine.refreshAlarmInventory()
        let rows = ManagedAlarm.rows(system: engine.systemAlarms, registrations: [], todos: [],
                                     deviceID: DeviceIdentity.id, inventoryIsCurrent: true)
        XCTAssertEqual(rows.count, 2)
        XCTAssertTrue(rows.allSatisfy { $0.isRecovered && $0.canCancel })
        XCTAssertTrue(rows.allSatisfy { $0.statusDescription == "Scheduled" })
        try await engine.cancelRecoveredAlarm(id: first.id)
        XCTAssertEqual(client.cancelledIDs, [first.id])
        XCTAssertEqual(engine.systemAlarms.map(\.id), [second.id])
    }

    func testExactIDMatchMakesOldDeviceRecordLocalAndCancellable() async throws {
        let persistence = PersistenceController(inMemory: true)
        let context = persistence.container.mainContext
        let todo = try todo(in: context), system = alarm()
        let record = try register(system, todo: todo, in: context, deviceID: "old-device-id")
        let client = FakeSystemAlarmClient([system])
        let engine = TodoActionEngine(alarmClient: client)
        let rows = ManagedAlarm.rows(system: [system], registrations: [record], todos: [todo],
                                     deviceID: DeviceIdentity.id, inventoryIsCurrent: true)
        XCTAssertEqual(rows.count, 1)
        XCTAssertTrue(rows[0].canCancel)
        XCTAssertEqual(rows[0].title, todo.title)
        try await engine.cancelAlarmRegistration(record, context: context)
        XCTAssertEqual(record.deviceID, DeviceIdentity.id)
        XCTAssertEqual(record.state, .stopped)
        XCTAssertNotEqual(todo.storedState, .completed)
        XCTAssertTrue(todo.actions[0].isEnabled)
    }

    func testRefreshFailureKeepsPreviousInventoryAndReportsError() {
        let system = alarm(), client = FakeSystemAlarmClient()
        client.inventory = [system]
        let engine = TodoActionEngine(alarmClient: client)
        engine.refreshAlarmInventory()
        client.readError = TestAlarmError.readFailed
        engine.refreshAlarmInventory()
        XCTAssertEqual(engine.systemAlarms, [system])
        XCTAssertNotNil(engine.alarmRefreshError)
        XCTAssertTrue(client.cancelledIDs.isEmpty)
        XCTAssertTrue(client.scheduledIDs.isEmpty)
    }

    func testLiveAlarmOverridesStaleStoppedRecord() throws {
        let persistence = PersistenceController(inMemory: true)
        let context = persistence.container.mainContext
        let todo = try todo(in: context), system = alarm()
        let record = try register(system, todo: todo, in: context)
        record.state = .stopped
        let rows = ManagedAlarm.rows(system: [system], registrations: [record], todos: [todo],
                                     deviceID: DeviceIdentity.id, inventoryIsCurrent: true)
        XCTAssertEqual(rows.count, 1)
        XCTAssertTrue(rows[0].canCancel)
        XCTAssertEqual(rows[0].state, .scheduled)
        XCTAssertEqual(rows[0].timeDescription, system.timeDescription)
    }

    func testUnverifiedStoppedRecordStillOffersCancellation() throws {
        let persistence = PersistenceController(inMemory: true)
        let context = persistence.container.mainContext
        let todo = try todo(in: context)
        let record = try register(alarm(), todo: todo, in: context)
        record.state = .stopped
        let rows = ManagedAlarm.rows(system: [], registrations: [record], todos: [todo],
                                     deviceID: DeviceIdentity.id, inventoryIsCurrent: false)
        XCTAssertTrue(rows[0].canCancel)
        XCTAssertEqual(rows[0].statusDescription, "Needs verification")
    }

    func testConfirmedMissingSystemAlarmBecomesHistory() throws {
        let persistence = PersistenceController(inMemory: true)
        let context = persistence.container.mainContext
        let todo = try todo(in: context)
        let record = try register(alarm(), todo: todo, in: context)
        let rows = ManagedAlarm.rows(system: [], registrations: [record], todos: [todo],
                                     deviceID: DeviceIdentity.id, inventoryIsCurrent: true)
        XCTAssertFalse(rows[0].canCancel)
        XCTAssertEqual(rows[0].state, .stopped)
        XCTAssertEqual(rows[0].statusDescription, "Stopped")
        record.state = .permissionDenied
        let failed = ManagedAlarm.rows(system: [], registrations: [record], todos: [todo],
                                       deviceID: DeviceIdentity.id, inventoryIsCurrent: true)
        XCTAssertFalse(failed[0].canCancel)
        XCTAssertEqual(failed[0].state, .permissionDenied)
    }

    func testBackgroundReadFailureDoesNotMarkAlarmStopped() async throws {
        let persistence = PersistenceController(inMemory: true)
        let context = persistence.container.mainContext
        let todo = try todo(in: context)
        let record = try register(alarm(), todo: todo, in: context)
        let client = FakeSystemAlarmClient()
        client.readError = TestAlarmError.readFailed
        let engine = TodoActionEngine(alarmClient: client)
        await engine.processPendingDeviceAlarms(context: context)
        XCTAssertEqual(record.state, .scheduled)
        XCTAssertEqual(todo.alarmState, .scheduled)
        XCTAssertTrue(client.scheduledIDs.isEmpty)
        XCTAssertTrue(client.cancelledIDs.isEmpty)
        XCTAssertNotNil(engine.alarmRefreshError)
    }

    func testCancelAndReadFailureDoesNotReportStopped() async throws {
        let persistence = PersistenceController(inMemory: true)
        let context = persistence.container.mainContext
        let todo = try todo(in: context), system = alarm()
        let record = try register(system, todo: todo, in: context)
        let client = FakeSystemAlarmClient([system])
        client.cancelError = TestAlarmError.cancelFailed
        client.readError = TestAlarmError.readFailed
        let engine = TodoActionEngine(alarmClient: client)
        do {
            try await engine.cancelAlarmRegistration(record, context: context)
            XCTFail("Unconfirmed cancellation must throw")
        } catch {}
        XCTAssertEqual(record.state, .scheduled)
        XCTAssertEqual(todo.alarmState, .scheduled)
        XCTAssertEqual(client.inventory, [system])
        XCTAssertFalse(engine.isRunning)
    }

    func testSuccessfulCancelCallStillRequiresSystemAbsence() async throws {
        let persistence = PersistenceController(inMemory: true)
        let context = persistence.container.mainContext
        let todo = try todo(in: context), system = alarm()
        let record = try register(system, todo: todo, in: context)
        let client = FakeSystemAlarmClient([system])
        client.keepsAlarmOnCancel = true
        let engine = TodoActionEngine(alarmClient: client)
        do {
            try await engine.cancelAlarmRegistration(record, context: context)
            XCTFail("Still-present alarm must not be marked stopped")
        } catch {}
        XCTAssertEqual(record.state, .scheduled)
        XCTAssertEqual(engine.systemAlarms, [system])
    }

    func testAlreadyAbsentAlarmCancellationIsIdempotent() async throws {
        let persistence = PersistenceController(inMemory: true)
        let context = persistence.container.mainContext
        let todo = try todo(in: context)
        let record = try register(alarm(), todo: todo, in: context)
        let client = FakeSystemAlarmClient()
        client.cancelError = TestAlarmError.cancelFailed
        let engine = TodoActionEngine(alarmClient: client)
        try await engine.cancelAlarmRegistration(record, context: context)
        try await engine.cancelAlarmRegistration(record, context: context)
        XCTAssertEqual(record.state, .stopped)
    }

    func testMissingTodoDoesNotSilentlyCancelExistingAlarm() async throws {
        let persistence = PersistenceController(inMemory: true)
        let context = persistence.container.mainContext
        let system = alarm()
        let record = AlarmRegistrationRecord(todoID: UUID(), deviceID: DeviceIdentity.id,
                                             deviceKind: "iPhone", fireDate: system.fireDate!)
        record.alarmID = system.id
        record.state = .scheduled
        context.insert(record)
        try context.save()
        let client = FakeSystemAlarmClient([system])
        let engine = TodoActionEngine(alarmClient: client)
        await engine.processPendingDeviceAlarms(context: context)
        XCTAssertTrue(client.cancelledIDs.isEmpty)
        XCTAssertEqual(record.state, .scheduled)
    }

    func testRepeatedManagementRefreshHasNoSideEffects() {
        let client = FakeSystemAlarmClient([alarm()])
        let engine = TodoActionEngine(alarmClient: client)
        for _ in 0..<5 { engine.refreshAlarmInventory() }
        XCTAssertTrue(client.cancelledIDs.isEmpty)
        XCTAssertTrue(client.scheduledIDs.isEmpty)
        XCTAssertEqual(engine.systemAlarms.count, 1)
    }

    func testSchedulePersistsIDBeforeCallingSystemAndRetryReusesIt() async throws {
        let persistence = PersistenceController(inMemory: true)
        let context = persistence.container.mainContext
        let todo = try todo(in: context)
        var actions = todo.actions
        actions[0].state = .pending
        todo.actions = actions
        try context.save()
        let client = FakeSystemAlarmClient()
        client.beforeSchedule = { id in
            let readContext = ModelContext(persistence.container)
            let stored = try readContext.fetch(FetchDescriptor<AlarmRegistrationRecord>())
            XCTAssertEqual(stored.first?.alarmID, id)
            XCTAssertFalse(context.hasChanges)
        }
        let engine = TodoActionEngine(alarmClient: client)
        await engine.prepareScheduledActions(todo: todo, context: context)
        XCTAssertEqual(client.scheduledIDs.count, 1)
        actions = todo.actions
        actions[0].state = .failed
        todo.actions = actions
        try context.save()
        await engine.prepareScheduledActions(todo: todo, context: context)
        XCTAssertEqual(client.scheduledIDs.count, 1)
        XCTAssertEqual(todo.actions[0].state, .succeeded)
    }

    func testSystemSuccessWithLostResponseDoesNotCreateDuplicateOnRetry() async throws {
        let persistence = PersistenceController(inMemory: true)
        let context = persistence.container.mainContext
        let todo = try todo(in: context)
        var actions = todo.actions
        actions[0].state = .pending
        todo.actions = actions
        try context.save()
        let client = FakeSystemAlarmClient()
        client.throwAfterSchedule = true
        let engine = TodoActionEngine(alarmClient: client)
        await engine.prepareScheduledActions(todo: todo, context: context)
        XCTAssertEqual(todo.actions[0].state, .failed)
        await engine.prepareScheduledActions(todo: todo, context: context)
        XCTAssertEqual(client.scheduledIDs.count, 1)
        XCTAssertEqual(todo.actions[0].state, .succeeded)
        XCTAssertEqual(todo.alarmState, .scheduled)
    }

    func testCancelledAlarmIsNotRecreatedOnForeground() async throws {
        let persistence = PersistenceController(inMemory: true)
        let context = persistence.container.mainContext
        let todo = try todo(in: context), system = alarm()
        let record = try register(system, todo: todo, in: context)
        let client = FakeSystemAlarmClient([system])
        let engine = TodoActionEngine(alarmClient: client)
        try await engine.cancelAlarmRegistration(record, context: context)
        await engine.processPendingDeviceAlarms(context: context)
        await engine.processPendingDeviceAlarms(context: context)
        XCTAssertTrue(client.scheduledIDs.isEmpty)
        XCTAssertEqual(record.state, .stopped)
    }

    func testDeleteFailureRetainsTodoAndAlarmID() async throws {
        let persistence = PersistenceController(inMemory: true)
        let context = persistence.container.mainContext
        let todo = try todo(in: context), system = alarm()
        let record = try register(system, todo: todo, in: context)
        let client = FakeSystemAlarmClient([system])
        client.cancelError = TestAlarmError.cancelFailed
        let engine = TodoActionEngine(alarmClient: client)
        do { try await engine.delete(todo: todo, context: context); XCTFail("Must preserve records") }
        catch {}
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<TodoRecord>()), 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<AlarmRegistrationRecord>()), 1)
        XCTAssertEqual(record.alarmID, system.id)
    }

    func testEditCleanupFailureRetainsAlarmIDAndBlocksReplacement() async throws {
        let persistence = PersistenceController(inMemory: true)
        let context = persistence.container.mainContext
        let todo = try todo(in: context), system = alarm()
        let record = try register(system, todo: todo, in: context)
        let client = FakeSystemAlarmClient([system])
        client.cancelError = TestAlarmError.cancelFailed
        let engine = TodoActionEngine(alarmClient: client)
        let success = await engine.cancelScheduledEffects(todoID: todo.id, context: context)
        XCTAssertFalse(success)
        XCTAssertEqual(record.alarmID, system.id)
        XCTAssertEqual(record.state, .scheduled)
        XCTAssertTrue(client.scheduledIDs.isEmpty)
        XCTAssertNotNil(engine.operationError)
    }

    func testDifferentIDOnOtherDeviceCannotBeCancelledByMatchingTime() async throws {
        let persistence = PersistenceController(inMemory: true)
        let context = persistence.container.mainContext
        let todo = try todo(in: context), system = alarm()
        let record = try register(alarm(), todo: todo, in: context, deviceID: "other-device")
        let client = FakeSystemAlarmClient([system])
        let engine = TodoActionEngine(alarmClient: client)
        do { try await engine.cancelAlarmRegistration(record, context: context); XCTFail("Not a local alarm") }
        catch {}
        XCTAssertTrue(client.cancelledIDs.isEmpty)
        XCTAssertEqual(record.state, .scheduled)
    }

    func testForegroundReconcilesOldDeviceIDWithoutSchedulingDuplicate() async throws {
        let persistence = PersistenceController(inMemory: true)
        let context = persistence.container.mainContext
        let todo = try todo(in: context), system = alarm()
        let record = try register(system, todo: todo, in: context, deviceID: "before-restore")
        let client = FakeSystemAlarmClient([system])
        let engine = TodoActionEngine(alarmClient: client)
        await engine.processPendingDeviceAlarms(context: context)
        XCTAssertEqual(record.deviceID, DeviceIdentity.id)
        XCTAssertTrue(client.scheduledIDs.isEmpty)
        XCTAssertTrue(client.cancelledIDs.isEmpty)
    }
}

private enum TestAlarmError: Error { case readFailed, cancelFailed, responseLost }

@MainActor
private final class FakeSystemAlarmClient: SystemAlarmClient {
    var inventory: [SystemAlarmSnapshot]
    var readError: Error?
    var cancelError: Error?
    var keepsAlarmOnCancel = false
    var throwAfterSchedule = false
    var beforeSchedule: ((UUID) throws -> Void)?
    var cancelledIDs: [UUID] = []
    var scheduledIDs: [UUID] = []

    init(_ inventory: [SystemAlarmSnapshot] = []) { self.inventory = inventory }
    func alarms() throws -> [SystemAlarmSnapshot] {
        if let readError { throw readError }
        return inventory
    }
    func cancel(id: UUID) throws {
        cancelledIDs.append(id)
        if let cancelError { throw cancelError }
        if !keepsAlarmOnCancel { inventory.removeAll { $0.id == id } }
    }
    func schedule(id: UUID, todo: TodoRecord, target: AlarmTarget, targetDeviceID: String?, fireDate: Date) async throws {
        try beforeSchedule?(id)
        scheduledIDs.append(id)
        inventory.append(.init(id: id, state: .scheduled, fireDate: fireDate))
        if throwAfterSchedule { throw TestAlarmError.responseLost }
    }
}
