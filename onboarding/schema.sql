-- Cuidar a Distancia: isolated customer onboarding schema
-- Run only in a NEW, dedicated Supabase project for commercial customers.
-- Do not run this in the personal/family-care Supabase project.
create extension if not exists pgcrypto;

create table if not exists public.customer_onboarding (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null unique references auth.users(id) on delete cascade,
  contact_name text not null check (char_length(contact_name) between 1 and 120),
  email text not null,
  country text not null check (char_length(country) between 1 and 100),
  family_member_name text,
  caregivers_count text not null default '1',
  plan text not null,
  preferred_language text not null default 'English',
  requested_tools text[] not null default '{}',
  notes text,
  status text not null default 'received' check (status in ('received','reviewing','setup_in_progress','active','closed')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.customer_onboarding_files (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  storage_path text not null unique,
  file_name text not null,
  mime_type text,
  size_bytes bigint not null check (size_bytes > 0 and size_bytes <= 10485760),
  created_at timestamptz not null default now()
);

alter table public.customer_onboarding enable row level security;
alter table public.customer_onboarding_files enable row level security;

-- Customers can see and update only their own onboarding record.
create policy "customer reads own onboarding"
on public.customer_onboarding for select to authenticated
using (auth.uid() = user_id or (auth.jwt() -> 'app_metadata' ->> 'role') = 'admin');

create policy "customer inserts own onboarding"
on public.customer_onboarding for insert to authenticated
with check (auth.uid() = user_id);

create policy "customer updates own onboarding"
on public.customer_onboarding for update to authenticated
using (auth.uid() = user_id or (auth.jwt() -> 'app_metadata' ->> 'role') = 'admin')
with check (auth.uid() = user_id or (auth.jwt() -> 'app_metadata' ->> 'role') = 'admin');

create policy "customer reads own file metadata"
on public.customer_onboarding_files for select to authenticated
using (auth.uid() = user_id or (auth.jwt() -> 'app_metadata' ->> 'role') = 'admin');

create policy "customer inserts own file metadata"
on public.customer_onboarding_files for insert to authenticated
with check (auth.uid() = user_id);

-- Private bucket: never make this bucket public.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'customer-onboarding-private',
  'customer-onboarding-private',
  false,
  10485760,
  array[
    'application/pdf','text/csv','application/vnd.ms-excel',
    'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    'application/msword','application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    'image/jpeg','image/png'
  ]
)
on conflict (id) do update set
  public = false,
  file_size_limit = 10485760,
  allowed_mime_types = excluded.allowed_mime_types;

-- The first folder in every object path is the authenticated user's UUID.
create policy "customer uploads only into own folder"
on storage.objects for insert to authenticated
with check (
  bucket_id = 'customer-onboarding-private'
  and (storage.foldername(name))[1] = auth.uid()::text
);

create policy "customer reads own private files"
on storage.objects for select to authenticated
using (
  bucket_id = 'customer-onboarding-private'
  and (
    (storage.foldername(name))[1] = auth.uid()::text
    or (auth.jwt() -> 'app_metadata' ->> 'role') = 'admin'
  )
);

-- No anonymous policies. No public bucket. Admin access is granted only by
-- setting app_metadata.role = 'admin' for the owner's Auth user in Supabase.
