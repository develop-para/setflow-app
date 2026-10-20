// Executes the production migration and validator with synthetic identities.
// Run: node tool/test_trainer_clients.mjs [path-to-@electric-sql/pglite]
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { createRequire } from 'node:module';
const require = createRequire(import.meta.url);
const { PGlite } = require(process.argv[2] || '../.dart_tool/workspace-security/node_modules/@electric-sql/pglite');
const db = new PGlite();
const id = n => `00000000-0000-4000-8000-${String(n).padStart(12, '0')}`;
const trainerUser = id(1), trainer = id(2), otherTrainerUser = id(3), otherTrainer = id(4);
const member = id(5), stranger = id(6), pendingUser = id(7), pendingTrainer = id(8);
let next = 100;
const request = () => id(++next);
function sourceFunction(path, signature) {
  const source = readFileSync(path, 'utf8');
  const start = source.indexOf(`create or replace function ${signature}`);
  assert.ok(start >= 0, signature);
  const delimiter = source.slice(start).match(/as\s+(\$\w*\$)/i)[1];
  const first = source.indexOf(delimiter, start);
  const end = source.indexOf(delimiter + ';', first + delimiter.length);
  return source.slice(start, end + delimiter.length + 1);
}
await db.exec(`
  create schema auth; create schema private;
  create role anon; create role authenticated; create role service_role;
  grant usage on schema public,private,auth to anon,authenticated,service_role;
  create function auth.uid() returns uuid language sql stable as
    $$ select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid $$;
  create table public.users(id uuid primary key,nickname text);
  create table public.trainers(id uuid primary key,user_id uuid,status text,display_name text);
  create table public.app_state_snapshots(user_id uuid primary key,payload jsonb);
  insert into users values('${trainerUser}','코치'),('${otherTrainerUser}','다른 코치'),
    ('${member}','회원'),('${stranger}','외부 회원'),('${pendingUser}','심사중');
  insert into trainers values('${trainer}','${trainerUser}','approved','김코치'),
    ('${otherTrainer}','${otherTrainerUser}','approved','이코치'),('${pendingTrainer}','${pendingUser}','pending','심사중');
`);
await db.exec(sourceFunction('supabase/migrations/20260911144942_coaching_workouts.sql',
  'private.validate_coaching_workout_session('));
await db.exec(readFileSync('supabase/migrations/20261020120000_trainer_managed_clients.sql', 'utf8'));
async function asUser(user, role = 'authenticated') {
  await db.exec(`reset role; set role ${role}`);
  await db.query("select set_config('request.jwt.claim.sub',$1,false)", [user ?? '']);
}
async function rpc(name, args = []) {
  return (await db.query(`select public.${name}(${args.map((_, i) => '$' + (i + 1)).join(',')}) result`, args)).rows[0].result;
}
async function denied(action, code = '42501') {
  await assert.rejects(action, error => error.code === code);
}
const session = (date = '2026-10-20') => ({ date: date + 'T00:00:00.000', exercises: [{
  id: 'bench-session', templateId: 'bench', template: { id: 'bench', name: '벤치 프레스', muscle: '가슴', measurement: 'weightReps' },
  sets: [{ number: 1, weight: 40, reps: 8, completed: true, type: '일반', restSeconds: 90, durationSeconds: 0, distanceKm: 0, intensityRpe: 0 }],
}] });
const create = (name = '동명이인', req = request()) => rpc('create_trainer_client', [name, '010-1234-5678', '트레이너 전용 메모', req]);
const save = (client, workoutId, version, value = session(), req = request()) => rpc('save_trainer_client_workout', [client.id, value, '수업 메모', req, workoutId, version]);
const invite = (client, req = request()) => rpc('create_trainer_client_invitation', [client.id, new Date(Date.now() + 86400000).toISOString(), req]);

await asUser(null, 'anon');
await denied(() => rpc('list_trainer_clients'));
await denied(() => rpc('list_my_trainer_client_workouts'));
await asUser(pendingUser);
await denied(() => create());
await denied(() => rpc('list_trainer_clients'));
await asUser(trainerUser);
const createReq = request();
const client = await create('동명이인', createReq);
assert.deepEqual(await create('동명이인', createReq), client);
await denied(() => create('다른 이름', createReq), '22023');
const second = await create();
assert.notEqual(client.id, second.id); // Never merge matching names/phones.
assert.equal((await rpc('list_trainer_clients')).length, 2);
await denied(() => db.query('select * from public.trainer_clients'));
await denied(() => db.query('select * from public.trainer_client_workouts'));
await denied(() => db.query('select * from public.trainer_client_invitations'));
await denied(() => db.query('select * from public.trainer_client_requests'));
await denied(() => db.query('select private.require_client_trainer()'));
const updateReq = request();
const update = () => rpc('update_trainer_client', [client.id, '김회원', '01099998888', '비공개 건강 메모', updateReq]);
assert.equal((await update()).name, '김회원');
assert.deepEqual(await update(), await update());
await denied(() => rpc('update_trainer_client', [client.id, '변경', '', '', updateReq]), '22023');
await denied(() => create('김회원', updateReq), '22023');
const workoutId = request(), saveReq = request();
const original = await save(client, workoutId, 0, session(), saveReq);
assert.equal(original.version, 1);
assert.equal(original.source, 'trainer');
assert.equal(original.can_edit, true);
assert.deepEqual(await save(client, workoutId, 0, session(), saveReq), original);
await denied(() => save(client, request(), 0), 'PT409');
await denied(() => save(client, workoutId, 0), 'PT409');
const changed = session(); changed.exercises[0].sets[0].reps = 6;
assert.equal((await save(client, workoutId, 1, changed)).version, 2);
await denied(() => save(client, workoutId, 2, session('2026-10-19')), '22023');
const invalid = session('2026-10-21'); invalid.exercises[0].sets[0].reps = -2;
await denied(() => save(client, request(), 0, invalid), '22023');
await asUser(otherTrainerUser);
assert.deepEqual(await rpc('list_trainer_clients'), []);
await denied(() => rpc('list_trainer_client_workouts', [client.id]));
await denied(() => save(client, request(), 0));
await denied(() => rpc('update_trainer_client', [client.id, '탈취', '', '', request()]));
await denied(() => invite(client));

await asUser(trainerUser);
const invitationReq = request();
const invitation = await invite(client, invitationReq);
const replayInvite = () => rpc('create_trainer_client_invitation', [client.id, invitation.expires_at, invitationReq]);
assert.deepEqual(await replayInvite(), invitation);
assert.equal(invitation.token.length, 64);
await denied(() => rpc('accept_trainer_client_invitation', [invitation.token, request()])); // Self-link rejected.
await asUser(member);
assert.deepEqual(await rpc('list_my_trainer_client_links'), []);
assert.deepEqual(await rpc('list_my_trainer_client_workouts'), []);
const acceptReq = request();
assert.deepEqual(await rpc('accept_trainer_client_invitation', [invitation.token, acceptReq]), { accepted: true });
assert.deepEqual(await rpc('accept_trainer_client_invitation', [invitation.token, acceptReq]), { accepted: true });
await denied(() => rpc('accept_trainer_client_invitation', [invitation.token, request()]));
const mine = await rpc('list_my_trainer_client_workouts');
assert.equal(mine[0].client_id, client.id);
assert.equal(mine[0].can_edit, false);
assert.equal(mine[0].session.exercises[0].sets[0].reps, 6);
assert.equal(JSON.stringify(mine).includes('비공개 건강 메모'), false);
assert.equal(JSON.stringify(mine).includes('01099998888'), false);
assert.equal((await rpc('list_my_trainer_client_links'))[0].is_sharing, true);
await denied(() => save(client, workoutId, 2));
await asUser(trainerUser);
await denied(replayInvite, 'PT410'); // Never present an already consumed token as usable.
await asUser(stranger);
await denied(() => rpc('accept_trainer_client_invitation', [invitation.token, request()]));
assert.deepEqual(await rpc('list_my_trainer_client_workouts'), []);
await denied(() => rpc('end_my_trainer_client_link', [client.id, request()]));

// Personal history and custom exercise templates are shared only after explicit
// acceptance, never copied into or edited by the trainer's personal snapshot.
const own = session('2026-10-19');
own.exercises[0].templateId = 'custom_owned'; delete own.exercises[0].template;
await db.exec('reset role');
await db.query('insert into app_state_snapshots values($1,$2),($3,$4)', [member,
  { sessions: [own], customExercises: [{ id: 'custom_owned', name: '내 종목', muscle: '가슴', measurement: 'weightReps' }] },
  trainerUser, { sessions: [session('2026-10-18')] }]);
await asUser(trainerUser);
const combined = await rpc('list_trainer_client_workouts', [client.id]);
assert.equal(combined.length, 2);
assert.equal(combined[1].source, 'member');
assert.equal(combined[1].can_edit, false);
assert.equal(combined[1].session.exercises[0].template.name, '내 종목');
assert.equal((await rpc('list_trainer_client_workouts', [second.id])).length, 0);
await asUser(member);
const revokeReq = request();
await rpc('end_my_trainer_client_link', [client.id, revokeReq]);
await rpc('end_my_trainer_client_link', [client.id, revokeReq]);
await denied(() => rpc('accept_trainer_client_invitation', [invitation.token, acceptReq]), 'PT410');
assert.equal((await rpc('list_my_trainer_client_links'))[0].is_sharing, false);
assert.equal((await rpc('list_my_trainer_client_workouts')).length, 1); // Historical coach records preserved.
await asUser(trainerUser);
assert.equal((await rpc('list_trainer_client_workouts', [client.id])).length, 1);
assert.equal((await rpc('list_trainer_clients')).find(c => c.id === client.id).member_user_id, null);
const bound = await invite(client);
await asUser(stranger);
await denied(() => rpc('accept_trainer_client_invitation', [bound.token, request()])); // Original identity cannot be reassigned.
await asUser(member);
await rpc('accept_trainer_client_invitation', [bound.token, request()]);
await denied(() => rpc('end_my_trainer_client_link', [client.id, revokeReq]), 'PT410'); // A stale disconnect cannot report success after renewed consent.
assert.equal((await rpc('list_my_trainer_client_links'))[0].is_sharing, true);
await rpc('end_my_trainer_client_link', [client.id, request()]);
await asUser(trainerUser);
const obsolete = await invite(second), valid = await invite(second);
await asUser(member);
await denied(() => rpc('accept_trainer_client_invitation', [obsolete.token, request()]));
await rpc('accept_trainer_client_invitation', [valid.token, request()]);
assert.equal((await rpc('list_my_trainer_client_links')).length, 2); // Revoke possible before first workout.
await rpc('end_my_trainer_client_link', [second.id, request()]);
await db.exec('reset role');
const untouched = (await db.query('select payload from app_state_snapshots where user_id=$1', [trainerUser])).rows[0].payload;
assert.deepEqual(untouched, { sessions: [session('2026-10-18')] });
await db.exec(`update trainers set status='pending' where id='${trainer}'`);
await asUser(trainerUser);
await denied(() => rpc('list_trainer_client_workouts', [client.id]));
await denied(() => save(client, workoutId, 2));
await denied(() => rpc('update_trainer_client', [client.id, '김회원', '', '', request()]));
await denied(() => invite(client));
await asUser(member);
assert.equal((await rpc('list_my_trainer_client_workouts')).length, 1); // Approval does not erase member history.
await db.exec(`reset role; update trainers set status='approved' where id='${trainer}'`);
await asUser(trainerUser);
const pendingAtPurge = await invite(client);
await db.exec('reset role');
await db.query('delete from public.users where id=$1', [member]); // Must not be blocked by any feature FK.
const tombstone = (await db.query('select * from public.trainer_clients where id=$1', [client.id])).rows[0];
assert.equal(tombstone.member_user_id, null);
assert.equal(tombstone.member_consented_at, null);
assert.ok(tombstone.member_bound_at);
assert.equal((await db.query('select count(*)::int count from public.trainer_client_invitations where accepted_at is not null and accepted_by is not null')).rows[0].count, 0);
assert.equal((await db.query('select count(*)::int count from public.trainer_client_requests where actor_user_id=$1', [member])).rows[0].count, 0);
await denied(() => db.query('update public.trainer_clients set member_user_id=$1,member_bound_at=null where id=$2', [stranger, client.id]));
await asUser(trainerUser);
assert.equal((await rpc('list_trainer_clients')).find(c => c.id === client.id).can_connect, false);
assert.equal((await rpc('list_trainer_client_workouts', [client.id])).length, 1); // Trainer-owned records survive the member's purge.
await denied(() => invite(client), 'PT410');
await asUser(stranger);
await denied(() => rpc('accept_trainer_client_invitation', [pendingAtPurge.token, request()]));
assert.deepEqual(await rpc('list_my_trainer_client_workouts'), []);
assert.deepEqual(await rpc('list_my_trainer_client_links'), []);
await db.close();
console.log('Trainer client SQL: approval, isolation, idempotency, versions, consent, revocation and account deletion passed.');
