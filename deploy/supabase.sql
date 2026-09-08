-- Run once in the SQL editor of the dedicated WWC V0 Supabase project.
-- App traffic goes through the Shiny server. No database keys go to the browser.
begin;
create table if not exists public.wwc_events (
  event_id uuid primary key,
  session_id uuid not null,
  timestamp_utc timestamptz not null,
  event_type text not null,
  participant_code text,
  app_version text not null,
  corpus_version text not null,
  consent_version text not null,
  body jsonb not null
);
create index if not exists wwc_events_session_time on public.wwc_events(session_id,timestamp_utc);
create table if not exists public.wwc_ai_budget(day date primary key, calls integer not null default 0);
alter table public.wwc_events enable row level security;
alter table public.wwc_ai_budget enable row level security;
revoke all on public.wwc_events, public.wwc_ai_budget from anon, authenticated;
grant select,insert,update,delete on public.wwc_events,public.wwc_ai_budget to service_role;

create or replace function public.wwc_append_event(p_event jsonb) returns boolean
language plpgsql set search_path = public as $$
begin
  if coalesce((p_event->>'consented')::boolean,false) is not true
    or coalesce(p_event->>'consent_version','')='' then
    raise exception 'A consented event with a consent version is required';
  end if;
  if octet_length(p_event::text)>1000000 then raise exception 'Event too large'; end if;
  insert into public.wwc_events(event_id,session_id,timestamp_utc,event_type,participant_code,app_version,corpus_version,consent_version,body)
  values((p_event->>'event_id')::uuid,(p_event->>'session_id')::uuid,(p_event->>'timestamp_utc')::timestamptz,
    p_event->>'type',p_event->>'participant_code',p_event->>'app_version',p_event->>'corpus_version',p_event->>'consent_version',p_event)
  on conflict(event_id) do nothing;
  return true;
end; $$;

create or replace function public.wwc_delete_session(p_session_id uuid) returns boolean
language plpgsql set search_path = public as $$
begin
  delete from public.wwc_events where session_id=p_session_id;
  return true;
end; $$;

create or replace function public.wwc_reserve_ai_call(p_limit integer) returns boolean
language plpgsql set search_path = public as $$
declare affected integer;
begin
  if p_limit<1 or p_limit>10000 then raise exception 'Invalid limit'; end if;
  insert into public.wwc_ai_budget(day,calls) values((now() at time zone 'UTC')::date,0) on conflict(day) do nothing;
  update public.wwc_ai_budget set calls=calls+1 where day=(now() at time zone 'UTC')::date and calls<p_limit;
  get diagnostics affected = row_count;
  return affected=1;
end; $$;

create or replace function public.wwc_storage_ready() returns boolean
language sql stable set search_path=public as $$ select true; $$;

revoke all on function public.wwc_append_event(jsonb),public.wwc_delete_session(uuid),public.wwc_reserve_ai_call(integer),public.wwc_storage_ready() from public,anon,authenticated;
grant execute on function public.wwc_append_event(jsonb),public.wwc_delete_session(uuid),public.wwc_reserve_ai_call(integer),public.wwc_storage_ready() to service_role;
commit;
