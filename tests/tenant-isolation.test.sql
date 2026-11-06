begin;

create extension if not exists pgtap with schema extensions;

create table public.ci_households (
  id uuid primary key,
  name text not null
);

create table public.ci_household_members (
  household_id uuid not null references public.ci_households(id),
  user_id uuid not null,
  primary key (household_id, user_id)
);

create table public.ci_records (
  id bigint generated always as identity primary key,
  household_id uuid not null references public.ci_households(id),
  payload text not null
);

create or replace function public.ci_is_household_member(target_household uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.ci_household_members m
    where m.household_id = target_household
      and m.user_id = auth.uid()
  );
$$;

revoke all on function public.ci_is_household_member(uuid) from public, anon;
grant execute on function public.ci_is_household_member(uuid) to authenticated;

alter table public.ci_households enable row level security;
alter table public.ci_household_members enable row level security;
alter table public.ci_records enable row level security;

create policy "ci household members can view their households"
on public.ci_households for select to authenticated
using (public.ci_is_household_member(id));

create policy "ci users can view their own memberships"
on public.ci_household_members for select to authenticated
using (user_id = auth.uid());

create policy "ci members can read household records"
on public.ci_records for select to authenticated
using (public.ci_is_household_member(household_id));

create policy "ci members can insert household records"
on public.ci_records for insert to authenticated
with check (public.ci_is_household_member(household_id));

grant select on public.ci_households, public.ci_household_members, public.ci_records to authenticated;
grant insert on public.ci_records to authenticated;
grant usage, select on sequence public.ci_records_id_seq to authenticated;

insert into public.ci_households (id, name) values
  ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'Synthetic Household A'),
  ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', 'Synthetic Household B');

insert into public.ci_household_members (household_id, user_id) values
  ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', '11111111-1111-4111-8111-111111111111'),
  ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', '22222222-2222-4222-8222-222222222222');

insert into public.ci_records (household_id, payload) values
  ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'A record 1'),
  ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'A record 2'),
  ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', 'B record 1');

select plan(5);

set local role authenticated;
select set_config('request.jwt.claim.sub', '11111111-1111-4111-8111-111111111111', true);
select is((select count(*)::integer from public.ci_records), 2, 'Household A user sees both own records');
select is((select count(*)::integer from public.ci_records where household_id = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'), 0, 'Household A user cannot read Household B records');
select lives_ok(
  $$insert into public.ci_records (household_id, payload) values ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'A new record')$$,
  'Household A user can insert into own household'
);
select throws_ok(
  $$insert into public.ci_records (household_id, payload) values ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', 'cross-tenant attempt')$$,
  '42501',
  null,
  'Household A user cannot insert into Household B'
);

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', '22222222-2222-4222-8222-222222222222', true);
select is((select count(*)::integer from public.ci_records), 1, 'Household B user sees only own record');

select * from finish();
rollback;
