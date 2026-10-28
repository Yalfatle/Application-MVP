-- =====================================================================
-- Messaging relay + WhatsApp notifications
-- =====================================================================
-- Lab staff talk to patients through the platform. Messages go out from
-- the platform's own WhatsApp Business number, so staff never see the
-- patient's phone number and the patient never sees staff numbers.
--
-- Anything that must reach WhatsApp is written to `whatsapp_outbox`.
-- A trigger pings the `whatsapp-dispatch` edge function immediately, and
-- a once-a-minute sweep retries anything that failed (weak networks,
-- WhatsApp hiccups), so nothing is silently lost.
-- =====================================================================

create extension if not exists pg_net  with schema extensions;
create extension if not exists pg_cron;

create table public.conversations (
  id               uuid primary key default gen_random_uuid(),
  lab_id           uuid not null references public.labs on delete cascade,
  patient_id       uuid not null references public.profiles on delete cascade,
  last_message_at  timestamptz not null default now(),
  created_at       timestamptz not null default now(),
  unique (lab_id, patient_id)
);
create index conversations_patient_idx on public.conversations (patient_id, last_message_at desc);
create index conversations_lab_idx     on public.conversations (lab_id, last_message_at desc);

create type public.message_direction as enum ('to_patient', 'from_patient');

create table public.messages (
  id                uuid primary key default gen_random_uuid(),
  conversation_id   uuid not null references public.conversations on delete cascade,
  direction         public.message_direction not null,
  sender_id         uuid references public.profiles on delete set null,
  body              text not null check (length(trim(body)) > 0 and length(body) <= 2000),
  channel           text not null default 'app' check (channel in ('app', 'whatsapp')),
  wa_message_id     text unique,
  created_at        timestamptz not null default now(),
  read_at           timestamptz
);
create index messages_conversation_idx on public.messages (conversation_id, created_at desc);

-- When did this person last message us on WhatsApp? WhatsApp only allows
-- free-form messages within 24 h of that; otherwise an approved template.
create table public.whatsapp_sessions (
  user_id          uuid primary key references public.profiles on delete cascade,
  last_inbound_at  timestamptz not null
);

create type public.outbox_status as enum ('pending', 'sent', 'failed');

create table public.whatsapp_outbox (
  id            bigint generated always as identity primary key,
  user_id       uuid not null references public.profiles on delete cascade,
  kind          text not null check (kind in ('order_update', 'lab_message')),
  -- free text to send if the 24 h window is open (lab_message only)
  text_body     text,
  -- template fallback
  template      text not null,
  params        jsonb not null default '[]',
  locale        text not null default 'ar',
  message_id    uuid references public.messages on delete set null,
  status        public.outbox_status not null default 'pending',
  attempts      integer not null default 0,
  last_error    text,
  created_at    timestamptz not null default now(),
  sent_at       timestamptz
);
create index whatsapp_outbox_pending_idx on public.whatsapp_outbox (created_at) where status = 'pending';

-- ---------------------------------------------------------------------
-- Starting / using a conversation
-- ---------------------------------------------------------------------
-- Staff open (or reuse) the thread with a patient who booked with their lab.
create or replace function public.open_conversation(p_lab_id uuid, p_patient_id uuid)
returns public.conversations
language plpgsql security definer set search_path = '' as $$
declare c public.conversations;
begin
  if not (public.has_lab_role(p_lab_id, 'clerk') and public.patient_booked_with_lab(p_patient_id, p_lab_id))
     and not (p_patient_id = auth.uid() and public.patient_booked_with_lab(p_patient_id, p_lab_id)) then
    raise exception 'not allowed';
  end if;
  insert into public.conversations (lab_id, patient_id) values (p_lab_id, p_patient_id)
  on conflict (lab_id, patient_id) do update set lab_id = excluded.lab_id
  returning * into c;
  return c;
end $$;

create or replace function public.prepare_message()
returns trigger language plpgsql security definer set search_path = '' as $$
declare c public.conversations;
begin
  select * into c from public.conversations where id = new.conversation_id;
  if not public.is_backend() then
    new.sender_id     := auth.uid();
    new.channel       := 'app';
    new.wa_message_id := null;
    new.read_at       := null;
    new.direction := case when c.patient_id = auth.uid() then 'from_patient'::public.message_direction
                          else 'to_patient'::public.message_direction end;
  end if;
  new.created_at := now();
  return new;
end $$;

create trigger messages_prepare before insert on public.messages
  for each row execute function public.prepare_message();

create or replace function public.after_message()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  c   public.conversations;
  lab public.labs;
  loc text;
begin
  select * into c from public.conversations where id = new.conversation_id;
  update public.conversations set last_message_at = new.created_at where id = c.id;

  if new.direction = 'to_patient' then
    select * into lab from public.labs where id = c.lab_id;
    select preferred_locale into loc from public.profiles where id = c.patient_id;
    insert into public.whatsapp_outbox (user_id, kind, text_body, template, params, locale, message_id)
    values (
      c.patient_id, 'lab_message',
      (case when loc = 'en' then lab.name_en else lab.name_ar end) || ': ' || new.body,
      'new_lab_message',
      jsonb_build_array(case when loc = 'en' then lab.name_en else lab.name_ar end),
      coalesce(loc, 'ar'), new.id
    );
  end if;
  return new;
end $$;

create trigger messages_after after insert on public.messages
  for each row execute function public.after_message();

-- Patient-facing order updates go out on WhatsApp too.
create or replace function public.notify_order_status()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  lab public.labs;
  loc text;
  status_text text;
begin
  if new.status is not distinct from old.status then return new; end if;
  if new.status not in ('accepted', 'refused', 'on_way', 'completed', 'cancelled') then return new; end if;
  -- don't message patients about cancellations they made themselves
  if new.status = 'cancelled' and auth.uid() = new.patient_id then return new; end if;

  select * into lab from public.labs where id = new.lab_id;
  select preferred_locale into loc from public.profiles where id = new.patient_id;
  loc := coalesce(loc, 'ar');

  status_text := case loc
    when 'en' then case new.status
      when 'accepted'  then 'accepted your booking'
      when 'refused'   then 'could not accept your booking'
      when 'on_way'    then 'has sent someone to you. Open the app to track them'
      when 'completed' then 'has sent your results. Open the app to view them'
      when 'cancelled' then 'cancelled your booking'
    end
    else case new.status
      when 'accepted'  then 'قبل حجزك'
      when 'refused'   then 'لم يتمكن من قبول حجزك'
      when 'on_way'    then 'أرسل مندوباً إليك. افتح التطبيق لتتبعه'
      when 'completed' then 'أرسل نتائجك. افتح التطبيق لعرضها'
      when 'cancelled' then 'ألغى حجزك'
    end
  end;

  insert into public.whatsapp_outbox (user_id, kind, template, params, locale)
  values (new.patient_id, 'order_update', 'order_update',
          jsonb_build_array(case when loc = 'en' then lab.name_en else lab.name_ar end, status_text),
          loc);
  return new;
end $$;

create trigger orders_notify after update of status on public.orders
  for each row execute function public.notify_order_status();

-- ---------------------------------------------------------------------
-- Dispatch: ping the edge function now, and sweep every minute.
-- Needs two Vault secrets (see SETUP.md): project_url, dispatch_secret.
-- Without them nothing breaks — messages just wait in the outbox.
-- ---------------------------------------------------------------------
create or replace function public.ping_whatsapp_dispatch()
returns void language plpgsql security definer set search_path = '' as $$
declare
  url    text;
  secret text;
begin
  select decrypted_secret into url    from vault.decrypted_secrets where name = 'project_url';
  select decrypted_secret into secret from vault.decrypted_secrets where name = 'dispatch_secret';
  if url is null or secret is null then return; end if;
  perform net.http_post(
    url     := url || '/functions/v1/whatsapp-dispatch',
    headers := jsonb_build_object('Content-Type', 'application/json', 'x-dispatch-secret', secret),
    body    := '{}'::jsonb
  );
end $$;

create or replace function public.outbox_ping()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  perform public.ping_whatsapp_dispatch();
  return null;
end $$;

create trigger whatsapp_outbox_ping after insert on public.whatsapp_outbox
  for each statement execute function public.outbox_ping();

select cron.schedule(
  'whatsapp-dispatch-sweep', '* * * * *',
  $$ select public.ping_whatsapp_dispatch()
     where exists (select 1 from public.whatsapp_outbox where status = 'pending') $$
);

revoke execute on function public.ping_whatsapp_dispatch() from public, anon, authenticated;
revoke execute on function public.open_conversation(uuid, uuid) from public, anon;
grant  execute on function public.open_conversation(uuid, uuid) to authenticated;

-- ---------------------------------------------------------------------
-- Row level security
-- ---------------------------------------------------------------------
alter table public.conversations     enable row level security;
alter table public.messages          enable row level security;
alter table public.whatsapp_sessions enable row level security;  -- backend only
alter table public.whatsapp_outbox   enable row level security;  -- backend only

create policy conversations_read on public.conversations for select to authenticated
  using (patient_id = (select auth.uid()) or public.has_lab_role(lab_id, 'clerk'));

create policy messages_read on public.messages for select to authenticated
  using (exists (select 1 from public.conversations c where c.id = conversation_id
                 and (c.patient_id = (select auth.uid()) or public.has_lab_role(c.lab_id, 'clerk'))));

create policy messages_insert on public.messages for insert to authenticated
  with check (exists (select 1 from public.conversations c where c.id = conversation_id
                      and (c.patient_id = (select auth.uid()) or public.has_lab_role(c.lab_id, 'clerk'))));

create or replace function public.mark_conversation_read(p_conversation_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare c public.conversations;
begin
  select * into c from public.conversations where id = p_conversation_id;
  if c.patient_id = auth.uid() then
    update public.messages set read_at = now()
     where conversation_id = c.id and direction = 'to_patient' and read_at is null;
  elsif public.has_lab_role(c.lab_id, 'clerk') then
    update public.messages set read_at = now()
     where conversation_id = c.id and direction = 'from_patient' and read_at is null;
  end if;
end $$;
revoke execute on function public.mark_conversation_read(uuid) from public, anon;
grant  execute on function public.mark_conversation_read(uuid) to authenticated;

alter publication supabase_realtime add table public.messages, public.conversations;
