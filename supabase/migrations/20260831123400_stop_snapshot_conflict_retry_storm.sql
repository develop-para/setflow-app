-- PostgREST 14.5/Hasql retries SQLSTATE 40001 inside the same HTTP request.
-- The optimistic snapshot lock used 40001 for a normal product conflict, so
-- one stale device could occupy every REST connection until the gateway timed
-- out. Translate that expected conflict to an explicit HTTP 409 instead.

create or replace function private.save_my_account_snapshot(
  p_expected_user_id uuid,
  p_schema_version smallint,
  p_payload jsonb,
  p_sessions jsonb,
  p_expected_updated_at timestamp with time zone
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_current_updated_at timestamp with time zone;
begin
  if p_expected_user_id is null
     or (select auth.uid()) is distinct from p_expected_user_id then
    raise exception using
      errcode = '42501',
      message = 'The authenticated account changed before snapshot save.';
  end if;

  begin
    return private.save_my_app_snapshot(
      p_schema_version,
      p_payload,
      p_sessions,
      p_expected_updated_at
    );
  exception when serialization_failure then
    -- A timed-out client can retry an already committed payload with its old
    -- version. Treat that exact replay as acknowledged instead of a conflict.
    select snapshot.updated_at
    into v_current_updated_at
    from public.app_state_snapshots snapshot
    where snapshot.user_id = p_expected_user_id
      and snapshot.schema_version = p_schema_version
      and snapshot.payload = p_payload;

    if found then
      return jsonb_build_object(
        'updated_at', v_current_updated_at,
        'workouts', jsonb_build_object('idempotent', true)
      );
    end if;

    raise exception using
      errcode = 'PT409',
      message = 'Snapshot changed on another device; reload before saving',
      detail = 'snapshot_version_conflict';
  end;
end
$function$;

create or replace function private.clear_my_account_data(
  p_expected_user_id uuid,
  p_expected_updated_at timestamp with time zone
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
begin
  if p_expected_user_id is null
     or (select auth.uid()) is distinct from p_expected_user_id then
    raise exception using
      errcode = '42501',
      message = 'The authenticated account changed before data clear.';
  end if;

  begin
    return private.clear_my_app_data(p_expected_updated_at);
  exception when serialization_failure then
    raise exception using
      errcode = 'PT409',
      message = 'Snapshot changed on another device; reload before clearing',
      detail = 'snapshot_version_conflict';
  end;
end
$function$;

revoke all on function private.save_my_account_snapshot(
  uuid, smallint, jsonb, jsonb, timestamp with time zone
), private.clear_my_account_data(uuid, timestamp with time zone)
  from public, anon, authenticated;
grant execute on function private.save_my_account_snapshot(
  uuid, smallint, jsonb, jsonb, timestamp with time zone
), private.clear_my_account_data(uuid, timestamp with time zone)
  to authenticated, service_role;
