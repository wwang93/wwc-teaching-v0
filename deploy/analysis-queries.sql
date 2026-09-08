-- Read-only examples. Export results from the dedicated project as needed.
-- Counts represent consented sessions, not unique people or confirmed reading.
select body->>'phase' as phase, app_version, corpus_version, consent_version,
       count(distinct session_id) as sessions, count(*) as events
from public.wwc_events
group by 1,2,3,4 order by 1,2,3,4;

select session_id, participant_code, timestamp_utc, event_type,
       app_version, corpus_version, consent_version, body->'payload' as payload
from public.wwc_events
where body->>'phase'='study'
order by session_id, (body->>'sequence')::integer;

select session_id, participant_code, timestamp_utc,
       body#>>'{payload,action_id}' as action_id,
       body#>>'{payload,decision}' as decision,
       body#>>'{payload,notes}' as next_action,
       body#>>'{payload,reason}' as reason,
       app_version, corpus_version
from public.wwc_events
where event_type='plan_saved' and body->>'phase'='study'
order by timestamp_utc;
