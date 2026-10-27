import ActivityKit
import SwiftUI
import WidgetKit

@main
struct SetflowWorkoutWidgetBundle: WidgetBundle {
  var body: some Widget { SetflowWorkoutLiveActivity() }
}

struct SetflowWorkoutLiveActivity: Widget {
  var body: some WidgetConfiguration {
    ActivityConfiguration(for: WorkoutActivityAttributes.self) { context in
      VStack(alignment: .leading, spacing: 8) {
        HStack {
          Text("SETFLOW").font(.caption.weight(.semibold))
          Spacer()
          if let rest = context.state.restEndsAt {
            HStack(spacing: 4) {
              Text("휴식")
              Text(timerInterval: Date.distantPast...rest, countsDown: true)
                .monospacedDigit().frame(maxWidth: 54)
            }.font(.caption)
          }
        }.foregroundStyle(.secondary)
        HStack(alignment: .center, spacing: 12) {
          VStack(alignment: .leading, spacing: 4) {
            Text(context.state.exerciseName)
              .font(.headline).lineLimit(2)
            if !context.state.finished {
              Text("\(context.state.setNumber)/\(context.state.setTotal)세트 · \(context.state.valuesLabel)")
                .font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
            }
          }
          Spacer(minLength: 0)
          action(context)
        }
      }
      .padding(16)
      .activityBackgroundTint(Color(.systemBackground))
      .activitySystemActionForegroundColor(.primary)
      .widgetURL(workoutURL(context.attributes.workoutDate))
    } dynamicIsland: { context in
      DynamicIsland {
        DynamicIslandExpandedRegion(.leading) {
          Text(context.state.exerciseName).font(.headline).lineLimit(1)
        }
        DynamicIslandExpandedRegion(.trailing) {
          if !context.state.finished {
            Text("\(context.state.setNumber)/\(context.state.setTotal)").monospacedDigit()
          }
        }
        DynamicIslandExpandedRegion(.bottom) {
          HStack {
            VStack(alignment: .leading) {
              Text(context.state.valuesLabel).font(.subheadline)
              if let rest = context.state.restEndsAt {
                HStack {
                  Text("휴식")
                  Text(timerInterval: Date.distantPast...rest, countsDown: true).monospacedDigit()
                }.font(.caption)
              }
            }
            Spacer()
            action(context)
          }.padding(.top, 8)
        }
      } compactLeading: {
        Image(systemName: "figure.strengthtraining.traditional")
      } compactTrailing: {
        if let rest = context.state.restEndsAt {
          Text(timerInterval: Date.distantPast...rest, countsDown: true)
            .monospacedDigit().frame(maxWidth: 46)
        } else { Text("\(context.state.setNumber)/\(context.state.setTotal)").monospacedDigit() }
      } minimal: {
        Image(systemName: context.state.finished ? "checkmark" : "figure.strengthtraining.traditional")
      }
      .widgetURL(workoutURL(context.attributes.workoutDate))
    }
  }

  @ViewBuilder
  private func action(_ context: ActivityViewContext<WorkoutActivityAttributes>) -> some View {
    if context.state.finished {
      Text("저장됨").font(.subheadline.weight(.semibold))
    } else if context.state.canComplete && !context.isStale {
      Button(intent: CompleteWorkoutSetIntent(
        sessionId: context.state.sessionId, token: context.state.token
      )) {
        Text("세트 완료").font(.subheadline.weight(.semibold)).padding(.vertical, 8)
      }
      .buttonStyle(.borderedProminent)
      .tint(Color(red: 0.8, green: 1, blue: 0))
      .foregroundStyle(.black)
      .accessibilityLabel("\(context.state.exerciseName) \(context.state.setNumber)세트 완료")
    } else {
      Link("앱에서 확인", destination: workoutURL(context.attributes.workoutDate))
        .font(.subheadline.weight(.semibold))
    }
  }

  private func workoutURL(_ date: String) -> URL {
    var components = URLComponents()
    components.scheme = "com.teampara.setflow"
    components.host = "workout"
    components.queryItems = [URLQueryItem(name: "date", value: date)]
    return components.url!
  }
}
