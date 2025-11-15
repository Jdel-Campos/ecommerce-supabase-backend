-- =============================================
-- RLS POLICIES: E-COMMERCE BACKEND (REV)
-- Pré-condições:
--   - customers.user_id uuid not null references auth.users(id) UNIQUE
--   - public.users (id = auth.users.id), coluna role com 'admin' quando aplicável
-- =============================================

-- Helper: checa se o ator é admin
create or replace function public.is_admin(p_uid uuid)
returns boolean
language sql
stable
as $$
  select exists (
    select 1 from public.users u
    where u.id = p_uid and u.role = 'admin'
  );
$$;

-- 1) Ativa RLS (opcional: FORCE para endurecer)
alter table public.users        enable row level security;
alter table public.customers    enable row level security;
alter table public.orders       enable row level security;
alter table public.order_items  enable row level security;
alter table public.products     enable row level security;

-- Opcional (recomendado em produção):
-- alter table public.users        force row level security;
-- alter table public.customers    force row level security;
-- alter table public.orders       force row level security;
-- alter table public.order_items  force row level security;
-- alter table public.products     force row level security;

-- =============================================
-- 2) USERS  (perfil da aplicação, não auth.users)
-- O usuário vê/edita somente o próprio registro; admin vê/edita todos.
-- Inserts/Deletes apenas por admin (na prática, crie via Admin API e sincronize).
-- =============================================

drop policy if exists users_select_own  on public.users;
drop policy if exists users_update_own  on public.users;
drop policy if exists admin_insert_users on public.users;
drop policy if exists admin_delete_users on public.users;

create policy users_select_own
  on public.users
  for select
  using ( id = auth.uid() or public.is_admin(auth.uid()) );

create policy users_update_own
  on public.users
  for update
  using ( id = auth.uid() or public.is_admin(auth.uid()) )
  with check ( id = auth.uid() or public.is_admin(auth.uid()) );

create policy admin_insert_users
  on public.users
  for insert
  with check ( public.is_admin(auth.uid()) );

create policy admin_delete_users
  on public.users
  for delete
  using ( public.is_admin(auth.uid()) );

-- =============================================
-- 3) CUSTOMERS
-- Dono (via customers.user_id) vê/edita o próprio registro; admin tudo.
-- =============================================

drop policy if exists customers_select_own on public.customers;
drop policy if exists customers_update_own on public.customers;
drop policy if exists admin_insert_customers on public.customers;
drop policy if exists admin_delete_customers on public.customers;

create policy customers_select_own
  on public.customers
  for select
  using ( user_id = auth.uid() or public.is_admin(auth.uid()) );

create policy customers_update_own
  on public.customers
  for update
  using ( user_id = auth.uid() or public.is_admin(auth.uid()) )
  with check ( user_id = auth.uid() or public.is_admin(auth.uid()) );

create policy admin_insert_customers
  on public.customers
  for insert
  with check ( public.is_admin(auth.uid()) );

create policy admin_delete_customers
  on public.customers
  for delete
  using ( public.is_admin(auth.uid()) );

-- =============================================
-- 4) ORDERS
-- Pertencem ao customer do usuário; admin tem acesso total.
-- =============================================

drop policy if exists orders_select_own on public.orders;
drop policy if exists orders_insert_own on public.orders;
drop policy if exists orders_update_own on public.orders;
drop policy if exists orders_delete_own on public.orders;

create policy orders_select_own
  on public.orders
  for select
  using (
    customer_id in (select id from public.customers where user_id = auth.uid())
    or public.is_admin(auth.uid())
  );

create policy orders_insert_own
  on public.orders
  for insert
  with check (
    customer_id in (select id from public.customers where user_id = auth.uid())
    or public.is_admin(auth.uid())
  );

create policy orders_update_own
  on public.orders
  for update
  using (
    customer_id in (select id from public.customers where user_id = auth.uid())
    or public.is_admin(auth.uid())
  )
  with check (
    customer_id in (select id from public.customers where user_id = auth.uid())
    or public.is_admin(auth.uid())
  );

create policy orders_delete_own
  on public.orders
  for delete
  using (
    customer_id in (select id from public.customers where user_id = auth.uid())
    or public.is_admin(auth.uid())
  );

-- =============================================
-- 5) ORDER ITEMS
-- Herdam o ownership do pedido; admin tem acesso total.
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
    or public.is_admin(auth.uid())
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
    or public.is_admin(auth.uid())
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
    or public.is_admin(auth.uid())
  )
  with check (
    order_id in (
      select o.id
      from public.orders o
      join public.customers c on c.id = o.customer_id
      where c.user_id = auth.uid()
    )
    or public.is_admin(auth.uid())
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
    or public.is_admin(auth.uid())
  );

-- =============================================
-- 6) PRODUCTS
-- Leitura pública (anon + authenticated); apenas admin gerencia.
-- =============================================

drop policy if exists products_select_public on public.products;
drop policy if exists admin_manage_products on public.products;

create policy products_select_public
  on public.products
  for select
  using ( true );

create policy admin_manage_products
  on public.products
  for all
  using ( public.is_admin(auth.uid()) )
  with check ( public.is_admin(auth.uid()) );

-- Permissões de tabela (RLS ainda se aplica)
grant usage on schema public to anon, authenticated;
grant select on public.products to anon, authenticated;
