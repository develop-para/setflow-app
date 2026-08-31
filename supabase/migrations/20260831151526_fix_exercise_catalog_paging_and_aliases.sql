-- Keep imported aliases tokenized and page the shared catalog with a stable
-- cursor. The initial importer used a literal double-backslash regex, which
-- left every generated alias sentence as one array element.

create or replace function public.normalize_imported_exercise_aliases()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.source_name = 'free-exercise-db' and
     nullif(pg_catalog.btrim(new.aliases_text), '') is not null
  then
    new.aliases := pg_catalog.regexp_split_to_array(
      pg_catalog.btrim(new.aliases_text),
      E'\\s+'
    );
  end if;
  return new;
end;
$$;

drop trigger if exists normalize_imported_exercise_aliases
  on public.master_exercises;
create trigger normalize_imported_exercise_aliases
before insert or update of aliases, aliases_text, source_name
on public.master_exercises
for each row
execute function public.normalize_imported_exercise_aliases();

update public.master_exercises
set aliases = pg_catalog.regexp_split_to_array(
  pg_catalog.btrim(aliases_text),
  E'\\s+'
),
updated_at = pg_catalog.now()
where source_name = 'free-exercise-db'
  and nullif(pg_catalog.btrim(aliases_text), '') is not null;

revoke all on function public.normalize_imported_exercise_aliases()
  from public, anon, authenticated;

create index if not exists master_exercises_public_page_idx
  on public.master_exercises (name, id)
  where is_active and not is_custom;

create or replace function public.list_master_exercises(
  p_after_name text default null,
  p_after_id uuid default null,
  p_limit integer default 500
)
returns table (
  id uuid,
  source_id text,
  name text,
  name_ko text,
  name_en text,
  target_muscle text,
  equipment text,
  equipment_key text,
  input_type text,
  aliases text[],
  difficulty text,
  category text,
  source_name text
)
language sql
stable
security invoker
set search_path = ''
as $$
  select
    exercise.id,
    exercise.source_id,
    exercise.name,
    exercise.name_ko,
    exercise.name_en,
    exercise.target_muscle,
    exercise.equipment,
    exercise.equipment_key,
    exercise.input_type,
    exercise.aliases,
    exercise.difficulty,
    exercise.category,
    exercise.source_name
  from public.master_exercises exercise
  where exercise.is_active
    and not exercise.is_custom
    and (
      p_after_name is null or
      p_after_id is null or
      (exercise.name, exercise.id) > (p_after_name, p_after_id)
    )
  order by exercise.name, exercise.id
  limit greatest(1, least(coalesce(p_limit, 500), 500));
$$;

revoke all on function public.list_master_exercises(text, uuid, integer)
  from public;
grant execute on function public.list_master_exercises(text, uuid, integer)
  to anon, authenticated, service_role;

comment on function public.list_master_exercises(text, uuid, integer) is
  'Pages active shared exercises by the stable (name, id) cursor.';
