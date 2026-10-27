import Foundation
import Darwin

/// Device-local performed records. The Flutter repository remains the owner of
/// the workout snapshot; this journal survives until that repository acks it.
enum LockScreenWorkoutStore {
  static let appGroup = "group.com.teampara.setflow"
  private static let fileName = "lock-screen-workout-v1.json"
  private static let maximumEvents = 2048
  // An internal file-system seam for native unit tests; never populated by UI.
  static var containerURLOverride: URL?

  private static var containerURL: URL? {
    containerURLOverride ?? FileManager.default.containerURL(
      forSecurityApplicationGroupIdentifier: appGroup
    )
  }

  enum StoreError: LocalizedError {
    case unavailable, invalidProjection, stale, journalFull
    var errorDescription: String? {
      switch self {
      case .unavailable: return "잠금화면에서 기록할 수 없습니다. 앱에서 확인해 주세요."
      case .invalidProjection: return "앱에서 운동 기록을 다시 열어 주세요."
      case .stale: return "운동 기록이 변경됐습니다. 앱에서 확인해 주세요."
      case .journalFull: return "앱을 열어 저장한 운동 기록을 동기화해 주세요."
      }
    }
  }

  static var available: Bool {
    containerURL != nil
  }

  static func guestOwnerKey() throws -> String {
    try transaction { state in
      if let existing = state["guestOwnerKey"] as? String { return existing }
      let key = "guest_\(UUID().uuidString.lowercased())"
      state["guestOwnerKey"] = key
      return key
    }
  }

  @discardableResult
  static func publish(_ projection: [String: Any]) throws -> Bool {
    guard number(projection["schemaVersion"]) == 1,
          let sessionId = projection["sessionId"] as? String, !sessionId.isEmpty,
          let owner = projection["ownerKey"] as? String, !owner.isEmpty,
          let sets = projection["sets"] as? [[String: Any]], sets.count <= 200,
          number(projection["expiresAtMillis"]) > nowMillis else {
      throw StoreError.invalidProjection
    }
    return try transaction { state in
      let pending = state["events"] as? [[String: Any]] ?? []
      // An intent can commit between Dart's read and publish calls. Keep the
      // authoritative projection until Dart has durably imported and acked it.
      if pending.contains(where: { $0["ownerKey"] as? String == owner }) { return false }
      let previous = state["projection"] as? [String: Any]
      if previous?["sessionId"] as? String != sessionId ||
          previous?["ownerKey"] as? String != owner {
        state["completedTokens"] = [String]()
        state["restEndsAtMillis"] = 0
      }
      state["projection"] = projection
      if let restEndsAt = projection["restEndsAtMillis"] as? NSNumber {
        state["restEndsAtMillis"] = restEndsAt
      }
      return true
    }
  }

  static func readState() throws -> [String: Any] { try transaction { $0 } }

  static func readEvents() throws -> [[String: Any]] {
    try transaction { $0["events"] as? [[String: Any]] ?? [] }
  }

  static func acknowledge(_ eventIds: [String]) throws {
    let ids = Set(eventIds)
    try transaction { state in
      let events = state["events"] as? [[String: Any]] ?? []
      state["events"] = events.filter { !ids.contains($0["eventId"] as? String ?? "") }
    }
  }

  static func clear() throws {
    try transaction { state in
      state.removeValue(forKey: "projection")
      state.removeValue(forKey: "completedTokens")
      state.removeValue(forKey: "restEndsAtMillis")
      // Unacknowledged performed records must survive logout and UI dismissal.
    }
  }

  @discardableResult
  static func complete(sessionId: String, token: String) throws -> [String: Any] {
    try transaction { state in
      guard let projection = state["projection"] as? [String: Any],
            projection["sessionId"] as? String == sessionId,
            number(projection["expiresAtMillis"]) > nowMillis else {
        throw StoreError.stale
      }
      var completed = state["completedTokens"] as? [String] ?? []
      if completed.contains(token) { return state }
      guard let current = currentSet(in: state),
            current["token"] as? String == token,
            current["canComplete"] as? Bool == true else { throw StoreError.stale }
      var events = state["events"] as? [[String: Any]] ?? []
      guard events.count < maximumEvents else { throw StoreError.journalFull }
      let completedAt = nowMillis
      let rest = projection["autoStartRestTimer"] as? Bool == true
        ? max(0, number(current["restSeconds"])) : 0
      let restEndsAt = completedAt + rest * 1000
      events.append([
        "eventId": UUID().uuidString.lowercased(),
        "sessionId": sessionId,
        "ownerKey": projection["ownerKey"] ?? "",
        "workoutDate": projection["workoutDate"] ?? "",
        "publishedAtMillis": projection["publishedAtMillis"] ?? 0,
        "expiresAtMillis": projection["expiresAtMillis"] ?? 0,
        "completedAtMillis": completedAt,
        "restEndsAtMillis": restEndsAt,
        "set": current,
      ])
      completed.append(token)
      state["events"] = events
      state["completedTokens"] = completed
      state["restEndsAtMillis"] = restEndsAt
      state["lastExerciseName"] = current["exerciseName"]
      return state
    }
  }

  static func currentSet(in state: [String: Any]) -> [String: Any]? {
    guard let projection = state["projection"] as? [String: Any],
          number(projection["expiresAtMillis"]) > nowMillis,
          let sets = projection["sets"] as? [[String: Any]] else { return nil }
    let completed = Set(state["completedTokens"] as? [String] ?? [])
    return sets.first { !completed.contains($0["token"] as? String ?? "") }
  }

  static var nowMillis: Double { Date().timeIntervalSince1970 * 1000 }
  static func number(_ value: Any?) -> Double { (value as? NSNumber)?.doubleValue ?? 0 }

  /// A separate lock inode remains stable while the JSON file is atomically
  /// replaced. Both the app and extension use this lock for every operation.
  private static func transaction<T>(_ action: (inout [String: Any]) throws -> T) throws -> T {
    guard let container = containerURL else { throw StoreError.unavailable }
    let directory = container.appendingPathComponent("WorkoutCheck", isDirectory: true)
    try FileManager.default.createDirectory(
      at: directory, withIntermediateDirectories: true,
      attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]
    )
    let lockPath = directory.appendingPathComponent("journal.lock").path
    let descriptor = open(lockPath, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
    guard descriptor >= 0 else { throw StoreError.unavailable }
    defer { close(descriptor) }
    guard flock(descriptor, LOCK_EX) == 0 else { throw StoreError.unavailable }
    defer { flock(descriptor, LOCK_UN) }
    let url = directory.appendingPathComponent(fileName)
    var state: [String: Any] = [:]
    if FileManager.default.fileExists(atPath: url.path) {
      let data = try Data(contentsOf: url)
      guard let decoded = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        throw StoreError.unavailable
      }
      state = decoded
    }
    let result = try action(&state)
    let data = try JSONSerialization.data(withJSONObject: state, options: [.sortedKeys])
    try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    return result
  }
}
