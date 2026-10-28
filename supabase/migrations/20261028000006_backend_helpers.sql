-- =====================================================================
-- Helpers used by edge functions and the super admin panel
-- =====================================================================

alter table public.whatsapp_outbox add column locked_until timestamptz;

-- Atomically take a batch of pending messages so two dispatcher runs
-- never send the same one twice. Gives up after 5 attempts.
create or replace function public.claim_whatsapp_outbox(p_limit integer default 50)
returns setof public.whatsapp_outbox
language plpgsql security definer set search_path = '' as $$
begin
  if not public.is_backend() then raise exception 'backend only'; end if;

  update public.whatsapp_outbox set status = 'failed'
   where status = 'pending' and attempts >= 5;

  return query
  update public.whatsapp_outbox o
     set attempts = o.attempts + 1, locked_until = now() + interval '2 minutes'
   where o.id in (
     select id from public.whatsapp_outbox
      where status = 'pending' and (locked_until is null or locked_until < now())
      order by created_at
      limit p_limit
      for update skip locked)
  returning o.*;
end $$;

-- Phone numbers in auth.users are stored as digits without "+".
create or replace function public.find_user_by_phone(p_phone text)
returns uuid language sql stable security definer set search_path = '' as $$
  select id from auth.users
   where public.is_backend()
     and phone = regexp_replace(p_phone, '[^0-9]', '', 'g')
   limit 1
$$;

create or replace function public.user_phone(p_user_id uuid)
returns text language sql stable security definer set search_path = '' as $$
  select phone from auth.users where public.is_backend() and id = p_user_id
$$;

-- Incoming WhatsApp message from a patient: route it to the conversation
-- the lab most recently wrote in. Returns the new message id, or null if
-- there's nowhere sensible to put it (or it was a duplicate delivery).
create or replace function public.record_whatsapp_inbound(
  p_phone text, p_body text, p_wa_message_id text
) returns uuid
language plpgsql security definer set search_path = '' as $$
declare
  uid  uuid;
  conv uuid;
  mid  uuid;
begin
  if not public.is_backend() then raise exception 'backend only'; end if;
  uid := public.find_user_by_phone(p_phone);
  if uid is null then return null; end if;

  insert into public.whatsapp_sessions (user_id, last_inbound_at) values (uid, now())
  on conflict (user_id) do update set last_inbound_at = now();

  select c.id into conv
    from public.conversations c
   where c.patient_id = uid
   order by (select max(m.created_at) from public.messages m
              where m.conversation_id = c.id and m.direction = 'to_patient') desc nulls last,
            c.last_message_at desc
   limit 1;
  if conv is null then return null; end if;

  insert into public.messages (conversation_id, direction, sender_id, body, channel, wa_message_id)
  values (conv, 'from_patient', uid, left(p_body, 2000), 'whatsapp', p_wa_message_id)
  on conflict (wa_message_id) do nothing
  returning id into mid;
  return mid;
end $$;

-- Super admin: find any account, including contact details.
create or replace function public.admin_list_users(p_search text default null, p_limit integer default 50)
returns table (id uuid, full_name text, role public.user_role, lab_id uuid, lab_name_en text,
               phone text, email text, created_at timestamptz)
language sql stable security definer set search_path = '' as $$
  select p.id, p.full_name, p.role, p.lab_id, l.name_en, u.phone, u.email::text, p.created_at
    from public.profiles p
    join auth.users u on u.id = p.id
    left join public.labs l on l.id = p.lab_id
   where public.is_super_admin()
     and (p_search is null or p_search = ''
          or p.full_name ilike '%' || p_search || '%'
          or u.phone like '%' || regexp_replace(p_search, '[^0-9]', '', 'g') || '%' and regexp_replace(p_search, '[^0-9]', '', 'g') <> ''
          or u.email ilike '%' || p_search || '%')
   order by p.created_at desc
   limit least(p_limit, 200)
$$;

-- Lab admin / super admin: list the lab's staff (no contact details).
create or replace function public.lab_staff(p_lab_id uuid)
returns table (id uuid, full_name text, role public.user_role, created_at timestamptz)
language sql stable security definer set search_path = '' as $$
  select p.id, p.full_name, p.role, p.created_at
    from public.profiles p
   where p.lab_id = p_lab_id and public.has_lab_role(p_lab_id, 'clerk')
   order by public.role_rank(p.role) desc, p.full_name
$$;

revoke execute on function public.claim_whatsapp_outbox(integer)            from public, anon, authenticated;
revoke execute on function public.find_user_by_phone(text)                  from public, anon, authenticated;
revoke execute on function public.user_phone(uuid)                          from public, anon, authenticated;
revoke execute on function public.record_whatsapp_inbound(text, text, text) from public, anon, authenticated;
revoke execute on function public.admin_list_users(text, integer)           from public, anon;
revoke execute on function public.lab_staff(uuid)                           from public, anon;
grant execute on function public.claim_whatsapp_outbox(integer)            to service_role;
grant execute on function public.find_user_by_phone(text)                  to service_role;
grant execute on function public.user_phone(uuid)                          to service_role;
grant execute on function public.record_whatsapp_inbound(text, text, text) to service_role;
grant execute on function public.admin_list_users(text, integer)           to authenticated;
grant execute on function public.lab_staff(uuid)                           to authenticated;
