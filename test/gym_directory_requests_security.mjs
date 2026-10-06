// node test/gym_directory_requests_security.mjs
// Runs only in an ephemeral database; uses no network or account credentials.
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { PGlite } from '../.dart_tool/workspace-security/node_modules/@electric-sql/pglite/dist/index.js';

const db = new PGlite();
const member = '10000000-0000-4000-8000-000000000001';
const other = '10000000-0000-4000-8000-000000000002';
const memberSession = '20000000-0000-4000-8000-000000000001';
const otherSession = '20000000-0000-4000-8000-000000000002';
let checks = 0;

async function check(name, action) {
  await action();
  checks++;
  console.log(`PASS ${name}`);
}

async function asUser(user = member, session = memberSession) {
  await db.exec('reset role');
  await db.query("select set_config('request.jwt.claims', $1, false)", [JSON.stringify({ sub: user, session_id: session })]);
  await db.exec('set role authenticated');
}

async function submit({ id = 'request-1', kind = 'correction', facility = 'place-example', name = '테스트짐', address = '서울특별시 종로구 1', note = '주소 확인' } = {}) {
  return (await db.query(
    'select public.submit_gym_directory_request($1,$2,$3,$4,$5,$6) as receipt',
    [id, kind, facility, name, address, note],
  )).rows[0].receipt;
}

const denied = (action, code = '42501') => assert.rejects(action, { code });

try {
  await db.exec(await readFile(new URL('../tool/fixtures/workspace_access.sql', import.meta.url), 'utf8'));
  await db.exec(await readFile(new URL('../supabase/migrations/20260919163342_server_managed_workspace_access.sql', import.meta.url), 'utf8'));
  await db.exec(await readFile(new URL('../supabase/migrations/20261006220000_gym_directory_requests.sql', import.meta.url), 'utf8'));

  await check('guests can probe capability but cannot read or submit requests', async () => {
    await db.exec('set role anon');
    assert.equal((await db.query('select public.gym_directory_request_service_available() as available')).rows[0].available, true);
    await denied(() => submit());
    await denied(() => db.query('select * from private.gym_directory_requests'));
  });

  await check('receipt uses the authenticated owner and same-payload retries are idempotent', async () => {
    await asUser();
    const receipt = await submit();
    assert.equal(receipt.owner_user_id, member);
    assert.equal(receipt.id, 'request-1');
    assert.ok(Date.parse(receipt.submitted_at));
    assert.deepEqual(await submit(), receipt);
    assert.equal((await db.query('select * from private.gym_directory_requests')).rows.length, 1);
    await denied(() => submit({ note: 'different content' }), '23505');
  });

  await check('different accounts cannot collide with or see each other\'s request IDs', async () => {
    await asUser(other, otherSession);
    assert.equal((await db.query('select * from private.gym_directory_requests')).rows.length, 0);
    assert.equal((await submit()).owner_user_id, other);
    const rows = (await db.query('select * from private.gym_directory_requests')).rows;
    assert.equal(rows.length, 1);
    assert.equal(rows[0].owner_user_id, other);
    await asUser();
    assert.equal((await db.query('select * from private.gym_directory_requests')).rows.length, 1);
  });

  await check('ordinary accounts cannot bypass RPC validation or review requests', async () => {
    await denied(() => db.query("insert into private.gym_directory_requests(id,owner_user_id,kind,gym_name,address) values ('forged',$1,'add','가짜','주소')", [other]));
    await denied(() => db.query("update private.gym_directory_requests set owner_user_id=$1", [other]));
    assert.equal((await db.query("update private.gym_directory_requests set status='reviewed',reviewed_by=$1,reviewed_at=now() returning id", [member])).rows.length, 0);
    await denied(() => db.query("select public.review_gym_directory_request('request-1',$1,'reviewed','확인')", [member]));
    await denied(() => submit({ id: 'wrong-add', kind: 'add' }), '22023');
    await denied(() => submit({ id: 'wrong-claim', kind: 'claim', facility: null }), '22023');
    await denied(() => submit({ id: 'bad id' }), '22023');
    await denied(() => submit({ name: 'x'.repeat(151), id: 'too-long' }), '22023');
  });

  await check('claims do not mutate gyms, ownership, roles or memberships', async () => {
    await db.exec('reset role');
    const before = (await db.query('select * from public.gyms order by id')).rows;
    const beforeUsers = (await db.query('select * from public.users order by id')).rows;
    await asUser();
    await submit({ id: 'claim-1', kind: 'claim' });
    await db.exec('reset role');
    assert.deepEqual((await db.query('select * from public.gyms order by id')).rows, before);
    assert.deepEqual((await db.query('select * from public.users order by id')).rows, beforeUsers);
    await asUser();
  });

  await check('administrator review changes only the request queue and records the actor', async () => {
    await db.exec('reset role');
    await db.query("insert into public.admin_users(user_id,status) values($1,'active')", [other]);
    await asUser(other, otherSession);
    const receipt = (await db.query("select public.review_gym_directory_request('request-1',$1,'reviewed','공개 주소 확인') as review", [member])).rows[0].review;
    assert.equal(receipt.status, 'reviewed');
    const row = (await db.query('select * from private.gym_directory_requests where owner_user_id=$1 and id=$2', [member, 'request-1'])).rows[0];
    assert.equal(row.reviewed_by, other);
    assert.equal(row.review_note, '공개 주소 확인');
    await asUser();
    assert.equal((await submit()).id, 'request-1');
    assert.equal((await db.query('select status from private.gym_directory_requests where id=$1', ['request-1'])).rows[0].status, 'reviewed');
  });

  await check('suspended users and deleted sessions cannot submit or read saved receipts', async () => {
    await db.exec('reset role');
    await db.query("update public.users set status='suspended' where id=$1", [member]);
    await asUser();
    await denied(() => submit({ id: 'suspended-request' }));
    assert.equal((await db.query('select * from private.gym_directory_requests')).rows.length, 0);
    await db.exec('reset role');
    await db.query("update public.users set status='active' where id=$1", [member]);
    await db.query('delete from auth.sessions where id=$1', [memberSession]);
    await asUser();
    await denied(() => submit({ id: 'deleted-session-request' }));
    assert.equal((await db.query('select * from private.gym_directory_requests')).rows.length, 0);
  });

  await check('review also requires a current administrator session', async () => {
    await db.exec('reset role');
    await db.query('delete from auth.sessions where id=$1', [otherSession]);
    await asUser(other, otherSession);
    await denied(() => db.query("select public.review_gym_directory_request('claim-1',$1,'reviewed','확인')", [member]));
  });

  console.log(`${checks} gym request database security checks passed.`);
} catch (error) {
  console.error(`FAIL ${error.code ?? ''}: ${error.message}`);
  if (error.query) console.error(error.query);
  process.exitCode = 1;
} finally {
  await db.close();
}
