// Run: node tool/test_coaching_history.mjs <path-to-@electric-sql/pglite>
// Runs the actual migration and existing authorization helper in PostgreSQL
// (PGlite), with synthetic fixtures only. No connection to a live account.
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { createRequire } from 'node:module';
const require = createRequire(import.meta.url);
const { PGlite } = require(process.argv[2] || '@electric-sql/pglite');
const db = new PGlite();
const id = n => `00000000-0000-4000-8000-${String(n).padStart(12, '0')}`;
await db.exec(`
  create schema auth; create schema private;
  create role anon; create role authenticated; create role service_role;
  grant usage on schema public, private, auth to authenticated, anon;
  create function auth.uid() returns uuid language sql stable as
    $$ select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid $$;
  create table public.coaching_schedules (
    id uuid primary key, member_user_id uuid, trainer_id uuid, gym_id uuid,
    completed_at timestamptz
  );
  create table public.coaching_health_consents (
    schedule_id uuid primary key, member_user_id uuid, trainer_id uuid, gym_id uuid,
    share_with_trainer boolean, share_with_gym boolean, updated_at timestamptz
  );
  create table public.trainers (id uuid primary key, user_id uuid, status text, display_name text);
  create table public.gyms (id uuid primary key, owner_user_id uuid, status text);
  create table public.users (id uuid primary key, nickname text);
  create table public.coaching_health_access_logs (
    schedule_id uuid, member_user_id uuid, trainer_id uuid, gym_id uuid,
    viewer_user_id uuid, viewer_role text
  );
  create table public.workout_sessions (
    id uuid primary key, user_id uuid, date date, category text, intensity text,
    feedback text, started_at timestamptz, ended_at timestamptz
  );
  create table public.workout_exercises (
    id uuid primary key, session_id uuid, base_exercise_id uuid,
    name text, target_muscle text, order_index int
  );
  create table public.workout_sets (
    id uuid primary key, exercise_id uuid, set_no int, type text, weight numeric,
    reps int, duration_sec int, distance_m numeric, intensity_rpe numeric,
    rir numeric, memo text, completed boolean, completed_at timestamptz,
    estimated_1rm numeric, rest_seconds int
  );
  create table public.session_feedback (
    id uuid primary key, session_id uuid, trainer_id uuid, text text, created_at timestamptz
  );
  create table public.user_profiles (
    user_id uuid, height numeric, weight numeric, age int, gender text, goal text, updated_at timestamptz
  );
  create table public.app_state_snapshots (user_id uuid, payload jsonb, updated_at timestamptz);
  create table public.body_compositions (
    id uuid, user_id uuid, record_date date, weight_kg numeric,
    skeletal_muscle_mass numeric, body_fat_pct numeric, bmi numeric, source text, created_at timestamptz
  );
`);
const original = readFileSync('supabase/migrations/20260830031529_coaching_health_data_consent.sql', 'utf8');
const start = original.indexOf('create or replace function private.coaching_health_access_role(');
await db.exec(original.slice(start, original.indexOf('$function$;', start) + '$function$;'.length));
await db.exec(readFileSync('supabase/migrations/20260911122556_coaching_workout_history.sql', 'utf8'));
await db.exec(`
  insert into users values ('${id(1)}', '회원');
  insert into trainers values ('${id(3)}', '${id(2)}', 'approved', '트레이너');
  insert into gyms values ('${id(4)}', '${id(5)}', 'verified');
  insert into coaching_schedules values ('${id(6)}', '${id(1)}', '${id(3)}', '${id(4)}', null);
  insert into coaching_health_consents values ('${id(6)}', '${id(1)}', '${id(3)}', '${id(4)}', true, false, now());
  insert into user_profiles values ('${id(1)}', 170, 65, 30, '남성', '근력', now());
  insert into app_state_snapshots values ('${id(1)}', '{"profile":{"recommendationProfile":{"goal":"strength"}}}', now());
`);
for (let i = 0; i < 45; i++) {
  await db.query('insert into workout_sessions(id,user_id,date,feedback) values($1,$2,$3,$4)',
    [id(100+i), id(1), i < 25 ? '2020-01-01' : '2018-01-01', '개인 운동 메모']);
}
await db.exec(`
  insert into workout_sessions(id,user_id,date) values('${id(999)}','${id(9)}','2026-01-01');
  insert into workout_exercises values('${id(700)}','${id(124)}',null,'스쿼트','하체',0);
  insert into workout_sets(id,exercise_id,set_no,type,weight,reps,completed,memo,rest_seconds)
    values('${id(701)}','${id(700)}',1,'normal',100,8,true,'깊이 유지',90);
  insert into session_feedback values('${id(702)}','${id(124)}','${id(2)}','좋아요',now());
`);
for (let i = 0; i < 55; i++) {
  await db.query('insert into body_compositions(id,user_id,record_date,weight_kg) values($1,$2,$3,65)',
    [id(800+i), id(1), '2019-01-01']);
}
async function asUser(user, role = 'authenticated') {
  await db.exec(`reset role; set role ${role}`);
  await db.query("select set_config('request.jwt.claim.sub', $1, false)", [user ?? '']);
}
async function page(cursor) {
  return (await db.query('select public.list_coaching_workout_history($1,$2,$3) as result',
    [id(6), cursor?.date ?? null, cursor?.id ?? null])).rows[0].result;
}
await asUser(id(2));
let first = await page();
assert.equal(first.sessions.length, 20);
assert.equal(first.sessions[0].exercises[0].sets[0].weight, 100);
assert.equal(first.sessions[0].exercises[0].sets[0].memo, '깊이 유지');
assert.equal(first.sessions[0].feedbacks[0].text, '좋아요');
let second = await page(first.next_cursor);
let third = await page(second.next_cursor);
assert.equal(second.sessions.length, 20);
assert.equal(third.sessions.length, 5);
assert.equal(third.next_cursor, null);
assert.equal(new Set([...first.sessions,...second.sessions,...third.sessions].map(s=>s.id)).size,45);
assert.ok(third.sessions.every(s => s.date === '2018-01-01'));
await assert.rejects(() => page({date:'2018-01-01'}), /Incomplete history cursor/);
await asUser(id(9));
await assert.rejects(page, /Member consent is required/);
await asUser(id(5));
await assert.rejects(page, /Member consent is required/);
await asUser(null, 'anon');
await assert.rejects(page, /permission denied/);
await asUser(null);
await assert.rejects(page, /Authentication required/);
await db.exec('reset role; update coaching_health_consents set share_with_trainer = false');
await asUser(id(2));
await assert.rejects(() => page(first.next_cursor), /Member consent is required/);
await db.exec('reset role; update coaching_health_consents set share_with_trainer = true; update coaching_schedules set completed_at = now()');
await asUser(id(2));
await assert.rejects(page, /Member consent is required/);
await db.exec('reset role; update coaching_schedules set completed_at = null; update trainers set status = \'pending\'');
await asUser(id(2));
await assert.rejects(page, /Member consent is required/);
await db.exec("reset role; update trainers set status = 'approved'");
await asUser(id(2));
const overview = (await db.query('select private.get_coaching_health_overview($1) as result',[id(6)])).rows[0].result;
assert.equal(overview.profile.height_cm,170);
assert.equal(overview.body_compositions.length,55);
await db.exec('reset role');
assert.equal((await db.query('select count(*)::int as n from coaching_health_access_logs')).rows[0].n,4);
await db.close();
console.log('PASS: full history, cursor ties, nested sets, profiles, 55 body records, anonymous/unrelated/gym denial, consent revocation, completed class, unapproved trainer, audit logs');
