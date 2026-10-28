-- =====================================================================
-- Staff invites and employee management
-- =====================================================================
-- A lab admin generates a link for a new runner or clerk. The link:
--   * stops working 1 hour after it was created, and
--   * is burned the moment one account has been created with it.
-- Only a hash of the token is stored, so even someone reading the database
-- can't reconstruct a working link.
-- Super admins can also create invites for new lab admins (lab owners).
-- Account creation itself happens in the `redeem-invite` edge function.
-- =====================================================================

create table public.staff_invites (
  id          uuid primary key default gen_random_uuid(),
  lab_id      uuid not null references public.labs on delete cascade,
  role        public.user_role not null check (role in ('clerk', 'runner', 'lab_admin')),
  token_hash  text not null unique,
  created_by  uuid references public.profiles on delete set null,
  created_at  timestamptz not null default now(),
  expires_at  timestamptz not null default now() + interval '1 hour',
  used_at     timestamptz,
  used_by     uuid references public.profiles on delete set null,
  revoked_at  timestamptz
);
create index staff_invites_lab_idx on public.staff_invites (lab_id, created_at desc);

create or replace function public.hash_invite_token(p_token text)
returns text language sql immutable set search_path = '' as $$
  select encode(extensions.digest(p_token, 'sha256'), 'hex')
$$;

-- Returns the raw token once. The app turns it into a link.
create or replace function public.create_staff_invite(p_lab_id uuid, p_role public.user_role)
returns table (invite_id uuid, token text, expires_at timestamptz)
language plpgsql security definer set search_path = '' as $$
declare
  t   text := encode(extensions.gen_random_bytes(24), 'hex');
  inv public.staff_invites;
begin
  if p_role = 'lab_admin' then
    if not public.is_super_admin() then raise exception 'only platform admins can invite lab owners'; end if;
  elsif p_role in ('clerk', 'runner') then
    if not public.has_lab_role(p_lab_id, 'lab_admin') then raise exception 'only the lab owner can invite staff'; end if;
  else
    raise exception 'invalid role';
  end if;

  insert into public.staff_invites (lab_id, role, token_hash, created_by)
  values (p_lab_id, p_role, public.hash_invite_token(t), auth.uid())
  returning * into inv;

  return query select inv.id, t, inv.expires_at;
end $$;

create or replace function public.revoke_staff_invite(p_invite_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
begin
  update public.staff_invites set revoked_at = now()
  where id = p_invite_id and used_at is null and revoked_at is null
    and public.has_lab_role(lab_id, 'lab_admin');
end $$;

-- What the join page shows before sign-up. Callable without an account.
create or replace function public.peek_staff_invite(p_token text)
returns table (lab_name_ar text, lab_name_en text, role public.user_role, expires_at timestamptz)
language sql stable security definer set search_path = '' as $$
  select l.name_ar, l.name_en, i.role, i.expires_at
  from public.staff_invites i join public.labs l on l.id = i.lab_id
  where i.token_hash = public.hash_invite_token(p_token)
    and i.used_at is null and i.revoked_at is null and i.expires_at > now()
$$;

-- Backend only: atomically burn the invite and attach the new account.
-- Two people racing the same link: exactly one wins.
create or replace function public.claim_staff_invite(p_token text, p_user_id uuid, p_full_name text)
returns public.staff_invites
language plpgsql security definer set search_path = '' as $$
declare inv public.staff_invites;
begin
  if not public.is_backend() then raise exception 'backend only'; end if;

  update public.staff_invites
     set used_at = now(), used_by = p_user_id
   where token_hash = public.hash_invite_token(p_token)
     and used_at is null and revoked_at is null and expires_at > now()
  returning * into inv;

  if inv.id is null then raise exception 'invite is invalid, expired or already used'; end if;

  update public.profiles
     set role = inv.role, lab_id = inv.lab_id,
         full_name = coalesce(nullif(trim(p_full_name), ''), full_name)
   where id = p_user_id;

  return inv;
end $$;

-- ---------------------------------------------------------------------
-- Employee management (lab admins, for their own lab)
-- ---------------------------------------------------------------------
create or replace function public.set_employee_role(p_user_id uuid, p_role public.user_role)
returns void language plpgsql security definer set search_path = '' as $$
declare target public.profiles;
begin
  select * into target from public.profiles where id = p_user_id;
  if target.id is null or target.lab_id is null then raise exception 'employee not found'; end if;
  if p_role not in ('clerk', 'runner', 'lab_admin') then
    raise exception 'use remove_employee to take someone off the lab';
  end if;
  if p_role = 'lab_admin' and not public.is_super_admin() then
    raise exception 'lab owners can only switch staff between runner and clerk';
  end if;
  if target.role = 'lab_admin' and not public.is_super_admin() then
    raise exception 'only platform admins can change a lab owner';
  end if;
  if not public.has_lab_role(target.lab_id, 'lab_admin') then raise exception 'not allowed'; end if;

  update public.profiles set role = p_role where id = p_user_id;
end $$;

-- Removes someone from the lab. Their account stays, as a plain patient
-- account, so their own medical history (if any) isn't lost.
create or replace function public.remove_employee(p_user_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare target public.profiles;
begin
  select * into target from public.profiles where id = p_user_id;
  if target.id is null or target.lab_id is null then raise exception 'employee not found'; end if;
  if p_user_id = auth.uid() then raise exception 'you cannot remove yourself'; end if;
  if target.role = 'lab_admin' and not public.is_super_admin() then
    raise exception 'only platform admins can remove a lab owner';
  end if;
  if not public.has_lab_role(target.lab_id, 'lab_admin') then raise exception 'not allowed'; end if;

  update public.orders set runner_id = null
   where runner_id = p_user_id and status = 'accepted';
  update public.profiles set role = 'patient', lab_id = null where id = p_user_id;
end $$;

alter table public.staff_invites enable row level security;

create policy invites_read on public.staff_invites for select to authenticated
  using (public.has_lab_role(lab_id, 'lab_admin'));

revoke execute on function public.create_staff_invite(uuid, public.user_role) from public, anon;
revoke execute on function public.revoke_staff_invite(uuid) from public, anon;
revoke execute on function public.claim_staff_invite(text, uuid, text) from public, anon, authenticated;
revoke execute on function public.set_employee_role(uuid, public.user_role) from public, anon;
revoke execute on function public.remove_employee(uuid) from public, anon;
grant execute on function public.create_staff_invite(uuid, public.user_role) to authenticated;
grant execute on function public.revoke_staff_invite(uuid) to authenticated;
grant execute on function public.set_employee_role(uuid, public.user_role) to authenticated;
grant execute on function public.remove_employee(uuid) to authenticated;
grant execute on function public.peek_staff_invite(text) to anon, authenticated;
grant execute on function public.claim_staff_invite(text, uuid, text) to service_role;
