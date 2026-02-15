-- =============================================
-- SCHEMA: E-COMMERCE BACKEND (REV V3)
-- =============================================

-- 1) EXTENSIONS
create extension if not exists "pgcrypto";

-- 2) TRIGGER HELPER: atualiza updated_at
create or replace function public.touch_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

-- =============================================
-- 3) CUSTOMERS -- Chave para RLS: user_id -> auth.users(id)
create table if not exists public.customers (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null unique references auth.users(id) on delete cascade,
  name        text not null,
  email       text not null unique,
  phone       text,
  address     text,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

drop trigger if exists trg_customers_set_timestamp on public.customers;
create trigger trg_customers_set_timestamp
  before update on public.customers
  for each row
  execute function public.touch_updated_at();

comment on table public.customers is
'Clientes vinculados a auth.users por user_id; base para RLS.';

-- =============================================
-- 5) PRODUCTS -- Catálogo de produtos do e-commerce

-- Tabela de produtos
create table if not exists public.products (
  id          uuid primary key default gen_random_uuid(),
  name        text not null,
  description text,
  price       numeric(12,2) not null check (price >= 0),
  stock       integer not null default 0 check (stock >= 0),
  active      boolean not null default true,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

-- Trigger para manter updated_at sempre atualizado
drop trigger if exists trg_products_set_timestamp on public.products;
create trigger trg_products_set_timestamp
  before update on public.products
  for each row
  execute function public.touch_updated_at();

-- Índices para performance em consultas comuns
create index if not exists idx_products_active
  on public.products (active);

create index if not exists idx_products_name
  on public.products (name);

comment on table public.products is
'Produtos disponíveis para venda. Usado por orders/order_items.';

-- =============================================
-- 6) ENUM: ORDER_STATUS -- Enum para status de pedido

do $$
begin
  if not exists (select 1 from pg_type where typname = 'order_status') then
    create type public.order_status as enum ('pending','paid','shipped','delivered','cancelled');
  end if;
end$$;

-- =============================================
-- 7) ORDERS -- Tabela de pedidos com status, total_amount e created_at/updated_at

create table if not exists public.orders (
  id           uuid primary key default gen_random_uuid(),
  customer_id  uuid not null references public.customers(id) on delete cascade,
  status       public.order_status not null default 'pending',
  total_amount numeric(12,2) not null default 0.00,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);

drop trigger if exists trg_orders_set_timestamp on public.orders;
create trigger trg_orders_set_timestamp
  before update on public.orders
  for each row
  execute function public.touch_updated_at();

create index if not exists idx_orders_customer_id on public.orders(customer_id);
create index if not exists idx_orders_status      on public.orders(status);
create index if not exists idx_orders_created_at  on public.orders(created_at);

-- =============================================
-- 8) ORDER_ITEMS -- Itens de pedido com quantity, unit_price e total gerado.

create table if not exists public.order_items (
  id           uuid primary key default gen_random_uuid(),
  order_id     uuid not null references public.orders(id)   on delete cascade,
  product_id   uuid not null references public.products(id) on delete restrict,
  quantity     integer not null check (quantity > 0),
  unit_price   numeric(12,2) not null check (unit_price >= 0),
  total_amount numeric(12,2) generated always as (quantity * unit_price) stored,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  constraint unique_order_product unique (order_id, product_id)
);

drop trigger if exists trg_order_items_set_timestamp on public.order_items;
create trigger trg_order_items_set_timestamp
  before update on public.order_items
  for each row
  execute function public.touch_updated_at();

create index if not exists idx_order_items_order_id   on public.order_items(order_id);
create index if not exists idx_order_items_product_id on public.order_items(product_id);

-- =============================================
-- 9) FUNÇÕES & TRIGGER DE CÁLCULO (versões finais)

-- calculate_order_total:
--  - calcula o total do pedido com base em order_items
--  - atualiza orders.total_amount e updated_at
--  - retorna o total calculado
create or replace function public.calculate_order_total(p_order_id uuid)
returns numeric(12,2)
language sql
as $$
  with t as (
    select coalesce(sum(oi.quantity * oi.unit_price), 0)::numeric(12,2) as total
    from public.order_items oi
    where oi.order_id = p_order_id
  )
  update public.orders o
     set total_amount = t.total,
         updated_at   = now()
    from t
   where o.id = p_order_id
  returning t.total;
$$;

-- Trigger function:
--  - dispara após INSERT/UPDATE/DELETE em order_items
--  - identifica o order_id impactado
--  - chama calculate_order_total para manter o total consistente
create or replace function public.recalculate_order_total_func()
returns trigger
language plpgsql
as $$
declare
  v_order_id uuid;
begin
  v_order_id := coalesce(new.order_id, old.order_id);
  perform public.calculate_order_total(v_order_id);

  if tg_op = 'DELETE' then
    return old;
  else
    return new;
  end if;
end;
$$;

drop trigger if exists trg_recalculate_order_total on public.order_items;
create trigger trg_recalculate_order_total
after insert or update or delete on public.order_items
for each row
execute function public.recalculate_order_total_func();

comment on trigger trg_recalculate_order_total on public.order_items
is 'Atualiza automaticamente orders.total_amount quando order_items muda.';

-- =============================================
-- 10) VIEWS (alinhadas com histórico e RLS)

-- View básica: pedidos + dados do cliente
create or replace view public.view_orders_with_customers
with (security_invoker = true) as
select
  o.id                           as order_id,
  o.customer_id,
  c.name                         as customer_name,
  c.email                        as customer_email,
  o.created_at                   as order_created_at,
  to_char(o.created_at, 'DD/MM/YYYY HH24:MI') as order_date_formatted,
  o.status,
  o.total_amount,
  o.updated_at
from public.orders o
join public.customers c on c.id = o.customer_id;

-- View detalhada: pedido + cliente + itens + produto
-- Usa i.total_amount (coluna gerada) para evitar duplicar lógica
create or replace view public.view_orders_detailed
with (security_invoker = true) as
select
  o.id                           as order_id,
  o.customer_id,
  c.name                         as customer_name,
  c.email                        as customer_email,
  o.created_at                   as order_created_at,
  to_char(o.created_at, 'DD/MM/YYYY HH24:MI') as order_date_formatted,
  o.status,
  o.total_amount                 as order_total,

  i.id                           as item_id,
  i.quantity                     as item_quantity,
  i.unit_price                   as item_unit_price,
  i.total_amount                 as item_total,

  p.id                           as product_id,
  p.name                         as product_name,
  p.price                        as product_price,
  p.active                       as product_active
from public.orders o
join public.customers c   on c.id = o.customer_id
join public.order_items i on i.order_id = o.id
join public.products p    on p.id = i.product_id;

-- View de resumo por cliente: total de pedidos, valor total, última compra
create or replace view public.view_orders_summary
with (security_invoker = true) as
select
  c.id                               as customer_id,
  c.name                             as customer_name,
  c.email                            as customer_email,
  count(o.id)                        as total_orders,
  coalesce(sum(o.total_amount), 0)::numeric(12,2) as total_spent,
  max(o.created_at)                  as last_order_date
from public.customers c
left join public.orders o on o.customer_id = c.id
group by c.id, c.name, c.email;
