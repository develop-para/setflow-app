-- Authenticated directory readers may only see certification titles for
-- trainers who are themselves public. Owners/admins keep their row access;
-- sensitive columns remain available only through bounded owner RPCs.

begin;

drop policy if exists trainer_certifications_authenticated_read
  on public.trainer_certifications;

create policy trainer_certifications_authenticated_read
  on public.trainer_certifications for select to authenticated
  using (
    (
      verification_status = 'approved'
      and exists (
        select 1
        from public.trainers t
        where t.id = trainer_certifications.trainer_id
          and t.status = 'approved'
          and t.is_public
      )
    )
    or (select public.owns_trainer(trainer_id))
    or (select public.is_admin())
  );

commit;
