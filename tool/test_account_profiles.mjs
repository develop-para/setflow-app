// Uses the same disposable Postgres dependency as test_workspace_access.mjs.
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { PGlite } from '../.dart_tool/workspace-security/node_modules/@electric-sql/pglite/dist/index.js';

const db = new PGlite();
const user = '10000000-0000-4000-8000-000000000001';
const other = '10000000-0000-4000-8000-000000000002';
let checks = 0;
async function check(name, action) {
  await action();
  console.log('PASS ' + name);
  checks++;
}
async function asUser(id = user) {
  await db.exec('reset role');
  await db.query("select set_config('request.jwt.claims', $1, false)", [JSON.stringify({
    sub: id, session_id: id.replace('10000000', '20000000'), role: 'authenticated',
    user_metadata: {birth_date: '1990-01-01', provider: 'google'},
  })]);
  await db.exec('set role authenticated');
}
async function admin(sql) {
  await db.exec('reset role');
  await db.exec(sql);
  await asUser();
}
const profile = async () => (await db.query('select public.get_my_account_profile() as value')).rows[0].value;
const denied = sql => assert.rejects(db.query(sql), {code: '42501'});
try {
  await db.exec(await readFile(new URL('fixtures/workspace_access.sql', import.meta.url), 'utf8'));
  await db.exec(`
    alter table auth.users add column email text;
    alter table public.users add column updated_at timestamptz;
    create table auth.identities (user_id uuid references auth.users, provider text, provider_id text, primary key(provider,provider_id));
    insert into auth.identities values ('${user}','email','email-user-1');
  `);
  await db.exec(await readFile(new URL('../supabase/migrations/20260919163342_server_managed_workspace_access.sql', import.meta.url), 'utf8'));
  await db.exec(await readFile(new URL('../supabase/migrations/20260919231805_portable_account_profiles.sql', import.meta.url), 'utf8'));
  await asUser();
  await check('existing identities are copied but editable metadata is ignored', async () => {
    assert.deepEqual((await profile()).providers, ['email']);
    assert.equal((await profile()).birth_date, null);
    assert.equal((await profile()).user_id, user);
  });
  await check('birth date is saved and returned only to its owner', async () => {
    await db.query("select public.save_my_account_birth_date('2000-02-29')");
    assert.equal((await profile()).birth_date, '2000-02-29');
    await asUser(other);
    assert.equal((await profile()).birth_date, null);
    await asUser();
  });
  await check('future and implausibly old dates are rejected on the server', async () => {
    for (const date of ["current_date+1", "date '1899-12-31'"]) {
      await assert.rejects(db.query('select public.save_my_account_birth_date('+date+')'), {code:'22023'});
    }
  });
  await check('removing the date really removes the saved value', async () => {
    await db.query('select public.save_my_account_birth_date(null)');
    assert.equal((await profile()).birth_date, null);
  });
  await check('clients cannot read private tables or forge identity mappings', async () => {
    await denied('select * from private.account_personal_details');
    await denied('select * from private.account_identity_links');
    await denied(`insert into private.account_identity_links values ('${user}','google','forged',now())`);
  });
  await check('trusted provider subjects are kept independently of email matching', async () => {
    await admin(`insert into auth.identities values ('${user}','google','google-user-1'),('${other}','google','google-user-2')`);
    assert.deepEqual((await profile()).providers, ['email','google']);
    await admin("update auth.identities set provider_id='google-user-1-new' where provider_id='google-user-1'");
    await db.exec('reset role');
    assert.equal((await db.query("select count(*)::int as n from private.account_identity_links where provider_subject='google-user-1'")).rows[0].n, 0);
    await asUser();
  });
  await check('unlinking a provider removes its application identity too', async () => {
    await admin("delete from auth.identities where provider_id='google-user-1-new'");
    assert.deepEqual((await profile()).providers, ['email']);
  });
  await check('authentication email changes update the application-owned copy', async () => {
    await admin(`update auth.users set email='updated@example.test' where id='${user}'`);
    assert.equal((await profile()).email, 'updated@example.test');
  });
  await check('revoked sessions cannot read or overwrite personal details', async () => {
    await admin(`delete from auth.sessions where user_id='${user}'`);
    await denied('select public.get_my_account_profile()');
    await denied("select public.save_my_account_birth_date('2000-01-01')");
  });
  await check('anonymous callers cannot invoke profile operations', async () => {
    await db.exec('reset role; set role anon');
    await denied('select public.get_my_account_profile()');
    await denied("select public.save_my_account_birth_date('2000-01-01')");
  });
  console.log(`${checks} account privacy checks passed.`);
} finally {
  await db.close();
}
