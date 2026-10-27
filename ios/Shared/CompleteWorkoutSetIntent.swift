import AppIntents
import Foundation

@available(iOS 17.0, *)
struct CompleteWorkoutSetIntent: LiveActivityIntent {
  static var title: LocalizedStringResource = "세트 완료"
  static var openAppWhenRun: Bool = false
  static var authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed

  @Parameter(title: "운동 세션") var sessionId: String
  @Parameter(title: "세트") var token: String

  init() {}
  init(sessionId: String, token: String) {
    self.sessionId = sessionId
    self.token = token
  }

  func perform() async throws -> some IntentResult {
    // Persist the actual displayed values before any success state is rendered.
    // A repeated intent for this exact token never toggles completion back off.
    try LockScreenWorkoutStore.complete(sessionId: sessionId, token: token)
    #if !SETFLOW_WIDGET_EXTENSION
    try await WorkoutLiveActivityCoordinator.refresh(allowStart: false)
    #endif
    return .result()
  }
}
