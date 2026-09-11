// Run: node tool/test_coaching_workouts.mjs <path-to-@electric-sql/pglite>
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
const { PGlite } = require(process.argv[2] || '@electric-sql/pglite');
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

// Access defaults, exact lesson ownership, and member-only separate consent.
await asUser(trainerUser);
let record = await rpc('open_lesson_workout',[lesson]);
assert.equal(record.kind,'lesson'); assert.equal(record.can_edit,false); assert.equal(record.recording_allowed,false);
assert.equal(new Date(record.starts_at).toISOString(),'2026-09-11T10:00:00.000Z');
await assert.rejects(()=>save(record,session()), /recording is not allowed/);
await assert.rejects(()=>rpc('set_lesson_recording_consent',[lesson,true]),/Only the scheduled member/);
for (const outsider of [stranger,gymOwner,pendingUser,otherTrainerUser]) {
  await asUser(outsider);
  await assert.rejects(()=>rpc('open_lesson_workout',[lesson]),/Assigned trainer or member/);
  assert.deepEqual(await rpc('list_coaching_workouts',[member]),[]);
}
await asUser(member);
await rpc('set_lesson_recording_consent',[lesson,true]);
assert.equal((await rpc('open_lesson_workout',[lesson])).can_edit,false);
await assert.rejects(()=>save(record,session()),/recording is not allowed/);
await asUser(trainerUser);
record = await rpc('open_lesson_workout',[lesson]);
assert.equal(record.can_edit,true); assert.equal(record.recording_allowed,true);

// Transactional saves, versions, exact replay, request payload binding, audit.
const firstSaveRequest = request();
const oldRecord = record;
record = await save(record,session(),firstSaveRequest);
assert.equal(record.version,2); assert.equal(record.member_user_id,member);
assert.equal(record.last_editor_name,'트레이너');
assert.deepEqual(await save(oldRecord,session(),firstSaveRequest),record);
await assert.rejects(()=>save(oldRecord,session(),request()),/changed; reload/);
await assert.rejects(()=>save(oldRecord,session(true),firstSaveRequest),/request ID cannot be reused/);
let notifications = await admin('select * from user_notifications');
assert.equal(notifications.length,1); assert.equal(notifications[0].data.workoutId,record.id);
assert.equal((await admin('select * from push_outbox')).length,0,'No device still retains inbox notification');
assert.equal((await admin("select * from coaching_workout_events where event='recorded'")).length,1);
assert.equal((await admin('select payload from app_state_snapshots'))[0].payload.sessions.length,0,'Does not mutate personal snapshots');
assert.equal((await admin('select * from workout_sessions')).length,0,'Does not mutate personal projections');
await asUser(trainerUser);
record = await save(record,session(true));
assert.equal(record.status,'completed');
assert.equal((await admin('select * from user_notifications')).length,1,'No per-set push spam');

// Consent revocation/time expiry blocks new writes but exact successful retries
// remain side-effect-free acknowledgements, even after permission expires.
await asUser(member);
await rpc('set_lesson_recording_consent',[lesson,false]);
await asUser(trainerUser);
await assert.rejects(()=>save(record,session()),/recording is not allowed/);
await clock('2026-09-11T11:00:00Z');
assert.deepEqual(await save(oldRecord,session(),firstSaveRequest),await rpc('save_coaching_workout',[oldRecord.id,oldRecord.version,session(),firstSaveRequest]));
assert.equal((await rpc('open_lesson_workout',[lesson])).can_edit,false);
await asUser(member);
await assert.rejects(()=>rpc('set_lesson_recording_consent',[lesson,true]),/lesson has ended/);
await clock();
await rpc('set_lesson_recording_consent',[lesson,true]);
await rpc('set_lesson_recording_consent',[lessonBefore,true]);
await asUser(trainerUser);
let futureLesson = await rpc('open_lesson_workout',[lessonBefore]);
assert.equal(futureLesson.can_edit,false);
await assert.rejects(()=>save(futureLesson,session()),/recording is not allowed/);
await clock('2026-09-11T11:00:00Z');
futureLesson = await rpc('open_lesson_workout',[lessonBefore]);
assert.equal(futureLesson.can_edit,true,'Exactly at booked start is permitted');
await save(futureLesson,session());
await clock('2026-09-11T12:00:00Z');
await assert.rejects(()=>save(futureLesson,session()),/recording is not allowed/);
await clock();
const finishedLesson = await rpc('open_lesson_workout',[lessonDone]);
assert.equal(finishedLesson.can_edit,false);
await assert.rejects(()=>save(finishedLesson,session()),/recording is not allowed/);

// Assignment ownership; trainer sets a plan but cannot write member completion.
const createRequest = request();
let assignment = await create(session(),createRequest);
assert.equal(assignment.kind,'assignment'); assert.equal(assignment.status,'assigned'); assert.equal(assignment.can_edit,false);
assert.deepEqual(await create(session(),createRequest),assignment);
await assert.rejects(()=>create(session(true)),/uncompleted exercise sets/);
await assert.rejects(()=>create(emptySession),/uncompleted exercise sets/);
await assert.rejects(()=>create(session(),request(),otherMember),/approved assigned trainer/);
await assert.rejects(()=>save(assignment,session(true)),/recording is not allowed/);
await asUser(pendingUser);
await assert.rejects(()=>create(),/approved assigned trainer/);
await asUser(member);
assert.ok((await rpc('list_coaching_workouts',[])).some(w=>w.id===assignment.id && w.can_edit));
await assert.rejects(()=>create(),/approved assigned trainer/);

// Invalid/nested/oversized payloads fail without changing the record version.
const invalids = [];
const duplicate = session(); duplicate.exercises.push(structuredClone(duplicate.exercises[0])); invalids.push(duplicate);
const wrongDate = session(false,'2026-09-12'); invalids.push(wrongDate);
const missingTemplate = session(); delete missingTemplate.exercises[0].template; invalids.push(missingTemplate);
const badWeight = session(); badWeight.exercises[0].sets[0].weight = -1; invalids.push(badWeight);
const fractionReps = session(); fractionReps.exercises[0].sets[0].reps = 3.5; invalids.push(fractionReps);
const textCompleted = session(); textCompleted.exercises[0].sets[0].completed = 'false'; invalids.push(textCompleted);
const badNumber = session(); badNumber.exercises[0].sets[0].number = 2; invalids.push(badNumber);
const tooManySets = session(); tooManySets.exercises[0].sets = Array.from({length:31},(_,i)=>({...set(),number:i+1})); invalids.push(tooManySets);
const tooManyExercises = session(); tooManyExercises.exercises = Array.from({length:51},(_,i)=>({...structuredClone(tooManyExercises.exercises[0]),id:'ex-'+i})); invalids.push(tooManyExercises);
const invalidRir = session(); invalidRir.exercises[0].sets[0].rir = 99; invalids.push(invalidRir);
const invalidCardio = session(); invalidCardio.exercises[0].template.muscle = '유산소'; invalids.push(invalidCardio);
for (const value of invalids) await assert.rejects(()=>save(assignment,value),/Invalid|must be numeric|outside supported|cannot change/);
const noActual = session(true); noActual.exercises[0].sets[0].reps = 0;
await assert.rejects(()=>save(assignment,noActual),/completed set needs/);
await assert.rejects(()=>save(assignment,{...session(),extra:'x'.repeat(550000)}),/Invalid coaching workout session/);
assert.equal((await rpc('list_coaching_workouts',[member])).find(w=>w.id===assignment.id).version,1);

// Same expected version: exactly one update wins; the loser receives HTTP 409.
const concurrent = await Promise.allSettled([save(assignment,session(true)),save(assignment,session())]);
assert.equal(concurrent.filter(r=>r.status==='fulfilled').length,1);
const rejected = concurrent.find(r=>r.status==='rejected').reason;
assert.equal(rejected.code,'PT409');
assignment = (await rpc('list_coaching_workouts',[member])).find(w=>w.id===assignment.id);
assert.equal(assignment.status,'completed');
assignment = await save(assignment,session());
assert.equal(assignment.status,'assigned','Member can undo accidental completion');
assignment = await save(assignment,session(true));
const completionPushes = await admin("select * from user_notifications where title='회원이 운동 과제를 마쳤어요'");
assert.equal(completionPushes.length,1,'Repeated complete/undo does not spam trainer');
assert.equal(completionPushes[0].user_id,trainerUser);
await asUser(trainerUser);
await assert.rejects(()=>rpc('cancel_workout_assignment',[assignment.id,assignment.version,request()]),/Completed or cancelled/);

// Explicit trainer cancellation and member decline preserve the original plan.
let cancelled = await create();
const cancelRequest = request();
const cancelledOld = cancelled;
cancelled = await rpc('cancel_workout_assignment',[cancelled.id,cancelled.version,cancelRequest]);
assert.equal(cancelled.status,'cancelled');
assert.equal(cancelled.session.exercises.length,1);
assert.deepEqual(await rpc('cancel_workout_assignment',[cancelledOld.id,cancelledOld.version,cancelRequest]),cancelled);
let declined = await create();
await asUser(member);
declined = await rpc('cancel_workout_assignment',[declined.id,declined.version,request()]);
assert.equal(declined.status,'cancelled');
await assert.rejects(()=>save(cancelled,session()),/recording is not allowed/);
assert.equal((await admin("select * from coaching_workout_events where event='declined'")).length,1);

// Daily reminders use the existing inbox+outbox gateway and opt in only.
await asUser(trainerUser);
const reminderTask = await create();
const laterTask = await create(session(false,'2026-09-12'),request(),member,'2026-09-12');
await asUser(member);
assert.deepEqual(await rpc('get_my_coaching_reminder'),{enabled:false,hour:19});
await assert.rejects(()=>rpc('set_my_coaching_reminder',[true,23]),/between 6 and 22/);
assert.equal((await admin('select private.remind_coaching_workouts() count'))[0].count,0);
await asUser(member);
await rpc('set_my_coaching_reminder',[true,19]);
await admin("insert into device_tokens values($1,'test-device')",[member]);
await clock('2026-09-11T09:50:00Z');
assert.equal((await admin('select private.remind_coaching_workouts() count'))[0].count,0,'Not before chosen KST hour');
await clock();
assert.equal((await admin('select private.remind_coaching_workouts() count'))[0].count,1);
assert.equal((await admin('select private.remind_coaching_workouts() count'))[0].count,0,'Same-day deduplication');
assert.equal((await admin("select * from push_outbox where title='오늘의 운동 과제를 확인해요'")).length,1);
await asUser(member);
await rpc('set_my_coaching_reminder',[false,19]);
await rpc('set_my_coaching_reminder',[true,19]);
assert.equal((await admin('select private.remind_coaching_workouts() count'))[0].count,0,'Toggling opt-in does not reset deduplication');
await clock('2026-09-12T10:30:00Z');
assert.equal((await admin('select private.remind_coaching_workouts() count'))[0].count,1,'Pending task remains eligible next day');
await asUser(member);
await save(reminderTask,session(true));
await rpc('cancel_workout_assignment',[laterTask.id,laterTask.version,request()]);
await clock('2026-09-13T10:30:00Z');
assert.equal((await admin('select private.remind_coaching_workouts() count'))[0].count,0,'Completed/cancelled tasks stop reminding');

// Relationship end disables writes/reads/reminders for trainer, preserving member history.
await clock();
await asUser(trainerUser);
const endedTask = await create();
await admin("update coachings set status='ended' where trainer_id=$1",[trainer]);
await asUser(trainerUser);
assert.deepEqual(await rpc('list_coaching_workouts',[member]),[]);
await assert.rejects(()=>save(record,session()),/recording is not allowed/);
await assert.rejects(()=>create(),/approved assigned trainer/);
await asUser(member);
assert.ok((await rpc('list_coaching_workouts',[])).some(w=>w.id===endedTask.id && !w.can_edit));
await assert.rejects(()=>save(endedTask,session(true)),/recording is not allowed/);
await clock('2026-09-14T10:30:00Z');
assert.equal((await admin('select private.remind_coaching_workouts() count'))[0].count,0);

// Replacing an old personal snapshot does not remove any canonical records.
const canonicalCount = (await admin('select count(*)::int count from coaching_workouts'))[0].count;
await admin("update app_state_snapshots set payload='{}'");
await admin('delete from workout_sessions');
assert.equal((await admin('select count(*)::int count from coaching_workouts'))[0].count,canonicalCount);

// Existing consent-scoped history includes ALL canonical trainers' work and
// personal records in one cursor, preserving completed work on cancellation.
await admin(`insert into coaching_health_consents values($1,$2,$3,$4,true,false)`,[lessonBefore,member,trainer,gym]);
for (let i=0;i<25;i++) await admin('insert into workout_sessions(id,user_id,date) values($1,$2,$3)',
  [id(500+i),member,i<13 ? day : '2020-01-01']);
const oldSession = session(true,'2020-01-01');
const partialSession = session(true,'2020-01-01');
partialSession.exercises[0].sets.push({...set(),number:2});
await admin(`insert into coaching_workouts(id,kind,status,trainer_id,member_user_id,workout_date,title,session)
  values($1,'lesson','completed',$2,$3,'2020-01-01','이전 트레이너 수업',$4),
  ($5,'assignment','cancelled',$2,$3,'2020-01-01','부분 완료 후 취소',$6)`,
  [id(700),otherTrainer,member,oldSession,id(701),partialSession]);
await asUser(trainerUser);
let cursor = null;
const history = [];
do {
  const page = await rpc('list_coaching_workout_history',[lessonBefore,cursor?.date ?? null,cursor?.id ?? null]);
  assert.ok(page.sessions.length<=20);
  history.push(...page.sessions);
  cursor = page.next_cursor;
} while(cursor);
assert.equal(new Set(history.map(item=>item.id)).size,history.length,'Merged cursor never duplicates a row');
assert.equal(history.filter(item=>!item.coaching_workout_id).length,25,'All personal pages retained');
assert.ok(history.some(item=>item.id===id(700)),'Prior trainer canonical history remains visible through consent');
assert.equal(history.find(item=>item.id===id(701)).exercises[0].sets.length,1,'Cancelled history keeps completed sets only');
assert.ok(!history.some(item=>item.id===cancelled.id),'Unperformed cancellation is omitted from history');
const canonicalExercises = history.filter(item=>item.coaching_workout_id).flatMap(item=>item.exercises);
const projectionIds = canonicalExercises.flatMap(exercise=>[exercise.id,...exercise.sets.map(set=>set.id)]);
const projectionUuid = /^[0-9a-f]{8}-[0-9a-f]{4}-3[0-9a-f]{3}-8[0-9a-f]{3}-[0-9a-f]{12}$/;
assert.ok(projectionIds.length>0 && projectionIds.every(value=>projectionUuid.test(value)),
  'History exercise/set IDs satisfy the Dart UUID contract, including version and variant bits');
assert.equal(new Set(projectionIds).size,projectionIds.length,'Namespaces separate exercises, sets and different workout records');
const reread = (await admin('select private.coaching_workout_history_json(workout) result from coaching_workouts workout where id=$1',[id(700)]))[0].result;
assert.deepEqual(reread.exercises,history.find(item=>item.id===id(700)).exercises,'Projection UUIDs remain stable across reads');
for (let i=1;i<history.length;i++) assert.ok(history[i-1].date>=history[i].date);
const accessLogCount = (await admin('select count(*)::int count from coaching_health_access_logs'))[0].count;
assert.equal(accessLogCount,Math.ceil(history.length/20),'Exactly one consent-gated access log per page');
await admin('update coaching_health_consents set share_with_trainer=false');
await asUser(trainerUser);
await assert.rejects(()=>rpc('list_coaching_workout_history',[lessonBefore,null,null]),/Member consent is required/);
await asUser(stranger);
await assert.rejects(()=>rpc('list_coaching_workout_history',[lessonBefore,null,null]),/Member consent is required/);

// Center-assigned offline members also qualify without a mobile coaching pair.
await clock();
await admin('insert into members values($1,$2,$3,\'active\')',[id(800),gym,otherMember]);
await admin('insert into member_assignments values($1,$2,$3,true)',[id(800),gym,trainer]);
await admin('insert into gym_trainers values($1,$2,\'active\')',[gym,trainer]);
await asUser(trainerUser);
let centerAssignment = await create(session(),request(),otherMember);
assert.equal(centerAssignment.member_user_id,otherMember);
await asUser(otherMember);
centerAssignment = await save(centerAssignment,session(true));
assert.equal(centerAssignment.status,'completed');
await admin('update member_assignments set active=false where trainer_id=$1',[trainer]);
await asUser(otherMember);
await assert.rejects(()=>save(centerAssignment,session()),/recording is not allowed/);

// Every exposed table is closed to direct writes and raw private helpers.
await asUser(member);
for (const table of ['coaching_workouts','coaching_recording_consents','coaching_workout_requests','coaching_workout_events','coaching_reminder_preferences']) {
  await assert.rejects(()=>sql(`select * from public.${table}`),/permission denied/);
  await assert.rejects(()=>sql(`delete from public.${table}`),/permission denied/);
}
await assert.rejects(()=>sql('select private.remind_coaching_workouts()'),/permission denied/);
await asUser(null,'anon');
await assert.rejects(()=>rpc('list_coaching_workouts',[]),/permission denied/);
await asUser(null);
await assert.rejects(()=>rpc('list_coaching_workouts',[]),/Authentication required/);
console.log('PASS: coaching workout SQL — ownership, consent/time, versions/replay, validation, completion/undo, cancellation, reminders, audit, snapshot isolation, combined history, center assignments');
await db.close();
