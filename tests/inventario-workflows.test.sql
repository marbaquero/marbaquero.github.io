begin;
create extension if not exists pgtap with schema extensions;

-- Isolated synthetic households; no real customer or family records.
insert into auth.users (
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values
  ('33333333-3333-4333-8333-333333333333', 'authenticated', 'authenticated',
   'inventario-a@example.invalid', '', now(), '{}'::jsonb, '{}'::jsonb, now(), now()),
  ('44444444-4444-4444-8444-444444444444', 'authenticated', 'authenticated',
   'inventario-b@example.invalid', '', now(), '{}'::jsonb, '{}'::jsonb, now(), now())
on conflict (id) do nothing;

insert into public.households (id, name, created_by) values
  ('cccccccc-cccc-4ccc-8ccc-cccccccccccc', 'Inventario Test A',
   '33333333-3333-4333-8333-333333333333'),
  ('dddddddd-dddd-4ddd-8ddd-dddddddddddd', 'Inventario Test B',
   '44444444-4444-4444-8444-444444444444');

select plan(12);

-- Create one medicine in each household through the same RPC used by the API.
select lives_ok($$select public.create_customer_medicine(
  'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
  'Test medicine A','10 mg','','20','5','1','tablet','0.25'
)$$, 'Household A can create its own medicine');
select lives_ok($$select public.create_customer_medicine(
  'dddddddd-dddd-4ddd-8ddd-dddddddddddd',
  'Test medicine B','5 mg','','7','2','1','tablet','0.10'
)$$, 'Household B can create its own medicine');

select is((select stock_quantity from customer_data.medicines
  where household_id='cccccccc-cccc-4ccc-8ccc-cccccccccccc' and name='Test medicine A'),
  20::numeric, 'New medicine starts with the requested stock');

-- Dispensing changes stock and writes an event atomically.
select lives_ok($$select public.record_customer_dispensing(
  'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
  (select id from customer_data.medicines where household_id='cccccccc-cccc-4ccc-8ccc-cccccccccccc' and name='Test medicine A'),
  3,'Synthetic caregiver',now()
)$$, 'Dispensing succeeds for a medicine in the same household');
select is((select stock_quantity from customer_data.medicines
  where household_id='cccccccc-cccc-4ccc-8ccc-cccccccccccc' and name='Test medicine A'),
  17::numeric, 'Dispensing decrements stock');
select is((select count(*)::integer from customer_data.medicine_dispensing_events
  where household_id='cccccccc-cccc-4ccc-8ccc-cccccccccccc'), 1,
  'Successful dispensing creates one history event');

select throws_ok($$select public.record_customer_dispensing(
  'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
  (select id from customer_data.medicines where household_id='cccccccc-cccc-4ccc-8ccc-cccccccccccc' and name='Test medicine A'),
  999,'Synthetic caregiver',now()
)$$, '22023', 'Insufficient stock',
  'Dispensing more than available stock is rejected');
select is((select stock_quantity from customer_data.medicines
  where household_id='cccccccc-cccc-4ccc-8ccc-cccccccccccc' and name='Test medicine A'),
  17::numeric, 'Rejected dispensing leaves stock unchanged');

-- A medicine ID from Household B cannot be used in Household A's operation.
select throws_ok($$select public.record_customer_dispensing(
  'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
  (select id from customer_data.medicines where household_id='dddddddd-dddd-4ddd-8ddd-dddddddddddd' and name='Test medicine B'),
  1,'Synthetic caregiver',now()
)$$, 'P0002', 'Medicine not found',
  'Cross-household medicine reference is rejected');

-- Purchase stock application and weekly fill both update stock atomically.
select lives_ok($$select public.record_customer_purchase(
  'cccccccc-cccc-4ccc-8ccc-cccccccccccc',current_date,'Test pharmacy','TEST-001',
  5,0,true,
  (select jsonb_build_array(jsonb_build_object(
    'name','Test medicine A','quantity',5,'subtotal',5,
    'medicine_id',id
  )) from customer_data.medicines
    where household_id='cccccccc-cccc-4ccc-8ccc-cccccccccccc' and name='Test medicine A')
)$$, 'Stock-applied purchase succeeds');
select is((select stock_quantity from customer_data.medicines
  where household_id='cccccccc-cccc-4ccc-8ccc-cccccccccccc' and name='Test medicine A'),
  22::numeric, 'Purchase adds the purchased quantity to stock');

select throws_ok($$select public.record_customer_weekly_fill(
  'cccccccc-cccc-4ccc-8ccc-cccccccccccc',now(),'Synthetic caregiver',true,
  (select jsonb_build_array(jsonb_build_object('medicine_id',id,'quantity',999))
   from customer_data.medicines
   where household_id='cccccccc-cccc-4ccc-8ccc-cccccccccccc' and name='Test medicine A')
)$$, '22023', 'Insufficient stock for weekly fill',
  'Weekly fill exceeding available stock is rejected');

select * from finish();
rollback;
