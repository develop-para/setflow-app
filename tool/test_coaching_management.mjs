// Run: node tool/test_coaching_management.mjs [path-to-@electric-sql/pglite]
// Executes production SQL with synthetic identities. Only the wall clock is
// replaced for deterministic lesson boundaries and KST reminder checks.
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { createRequire } from 'node:module';
process.on('uncaughtException', error => {
  console.error(error.message, error.code ?? '', error.where ?? '', error.position ?? '');
  console.error(error.stack?.split('\n').slice(0, 7).join('\n'));
  process.exit(1);
});
const require = createRequire(import.meta.url);
const { PGlite } = require(process.argv[2] || '../.dart_tool/workspace-security/node_modules/@electric-sql/pglite');
const db = new PGlite();
const id = n => `00000000-0000-4000-8000-${String(n).padStart(12, '0')}`;
const member = id(1), trainerUser = id(2), trainer = id(3), stranger = id(4);
const gymOwner = id(5), gym = id(6), pendingUser = id(7), pendingTrainer = id(8);
const otherMember = id(9), otherTrainerUser = id(10), otherTrainer = id(11);
const lesson = id(20), lessonBefore = id(21), lessonAfter = id(22), lessonDone = id(23);
let requestNumber = 1000;
const request = () => id(++requestNumber);
const day = '2026-09-11';
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
  grant usage on schema public,private,auth to authenticated,anon,service_role;
  create function auth.uid() returns uuid language sql stable as
    $$ select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid $$;
  create function private.test_clock() returns timestamptz language sql volatile as
    $$ select coalesce(nullif(current_setting('test.clock',true),'')::timestamptz,clock_timestamp()) $$;
  create table public.users(id uuid primary key,nickname text);
  create table public.trainers(id uuid primary key,user_id uuid,status text,display_name text);
  create table public.gyms(id uuid primary key,owner_user_id uuid,status text);
  create table public.coachings(id uuid primary key,trainer_id uuid,user_id uuid,status text);
  create table public.members(id uuid primary key,gym_id uuid,user_id uuid,status text);
  create table public.member_assignments(member_id uuid,gym_id uuid,trainer_id uuid,active boolean);
  create table public.gym_trainers(gym_id uuid,trainer_id uuid,status text);
  create table public.coaching_schedules(id uuid primary key,trainer_id uuid,member_user_id uuid,gym_id uuid,
    date date,title text,start_time time,end_time time,completed_at timestamptz);
  create table public.app_state_snapshots(user_id uuid primary key,payload jsonb,updated_at timestamptz);
  create table public.user_notifications(id uuid default gen_random_uuid(),user_id uuid,kind text,title text,body text,data jsonb);
  create table public.push_outbox(id uuid default gen_random_uuid(),user_id uuid,kind text,title text,body text,data jsonb);
  create table public.device_tokens(user_id uuid,token text);
  create table public.workout_sessions(id uuid primary key,user_id uuid,date date,category text,intensity text,
    feedback text,started_at timestamptz,ended_at timestamptz);
  create table public.workout_exercises(id uuid primary key,session_id uuid,base_exercise_id uuid,name text,
    target_muscle text,order_index integer);
  create table public.workout_sets(id uuid primary key,exercise_id uuid,set_no integer,type text,weight numeric,
    reps integer,duration_sec integer,distance_m numeric,intensity_rpe numeric,rir numeric,memo text,
    completed boolean,completed_at timestamptz,estimated_1rm numeric,rest_seconds integer);
  create table public.session_feedback(id uuid,session_id uuid,trainer_id uuid,text text,created_at timestamptz);
  create table public.coaching_health_consents(schedule_id uuid primary key,member_user_id uuid,trainer_id uuid,
    gym_id uuid,share_with_trainer boolean,share_with_gym boolean);
  create table public.coaching_health_access_logs(schedule_id uuid,member_user_id uuid,trainer_id uuid,gym_id uuid,
    viewer_user_id uuid,viewer_role text);
`);
await db.exec(sourceFunction('supabase/migrations/20260830020453_mobile_coaching_sessions.sql',
  'private.has_active_coaching_schedule_relationship('));
await db.exec(sourceFunction('supabase/migrations/20260828090000_push_catalog.sql', 'private.push_enabled('));
await db.exec(sourceFunction('supabase/migrations/20260828090000_push_catalog.sql', 'private.display_name_of('));
await db.exec(sourceFunction('supabase/migrations/20260903090000_notification_inbox.sql', 'private.enqueue_push('));
await db.exec(sourceFunction('supabase/migrations/20260830031529_coaching_health_data_consent.sql', 'private.coaching_health_access_role('));
await db.exec(sourceFunction('supabase/migrations/20260911122556_coaching_workout_history.sql', 'private.list_coaching_workout_history('));
await db.exec(sourceFunction('supabase/migrations/20260911122556_coaching_workout_history.sql', 'public.list_coaching_workout_history('));
const migration = readFileSync('supabase/migrations/20260911144942_coaching_workouts.sql','utf8');
await db.exec(migration.replaceAll('clock_timestamp()', 'private.test_clock()')
  .replaceAll('statement_timestamp()', 'private.test_clock()'));
await db.exec(`
  insert into users values('${member}','회원'),('${trainerUser}','트레이너'),('${stranger}','외부인'),
    ('${gymOwner}','센터장'),('${pendingUser}','심사중'),('${otherMember}','다른 회원'),('${otherTrainerUser}','다른 트레이너');
  insert into trainers values('${trainer}','${trainerUser}','approved','담당 트레이너'),
    ('${pendingTrainer}','${pendingUser}','pending','심사중'),('${otherTrainer}','${otherTrainerUser}','approved','다른 트레이너');
  insert into gyms values('${gym}','${gymOwner}','verified');
  insert into coachings values('${id(30)}','${trainer}','${member}','active'),
    ('${id(31)}','${pendingTrainer}','${member}','active'),('${id(32)}','${otherTrainer}','${otherMember}','active');
  insert into coaching_schedules values
    ('${lesson}','${trainer}','${member}',null,'${day}','정규 수업','19:00','20:00',null),
    ('${lessonBefore}','${trainer}','${member}','${gym}','${day}','예정 수업','20:00','21:00',null),
    ('${lessonAfter}','${trainer}','${member}','${gym}','${day}','지난 수업','17:00','18:00',null),
    ('${lessonDone}','${trainer}','${member}','${gym}','${day}','완료 수업','19:00','20:00','2026-09-11T10:00:00Z');
  insert into app_state_snapshots values('${member}','{"sessions":[],"preferences":{}}',now());
`);
async function asUser(user,role='authenticated') {
  await db.exec(`reset role; set role ${role}`);
  await db.query("select set_config('request.jwt.claim.sub',$1,false)",[user ?? '']);
}
async function clock(value='2026-09-11T10:30:00Z') {
  await db.query("select set_config('test.clock',$1,false)",[value]);
}
async function sql(query,params=[]) { return (await db.query(query,params)).rows; }
async function admin(query,params=[]) { await db.exec('reset role'); return sql(query,params); }
async function rpc(name,args=[]) {
  return (await sql(`select public.${name}(${args.map((_,i)=>'$'+(i+1)).join(',')}) result`,args))[0].result;
}
const set = (completed=false) => ({number:1,weight:40,reps:10,completed,type:'일반',restSeconds:90,durationSeconds:0,distanceKm:0,intensityRpe:0});
const session = (completed=false,date=day) => ({date:date+'T00:00:00.000',exercises:[{
  id:'stable-coaching-exercise',templateId:'bench',
  template:{id:'bench',name:'바벨 벤치 프레스',muscle:'가슴',measurement:'weightReps'},sets:[set(completed)]
}]});
const emptySession = {date:day+'T00:00:00.000',exercises:[]};
const save = (workout,value,req=request(),version=workout.version) => rpc('save_coaching_workout',[workout.id,version,value,req]);
const create = (value=session(),req=request(),target=member,date=day) => rpc('create_workout_assignment',[target,date,'오늘의 근력','천천히 해주세요',value,req]);
await clock();

await db.exec(`reset role;
  alter table gyms add column name text default '소속 업장';
  alter table coachings alter column id set default gen_random_uuid();
  alter table coachings add column program_name text;
  alter table coachings add column start_date date;
  create unique index coaching_active_pair on coachings(trainer_id,user_id) where status = 'active';
  alter table workout_sessions add column updated_at timestamptz default now();
  alter table app_state_snapshots add column schema_version smallint default 11;
  create function private.save_my_app_snapshot(smallint,jsonb,jsonb,timestamptz)
    returns jsonb language sql as $$ select jsonb_build_object('accepted',true) $$;
  alter table workout_exercises add column client_id text;
  create table consultations(id uuid primary key,user_id uuid,trainer_id uuid,assigned_trainer_id uuid);
  insert into consultations values('${id(100)}','${member}','${trainer}',null),
    ('${id(101)}','${otherMember}','${otherTrainer}',null);
  insert into members values('${id(120)}','${gym}','${member}','active');
  insert into gym_trainers values('${gym}','${otherTrainer}','active');
`);
await db.exec(readFileSync('supabase/migrations/20260930120000_coaching_management_consent.sql','utf8')
  .replaceAll('clock_timestamp()', 'private.test_clock()')
  .replaceAll('statement_timestamp()', 'private.test_clock()'));
// Historical personal snapshots use KST without a zone; this is 10:00 UTC.
const today = {...session(true),startedAt:'2026-09-11T18:00:00.000',endedAt:'2026-09-11T19:00:00.000'};
const old = {...session(true,'2026-09-08'),startedAt:'2026-09-08T09:00:00Z',endedAt:'2026-09-08T10:00:00Z'};
await admin('update app_state_snapshots set payload=$1 where user_id=$2',[
  {sessions:[today,old],preferences:{preserve:'yes'},profile:{heightCm:177}},member]);
for (const [index,value] of [today,old].entries()) {
  await admin(`insert into workout_sessions(id,user_id,date) values($1,$2,$3)`,[id(200+index),member,value.date.slice(0,10)]);
  await admin(`insert into workout_exercises(id,session_id,client_id) values($1,$2,$3)`,[id(210+index),id(200+index),'stable-coaching-exercise']);
  await admin(`insert into workout_sets(id,exercise_id,set_no,type,weight,reps,completed,rest_seconds) values($1,$2,1,'normal',40,10,true,90)`,[id(220+index),id(210+index)]);
}
const links = () => rpc('list_management_links');
const corrections = () => rpc('list_workout_corrections');
const history = (link,before=null) => rpc('list_managed_workouts',[link,before]);
const propose = (link,record,value=50,req=request(),metric='weight') => rpc('propose_workout_correction',[
  link,record.key,record.revision,'stable-coaching-exercise',1,metric,value,'회원과 확인한 기록 정정',req]);

// Consultation and an old coaching relationship alone grant no management access.
await asUser(trainerUser);
assert.deepEqual(await links(),[]);
await assert.rejects(() => history(id(999)),/consent required/);
for (const outsider of [stranger,gymOwner,pendingUser,otherTrainerUser]) {
  await asUser(outsider);
  await assert.rejects(()=>rpc('request_management_link',[id(100)]),/participant required/);
}
await asUser(trainerUser);
await rpc('request_management_link',[id(100)]);
await rpc('request_management_link',[id(100)]);
let link = (await links())[0].id;
assert.equal((await links()).length,1);
assert.equal((await links())[0].can_respond,false);
await assert.rejects(()=>rpc('respond_management_link',[link,true]),/already consented/);
await assert.rejects(()=>history(link),/consent required/);
await asUser(member);
assert.equal((await links())[0].can_respond,true);
await rpc('respond_management_link',[link,true]);
assert.equal((await links())[0].status,'active');
await rpc('respond_management_link',[link,true]); // safe response replay
await asUser(trainerUser);
let page = await history(link);
assert.equal(page.workouts.length,2);
let recent = page.workouts.find(w=>w.key === 'personal:2026-09-11');
let historical = page.workouts.find(w=>w.key === 'personal:2026-09-08');
assert.equal(recent.requires_approval,false);
assert.equal(historical.requires_approval,true);
const retry = request();
await propose(link,recent,45,retry);
await propose(link,recent,45,retry);
await assert.rejects(()=>propose(link,recent,46,retry),/bound to another/);
await assert.rejects(()=>propose(link,recent,47),/Workout changed/);
assert.equal((await corrections()).length,1);
assert.equal((await corrections())[0].status,'applied');
let snapshot = (await admin('select payload,updated_at from app_state_snapshots where user_id=$1',[member]))[0];
assert.equal(snapshot.payload.sessions[0].exercises[0].sets[0].weight,45);
assert.equal(snapshot.payload.preferences.preserve,'yes');
assert.equal(snapshot.payload.profile.heightCm,177);
assert.equal(snapshot.payload.sessions[1].exercises[0].sets[0].weight,40);
assert.equal(Number((await admin('select weight from workout_sets where id=$1',[id(220)]))[0].weight),45);
await asUser(member);
await assert.rejects(()=>sql('select private.save_my_account_snapshot($1,11::smallint,$2,$3,$4)',[
  member,{...snapshot.payload,sessions:[today,old]},[],snapshot.updated_at]),/Workout corrections changed/);
assert.deepEqual((await sql('select private.save_my_account_snapshot($1,11::smallint,$2,$3,$4) result',[
  member,snapshot.payload,[],snapshot.updated_at]))[0].result,{accepted:true});

// A proposal does not change either canonical or normalized records until approval.
await asUser(trainerUser);
await propose(link,historical,60);
for (const [metric,value] of [['weight',-1],['weight',10000],['reps',1.5],['reps',0],['distanceKm',-1],['rir',11],['completed',1]]) {
  await assert.rejects(()=>propose(link,historical,value,request(),metric),/Invalid metric/);
}
let pending = (await corrections()).find(c=>c.status === 'pending');
assert.equal(pending.before_value,40); assert.equal(pending.after_value,60);
assert.equal((await history(link)).workouts.find(w=>w.key === historical.key).session.exercises[0].sets[0].weight,40);
await assert.rejects(()=>rpc('respond_workout_correction',[pending.id,true]),/record owner/);
await asUser(otherMember);
await assert.rejects(()=>rpc('respond_workout_correction',[pending.id,true]),/record owner/);
await asUser(member);
await rpc('respond_workout_correction',[pending.id,true]);
await rpc('respond_workout_correction',[pending.id,true]);
assert.equal((await corrections()).find(c=>c.id === pending.id).status,'applied');
assert.equal((await history(link)).workouts.find(w=>w.key === historical.key).session.exercises[0].sets[0].weight,60);

// Approving one of two concurrent proposals makes the second stale, never overwrites it.
await asUser(trainerUser);
historical = (await history(link)).workouts.find(w=>w.key === historical.key);
await propose(link,historical,61);
await propose(link,historical,62);
const proposals = (await corrections()).filter(c=>c.status === 'pending');
await asUser(member);
await rpc('respond_workout_correction',[proposals[0].id,true]);
await rpc('respond_workout_correction',[proposals[1].id,true]);
assert.equal((await corrections()).filter(c=>c.status === 'conflict').length,1);

// Exact 48h boundary comes from the server, for both personal and lesson records.
await asUser(member);
await rpc('set_lesson_recording_consent',[lesson,true]);
await asUser(trainerUser);
let lessonRecord = await rpc('open_lesson_workout',[lesson]);
lessonRecord = await save(lessonRecord,session(true));
await clock('2026-09-13T09:59:59.999Z');
recent = (await history(link)).workouts.find(w=>w.key === recent.key);
assert.equal(recent.requires_approval,false);
await clock('2026-09-13T10:00:00Z');
assert.equal((await history(link)).workouts.find(w=>w.key === recent.key).requires_approval,true);
await clock('2026-09-13T10:59:59.999Z');
let lessonManaged = (await history(link)).workouts.find(w=>w.key === 'coaching:'+lessonRecord.id);
assert.equal(lessonManaged.requires_approval,false);
await propose(link,lessonManaged,70);
assert.equal((await history(link)).workouts.find(w=>w.key === lessonManaged.key).session.exercises[0].sets[0].weight,70);
await clock('2026-09-13T11:00:00Z');
lessonManaged = (await history(link)).workouts.find(w=>w.key === lessonManaged.key);
assert.equal(lessonManaged.requires_approval,true);
await admin("update coaching_schedules set date='2026-09-20',end_time='23:00' where id=$1",[lesson]);
await asUser(trainerUser);
assert.equal((await history(link)).workouts.find(w=>w.key === lessonManaged.key).requires_approval,true,
  'Rescheduling a past lesson must not reopen its edit window');
await admin("update coaching_schedules set completed_at='2026-09-11T10:30:00Z' where id=$1",[lesson]);
await admin('update coaching_schedules set completed_at=null where id=$1',[lesson]);
await clock('2026-09-13T10:30:00Z');
await asUser(trainerUser);
assert.equal((await history(link)).workouts.find(w=>w.key === lessonManaged.key).requires_approval,true,
  'Undoing completion must not erase the actual earlier lesson ending');
await propose(link,lessonManaged,71);
pending = (await corrections()).find(c=>c.status === 'pending');
await asUser(member);
await rpc('respond_workout_correction',[pending.id,false]);
assert.equal((await corrections()).find(c=>c.id === pending.id).status,'rejected');

// Gym access requires explicit selection AND a current real membership.
await asUser(gymOwner);
assert.deepEqual(await links(),[]);
await assert.rejects(()=>history(link),/consent required/);
await asUser(trainerUser);
await assert.rejects(()=>rpc('set_management_gym',[link,gym]),/connected member/);
await asUser(member);
await assert.rejects(()=>rpc('set_management_gym',[link,id(999)]),/membership required/);
await rpc('set_management_gym',[link,gym]);
await asUser(gymOwner);
assert.equal((await links())[0].viewer_role,'gym');
assert.equal((await history(link)).workouts.every(w=>!w.can_propose),true);
await assert.rejects(()=>propose(link,recent,80),/Connected trainer/);
await admin("update members set status='ended' where id=$1",[id(120)]);
await asUser(gymOwner);
await assert.rejects(()=>history(link),/consent required/);
await admin("update members set status='active' where id=$1",[id(120)]);

// A center can request reassignment, but both the new trainer and member consent.
await asUser(gymOwner);
await rpc('request_management_trainer_change',[link,otherTrainer]);
await rpc('request_management_trainer_change',[link,otherTrainer]);
const transfer = (await links()).find(l=>l.status === 'pending').id;
await assert.rejects(()=>history(transfer),/consent required/);
await asUser(otherTrainerUser);
await rpc('respond_management_link',[transfer,true]);
assert.equal((await links()).find(l=>l.id === transfer).status,'pending');
await assert.rejects(()=>history(transfer),/consent required/);
await asUser(member);
await rpc('respond_management_link',[transfer,true]);
assert.equal((await links()).find(l=>l.id === transfer).status,'active');
assert.equal((await links()).find(l=>l.id === link).status,'ended');
await asUser(trainerUser);
await assert.rejects(()=>history(link),/consent required/);
await asUser(otherTrainerUser);
assert.ok((await history(transfer)).workouts.length > 0);
for (let i=1;i<=24;i++) {
  const date = `2026-08-${String(i).padStart(2,'0')}`;
  await clock(date+'T00:00:00Z');
  await create(session(false,date),request(),member,date);
}
await clock('2026-09-13T11:00:00Z');
let cursor = null;
const allKeys = [];
do {
  const page = await history(transfer,cursor);
  allKeys.push(...page.workouts.map(w=>w.key));
  cursor = page.next_cursor;
} while (cursor);
assert.equal(allKeys.length,27);
assert.equal(new Set(allKeys).size,27,'Every page is stable and has no duplicated/missing records');

// Revocation cancels pending corrections and closes every future read and write.
historical = (await history(transfer)).workouts.find(w=>w.key === historical.key);
await propose(transfer,historical,90);
pending = (await corrections()).find(c=>c.status === 'pending');
await asUser(member);
await rpc('end_management_link',[transfer]);
assert.equal((await corrections()).find(c=>c.id === pending.id).status,'cancelled');
await rpc('respond_workout_correction',[pending.id,true]);
await asUser(otherTrainerUser);
await assert.rejects(()=>history(transfer),/consent required/);
await assert.rejects(()=>propose(transfer,historical,91),/consent required/);
await assert.rejects(()=>sql('select private.management_record($1,$2)',[member,historical.key]),/permission denied/);
await assert.rejects(()=>sql('select private.apply_workout_correction($1)',[pending.id]),/permission denied/);
await assert.rejects(()=>sql("update public.coaching_management_links set status='active'"),/permission denied/);
await asUser(null,'anon');
await assert.rejects(()=>links(),/permission denied/);
const notices = await admin("select * from user_notifications where data->>'event'='coaching_management'");
assert.ok(notices.length > 0,'Notifications are retained without push devices');
console.log('PASS: mutual consent, full history, atomic corrections, 48h boundaries, approvals, gym access, reassignment, revocation, RPC permissions');
await db.close();
