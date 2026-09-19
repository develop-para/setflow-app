begin;

-- Application-owned profile data. No passwords, tokens or OAuth secrets live
-- in a publicly readable profile, and birth dates never enter workout shares.
create table private.account_personal_details (
  user_id uuid primary key references public.users(id) on delete cascade,
  birth_date date check (birth_date >= date '1900-01-01'),
  updated_at timestamptz not null default now()
);
create table private.account_identity_links (
  user_id uuid not null references public.users(id) on delete cascade,
  provider text not null,
  provider_subject text not null,
  updated_at timestamptz not null default now(),
  primary key (provider, provider_subject)
);
create index account_identity_links_user_id_idx
  on private.account_identity_links(user_id);
alter table private.account_personal_details enable row level security;
alter table private.account_identity_links enable row level security;
revoke all on private.account_personal_details, private.account_identity_links
  from public, anon, authenticated;

-- Only the authentication authority may link a provider subject to an account.
-- Matching email strings never links two identities in this application layer.
create function private.sync_account_identity_link()
returns trigger language plpgsql security definer set search_path = ''
as $function$
begin
  if tg_op = 'DELETE' then
    delete from private.account_identity_links
    where provider = old.provider and provider_subject = old.provider_id;
    return old;
  end if;
  if tg_op = 'UPDATE' then
    delete from private.account_identity_links
    where provider = old.provider and provider_subject = old.provider_id;
  end if;
  insert into private.account_identity_links(user_id, provider, provider_subject)
  values (new.user_id, new.provider, new.provider_id)
  on conflict (provider, provider_subject) do update
  set user_id = excluded.user_id, updated_at = now();
  return new;
end;
$function$;
revoke all on function private.sync_account_identity_link()
  from public, anon, authenticated;
create trigger sync_setflow_account_identity
after insert or update of user_id, provider, provider_id or delete on auth.identities
for each row execute function private.sync_account_identity_link();
insert into private.account_identity_links(user_id, provider, provider_subject)
select i.user_id, i.provider, i.provider_id
from auth.identities i join public.users u on u.id = i.user_id;

-- The insertion trigger already copies the email. Keep the app's copy current
-- after a provider/login service changes it as well.
create function private.sync_account_email()
returns trigger language plpgsql security definer set search_path = ''
as $function$
begin
  update public.users set email = new.email, updated_at = now()
  where id = new.id and email is distinct from new.email;
  return new;
end;
$function$;
revoke all on function private.sync_account_email()
  from public, anon, authenticated;
create trigger sync_setflow_account_email
after update of email on auth.users
for each row execute function private.sync_account_email();

create function private.get_my_account_profile()
returns jsonb language plpgsql stable security definer set search_path = ''
as $function$
declare v_user_id uuid := (select auth.uid());
begin
  if not private.has_active_app_session() then
    raise exception using errcode = '42501', message = '유효한 로그인이 필요해요.';
  end if;
  return (
    select jsonb_build_object(
      'user_id', u.id, 'email', u.email, 'birth_date', d.birth_date,
      'providers', coalesce((
        select jsonb_agg(distinct i.provider order by i.provider)
        from private.account_identity_links i where i.user_id = u.id
      ), '[]'::jsonb)
    )
    from public.users u
    left join private.account_personal_details d on d.user_id = u.id
    where u.id = v_user_id
  );
end;
$function$;

create function private.save_my_account_birth_date(p_birth_date date)
returns jsonb language plpgsql security definer set search_path = ''
as $function$
begin
  if not private.has_active_app_session() then
    raise exception using errcode = '42501', message = '유효한 로그인이 필요해요.';
  end if;
  if p_birth_date is not null and
      (p_birth_date < date '1900-01-01' or p_birth_date > current_date) then
    raise exception using errcode = '22023', message = '생년월일을 확인해주세요.';
  end if;
  insert into private.account_personal_details(user_id, birth_date)
  values ((select auth.uid()), p_birth_date)
  on conflict (user_id) do update
  set birth_date = excluded.birth_date, updated_at = now();
  return private.get_my_account_profile();
end;
$function$;

create function public.get_my_account_profile()
returns jsonb language sql stable security invoker set search_path = ''
as $function$ select private.get_my_account_profile(); $function$;
create function public.save_my_account_birth_date(p_birth_date date)
returns jsonb language sql security invoker set search_path = ''
as $function$ select private.save_my_account_birth_date(p_birth_date); $function$;
revoke all on function private.get_my_account_profile(),
  private.save_my_account_birth_date(date), public.get_my_account_profile(),
  public.save_my_account_birth_date(date) from public, anon;
grant execute on function private.get_my_account_profile(),
  private.save_my_account_birth_date(date), public.get_my_account_profile(),
  public.save_my_account_birth_date(date) to authenticated;

notify pgrst, 'reload schema';
commit;
