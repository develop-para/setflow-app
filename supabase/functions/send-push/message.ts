interface PushNotification {
  kind: string;
  title: string;
  body: string;
  data: Record<string, unknown>;
}

// Keep notification + data together: Android displays it while Flutter is closed,
// then passes the same destination to the app when the user taps it.
export function buildPushMessage(token: string, row: PushNotification) {
  return {
    message: {
      token,
      notification: { title: row.title, body: row.body },
      data: Object.fromEntries(
        Object.entries({ ...row.data, kind: row.kind }).map(
          ([key, value]) => [key, String(value)],
        ),
      ),
      android: {
        priority: "HIGH",
        notification: {
          channel_id: "setflow_messages",
          sound: "default",
          default_vibrate_timings: true,
          notification_priority: "PRIORITY_HIGH",
        },
      },
      apns: {
        headers: { "apns-priority": "10" },
        payload: { aps: { sound: "default" } },
      },
    },
  };
}
