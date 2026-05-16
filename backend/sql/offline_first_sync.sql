-- Run in Supabase SQL Editor if automatic table preparation is disabled or
-- your Supabase schema already existed before offline-first sync was added.

create table if not exists restaurants (
  id text primary key,
  name text not null,
  created_at timestamptz,
  updated_at timestamptz
);

create table if not exists outlets (
  id text primary key,
  restaurant_id text references restaurants(id),
  name text not null,
  server_id text unique not null,
  banner_url text,
  video_url text,
  gallery_images jsonb,
  created_at timestamptz,
  updated_at timestamptz
);

create table if not exists admin_accounts (
  id text primary key,
  outlet_id text references outlets(id),
  email text unique not null,
  username text unique not null,
  password_hash text not null,
  created_at timestamptz,
  updated_at timestamptz
);

create table if not exists devices (
  id text primary key,
  outlet_id text references outlets(id),
  server_id text not null,
  registered_at timestamptz,
  created_at timestamptz,
  updated_at timestamptz
);

create table if not exists menu_items (
  id text primary key,
  outlet_id text references outlets(id),
  name text not null,
  description text,
  price numeric(10,2) not null,
  category text,
  is_available boolean default true,
  image_url text,
  video_url text,
  version integer default 1,
  created_at timestamptz,
  updated_at timestamptz,
  deleted_at timestamptz
);

create table if not exists customers (
  id text primary key,
  outlet_id text references outlets(id),
  name text,
  phone text,
  email text,
  created_at timestamptz,
  updated_at timestamptz
);

create table if not exists orders (
  id text primary key,
  outlet_id text references outlets(id),
  serial_number integer default 0,
  source text default 'pos',
  status text default 'pending',
  total_amount numeric(10,2) default 0,
  items jsonb,
  notes text,
  table_no text,
  customer_id text,
  payment_status text default 'unpaid',
  created_at timestamptz,
  updated_at timestamptz
);

create table if not exists order_items (
  id text primary key,
  order_id text references orders(id),
  outlet_id text references outlets(id),
  menu_item_id text,
  name text not null,
  qty integer default 1,
  price numeric(10,2) default 0,
  line_total numeric(10,2) default 0,
  created_at timestamptz,
  updated_at timestamptz
);

create table if not exists pos_tables (
  id text primary key,
  outlet_id text references outlets(id),
  table_no text not null,
  label text,
  is_active boolean default true,
  created_at timestamptz,
  updated_at timestamptz
);

create table if not exists sales (
  id text primary key,
  outlet_id text references outlets(id),
  order_id text references orders(id),
  total_amount numeric(10,2) default 0,
  status text default 'open',
  sold_at timestamptz,
  created_at timestamptz,
  updated_at timestamptz
);

create table if not exists payments (
  id text primary key,
  outlet_id text references outlets(id),
  order_id text references orders(id),
  amount numeric(10,2) default 0,
  currency text default 'BDT',
  method text default 'cash',
  status text default 'pending',
  transaction_id text,
  created_at timestamptz,
  updated_at timestamptz
);

create table if not exists bkash_sessions (
  id text primary key,
  server_id text not null,
  amount numeric(10,2) not null,
  currency text default 'BDT',
  purpose text not null,
  status text default 'pending',
  created_at timestamptz,
  updated_at timestamptz
);

do $$
declare
  t text;
begin
  foreach t in array array[
    'restaurants', 'outlets', 'admin_accounts', 'devices', 'menu_items',
    'customers', 'orders', 'order_items', 'pos_tables', 'sales', 'payments',
    'bkash_sessions'
  ]
  loop
    execute format('alter table %I add column if not exists local_id text', t);
    execute format('alter table %I add column if not exists remote_id text', t);
    execute format('alter table %I add column if not exists sync_status text default ''pending''', t);
    execute format('alter table %I add column if not exists last_sync_error text', t);
    execute format('alter table %I add column if not exists created_at timestamptz', t);
    execute format('alter table %I add column if not exists updated_at timestamptz', t);
    execute format('alter table %I add column if not exists synced_at timestamptz', t);
    execute format('update %I set local_id = id where local_id is null', t);
    execute format('update %I set created_at = now() where created_at is null', t);
    execute format('update %I set updated_at = created_at where updated_at is null', t);
    execute format('create unique index if not exists ix_%s_local_id on %I(local_id) where local_id is not null', t, t);
  end loop;
end $$;
