// Run after:
// npm install --prefix .dart_tool/workspace-security --no-audit --no-fund @electric-sql/pglite@0.5.8
// node tool/test_workspace_access.mjs
// No network, credentials or production writes are used by this test.
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { PGlite } from '../.dart_tool/workspace-security/node_modules/@electric-sql/pglite/dist/index.js';

const db = new PGlite();
const user = '10000000-0000-4000-8000-000000000001';
const session = '20000000-0000-4000-8000-000000000001';
const trainer = '30000000-0000-4000-8000-000000000001';
let checks = 0;
async function check(name, action) {
  await action();
  checks++;
  console.log(`PASS ${name}`);
}
async function asUser(claims = { sub: user, session_id: session }) {
  await db.exec('reset role');
  await db.query("select set_config('request.jwt.claims', $1, false)", [JSON.stringify(claims)]);
  await db.exec('set role authenticated');
}
async function admin(sql) {
  await db.exec('reset role');
  await db.exec(sql);
  await asUser();
}
const access = async () => (await db.query('select public.get_my_business_access() as access')).rows[0].access;
const denied = async (sql) => assert.rejects(db.query(sql), { code: '42501' });

try {
  await db.exec(await readFile(new URL('fixtures/workspace_access.sql', import.meta.url), 'utf8'));
  await db.exec(await readFile(new URL('../supabase/migrations/20260919163342_server_managed_workspace_access.sql', import.meta.url), 'utf8'));
  await asUser();

  await check('valid account receives all approved roles', async () => {
    await db.query('select private.check_app_session()');
    assert.deepEqual((await access()).available_roles, ['member', 'trainer', 'gym']);
    assert.equal((await access()).user.id, user);
  });
  await check('existing row ownership remains enforced', async () => {
    assert.equal((await db.query('select * from public.users')).rows.length, 1);
    assert.equal((await db.query('select * from storage.objects')).rows.length, 1);
    assert.equal((await db.query('select * from public.rpc_only')).rows.length, 0);
  });
  await check('client metadata cannot grant administrator rights', async () => {
    await asUser({ sub: user, session_id: session, user_metadata: { role: 'admin', available_roles: ['admin'] } });
    assert.equal((await access()).available_roles.includes('admin'), false);
    await asUser();
  });
  await check('pending approvals remove roles despite approved application', async () => {
    await admin("update public.trainers set status='pending'; update public.gyms set status='pending'");
    assert.deepEqual((await access()).available_roles, ['member']);
    await denied(`insert into public.coaching_routines(id,trainer_id) values ('70000000-0000-4000-8000-000000000001','${trainer}')`);
  });
  await check('approved authors can save, revoked authors cannot mutate', async () => {
    await admin("update public.trainers set status='approved'");
    await db.query(`insert into public.coaching_routines(id,trainer_id) values ('70000000-0000-4000-8000-000000000001','${trainer}')`);
    await admin("update public.trainers set status='suspended'");
    assert.equal((await db.query("update public.coaching_routines set status='draft' returning id")).rows.length, 0);
    assert.equal((await db.query('delete from public.coaching_routines returning id')).rows.length, 0);
  });
  for (const status of ['suspended', 'banned', 'inactive']) {
    await check(`${status} account cannot call RPCs or access rows/storage`, async () => {
      await admin(`update public.users set status='${status}' where id='${user}'`);
      await denied('select private.check_app_session()');
      await denied('select public.get_my_business_access()');
      assert.equal((await db.query('select * from public.users')).rows.length, 0);
      assert.equal((await db.query('select * from storage.objects')).rows.length, 0);
      await admin(`update public.users set status='active' where id='${user}'`);
    });
  }
  for (const change of ["banned_until=now()+interval '1 day'", 'deleted_at=now()', 'is_anonymous=true']) {
    await check(`auth restriction ${change} is enforced`, async () => {
      await admin(`update auth.users set ${change} where id='${user}'`);
      await denied('select public.get_my_business_access()');
      await admin(`update auth.users set banned_until=null, deleted_at=null, is_anonymous=false where id='${user}'`);
    });
  }
  await check('a session belonging to another user is rejected', async () => {
    await asUser({ sub: user, session_id: '20000000-0000-4000-8000-000000000002' });
    await denied('select public.get_my_business_access()');
    await asUser();
  });
  await check('missing session claims cannot bypass the request hook', async () => {
    await asUser({ sub: user });
    await denied('select private.check_app_session()');
    await asUser();
  });
  await check('expired sessions are rejected', async () => {
    await admin(`update auth.sessions set not_after=now()-interval '1 second' where id='${session}'`);
    await denied('select public.get_my_business_access()');
    await admin(`update auth.sessions set not_after=null where id='${session}'`);
  });
  await check('deleted sessions immediately reject still-valid JWT claims', async () => {
    await admin(`delete from auth.sessions where id='${session}'`);
    await denied('select private.check_app_session()');
    await denied('select public.get_my_business_access()');
    assert.equal((await db.query('select * from storage.objects')).rows.length, 0);
  });
  await check('guest public reads stay available but access RPC is private', async () => {
    await db.exec('reset role; set role anon');
    await db.query('select private.check_app_session()');
    await db.query('select * from public.coaching_routines');
    await denied('select public.get_my_business_access()');
  });
  await check('service jobs are not forced to impersonate a user session', async () => {
    await db.exec('reset role; set role service_role');
    await db.query('select private.check_app_session()');
  });
  await check('migration wires the Data API request hook', async () => {
    await db.exec('reset role');
    const result = await db.query("select setconfig from pg_db_role_setting where setrole = 'authenticator'::regrole");
    assert.ok(result.rows[0].setconfig.includes('pgrst.db_pre_request=private.check_app_session'));
  });
  console.log(`${checks} database security checks passed.`);
} catch (error) {
  console.error(`FAIL ${error.code ?? ''}: ${error.message}`);
  if (error.query) console.error(error.query);
  process.exitCode = 1;
} finally {
  await db.close();
}
