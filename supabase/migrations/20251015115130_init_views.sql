-- =============================================
-- VIEWS: E-COMMERCE BACKEND (FINAL V3)
-- =============================================

-- 1️⃣ VIEW: view_orders_with_customers
-- Mostra pedidos junto com dados básicos dos clientes.
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

comment on view view_orders_with_customers is
'Mostra os pedidos com informações básicas dos clientes (usado para consultas rápidas e dashboards).';

-- =============================================
-- 2️⃣ VIEW: view_orders_detailed
-- Exibe os pedidos com informações detalhadas dos itens e produtos.
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
    p.price as product_price,
    p.active as product_active
from orders o
join customers c on c.id = o.customer_id
join order_items i on i.order_id = o.id
join products p on p.id = i.product_id
where p.active = true;

comment on view view_orders_detailed is
'Exibe pedidos com detalhes completos de cliente, itens e produtos.';

-- =============================================
-- 3️⃣ VIEW: view_orders_summary
-- Exibe resumo de pedidos e gastos por cliente.
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

comment on view view_orders_summary is
'Exibe o resumo total de pedidos e valores gastos por cliente.';

-- =============================================
-- 4️⃣ VIEW: view_sales_by_product
-- Nova view opcional: mostra volume e receita por produto.
create or replace view view_sales_by_product
with (security_invoker = true) as
select
    p.id as product_id,
    p.name as product_name,
    count(i.id) as total_items_sold,
    coalesce(sum(i.quantity), 0) as total_units,
    coalesce(sum(i.total_amount), 0)::numeric(10,2) as total_revenue,
    p.price,
    p.active,
    max(o.created_at) as last_sale_date
from products p
left join order_items i on p.id = i.product_id
left join orders o on o.id = i.order_id
group by p.id, p.name, p.price, p.active;

comment on view view_sales_by_product is
'Mostra estatísticas agregadas de vendas por produto.';

-- =============================================
-- 5️⃣ ÍNDICES (melhoram desempenho de consultas nas views)
create index if not exists idx_orders_status on orders(status);
create index if not exists idx_orders_date on orders(order_date);
create index if not exists idx_products_active on products(active);
