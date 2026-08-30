-- Cover nullable foreign keys used by invite recovery and routine snapshots.

create index coaching_connection_invites_accepted_coaching_idx
  on public.coaching_connection_invites (accepted_coaching_id)
  where accepted_coaching_id is not null;

create index coaching_session_records_routine_idx
  on public.coaching_session_records (routine_id)
  where routine_id is not null;
