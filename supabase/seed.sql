-- =============================================
-- SEED DATA: E-COMMERCE BACKEND (SUPABASE-FRIENDLY)
-- DO NOT ALTER auth.users. Use real UUIDs below.
-- =============================================

BEGIN;

-- Cleaning with reset of IDs
TRUNCATE TABLE order_items RESTART IDENTITY CASCADE;
TRUNCATE TABLE orders RESTART IDENTITY CASCADE;
TRUNCATE TABLE products RESTART IDENTITY CASCADE;
TRUNCATE TABLE customers RESTART IDENTITY CASCADE;

-- =============================================
-- 1) CUSTOMERS (linked to auth.users by user_id)
-- Only insert customers for users that exist in auth.users
INSERT INTO customers (user_id, name, email, phone, address)
SELECT au.id, 'Alice Doe', 'alice@example.com', '1111111111', '123 Main St'
FROM auth.users au
WHERE au.email = 'alice@example.com'
ON CONFLICT (email) DO NOTHING;

INSERT INTO customers (user_id, name, email, phone, address)
SELECT au.id, 'Bob Smith', 'bob@example.com', '2222222222', '456 High St'
FROM auth.users au
WHERE au.email = 'bob@example.com'
ON CONFLICT (email) DO NOTHING;

INSERT INTO customers (user_id, name, email, phone, address)
SELECT au.id, 'Charlie Brown', 'charlie@example.com', '3333333333', '789 Park Ave'
FROM auth.users au
WHERE au.email = 'charlie@example.com'
ON CONFLICT (email) DO NOTHING;

-- =============================================
-- 2) PRODUCTS
-- Guarantee unique(name) and/or unique(sku)
INSERT INTO products (name, description, price, stock, sku)
VALUES
  ('Laptop',  '15-inch laptop',      3500.00,  5,  'LAP-15'),
  ('Mouse',   'Wireless mouse',       150.00, 50,  'MOU-WLS'),
  ('Keyboard','Mechanical keyboard',  200.00, 20,  'KEY-MEC'),
  ('Monitor', '27-inch 4K display',  1200.00, 10,  'MON-27-4K'),
  ('Headset', 'Noise cancelling',     350.00, 15,  'HDS-NC')
ON CONFLICT (name) DO NOTHING;

-- =============================================
-- 3) ORDERS (one order per customer)
INSERT INTO orders (customer_id, total_amount, status)
SELECT c.id, 0, 'pending'::order_status
FROM customers c
ON CONFLICT DO NOTHING;

-- =============================================
-- 4) ORDER ITEMS
-- Helper CTE to get (order_id by customer) and (product_id by name)
WITH
  oc AS (
    SELECT o.id AS order_id, c.email
    FROM orders o
    JOIN customers c ON c.id = o.customer_id
  ),
  p AS (
    SELECT id, name FROM products
  )
-- All order items in one statement
INSERT INTO order_items (order_id, product_id, quantity, unit_price)
-- Alice: Laptop (1) + Mouses (2)
SELECT oc.order_id, p.id, 1, p2.price
FROM oc
JOIN p ON p.name = 'Laptop'
JOIN products p2 ON p2.id = p.id
WHERE oc.email = 'alice@example.com'
UNION ALL
SELECT oc.order_id, p.id, 2, p2.price
FROM oc
JOIN p ON p.name = 'Mouse'
JOIN products p2 ON p2.id = p.id
WHERE oc.email = 'alice@example.com'
UNION ALL
-- Bob: Keyboard (1) + Monitors (1)
SELECT oc.order_id, p.id, 1, p2.price
FROM oc
JOIN p ON p.name = 'Keyboard'
JOIN products p2 ON p2.id = p.id
WHERE oc.email = 'bob@example.com'
UNION ALL
SELECT oc.order_id, p.id, 1, p2.price
FROM oc
JOIN p ON p.name = 'Monitor'
JOIN products p2 ON p2.id = p.id
WHERE oc.email = 'bob@example.com'
UNION ALL
-- Charlie: Headsets (3)
SELECT oc.order_id, p.id, 3, p2.price
FROM oc
JOIN p ON p.name = 'Headset'
JOIN products p2 ON p2.id = p.id
WHERE oc.email = 'charlie@example.com';

-- =============================================
-- 5) Update totals
UPDATE orders o
SET total_amount = t.total
FROM (
  SELECT order_id, SUM(quantity * unit_price)::numeric AS total
  FROM order_items
  GROUP BY order_id
) t
WHERE t.order_id = o.id;

-- =============================================
-- 6) Update status (example)
UPDATE orders o
SET status = CASE
  WHEN o.customer_id = (SELECT id FROM customers WHERE email = 'alice@example.com')  THEN 'paid'::order_status
  WHEN o.customer_id = (SELECT id FROM customers WHERE email = 'bob@example.com')    THEN 'shipped'::order_status
  ELSE 'pending'::order_status
END;

-- =============================================
-- 7) Reduce stock based on the items of the order
UPDATE products p
SET stock = p.stock - COALESCE(s.sold, 0)
FROM (
  SELECT product_id, SUM(quantity) AS sold
  FROM order_items
  GROUP BY product_id
) s
WHERE s.product_id = p.id;

COMMIT;
