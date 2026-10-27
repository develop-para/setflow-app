import ActivityKit
import Foundation

@available(iOS 17.0, *)
@MainActor
enum WorkoutLiveActivityCoordinator {
  static func refresh(allowStart: Bool) async throws {
    let state = try LockScreenWorkoutStore.readState()
    guard let projection = state["projection"] as? [String: Any],
          let sessionId = projection["sessionId"] as? String,
          let ownerKey = projection["ownerKey"] as? String,
          let workoutDate = projection["workoutDate"] as? String,
          LockScreenWorkoutStore.number(projection["expiresAtMillis"]) > LockScreenWorkoutStore.nowMillis else {
      await endAll()
      return
    }
    let current = LockScreenWorkoutStore.currentSet(in: state)
    let restMillis = LockScreenWorkoutStore.number(state["restEndsAtMillis"])
    let restEndsAt = restMillis > LockScreenWorkoutStore.nowMillis
      ? Date(timeIntervalSince1970: restMillis / 1000) : nil
    let content = WorkoutActivityAttributes.ContentState(
      sessionId: sessionId,
      exerciseName: current?["exerciseName"] as? String ?? "오늘 운동 기록 완료",
      valuesLabel: current?["valuesLabel"] as? String ?? "앱에서 기록을 확인할 수 있어요",
      setNumber: Int(LockScreenWorkoutStore.number(current?["setNumber"])),
      setTotal: Int(LockScreenWorkoutStore.number(current?["setTotal"])),
      token: current?["token"] as? String ?? "",
      canComplete: current?["canComplete"] as? Bool == true,
      restEndsAt: restEndsAt,
      finished: current == nil
    )
    let stale = Date(timeIntervalSince1970:
      LockScreenWorkoutStore.number(projection["expiresAtMillis"]) / 1000)
    let activityContent = ActivityContent(state: content, staleDate: stale)
    var matching: Activity<WorkoutActivityAttributes>?
    for activity in Activity<WorkoutActivityAttributes>.activities {
      if activity.attributes.ownerKey == ownerKey &&
          activity.attributes.workoutDate == workoutDate {
        matching = activity
      } else {
        await activity.end(nil, dismissalPolicy: .immediate)
      }
    }
    if let activity = matching {
      await activity.update(activityContent)
    } else if allowStart && ActivityAuthorizationInfo().areActivitiesEnabled {
      _ = try Activity.request(
        attributes: WorkoutActivityAttributes(
          ownerKey: ownerKey,
          workoutDate: workoutDate
        ),
        content: activityContent, pushType: nil
      )
    }
  }

  static func endAll() async {
    for activity in Activity<WorkoutActivityAttributes>.activities {
      await activity.end(nil, dismissalPolicy: .immediate)
    }
  }
}
