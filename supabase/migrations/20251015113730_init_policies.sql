-- =============================================
-- RLS POLICIES: E-COMMERCE BACKEND (VERSÃO SIMPLIFICADA P/ TESTE JR)
-- Pré-condições:
--   - customers.user_id uuid not null unique references auth.users(id)
--   - orders.customer_id -> customers.id
--   - order_items.order_id -> orders.id
-- =============================================

-- 1) Ativa RLS nas tabelas de negócio
alter table public.customers    enable row level security;
alter table public.orders       enable row level security;
alter table public.order_items  enable row level security;
alter table public.products     enable row level security;

-- Opcional em produção (mais rígido):
-- alter table public.customers    force row level security;
-- alter table public.orders       force row level security;
-- alter table public.order_items  force row level security;
-- alter table public.products     force row level security;

-- =============================================
-- 2) CUSTOMERS
-- Regra: cada usuário só enxerga / altera o próprio customer.
-- Inserts: só pode criar registro com user_id = auth.uid().
-- =============================================

drop policy if exists customers_select_own on public.customers;
drop policy if exists customers_insert_own on public.customers;
drop policy if exists customers_update_own on public.customers;
drop policy if exists customers_delete_own on public.customers;

create policy customers_select_own
  on public.customers
  for select
  using ( user_id = auth.uid() );

create policy customers_insert_own
  on public.customers
  for insert
  with check ( user_id = auth.uid() );

create policy customers_update_own
  on public.customers
  for update
  using ( user_id = auth.uid() )
  with check ( user_id = auth.uid() );

create policy customers_delete_own
  on public.customers
  for delete
  using ( user_id = auth.uid() );

-- =============================================
-- 3) ORDERS
-- Regra: o usuário só acessa pedidos vinculados ao seu customer.
-- =============================================

drop policy if exists orders_select_own on public.orders;
drop policy if exists orders_insert_own on public.orders;
drop policy if exists orders_update_own on public.orders;
drop policy if exists orders_delete_own on public.orders;

create policy orders_select_own
  on public.orders
  for select
  using (
    customer_id in (
      select id
      from public.customers
      where user_id = auth.uid()
    )
  );

create policy orders_insert_own
  on public.orders
  for insert
  with check (
    customer_id in (
      select id
      from public.customers
      where user_id = auth.uid()
    )
  );

create policy orders_update_own
  on public.orders
  for update
  using (
    customer_id in (
      select id
      from public.customers
      where user_id = auth.uid()
    )
  )
  with check (
    customer_id in (
      select id
      from public.customers
      where user_id = auth.uid()
    )
  );

create policy orders_delete_own
  on public.orders
  for delete
  using (
    customer_id in (
      select id
      from public.customers
      where user_id = auth.uid()
    )
  );

-- =============================================
-- 4) ORDER_ITEMS
-- Regra: herda a "propriedade" do pedido.
-- Só acessa itens de pedidos que pertencem ao seu customer.
-- =============================================

drop policy if exists order_items_select_own on public.order_items;
drop policy if exists order_items_insert_own on public.order_items;
drop policy if exists order_items_update_own on public.order_items;
drop policy if exists order_items_delete_own on public.order_items;

create policy order_items_select_own
  on public.order_items
  for select
  using (
    order_id in (
      select o.id
      from public.orders o
      join public.customers c on c.id = o.customer_id
      where c.user_id = auth.uid()
    )
  );

create policy order_items_insert_own
  on public.order_items
  for insert
  with check (
    order_id in (
      select o.id
      from public.orders o
      join public.customers c on c.id = o.customer_id
      where c.user_id = auth.uid()
    )
  );

create policy order_items_update_own
  on public.order_items
  for update
  using (
    order_id in (
      select o.id
      from public.orders o
      join public.customers c on c.id = o.customer_id
      where c.user_id = auth.uid()
    )
  )
  with check (
    order_id in (
      select o.id
      from public.orders o
      join public.customers c on c.id = o.customer_id
      where c.user_id = auth.uid()
    )
  );

create policy order_items_delete_own
  on public.order_items
  for delete
  using (
    order_id in (
      select o.id
      from public.orders o
      join public.customers c on c.id = o.customer_id
      where c.user_id = auth.uid()
    )
  );

-- =============================================
-- 5) PRODUCTS
-- Regra:
--   - SELECT liberado (anon + authenticated) -> catálogo público.
--   - Sem políticas de INSERT/UPDATE/DELETE:
--       só o service_role (banco / backend com chave secreta) gerencia.
-- =============================================

drop policy if exists products_select_public on public.products;

create policy products_select_public
  on public.products
  for select
  using ( true );

-- Permissões de tabela (RLS ainda se aplica)
grant usage on schema public to anon, authenticated;
grant select on public.products to anon, authenticated;