import ActivityKit
import Flutter
import Foundation
import UIKit

final class LockScreenWorkoutPlugin: NSObject, FlutterPlugin {
  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "com.teampara.setflow/lock_screen_workout",
      binaryMessenger: registrar.messenger()
    )
    registrar.addMethodCallDelegate(LockScreenWorkoutPlugin(), channel: channel)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    do {
      switch call.method {
      case "openSettings":
        guard let url = URL(string: UIApplication.openSettingsURLString) else { result(false); return }
        UIApplication.shared.open(url, options: [:]) { result($0) }
      case "getGuestOwnerKey": result(try LockScreenWorkoutStore.guestOwnerKey())
      case "readEvents": result(try LockScreenWorkoutStore.readEvents())
      case "ack":
        guard let arguments = call.arguments as? [String: Any],
              let ids = arguments["eventIds"] as? [String] else {
          throw LockScreenWorkoutStore.StoreError.invalidProjection
        }
        try LockScreenWorkoutStore.acknowledge(ids)
        result(nil)
      case "status":
        let state = try LockScreenWorkoutStore.readState()
        let projection = state["projection"] as? [String: Any]
        let enabled = LockScreenWorkoutStore.currentSet(in: state) != nil
        if #available(iOS 17.0, *) {
          result([
            "supported": LockScreenWorkoutStore.available,
            "enabled": enabled,
            "notificationsAllowed": ActivityAuthorizationInfo().areActivitiesEnabled,
            "ownerKey": projection?["ownerKey"] ?? NSNull(),
            "workoutDate": projection?["workoutDate"] ?? NSNull(),
            "sessionId": projection?["sessionId"] ?? NSNull(),
          ])
        } else {
          result(["supported": false, "enabled": false, "notificationsAllowed": false])
        }
      case "publish":
        guard let projection = call.arguments as? [String: Any] else {
          throw LockScreenWorkoutStore.StoreError.invalidProjection
        }
        if #available(iOS 17.0, *) {
          guard ActivityAuthorizationInfo().areActivitiesEnabled else { result(false); return }
          guard try LockScreenWorkoutStore.publish(projection) else { result(false); return }
          Task { @MainActor in
            do {
              try await WorkoutLiveActivityCoordinator.refresh(allowStart: true)
              result(true)
            } catch {
              result(Self.failure(error))
            }
          }
        } else { result(false) }
      case "clear":
        try LockScreenWorkoutStore.clear()
        if #available(iOS 17.0, *) {
          Task { @MainActor in
            await WorkoutLiveActivityCoordinator.endAll()
            result(nil)
          }
        } else { result(nil) }
      default: result(FlutterMethodNotImplemented)
      }
    } catch { result(Self.failure(error)) }
  }

  private static func failure(_ error: Error) -> FlutterError {
    FlutterError(code: "lock_screen_workout_unavailable",
                 message: error.localizedDescription, details: nil)
  }
}
