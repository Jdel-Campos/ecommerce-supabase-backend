-- =============================================
-- SEED DATA: E-COMMERCE BACKEND (COMPATÍVEL COM SUPABASE AUTH)
-- =============================================

-- 🔄 Limpa dados anteriores
truncate table order_items cascade;
truncate table orders cascade;
truncate table products cascade;
truncate table customers cascade;
truncate table users cascade;

-- =============================================
-- 1️⃣ USERS (Admin + Clientes)
-- ⚙️ ID será o mesmo do Supabase Auth (use o mesmo UUID da tabela auth.users)
-- Você pode substituir pelos reais depois com:
-- select id, email from auth.users;
insert into auth.users (id, email, encrypted_password, email_confirmed_at)
values
  ('00000000-0000-0000-0000-000000000001', 'admin@exemplo.com', crypt('admin_secure_password', gen_salt('bf')), now()),
  ('00000000-0000-0000-0000-000000000002', 'alice@example.com', crypt('user_secure_password', gen_salt('bf')), now()),
  ('00000000-0000-0000-0000-000000000003', 'bob@example.com', crypt('user_secure_password', gen_salt('bf')), now()),
  ('00000000-0000-0000-0000-000000000004', 'charlie@example.com', crypt('user_secure_password', gen_salt('bf')), now())
on conflict (id) do nothing;

-- =============================================
-- 2️⃣ CUSTOMERS (vinculados ao email dos usuários)
insert into customers (name, email, phone, address)
values 
  ('Alice Doe', 'alice@example.com', '1111111111', '123 Main St'),
  ('Bob Smith', 'bob@example.com', '2222222222', '456 High St'),
  ('Charlie Brown', 'charlie@example.com', '3333333333', '789 Park Ave')
on conflict (email) do nothing;

-- =============================================
-- 3️⃣ PRODUCTS
insert into products (name, description, price, stock)
values
  ('Laptop', '15-inch laptop', 3500.00, 5),
  ('Mouse', 'Wireless mouse', 150.00, 50),
  ('Keyboard', 'Mechanical keyboard', 200.00, 20),
  ('Monitor', '27-inch 4K display', 1200.00, 10),
  ('Headset', 'Noise cancelling headset', 350.00, 15)
on conflict (name) do nothing;

-- =============================================
-- 4️⃣ ORDERS (vinculados aos customers)
insert into orders (customer_id, total_amount, status)
select id, 0, 'pending'::order_status from customers
on conflict do nothing;

-- =============================================
-- 5️⃣ ORDER ITEMS
-- Alice: Laptop + 2x Mouse
insert into order_items (order_id, product_id, quantity, unit_price)
select o.id, p.id, 1, p.price
from orders o
join customers c on o.customer_id = c.id
join products p on p.name = 'Laptop'
where c.email = 'alice@example.com';

insert into order_items (order_id, product_id, quantity, unit_price)
select o.id, p.id, 2, p.price
from orders o
join customers c on o.customer_id = c.id
join products p on p.name = 'Mouse'
where c.email = 'alice@example.com';

-- Bob: Keyboard + Monitor
insert into order_items (order_id, product_id, quantity, unit_price)
select o.id, p.id, 1, p.price
from orders o
join customers c on o.customer_id = c.id
join products p on p.name = 'Keyboard'
where c.email = 'bob@example.com';

insert into order_items (order_id, product_id, quantity, unit_price)
select o.id, p.id, 1, p.price
from orders o
join customers c on o.customer_id = c.id
join products p on p.name = 'Monitor'
where c.email = 'bob@example.com';

-- Charlie: 3x Headset
insert into order_items (order_id, product_id, quantity, unit_price)
select o.id, p.id, 3, p.price
from orders o
join customers c on o.customer_id = c.id
join products p on p.name = 'Headset'
where c.email = 'charlie@example.com';

-- =============================================
-- 6️⃣ Atualiza totais e status
update orders
set total_amount = (
  select sum(quantity * unit_price)
  from order_items
  where order_items.order_id = orders.id
);

update orders
set status = case
  when customer_id = (select id from customers where email = 'alice@example.com') then 'paid'::order_status
  when customer_id = (select id from customers where email = 'bob@example.com') then 'shipped'::order_status
  else 'pending'::order_status
end;
