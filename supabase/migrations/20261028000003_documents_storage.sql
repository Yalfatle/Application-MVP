-- =====================================================================
-- Patient documents (results, reports) and file storage
-- =====================================================================
-- Medical files live in a PRIVATE bucket. The app opens them with
-- short-lived signed links, so a leaked link stops working within minutes.
--
-- File path layout:  patient-documents/{lab_id}/{patient_id}/{random}-{name}
--
-- "Deleting" a document hides it from everyone but super admins (soft
-- delete). Medical records shouldn't vanish by accident; super admins can
-- restore or permanently purge.
-- =====================================================================

create table public.patient_documents (
  id            uuid primary key default gen_random_uuid(),
  patient_id    uuid not null references public.profiles on delete cascade,
  lab_id        uuid not null references public.labs on delete restrict,
  order_id      uuid references public.orders on delete set null,
  title         text check (length(title) <= 200),
  file_name     text not null,
  mime_type     text not null check (mime_type in ('application/pdf', 'image/jpeg', 'image/png', 'image/webp')),
  size_bytes    integer not null check (size_bytes > 0 and size_bytes <= 20 * 1024 * 1024),
  storage_path  text not null unique,
  uploaded_by   uuid references public.profiles on delete set null,
  created_at    timestamptz not null default now(),
  deleted_at    timestamptz,
  deleted_by    uuid references public.profiles on delete set null,
  constraint path_matches check (storage_path like lab_id::text || '/' || patient_id::text || '/%')
);
create index patient_documents_patient_idx on public.patient_documents (patient_id, created_at desc) where deleted_at is null;
create index patient_documents_order_idx   on public.patient_documents (order_id) where order_id is not null;

create or replace function public.prepare_document()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if not public.is_backend() then
    new.uploaded_by := auth.uid();
  end if;
  new.deleted_at := null;
  new.deleted_by := null;
  if new.order_id is not null and not exists (
       select 1 from public.orders where id = new.order_id
       and patient_id = new.patient_id and lab_id = new.lab_id) then
    raise exception 'order does not belong to this patient and lab';
  end if;
  return new;
end $$;

create trigger patient_documents_prepare before insert on public.patient_documents
  for each row execute function public.prepare_document();

create or replace function public.delete_patient_document(p_document_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare d public.patient_documents;
begin
  select * into d from public.patient_documents where id = p_document_id and deleted_at is null;
  if d.id is null then raise exception 'document not found'; end if;
  if not public.has_lab_role(d.lab_id, 'clerk') then raise exception 'not allowed'; end if;
  update public.patient_documents set deleted_at = now(), deleted_by = auth.uid() where id = d.id;
end $$;

revoke execute on function public.delete_patient_document(uuid) from public, anon;
grant  execute on function public.delete_patient_document(uuid) to authenticated;

alter table public.patient_documents enable row level security;

-- Patients see their own; staff see documents of patients who booked with
-- their lab (including documents uploaded by other labs — full history).
create policy documents_read on public.patient_documents for select to authenticated
  using (
    public.is_super_admin()
    or (deleted_at is null and (
          patient_id = (select auth.uid())
          or public.can_staff_see_patient(patient_id)))
  );

create policy documents_insert on public.patient_documents for insert to authenticated
  with check (
    public.has_lab_role(lab_id, 'clerk')
    and public.patient_booked_with_lab(patient_id, lab_id)
  );

create policy documents_admin on public.patient_documents for update to authenticated
  using (public.is_super_admin()) with check (public.is_super_admin());

-- ---------------------------------------------------------------------
-- Storage buckets
-- ---------------------------------------------------------------------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types) values
  ('patient-documents', 'patient-documents', false, 20 * 1024 * 1024,
     array['application/pdf', 'image/jpeg', 'image/png', 'image/webp']),
  ('lab-photos', 'lab-photos', true, 5 * 1024 * 1024,
     array['image/jpeg', 'image/png', 'image/webp'])
on conflict (id) do nothing;

-- Path helpers: {lab_id}/{patient_id}/...
create or replace function public.path_lab(p_name text)
returns uuid language sql immutable set search_path = '' as $$
  select case when split_part(p_name, '/', 1) ~ '^[0-9a-f-]{36}$'
              then split_part(p_name, '/', 1)::uuid end
$$;
create or replace function public.path_patient(p_name text)
returns uuid language sql immutable set search_path = '' as $$
  select case when split_part(p_name, '/', 2) ~ '^[0-9a-f-]{36}$'
              then split_part(p_name, '/', 2)::uuid end
$$;

-- Reading a file requires a live (not deleted) document row you're allowed
-- to see — so soft-deleted files can't be opened even with the path.
create policy "documents: read" on storage.objects for select to authenticated
  using (
    bucket_id = 'patient-documents'
    and exists (select 1 from public.patient_documents d where d.storage_path = name)
  );

create policy "documents: upload" on storage.objects for insert to authenticated
  with check (
    bucket_id = 'patient-documents'
    and public.has_lab_role(public.path_lab(name), 'clerk')
    and public.patient_booked_with_lab(public.path_patient(name), public.path_lab(name))
  );

create policy "documents: purge" on storage.objects for delete to authenticated
  using (bucket_id = 'patient-documents' and public.is_super_admin());

-- Lab photos: public to view, lab admins manage their folder ({lab_id}/...).
create policy "lab photos: write" on storage.objects for insert to authenticated
  with check (bucket_id = 'lab-photos' and public.has_lab_role(public.path_lab(name), 'lab_admin'));
create policy "lab photos: update" on storage.objects for update to authenticated
  using (bucket_id = 'lab-photos' and public.has_lab_role(public.path_lab(name), 'lab_admin'));
create policy "lab photos: delete" on storage.objects for delete to authenticated
  using (bucket_id = 'lab-photos' and public.has_lab_role(public.path_lab(name), 'lab_admin'));
