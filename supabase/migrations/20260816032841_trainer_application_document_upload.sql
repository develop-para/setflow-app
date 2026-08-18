-- Require real, privately-owned Storage objects before accepting a trainer
-- application. Storage uploads happen first; all public application/document
-- rows are then written atomically by this checked RPC.

insert into storage.buckets (
  id,
  name,
  public,
  file_size_limit,
  allowed_mime_types
) values (
  'trainer-documents',
  'trainer-documents',
  false,
  8388608,
  array[
      'image/jpeg',
      'image/png',
      'image/webp',
      'image/heic',
      'image/heif'
    ]::text[]
)
on conflict (id) do update
set public = false,
    file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;

-- This project already has shared private-bucket policies. Abort instead of
-- adding overlapping permissive policies if their owner/admin guarantees are
-- ever removed or renamed.
do $trainer_document_storage_policy_preflight$
declare
  v_write_expression text;
  v_read_expression text;
  v_delete_expression text;
begin
  select pg_get_expr(p.polwithcheck, p.polrelid)
    into v_write_expression
  from pg_policy p
  where p.polrelid = 'storage.objects'::regclass
    and p.polname = 'priv_write'
    and p.polcmd = 'a';

  select pg_get_expr(p.polqual, p.polrelid)
    into v_read_expression
  from pg_policy p
  where p.polrelid = 'storage.objects'::regclass
    and p.polname = 'priv_read'
    and p.polcmd = 'r';

  select pg_get_expr(p.polqual, p.polrelid)
    into v_delete_expression
  from pg_policy p
  where p.polrelid = 'storage.objects'::regclass
    and p.polname = 'priv_delete'
    and p.polcmd = 'd';

  if v_write_expression is null
     or v_write_expression not ilike '%trainer-documents%'
     or v_write_expression not ilike '%foldername%'
     or v_write_expression not ilike '%auth.uid%'
  then
    raise exception 'trainer-documents owner insert policy preflight failed';
  end if;
  if v_read_expression is null
     or v_read_expression not ilike '%trainer-documents%'
     or v_read_expression not ilike '%foldername%'
     or v_read_expression not ilike '%auth.uid%'
     or v_read_expression not ilike '%is_admin%'
  then
    raise exception 'trainer-documents owner/admin read policy preflight failed';
  end if;
  if v_delete_expression is null
     or v_delete_expression not ilike '%trainer-documents%'
     or v_delete_expression not ilike '%foldername%'
     or v_delete_expression not ilike '%auth.uid%'
     or v_delete_expression not ilike '%is_admin%'
  then
    raise exception 'trainer-documents owner/admin delete policy preflight failed';
  end if;
end
$trainer_document_storage_policy_preflight$;

create unique index if not exists trainer_documents_application_type_uidx
  on public.trainer_documents (application_id, doc_type)
  where application_id is not null;

create or replace function private.submit_trainer_application(
  p_name text,
  p_certification_number text,
  p_documents jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_user_id uuid := auth.uid();
  v_name text := nullif(btrim(p_name), '');
  v_certification_number text := nullif(btrim(p_certification_number), '');
  v_trainer_id uuid;
  v_application_id uuid;
  v_status text;
  v_document_count integer;
  v_valid_object_count integer;
begin
  if v_user_id is null then
    raise exception using errcode = '42501', message = 'Authentication required';
  end if;
  if v_name is null or char_length(v_name) > 100 then
    raise exception using errcode = '22023', message = 'A valid trainer name is required';
  end if;
  if v_certification_number is null
     or char_length(v_certification_number) > 100 then
    raise exception using errcode = '22023', message = 'A valid certification number is required';
  end if;
  if not exists (select 1 from public.users u where u.id = v_user_id) then
    raise exception using errcode = '23503', message = 'User profile is not ready';
  end if;
  if jsonb_typeof(p_documents) is distinct from 'array' then
    raise exception using errcode = '22023', message = 'Documents must be an array';
  end if;

  v_document_count := jsonb_array_length(p_documents);
  if v_document_count < 2 or v_document_count > 4 then
    raise exception using errcode = '22023', message = 'Between 2 and 4 documents are required';
  end if;

  if (
    select count(distinct d.doc_type)
    from jsonb_to_recordset(p_documents) as d(doc_type text, file_path text)
  ) <> v_document_count then
    raise exception using errcode = '22023', message = 'Document types must be unique';
  end if;
  if not exists (
    select 1
    from jsonb_to_recordset(p_documents) as d(doc_type text, file_path text)
    where d.doc_type = 'id'
  ) or not exists (
    select 1
    from jsonb_to_recordset(p_documents) as d(doc_type text, file_path text)
    where d.doc_type in ('national', 'private')
  ) then
    raise exception using errcode = '22023', message = 'Identity and certification documents are required';
  end if;
  if exists (
    select 1
    from jsonb_to_recordset(p_documents) as d(doc_type text, file_path text)
    where d.doc_type not in ('national', 'private', 'id', 'award')
       or d.file_path is null
       or array_length(string_to_array(d.file_path, '/'), 1) <> 4
       or split_part(d.file_path, '/', 1) <> v_user_id::text
       or split_part(d.file_path, '/', 2) <> 'pending'
       or split_part(d.file_path, '/', 3)
            !~ '^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
       or split_part(d.file_path, '/', 4)
            !~ ('^' || d.doc_type || '\.(jpg|jpeg|png|webp|heic|heif)$')
  ) then
    raise exception using errcode = '22023', message = 'Invalid trainer document object key';
  end if;

  select count(*)
    into v_valid_object_count
  from jsonb_to_recordset(p_documents) as d(doc_type text, file_path text)
  join storage.objects o
    on o.bucket_id = 'trainer-documents'
   and o.name = d.file_path
   and (o.owner = v_user_id or o.owner_id = v_user_id::text)
  where lower(coalesce(o.metadata ->> 'mimetype', '')) in (
      'image/jpeg', 'image/png', 'image/webp', 'image/heic', 'image/heif'
    )
    and coalesce((o.metadata ->> 'size')::bigint, 0) between 1 and 8388608;

  if v_valid_object_count <> v_document_count then
    raise exception using errcode = '42501', message = 'A document is missing, invalid, or not owned by the current user';
  end if;

  select t.id, t.status
    into v_trainer_id, v_status
  from public.trainers t
  where t.user_id = v_user_id
  for update;

  if v_status = 'approved' then
    raise exception using errcode = '23514', message = 'Trainer profile is already approved';
  elsif v_status in ('suspended', 'grace_period') then
    raise exception using errcode = '42501', message = 'Trainer profile cannot be resubmitted in its current state';
  end if;

  if v_trainer_id is null then
    insert into public.trainers (
      user_id, display_name, status, is_public, verified_badge
    ) values (
      v_user_id, v_name, 'pending', false, false
    )
    returning id into v_trainer_id;
  else
    update public.trainers
    set display_name = v_name,
        status = 'pending',
        is_public = false,
        verified_badge = false,
        updated_at = now()
    where id = v_trainer_id;
  end if;

  insert into public.trainer_applications (
    trainer_id, user_id, name, submitted_at, sla_due_at, status,
    reject_reason, reviewer_id, reviewed_at, updated_at
  ) values (
    v_trainer_id, v_user_id, v_name, now(), now() + interval '3 days',
    'pending', null, null, null, now()
  )
  on conflict (user_id)
    where status = 'pending' and user_id is not null
  do update
    set trainer_id = excluded.trainer_id,
        name = excluded.name,
        submitted_at = excluded.submitted_at,
        sla_due_at = excluded.sla_due_at,
        reject_reason = null,
        reviewer_id = null,
        reviewed_at = null,
        updated_at = now()
  returning id into v_application_id;

  insert into public.trainer_certifications (
    trainer_id, title, credential_number, verification_status,
    created_at, updated_at
  ) values (
    v_trainer_id, 'Professional certification',
    v_certification_number, 'submitted', now(), now()
  )
  on conflict (trainer_id, credential_number)
    where credential_number is not null
  do update
    set verification_status = 'submitted',
        updated_at = now();

  delete from public.trainer_documents td
  where td.application_id = v_application_id
    and coalesce(td.review_status, 'submitted') = 'submitted';

  insert into public.trainer_documents (
    trainer_id,
    application_id,
    doc_type,
    file_path,
    review_status,
    uploaded_at
  )
  select
    v_trainer_id,
    v_application_id,
    d.doc_type,
    d.file_path,
    'submitted',
    now()
  from jsonb_to_recordset(p_documents) as d(doc_type text, file_path text);

  return jsonb_build_object(
    'application_id', v_application_id,
    'trainer_id', v_trainer_id,
    'status', 'pending',
    'document_count', v_document_count
  );
end
$function$;

-- Compatibility endpoint for old clients: it now fails the same mandatory
-- document validation instead of creating a document-less application.
create or replace function private.submit_trainer_application(
  p_name text,
  p_certification_number text
)
returns jsonb
language sql
volatile
security invoker
set search_path = ''
as $function$
  select private.submit_trainer_application($1, $2, '[]'::jsonb);
$function$;

create or replace function public.submit_trainer_application(
  name text,
  certification_number text,
  documents jsonb
)
returns jsonb
language sql
volatile
security invoker
set search_path = ''
as $function$
  select private.submit_trainer_application($1, $2, $3);
$function$;

revoke all on function private.submit_trainer_application(text, text, jsonb)
  from public, anon;
revoke all on function private.submit_trainer_application(text, text)
  from public, anon;
grant execute on function private.submit_trainer_application(text, text, jsonb),
  private.submit_trainer_application(text, text)
  to authenticated, service_role;

revoke all on function public.submit_trainer_application(text, text, jsonb)
  from public, anon;
grant execute on function public.submit_trainer_application(text, text, jsonb)
  to authenticated, service_role;

-- Document rows are now written only by the checked RPC and reviewed by the
-- existing admin SECURITY DEFINER function. Applicants retain read access.
revoke insert, update, delete on table public.trainer_documents
  from authenticated;
grant select on table public.trainer_documents to authenticated;

drop policy if exists trainer_documents_owner_insert
  on public.trainer_documents;
drop policy if exists trainer_documents_owner_update
  on public.trainer_documents;
drop policy if exists trainer_documents_owner_delete
  on public.trainer_documents;
