import Flutter
import UIKit
import XCTest
@testable import Runner

class RunnerTests: XCTestCase {
  private var directory: URL!

  override func setUpWithError() throws {
    directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("setflow-lock-test-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    LockScreenWorkoutStore.containerURLOverride = directory
  }

  override func tearDownWithError() throws {
    LockScreenWorkoutStore.containerURLOverride = nil
    try FileManager.default.removeItem(at: directory)
  }

  func testCompletionPersistsActualValuesBeforeAdvancing() throws {
    try LockScreenWorkoutStore.publish(projection())
    try LockScreenWorkoutStore.complete(sessionId: "session-1", token: "set-1")
    let event = try XCTUnwrap(LockScreenWorkoutStore.readEvents().first)
    XCTAssertEqual(event["ownerKey"] as? String, "account-1")
    let set = try XCTUnwrap(event["set"] as? [String: Any])
    XCTAssertEqual(set["weight"] as? Double, 40)
    XCTAssertEqual(set["reps"] as? Int, 10)
    XCTAssertEqual(set["fingerprint"] as? String, "set-1")
    let restored = try LockScreenWorkoutStore.readState()
    XCTAssertEqual(LockScreenWorkoutStore.currentSet(in: restored)?["token"] as? String, "set-2")
    XCTAssertGreaterThan(LockScreenWorkoutStore.number(restored["restEndsAtMillis"]),
                         LockScreenWorkoutStore.nowMillis)
    XCTAssertEqual(LockScreenWorkoutStore.number(event["restEndsAtMillis"]),
                   LockScreenWorkoutStore.number(restored["restEndsAtMillis"]))
  }

  func testDuplicateAndOutOfOrderActionsNeverToggleOrSkipSets() throws {
    try LockScreenWorkoutStore.publish(projection())
    XCTAssertThrowsError(try LockScreenWorkoutStore.complete(sessionId: "session-1", token: "set-2"))
    try LockScreenWorkoutStore.complete(sessionId: "session-1", token: "set-1")
    try LockScreenWorkoutStore.complete(sessionId: "session-1", token: "set-1")
    XCTAssertEqual(try LockScreenWorkoutStore.readEvents().count, 1)
    let current = LockScreenWorkoutStore.currentSet(in: try LockScreenWorkoutStore.readState())
    XCTAssertEqual(current?["token"] as? String, "set-2")
  }

  func testLogoutRemovesTheActionButKeepsUnacknowledgedPerformedRecords() throws {
    try LockScreenWorkoutStore.publish(projection())
    try LockScreenWorkoutStore.complete(sessionId: "session-1", token: "set-1")
    try LockScreenWorkoutStore.clear()
    XCTAssertNil(LockScreenWorkoutStore.currentSet(in: try LockScreenWorkoutStore.readState()))
    XCTAssertThrowsError(try LockScreenWorkoutStore.complete(sessionId: "session-1", token: "set-2"))
    XCTAssertEqual(try LockScreenWorkoutStore.readEvents().count, 1)
    let eventId = try XCTUnwrap(try LockScreenWorkoutStore.readEvents().first?["eventId"] as? String)
    try LockScreenWorkoutStore.acknowledge([eventId])
    XCTAssertTrue(try LockScreenWorkoutStore.readEvents().isEmpty)
  }

  func testChangedSessionCannotReuseAnOldNotificationAction() throws {
    try LockScreenWorkoutStore.publish(projection())
    var next = projection()
    next["sessionId"] = "session-2"
    next["ownerKey"] = "account-2"
    try LockScreenWorkoutStore.publish(next)
    XCTAssertThrowsError(try LockScreenWorkoutStore.complete(sessionId: "session-1", token: "set-1"))
    XCTAssertTrue(try LockScreenWorkoutStore.readEvents().isEmpty)
  }

  func testMissingInputsNeverBecomePerformedSets() throws {
    var blocked = projection()
    var sets = blocked["sets"] as! [[String: Any]]
    sets[0]["canComplete"] = false
    blocked["sets"] = sets
    try LockScreenWorkoutStore.publish(blocked)
    XCTAssertThrowsError(try LockScreenWorkoutStore.complete(sessionId: "session-1", token: "set-1"))
    XCTAssertTrue(try LockScreenWorkoutStore.readEvents().isEmpty)
  }

  func testGuestOwnershipIsStableAcrossReadsAndClear() throws {
    let owner = try LockScreenWorkoutStore.guestOwnerKey()
    try LockScreenWorkoutStore.clear()
    XCTAssertEqual(try LockScreenWorkoutStore.guestOwnerKey(), owner)
  }

  func testUnacknowledgedCommitPreventsAStaleProjectionFromReplacingIt() throws {
    try LockScreenWorkoutStore.publish(projection())
    try LockScreenWorkoutStore.complete(sessionId: "session-1", token: "set-1")
    var replacement = projection()
    replacement["sessionId"] = "replacement"
    XCTAssertFalse(try LockScreenWorkoutStore.publish(replacement))
    let preserved = try LockScreenWorkoutStore.readState()["projection"] as? [String: Any]
    XCTAssertEqual(preserved?["sessionId"] as? String, "session-1")
    replacement["ownerKey"] = "account-2"
    XCTAssertTrue(try LockScreenWorkoutStore.publish(replacement))
    XCTAssertEqual(try LockScreenWorkoutStore.readEvents().count, 1)
  }

  private func projection() -> [String: Any] {
    [
      "schemaVersion": 1, "sessionId": "session-1", "ownerKey": "account-1",
      "workoutDate": "2026-10-27", "publishedAtMillis": LockScreenWorkoutStore.nowMillis,
      "expiresAtMillis": LockScreenWorkoutStore.nowMillis + 600_000,
      "autoStartRestTimer": true,
      "sets": [1, 2].map { index -> [String: Any] in
        ["token": "set-\(index)", "exerciseEntryId": "bench-entry", "templateId": "bench",
         "exerciseName": "벤치 프레스", "setNumber": index, "setTotal": 2,
         "measurement": "weightReps", "valuesLabel": "40kg × 10회", "weight": 40.0,
         "reps": 10, "durationSeconds": 0, "distanceKm": 0.0, "intensityRpe": 0.0,
         "rir": NSNull(), "type": "일반", "restSeconds": 90,
         "fingerprint": "set-\(index)", "canComplete": true]
      },
    ]
  }
}
