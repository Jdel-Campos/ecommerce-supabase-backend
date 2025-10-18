-- =============================================
-- SCHEMA: E-COMMERCE BACKEND (FINAL V3)
-- =============================================

-- 1️⃣ EXTENSIONS
create extension if not exists "pgcrypto";

-- =============================================
-- 2️⃣ FUNCTION: Atualização automática de "updated_at"
create or replace function update_updated_at_column()
returns trigger as $$
begin
    new.updated_at = now();
    return new;
end;
$$ language plpgsql;

-- =============================================
-- 3️⃣ TABELA: USERS (Controle de acesso e autenticação)
create table if not exists public.users (
    id uuid primary key references auth.users(id) on delete cascade,
    name text not null,
    email text unique not null,
    password_hash text default 'auth_managed', -- placeholder (Auth gerencia senha)
    role text default 'user' check (role in ('user', 'admin')),
    created_at timestamp default now(),
    updated_at timestamp default now()
);

create or replace function public.update_updated_at_column()
returns trigger as $$
begin
  new.updated_at = now();
  return new;
end;
$$ language plpgsql;

create trigger trg_users_set_timestamp
  before update on public.users
  for each row
  execute procedure public.update_updated_at_column();

-- =============================================
-- 4️⃣ TABELA: CUSTOMERS (Clientes comerciais)
create table if not exists customers (
    id uuid default gen_random_uuid() primary key,
    name text not null,
    email text not null unique,
    phone text,
    address text,
    created_at timestamp default now(),
    updated_at timestamp default now()
);

create trigger trg_customers_set_timestamp
    before update on customers
    for each row
    execute procedure update_updated_at_column();

comment on table customers is
'Informações dos clientes vinculadas aos pedidos. O e-mail conecta com a tabela users.';

-- =============================================
-- 5️⃣ TABELA: PRODUCTS (Catálogo)
create table if not exists products (
    id uuid default gen_random_uuid() primary key,
    name text not null,
    description text,
    price numeric(10, 2) not null,
    stock integer default 0 check (stock >= 0),
    active boolean default true,
    created_at timestamp default now(),
    updated_at timestamp default now(),
    constraint unique_product_name unique (name)
);

create trigger trg_products_set_timestamp
    before update on products
    for each row
    execute procedure update_updated_at_column();

comment on table products is
'Catálogo de produtos disponíveis para venda.';

-- =============================================
-- 6️⃣ ENUM: ORDER_STATUS (Estados do pedido)
create type order_status as enum (
    'pending',
    'paid',
    'shipped',
    'delivered',
    'cancelled'
);

-- =============================================
-- 7️⃣ TABELA: ORDERS (Pedidos)
create table if not exists orders (
    id uuid default gen_random_uuid() primary key,
    customer_id uuid references customers(id) on delete cascade,
    order_date timestamp default now(),
    status order_status default 'pending',
    total_amount numeric(10, 2) default 0.00,
    created_at timestamp default now(),
    updated_at timestamp default now()
);

create trigger trg_orders_set_timestamp
    before update on orders
    for each row
    execute procedure update_updated_at_column();

create index if not exists idx_orders_customer_id on orders(customer_id);
create index if not exists idx_orders_status on orders(status);
create index if not exists idx_orders_date on orders(order_date);

comment on table orders is
'Pedidos realizados por clientes, vinculados à tabela customers.';

-- =============================================
-- 8️⃣ TABELA: ORDER_ITEMS (Itens de cada pedido)
create table if not exists order_items (
    id uuid default gen_random_uuid() primary key,
    order_id uuid references orders(id) on delete cascade,
    product_id uuid references products(id) on delete restrict,
    quantity integer not null check (quantity > 0),
    unit_price numeric(10, 2) not null,
    total_amount numeric(10, 2) generated always as (quantity * unit_price) stored,
    constraint unique_order_product unique (order_id, product_id)
);

create index if not exists idx_order_items_order_id on order_items(order_id);
create index if not exists idx_order_items_product_id on order_items(product_id);

comment on table order_items is
'Itens vinculados aos pedidos, armazenando quantidade, preço unitário e total.';

-- =============================================
-- 9️⃣ FUNCTIONS DE CÁLCULO E TRIGGER
-- (Incluídas diretamente aqui para integridade)
create or replace function calculate_order_total(p_order_id uuid)
returns void
language plpgsql
security definer
as $$
begin
  update orders
  set total_amount = coalesce((
    select sum(quantity * unit_price)::numeric(10,2)
    from order_items
    where order_id = p_order_id
  ), 0)
  where id = p_order_id;
end;
$$;

create or replace function recalculate_order_total_func()
returns trigger
language plpgsql
security definer
as $$
declare
  target_order_id uuid;
begin
  target_order_id := coalesce(new.order_id, old.order_id);
  perform calculate_order_total(target_order_id);
  return new;
end;
$$;

drop trigger if exists trg_recalculate_order_total on order_items;

create trigger trg_recalculate_order_total
after insert or update or delete on order_items
for each row
execute procedure recalculate_order_total_func();

comment on trigger trg_recalculate_order_total on order_items
is 'Recalcula automaticamente o total do pedido após alterações nos itens.';

-- =============================================
-- 🔟 VIEW: view_orders_with_customers (básica)
create or replace view view_orders_with_customers
with (security_invoker = true) as
select
    o.id as order_id,
    o.customer_id,
    c.name as customer_name,
    c.email as customer_email,
    to_char(o.order_date, 'DD/MM/YYYY HH24:MI') as order_date_formatted,
    o.status,
    o.total_amount,
    o.created_at as order_created_at,
    o.updated_at as order_updated_at
from orders o
join customers c on c.id = o.customer_id;

-- =============================================
-- 11️⃣ VIEW: view_orders_detailed (detalhada)
create or replace view view_orders_detailed
with (security_invoker = true) as
select
    o.id as order_id,
    o.customer_id,
    c.name as customer_name,
    c.email as customer_email,
    to_char(o.order_date, 'DD/MM/YYYY HH24:MI') as order_date_formatted,
    o.status,
    o.total_amount as order_total,
    i.id as item_id,
    i.quantity as item_quantity,
    i.unit_price as item_unit_price,
    i.total_amount as item_total,
    p.id as product_id,
    p.name as product_name,
    p.price as product_price
from orders o
join customers c on c.id = o.customer_id
join order_items i on i.order_id = o.id
join products p on p.id = i.product_id
where p.active = true;

-- =============================================
-- 12️⃣ VIEW: view_orders_summary (resumo geral)
create or replace view view_orders_summary
with (security_invoker = true) as
select
    c.id as customer_id,
    c.name as customer_name,
    c.email as customer_email,
    count(o.id) as total_orders,
    coalesce(sum(o.total_amount), 0) as total_spent,
    max(o.created_at) as last_order_date
from customers c
left join orders o on o.customer_id = c.id
group by c.id, c.name, c.email;
