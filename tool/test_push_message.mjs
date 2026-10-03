// Run: node --experimental-strip-types tool/test_push_message.mjs
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { buildPushMessage } from '../supabase/functions/send-push/message.ts';

const { message } = buildPushMessage('registered-device', {
  kind: 'business',
  title: '운동 관리 연결 신청',
  body: '민지님이 운동 관리 연결을 신청했어요.',
  data: { event: 'coaching_management', linkId: 'connection-id', action: 'requested', count: 1, kind: 'spoofed' },
});
assert.deepEqual(message.notification, {
  title: '운동 관리 연결 신청',
  body: '민지님이 운동 관리 연결을 신청했어요.',
}, 'A notification payload lets Android display it without starting Flutter');
assert.equal(message.token, 'registered-device');
assert.equal(message.data.kind, 'business');
assert.equal(message.data.event, 'coaching_management');
assert.equal(message.data.linkId, 'connection-id');
assert.equal(message.data.action, 'requested');
assert.ok(Object.values(message.data).every(value => typeof value === 'string'));
assert.equal(message.android.priority, 'HIGH');
assert.equal(message.android.notification.notification_priority, 'PRIORITY_HIGH');
assert.equal(message.android.notification.sound, 'default');
assert.equal(message.android.notification.default_vibrate_timings, true);
const resources = readFileSync('android/app/src/main/res/values/strings.xml', 'utf8');
const channel = resources.match(/name="push_channel_id"[^>]*>([^<]+)</)[1];
assert.equal(message.android.notification.channel_id, channel, 'Server and Android must use the same popup channel');
const manifest = readFileSync('android/app/src/main/AndroidManifest.xml', 'utf8');
assert.match(manifest, /android:name="\.SetflowApplication"/);
assert.match(manifest, /default_notification_channel_id"\s+android:value="@string\/push_channel_id"/);
console.log('PASS: background notification payload, exact tap destination, popup channel and sound');
