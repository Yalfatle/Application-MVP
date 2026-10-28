-- =====================================================================
-- Mukhtabarat — core schema: roles, profiles, labs, packages, settings
-- =====================================================================
-- Role hierarchy (each role has every permission of the roles below it):
--   super_admin  > lab_admin > runner > clerk > patient
-- Staff roles (lab_admin, runner, clerk) always belong to exactly one lab.
-- Super admins are set by hand in SQL; nothing in the app can grant it.
-- =====================================================================

create extension if not exists pgcrypto with schema extensions;

create type public.user_role as enum ('patient', 'clerk', 'runner', 'lab_admin', 'super_admin');

-- ---------------------------------------------------------------------
-- Platform settings (single row)
-- ---------------------------------------------------------------------
create table public.app_settings (
  id               boolean primary key default true check (id),
  commission_rate  numeric(5,4) not null default 0.15 check (commission_rate between 0 and 1),
  updated_at       timestamptz not null default now()
);
insert into public.app_settings (id) values (true);

-- ---------------------------------------------------------------------
-- Labs
-- ---------------------------------------------------------------------
create table public.labs (
  id                uuid primary key default gen_random_uuid(),
  name_ar           text not null check (length(trim(name_ar)) > 0),
  name_en           text not null check (length(trim(name_en)) > 0),
  description_ar    text,
  description_en    text,
  area_ar           text,            -- e.g. "المنصور - بغداد"
  area_en           text,            -- e.g. "Al-Mansour, Baghdad"
  address_ar        text,
  address_en        text,
  lat               double precision check (lat between -90 and 90),
  lng               double precision check (lng between -180 and 180),
  contact_phone     text,            -- the lab's own public number (not patients')
  contact_whatsapp  text,
  contact_email     text,
  cover_photo_path  text,            -- path inside the "lab-photos" bucket
  commission_rate   numeric(5,4) check (commission_rate between 0 and 1), -- null = platform default
  is_active         boolean not null default true,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now()
);
create index labs_active_idx on public.labs (is_active);

create table public.lab_photos (
  id            uuid primary key default gen_random_uuid(),
  lab_id        uuid not null references public.labs on delete cascade,
  storage_path  text not null unique,
  position      integer not null default 0,
  created_at    timestamptz not null default now()
);
create index lab_photos_lab_idx on public.lab_photos (lab_id, position);

-- ---------------------------------------------------------------------
-- Profiles (one per auth user). Phone numbers and emails are NOT stored
-- here: they stay in auth.users, which no lab staff can read.
-- ---------------------------------------------------------------------
create table public.profiles (
  id                uuid primary key references auth.users on delete cascade,
  full_name         text,
  role              public.user_role not null default 'patient',
  lab_id            uuid references public.labs on delete set null,
  preferred_locale  text not null default 'ar' check (preferred_locale in ('ar', 'en')),
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  constraint staff_have_lab check (
    (role in ('clerk', 'runner', 'lab_admin') and lab_id is not null)
    or (role in ('patient', 'super_admin') and lab_id is null)
  )
);
create index profiles_lab_idx on public.profiles (lab_id) where lab_id is not null;

-- ---------------------------------------------------------------------
-- Packages (tests a lab offers)
-- ---------------------------------------------------------------------
create table public.packages (
  id              uuid primary key default gen_random_uuid(),
  lab_id          uuid not null references public.labs on delete cascade,
  name_ar         text not null check (length(trim(name_ar)) > 0),
  name_en         text not null check (length(trim(name_en)) > 0),
  description_ar  text,
  description_en  text,
  price_iqd       integer not null check (price_iqd >= 0),
  is_active       boolean not null default true,
  position        integer not null default 0,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);
create index packages_lab_idx on public.packages (lab_id, position) where is_active;

-- ---------------------------------------------------------------------
-- updated_at maintenance
-- ---------------------------------------------------------------------
create or replace function public.touch_updated_at()
returns trigger language plpgsql set search_path = '' as $$
begin
  new.updated_at := now();
  return new;
end $$;

create trigger labs_touch      before update on public.labs         for each row execute function public.touch_updated_at();
create trigger profiles_touch  before update on public.profiles     for each row execute function public.touch_updated_at();
create trigger packages_touch  before update on public.packages     for each row execute function public.touch_updated_at();
create trigger settings_touch  before update on public.app_settings for each row execute function public.touch_updated_at();

-- ---------------------------------------------------------------------
-- Permission helpers. SECURITY DEFINER so policies can call them without
-- recursing into profiles' own RLS.
-- ---------------------------------------------------------------------
create or replace function public.role_rank(r public.user_role)
returns integer language sql immutable set search_path = '' as $$
  select case r
    when 'patient'     then 0
    when 'clerk'       then 1
    when 'runner'      then 2
    when 'lab_admin'   then 3
    when 'super_admin' then 4
  end
$$;

-- True when the request runs with the service-role key (edge functions)
-- or directly in the SQL editor — i.e. trusted backend code.
create or replace function public.is_backend()
returns boolean language sql stable set search_path = '' as $$
  select coalesce(auth.jwt() ->> 'role', '') = 'service_role'
      or (auth.uid() is null and current_user in ('postgres', 'supabase_admin'))
$$;

create or replace function public.my_role()
returns public.user_role language sql stable security definer set search_path = '' as $$
  select coalesce((select role from public.profiles where id = auth.uid()), 'patient'::public.user_role)
$$;

create or replace function public.my_lab_id()
returns uuid language sql stable security definer set search_path = '' as $$
  select lab_id from public.profiles where id = auth.uid()
$$;

create or replace function public.is_super_admin()
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.profiles where id = auth.uid() and role = 'super_admin')
$$;

-- Has at least `min_role` inside `p_lab` (super admins pass for every lab).
create or replace function public.has_lab_role(p_lab uuid, min_role public.user_role)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.profiles p
    where p.id = auth.uid()
      and (
        p.role = 'super_admin'
        or (p.lab_id = p_lab and public.role_rank(p.role) >= public.role_rank(min_role)
            and p.role <> 'patient')
      )
  )
$$;

-- ---------------------------------------------------------------------
-- New auth user -> patient profile
-- ---------------------------------------------------------------------
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  insert into public.profiles (id, full_name, preferred_locale)
  values (
    new.id,
    nullif(trim(new.raw_user_meta_data ->> 'full_name'), ''),
    case when new.raw_user_meta_data ->> 'locale' = 'en' then 'en' else 'ar' end
  )
  on conflict (id) do nothing;
  return new;
end $$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- Users may edit their own name and language, but never their role or lab.
-- Role/lab changes only happen through the approved functions (which run
-- as their owner, not as `authenticated`) or backend code.
-- Deliberately NOT security definer: current_user tells us whether the
-- change comes straight from an app user or from trusted database code.
create or replace function public.guard_profile_update()
returns trigger language plpgsql set search_path = '' as $$
begin
  if current_user not in ('authenticated', 'anon') then
    return new;  -- approved function or backend
  end if;
  if public.is_super_admin() then
    -- Nobody may hand out super_admin from the app, not even a super admin.
    if new.role = 'super_admin' and old.role <> 'super_admin' then
      raise exception 'super_admin can only be granted directly in the database';
    end if;
    return new;
  end if;
  if new.role is distinct from old.role or new.lab_id is distinct from old.lab_id then
    raise exception 'not allowed to change role or lab';
  end if;
  return new;
end $$;

create trigger profiles_guard before update on public.profiles
  for each row execute function public.guard_profile_update();

-- Lab admins can edit their lab's details but not activation or commission.
create or replace function public.guard_lab_update()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if public.is_backend() or public.is_super_admin() then
    return new;
  end if;
  if new.is_active is distinct from old.is_active
     or new.commission_rate is distinct from old.commission_rate then
    raise exception 'only platform admins can change activation or commission';
  end if;
  return new;
end $$;

create trigger labs_guard before update on public.labs
  for each row execute function public.guard_lab_update();

-- ---------------------------------------------------------------------
-- Row level security
-- ---------------------------------------------------------------------
alter table public.app_settings enable row level security;
alter table public.labs         enable row level security;
alter table public.lab_photos   enable row level security;
alter table public.profiles     enable row level security;
alter table public.packages     enable row level security;

-- Settings: anyone signed in can read, only super admins change.
create policy settings_read  on public.app_settings for select to authenticated using (true);
create policy settings_write on public.app_settings for update to authenticated
  using (public.is_super_admin()) with check (public.is_super_admin());

-- Labs: active labs are public (patients browse before signing in).
create policy labs_read on public.labs for select to anon, authenticated
  using (is_active or public.has_lab_role(id, 'clerk'));
create policy labs_insert on public.labs for insert to authenticated
  with check (public.is_super_admin());
create policy labs_update on public.labs for update to authenticated
  using (public.has_lab_role(id, 'lab_admin')) with check (public.has_lab_role(id, 'lab_admin'));
create policy labs_delete on public.labs for delete to authenticated
  using (public.is_super_admin());

create policy lab_photos_read on public.lab_photos for select to anon, authenticated using (true);
create policy lab_photos_write on public.lab_photos for all to authenticated
  using (public.has_lab_role(lab_id, 'lab_admin')) with check (public.has_lab_role(lab_id, 'lab_admin'));

-- Packages: active ones public; lab admins manage their own.
create policy packages_read on public.packages for select to anon, authenticated
  using (is_active or public.has_lab_role(lab_id, 'clerk'));
create policy packages_write on public.packages for all to authenticated
  using (public.has_lab_role(lab_id, 'lab_admin')) with check (public.has_lab_role(lab_id, 'lab_admin'));

-- Profiles: you, your lab colleagues, and super admins.
-- (Patients-of-my-lab and my-runner visibility are added in the orders migration.)
create policy profiles_read_self on public.profiles for select to authenticated
  using (id = (select auth.uid()) or public.is_super_admin());
create policy profiles_read_colleagues on public.profiles for select to authenticated
  using (lab_id is not null and lab_id = public.my_lab_id());
create policy profiles_update_self on public.profiles for update to authenticated
  using (id = (select auth.uid()) or public.is_super_admin())
  with check (id = (select auth.uid()) or public.is_super_admin());
