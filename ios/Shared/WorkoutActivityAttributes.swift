import ActivityKit
import Foundation

@available(iOS 17.0, *)
struct WorkoutActivityAttributes: ActivityAttributes {
  struct ContentState: Codable, Hashable {
    var sessionId: String
    var exerciseName: String
    var valuesLabel: String
    var setNumber: Int
    var setTotal: Int
    var token: String
    var canComplete: Bool
    var restEndsAt: Date?
    var finished: Bool
  }
  var ownerKey: String
  var workoutDate: String
}
