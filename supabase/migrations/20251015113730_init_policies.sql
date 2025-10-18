-- =============================================
-- RLS POLICIES: E-COMMERCE BACKEND (REFATORADO)
-- =============================================

-- 1️⃣ Ativa o Row Level Security
alter table users enable row level security;
alter table customers enable row level security;
alter table orders enable row level security;
alter table order_items enable row level security;
alter table products enable row level security;

-- =============================================
-- 2️⃣ USERS
-- =============================================

-- Usuário pode ver e atualizar apenas seus próprios dados
create policy "users_select_own"
  on users
  for select
  using (auth.uid() = id or role = 'admin');

create policy "users_update_own"
  on users
  for update
  using (auth.uid() = id or role = 'admin')
  with check (auth.uid() = id or role = 'admin');

-- Apenas admin pode inserir ou deletar usuários
create policy "admin_insert_users"
  on users for insert
  with check (role = 'admin');

create policy "admin_delete_users"
  on users for delete
  using (role = 'admin');

-- =============================================
-- 3️⃣ CUSTOMERS
-- =============================================

-- Usuário comum vê apenas o seu registro de cliente (por email)
create policy "customers_select_own"
  on customers
  for select
  using (
    exists (
      select 1
      from users u
      where u.id = auth.uid()
      and u.email = customers.email
    )
    or exists (
      select 1 from users u where u.id = auth.uid() and u.role = 'admin'
    )
  );

-- Pode atualizar apenas seus dados
create policy "customers_update_own"
  on customers
  for update
  using (
    exists (
      select 1
      from users u
      where u.id = auth.uid()
      and u.email = customers.email
    )
    or exists (
      select 1 from users u where u.id = auth.uid() and u.role = 'admin'
    )
  )
  with check (
    exists (
      select 1
      from users u
      where u.id = auth.uid()
      and u.email = customers.email
    )
    or exists (
      select 1 from users u where u.id = auth.uid() and u.role = 'admin'
    )
  );

-- Admin pode inserir e deletar clientes
create policy "admin_insert_customers"
  on customers
  for insert
  with check (exists (select 1 from users where id = auth.uid() and role = 'admin'));

create policy "admin_delete_customers"
  on customers
  for delete
  using (exists (select 1 from users where id = auth.uid() and role = 'admin'));

-- =============================================
-- 4️⃣ ORDERS (CORRIGIDO – sem alias)
-- =============================================

-- Ver apenas pedidos associados ao próprio cliente (ou admin)
create policy "orders_select_own"
  on orders
  for select
  using (
    exists (
      select 1
      from customers c
      join users u on c.email = u.email
      where orders.customer_id = c.id
        and u.id = auth.uid()
    )
    or exists (
      select 1 from users where id = auth.uid() and role = 'admin'
    )
  );

-- Inserir pedidos apenas para o próprio cliente (ou admin)
create policy "orders_insert_own"
  on orders
  for insert
  with check (
    exists (
      select 1
      from customers c
      join users u on c.email = u.email
      where c.id = orders.customer_id
        and u.id = auth.uid()
    )
    or exists (
      select 1 from users where id = auth.uid() and role = 'admin'
    )
  );

-- Atualizar apenas pedidos próprios (ou admin)
create policy "orders_update_own"
  on orders
  for update
  using (
    exists (
      select 1
      from customers c
      join users u on c.email = u.email
      where orders.customer_id = c.id
        and u.id = auth.uid()
    )
    or exists (
      select 1 from users where id = auth.uid() and role = 'admin'
    )
  )
  with check (
    exists (
      select 1
      from customers c
      join users u on c.email = u.email
      where orders.customer_id = c.id
        and u.id = auth.uid()
    )
    or exists (
      select 1 from users where id = auth.uid() and role = 'admin'
    )
  );

-- Deletar apenas pedidos próprios (ou admin)
create policy "orders_delete_own"
  on orders
  for delete
  using (
    exists (
      select 1
      from customers c
      join users u on c.email = u.email
      where orders.customer_id = c.id
        and u.id = auth.uid()
    )
    or exists (
      select 1 from users where id = auth.uid() and role = 'admin'
    )
  );

-- =============================================
-- 5️⃣ ORDER ITEMS
-- =============================================

-- Usuário vê apenas itens de pedidos seus
create policy "order_items_select_own"
  on order_items
  for select
  using (
    exists (
      select 1
      from orders o
      join customers c on o.customer_id = c.id
      join users u on c.email = u.email
      where order_items.order_id = o.id
      and u.id = auth.uid()
    )
    or exists (
      select 1 from users where id = auth.uid() and role = 'admin'
    )
  );

-- Inserir, atualizar e deletar apenas itens de pedidos próprios
create policy "order_items_insert_own"
  on order_items
  for insert
  with check (
    exists (
      select 1
      from orders o
      join customers c on o.customer_id = c.id
      join users u on c.email = u.email
      where order_items.order_id = o.id
      and u.id = auth.uid()
    )
    or exists (
      select 1 from users where id = auth.uid() and role = 'admin'
    )
  );

create policy "order_items_update_own"
  on order_items
  for update
  using (
    exists (
      select 1
      from orders o
      join customers c on o.customer_id = c.id
      join users u on c.email = u.email
      where order_items.order_id = o.id
      and u.id = auth.uid()
    )
    or exists (
      select 1 from users where id = auth.uid() and role = 'admin'
    )
  )
  with check (
    exists (
      select 1
      from orders o
      join customers c on o.customer_id = c.id
      join users u on c.email = u.email
      where order_items.order_id = o.id
      and u.id = auth.uid()
    )
    or exists (
      select 1 from users where id = auth.uid() and role = 'admin'
    )
  );

create policy "order_items_delete_own"
  on order_items
  for delete
  using (
    exists (
      select 1
      from orders o
      join customers c on o.customer_id = c.id
      join users u on c.email = u.email
      where order_items.order_id = o.id
      and u.id = auth.uid()
    )
    or exists (
      select 1 from users where id = auth.uid() and role = 'admin'
    )
  );

-- =============================================
-- 6️⃣ PRODUCTS
-- =============================================

-- Produtos são públicos para leitura
create policy "products_select_public"
  on products
  for select
  using (true);

-- Apenas admin pode gerenciar produtos
create policy "admin_manage_products"
  on products
  for all
  using (exists (select 1 from users where id = auth.uid() and role = 'admin'))
  with check (exists (select 1 from users where id = auth.uid() and role = 'admin'));

grant select on products to anon;
grant select on products to authenticated;
