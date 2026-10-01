// Run: node tool/test_consultation_chat.mjs [path-to-@electric-sql/pglite]
// Runs the production migration and authorization/notification functions unchanged.
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { createRequire } from 'node:module';
const require = createRequire(import.meta.url);
const { PGlite } = require(process.argv[2] || '../.dart_tool/workspace-security/node_modules/@electric-sql/pglite');
process.on('uncaughtException', error => {
  console.error(error.message, error.code ?? '', error.where ?? '');
  console.error(error.stack?.split('\n').slice(0, 5).join('\n'));
  process.exit(1);
});
const db = new PGlite();
const id = n => `00000000-0000-4000-8000-${String(n).padStart(12, '0')}`;
const member = id(1), trainerUser = id(2), gymOwner = id(3), stranger = id(4);
const otherTrainerUser = id(5), pendingUser = id(6), trainer = id(10), otherTrainer = id(11);
const pendingTrainer = id(12), gym = id(20), direct = id(30), assigned = id(31), gymOnly = id(32);
let requestCount = 1000;
const request = () => id(++requestCount);
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
  create function auth.jwt() returns jsonb language sql stable as
    $$ select coalesce(nullif(current_setting('request.jwt.claims',true),''),'{}')::jsonb $$;
  create function auth.uid() returns uuid language sql stable as
    $$ select nullif(auth.jwt()->>'sub','')::uuid $$;
  create table auth.users(id uuid primary key,deleted_at timestamptz,banned_until timestamptz,is_anonymous boolean default false);
  create table auth.sessions(id uuid primary key,user_id uuid,not_after timestamptz);
  create table public.users(id uuid primary key,nickname text,status text default 'active');
  create table public.trainers(id uuid primary key,user_id uuid,status text,display_name text);
  create table public.gyms(id uuid primary key,owner_user_id uuid,status text);
  create table public.gym_trainers(gym_id uuid,trainer_id uuid,trainer_user_id uuid,status text);
  create table public.admin_users(user_id uuid,status text);
  create table public.consultations(id uuid primary key,user_id uuid,trainer_id uuid,assigned_trainer_id uuid,
    gym_id uuid,requester_name text,question text,status text default 'pending',is_read boolean default false);
  create table public.consultation_messages(id uuid primary key default gen_random_uuid(),request_id uuid,
    consultation_id uuid references consultations(id),sender_type text check(sender_type in ('user','trainer','gym')),
    sender_id uuid,text text,created_at timestamptz default now());
  create unique index consultation_messages_sender_request_uidx on consultation_messages(sender_id,request_id)
    where request_id is not null;
  create table public.app_state_snapshots(user_id uuid primary key,payload jsonb);
  create table public.user_notifications(id uuid default gen_random_uuid(),user_id uuid,kind text,title text,body text,data jsonb);
  create table public.push_outbox(id uuid default gen_random_uuid(),user_id uuid,kind text,title text,body text,data jsonb);
  create table public.device_tokens(user_id uuid,token text);
  insert into users(id,nickname) values ('${member}','회원'),('${trainerUser}','담당 트레이너'),('${gymOwner}','센터장'),
    ('${stranger}','외부인'),('${otherTrainerUser}','다른 트레이너'),('${pendingUser}','심사중');
  insert into auth.users(id) select id from users;
  insert into auth.sessions(id,user_id) select id,id from users;
  insert into trainers values('${trainer}','${trainerUser}','approved','담당 트레이너'),
    ('${otherTrainer}','${otherTrainerUser}','approved','다른 트레이너'),('${pendingTrainer}','${pendingUser}','pending','심사중');
  insert into gyms values('${gym}','${gymOwner}','verified');
  insert into gym_trainers values('${gym}','${trainer}','${trainerUser}','active'),
    ('${gym}','${otherTrainer}','${otherTrainerUser}','active');
  insert into consultations values('${direct}','${member}','${trainer}',null,null,'회원','첫 질문','pending',false),
    ('${assigned}','${member}',null,'${trainer}','${gym}','회원','센터 질문','assigned',false),
    ('${gymOnly}','${member}',null,null,'${gym}','회원','센터에게','pending',false);
  insert into device_tokens select id,id::text from users;
`);
await db.exec(sourceFunction('supabase/migrations/20260919163342_server_managed_workspace_access.sql', 'private.has_active_app_session('));
await db.exec(sourceFunction('supabase/migrations/20260816130351_consultation_trainer_handoff.sql', 'private.can_access_business_consultation('));
await db.exec(sourceFunction('supabase/migrations/20260828090000_push_catalog.sql', 'private.push_enabled('));
await db.exec(sourceFunction('supabase/migrations/20260828090000_push_catalog.sql', 'private.display_name_of('));
await db.exec(sourceFunction('supabase/migrations/20260903090000_notification_inbox.sql', 'private.enqueue_push('));
await db.exec(`
  grant select,insert,update,delete on consultations,consultation_messages to authenticated;
  alter table consultations enable row level security;
  alter table consultation_messages enable row level security;
  create policy consultations_participant_read on consultations for select to authenticated
    using (private.can_access_business_consultation(id));
  create policy consultation_messages_participant_read on consultation_messages for select to authenticated
    using (private.can_access_business_consultation(consultation_id));
  create policy app_active_session on consultations as restrictive for all to authenticated
    using (private.has_active_app_session()) with check (private.has_active_app_session());
  create policy app_active_session on consultation_messages as restrictive for all to authenticated
    using (private.has_active_app_session()) with check (private.has_active_app_session());
  create policy consultation_messages_requester_insert on consultation_messages for insert to authenticated
    with check (sender_type='user' and sender_id=auth.uid());
  create function private.notify_consultation_reply() returns trigger language plpgsql as $$ begin return new; end $$;
  create trigger notify_consultation_reply after insert on consultation_messages
    for each row execute function private.notify_consultation_reply();
`);
await db.exec(readFileSync('supabase/migrations/20261001070634_consultation_chat.sql','utf8'));
await db.exec(sourceFunction('supabase/migrations/20260816131113_consultation_request_idempotency.sql', 'public.reply_business_consultation('));
await db.exec(`
  revoke all on function public.reply_business_consultation(uuid,uuid,text) from public,anon;
  grant execute on function public.reply_business_consultation(uuid,uuid,text) to authenticated,service_role;
  revoke all on function private.reply_business_consultation(uuid,uuid,text) from public,anon;
  grant execute on function private.reply_business_consultation(uuid,uuid,text) to authenticated,service_role;
`);
async function asUser(user, role='authenticated', session=user) {
  await db.exec(`reset role; set role ${role}`);
  await db.query("select set_config('request.jwt.claims',$1,false)",[JSON.stringify({sub:user,session_id:session})]);
}
async function sql(query, params=[]) { return (await db.query(query,params)).rows; }
async function admin(query,params=[]) { await db.exec('reset role'); return sql(query,params); }
async function send(conversation,text,req=request(),endpoint='send_consultation_message') {
  return (await sql(`select public.${endpoint}($1,$2,$3) result`,[req,conversation,text]))[0].result;
}
const count = async table => Number((await admin(`select count(*) value from ${table}`))[0].value);
const refusal = (action,code='42501') => assert.rejects(action, error => error.code===code);
for (const signature of ['public.send_consultation_message(uuid,uuid,text)',
  'private.send_consultation_message(uuid,uuid,text,boolean)',
  'private.reply_business_consultation(uuid,uuid,text)']) {
  const privileges = (await admin('select has_function_privilege($1,$2,$3) anon,has_function_privilege($4,$2,$3) member',
    ['anon',signature,'EXECUTE','authenticated']))[0];
  assert.equal(privileges.anon,false); assert.equal(privileges.member,true);
}

await asUser(member);
const memberRequest = request();
const question = await send(direct,'  한 번 더 질문할게요  ',memberRequest);
assert.equal(question.sender_type,'user'); assert.equal(question.status,'pending'); assert.equal(question.replayed,false);
assert.equal(await count('consultation_messages'),1);
let notices = await admin('select * from user_notifications');
assert.equal(notices[0].user_id,trainerUser); assert.equal(notices[0].kind,'business');
assert.equal(notices[0].data.consultationId,direct); assert.equal(notices[0].data.event,'consultation_message');
assert.equal(await count('push_outbox'),1);
await asUser(member);
const replay = await send(direct,'한 번 더 질문할게요',memberRequest);
assert.equal(replay.message_id,question.message_id); assert.equal(replay.replayed,true);
assert.equal(await count('consultation_messages'),1); assert.equal(await count('user_notifications'),1);
await asUser(member);
await refusal(()=>send(direct,'다른 본문',memberRequest),'22023');
await refusal(()=>send(assigned,'한 번 더 질문할게요',memberRequest),'22023');
await refusal(()=>send(direct,' '),'22023'); await refusal(()=>send(direct,'가'.repeat(5001)),'22023');
await refusal(()=>send(direct,'ID 누락',null),'22023');
await refusal(()=>send(direct,'회원은 사업자 답변 불가',request(),'reply_business_consultation'));

await asUser(trainerUser);
const trainerRequest = request();
const answer = await send(direct,'천천히 진행해주세요',trainerRequest,'reply_business_consultation');
assert.equal(answer.sender_type,'trainer'); assert.equal(answer.status,'replied');
notices = await admin('select * from user_notifications where user_id=$1',[member]);
assert.equal(notices.length,1); assert.equal(notices[0].data.event,'consultation_reply');
await asUser(trainerUser);
assert.equal((await send(direct,'천천히 진행해주세요',trainerRequest)).message_id,answer.message_id);
await asUser(member);
assert.equal((await send(direct,'그럼 횟수는 어떻게 해요?')).status,'pending');
assert.equal((await sql('select is_read from consultations where id=$1',[direct]))[0].is_read,false);
assert.equal((await send(assigned,'다음 질문')).status,'assigned');

await asUser(gymOwner);
assert.equal((await send(gymOnly,'센터에서 도와드릴게요')).sender_type,'gym');
await asUser(member);
await send(gymOnly,'담당 배정 부탁드려요');
assert.equal((await admin('select user_id from user_notifications order by ctid desc limit 1'))[0].user_id,gymOwner);

for (const actor of [stranger,otherTrainerUser,pendingUser]) {
  await asUser(actor); await refusal(()=>send(direct,'관계없는 상담'));
  assert.equal((await sql('select * from consultation_messages where consultation_id=$1',[direct])).length,0);
}
await asUser(stranger);
await refusal(()=>sql('select private.send_consultation_message($1,$2,$3,null)',[request(),direct,'NULL 역할 공격']),'22023');
await asUser(member,'anon'); await refusal(()=>send(direct,'게스트'));
await asUser(member,'authenticated',null); await refusal(()=>send(direct,'세션 만료'));
await admin('update users set status=$1 where id=$2',['suspended',member]);
await asUser(member); await refusal(()=>send(direct,'계정 이용 제한'));
await admin("update users set status='active' where id=$1",[member]);

// A member cannot bypass validation/status changes through a crafted table insert.
await asUser(member);
await refusal(()=>sql("insert into consultation_messages(consultation_id,sender_type,sender_id,text) values($1,'user',$2,'우회')",[direct,member]));
assert.equal((await sql('select * from consultation_messages where consultation_id=$1',[direct])).length,3);

// Reassignment changes both read and send authorization, including old retries.
await admin('update consultations set assigned_trainer_id=$1 where id=$2',[otherTrainer,assigned]);
await asUser(trainerUser); await refusal(()=>send(assigned,'이전 담당'));
assert.equal((await sql('select * from consultation_messages where consultation_id=$1',[assigned])).length,0);
await asUser(otherTrainerUser); assert.equal((await send(assigned,'새 담당입니다')).sender_type,'trainer');
await asUser(member); await send(assigned,'새 담당에게 질문');
assert.equal((await admin('select user_id from user_notifications order by ctid desc limit 1'))[0].user_id,otherTrainerUser);
await admin("update trainers set status='suspended' where id=$1",[trainer]);
await asUser(trainerUser); await refusal(()=>send(direct,'천천히 진행해주세요',trainerRequest));
assert.equal((await sql('select * from consultations where id=$1',[direct])).length,0);
await admin("update trainers set status='approved' where id=$1",[trainer]);
await admin("update gym_trainers set status='inactive' where trainer_id=$1",[otherTrainer]);
await asUser(otherTrainerUser); await refusal(()=>send(assigned,'센터 탈퇴 후 메시지'));
await admin("update gyms set status='suspended' where id=$1",[gym]);
await asUser(gymOwner); await refusal(()=>send(gymOnly,'미승인 센터'));

// Push preferences remain authoritative; no external calls happen in the trigger.
await admin('insert into app_state_snapshots values($1,$2)',[trainerUser,{preferences:{businessNotifications:{primary:false}}}]);
const beforeNotifications = await count('user_notifications');
await asUser(member); await send(direct,'알림을 꺼도 대화는 저장돼요');
assert.equal(await count('user_notifications'),beforeNotifications);
assert.equal(Number((await admin('select count(*) value from consultation_messages'))[0].value),9);
await db.close();
console.log('Consultation chat passed: member/trainer/gym messaging, canonical sender, retries, pending state, RLS, session revocation, reassignment and notification routing.');
