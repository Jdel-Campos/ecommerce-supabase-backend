-- =============================================
-- SEED DATA: E-COMMERCE BACKEND (SUPABASE-FRIENDLY)
-- customers.user_id referencia auth.users.id (1–1 por usuário)
-- Pré-requisito: usuários alice, bob, charlie já criados em auth.users
-- =============================================

BEGIN;

-- Limpeza (ordem importa por FK)
TRUNCATE TABLE public.order_items CASCADE;
TRUNCATE TABLE public.orders      CASCADE;
TRUNCATE TABLE public.products    CASCADE;
TRUNCATE TABLE public.customers   CASCADE;

-- =============================================
-- 1) CUSTOMERS (1–1 com auth.users)
-- Cria perfis para usuários que já existem em auth.users.
-- customers.id é gerado (gen_random_uuid); o vínculo é via user_id.
INSERT INTO public.customers (user_id, name, email, phone, address)
SELECT au.id, 'Alice Doe', lower(au.email), '1111111111', '123 Main St'
FROM auth.users au
WHERE au.email = 'alice@example.com';

INSERT INTO public.customers (user_id, name, email, phone, address)
SELECT au.id, 'Bob Smith', lower(au.email), '2222222222', '456 High St'
FROM auth.users au
WHERE au.email = 'bob@example.com';

INSERT INTO public.customers (user_id, name, email, phone, address)
SELECT au.id, 'Charlie Brown', lower(au.email), '3333333333', '789 Park Ave'
FROM auth.users au
WHERE au.email = 'charlie@example.com';

-- =============================================
-- 2) PRODUCTS
-- Catálogo inicial de produtos.
INSERT INTO public.products (name, description, price, stock, active)
VALUES
  ('Laptop',   '15-inch laptop',        3500.00,  5,  true),
  ('Mouse',    'Wireless mouse',         150.00, 50,  true),
  ('Keyboard', 'Mechanical keyboard',    200.00, 20,  true),
  ('Monitor',  '27-inch 4K display',    1200.00, 10,  true),
  ('Headset',  'Noise cancelling',       350.00, 15,  true);

-- Como usamos TRUNCATE acima, não precisamos de ON CONFLICT aqui.

-- =============================================
-- 3) ORDERS (um pedido por cliente para o seed)
-- total_amount começa 0; a trigger em order_items vai recalcular depois.
INSERT INTO public.orders (customer_id, order_date, total_amount, status)
SELECT c.id, now(), 0, 'pending'::order_status
FROM public.customers c;

-- =============================================
-- 4) ORDER ITEMS
-- CTEs para mapear pedidos por cliente e produto/preço
WITH oc AS (
  SELECT o.id AS order_id, c.email
  FROM public.orders o
  JOIN public.customers c ON c.id = o.customer_id
),
pp AS (
  SELECT id, name, price FROM public.products
)
INSERT INTO public.order_items (order_id, product_id, quantity, unit_price)
-- Alice: 1x Laptop + 2x Mouse
SELECT oc.order_id, pp.id, 1, pp.price
FROM oc JOIN pp ON pp.name = 'Laptop'
WHERE oc.email = 'alice@example.com'
UNION ALL
SELECT oc.order_id, pp.id, 2, pp.price
FROM oc JOIN pp ON pp.name = 'Mouse'
WHERE oc.email = 'alice@example.com'
UNION ALL
-- Bob: 1x Keyboard + 1x Monitor
SELECT oc.order_id, pp.id, 1, pp.price
FROM oc JOIN pp ON pp.name = 'Keyboard'
WHERE oc.email = 'bob@example.com'
UNION ALL
SELECT oc.order_id, pp.id, 1, pp.price
FROM oc JOIN pp ON pp.name = 'Monitor'
WHERE oc.email = 'bob@example.com'
UNION ALL
-- Charlie: 3x Headset
SELECT oc.order_id, pp.id, 3, pp.price
FROM oc JOIN pp ON pp.name = 'Headset'
WHERE oc.email = 'charlie@example.com';

-- A partir daqui, como temos trigger em order_items,
-- cada INSERT já dispara o recálculo de orders.total_amount.

-- =============================================
-- 5) Status de exemplo (muda o estado de alguns pedidos)
UPDATE public.orders o
SET status = CASE
  WHEN o.customer_id = (SELECT id FROM public.customers WHERE email = 'alice@example.com')  THEN 'paid'::order_status
  WHEN o.customer_id = (SELECT id FROM public.customers WHERE email = 'bob@example.com')    THEN 'shipped'::order_status
  ELSE 'pending'::order_status
END;

-- =============================================
-- 6) Baixa de estoque com base nos itens vendidos
UPDATE public.products p
SET stock = p.stock - COALESCE(s.sold, 0)
FROM (
  SELECT product_id, SUM(quantity) AS sold
  FROM public.order_items
  GROUP BY product_id
) s
WHERE s.product_id = p.id;

COMMIT;