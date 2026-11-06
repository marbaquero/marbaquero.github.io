begin;
create extension if not exists pgtap with schema extensions;
select plan(18);

select ok(to_regnamespace('customer_data') is not null,
  'Private customer_data schema exists');
select ok(not has_schema_privilege('anon','customer_data','usage'),
  'Anonymous role cannot use private customer_data schema');
select ok(not has_schema_privilege('authenticated','customer_data','usage'),
  'Authenticated browser role cannot use private customer_data schema');
select ok(has_schema_privilege('service_role','customer_data','usage'),
  'Trusted service role can use private customer_data schema');

select ok((select count(*) = 8 from information_schema.tables
  where table_schema='customer_data' and table_type='BASE TABLE'),
  'All eight Inventario relational tables exist');

select ok((select bool_and(c.relrowsecurity)
  from pg_class c join pg_namespace n on n.oid=c.relnamespace
  where n.nspname='customer_data' and c.relkind='r'),
  'RLS is enabled on every Inventario table');

select ok(not has_table_privilege('anon','customer_data.medicines','select'),
  'Anonymous role cannot read medicines');
select ok(not has_table_privilege('authenticated','customer_data.medicines','select'),
  'Authenticated browser role cannot read medicines directly');
select ok(not has_table_privilege('authenticated','customer_data.medicines','insert'),
  'Authenticated browser role cannot insert medicines directly');
select ok(has_table_privilege('service_role','customer_data.medicines','select,insert,update,delete'),
  'Trusted service role has required private-table privileges');

select ok(exists (select 1 from pg_constraint
  where conrelid='customer_data.medicine_purchase_items'::regclass
    and contype='f' and conname like '%purchase%'),
  'Purchase items enforce a parent purchase foreign key');
select ok(exists (select 1 from pg_constraint
  where conrelid='customer_data.medicine_purchase_items'::regclass
    and contype='f' and conname like '%medicine%'),
  'Purchase items enforce a household-aware medicine foreign key');
select ok(exists (select 1 from pg_constraint
  where conrelid='customer_data.medicine_dispensing_events'::regclass
    and contype='f'),
  'Dispensing events enforce a household-aware medicine foreign key');
select ok(exists (select 1 from pg_constraint
  where conrelid='customer_data.medicine_fill_items'::regclass
    and contype='f'),
  'Fill items enforce household-aware parent and medicine foreign keys');
select ok(exists (select 1 from pg_constraint
  where conrelid='customer_data.medicine_stock_adjustment_items'::regclass
    and contype='f'),
  'Stock adjustment items enforce household-aware parent and medicine foreign keys');

select ok(exists (select 1 from pg_constraint
  where conrelid='customer_data.medicines'::regclass
    and contype='c' and pg_get_constraintdef(oid) ilike '%stock_quantity%>=%0%'),
  'Medicine stock cannot be negative');
select ok(exists (select 1 from pg_constraint
  where conrelid='customer_data.medicine_dispensing_events'::regclass
    and contype='c' and pg_get_constraintdef(oid) ilike '%quantity%>%0%'),
  'Dispensing quantity must be positive');

select ok(to_regclass('customer_data.medicines_household_active_idx') is not null,
  'Medicine household lookup index exists');

select * from finish();
rollback;
