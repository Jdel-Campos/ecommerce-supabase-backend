-- =============================================
-- VIEWS: E-COMMERCE BACKEND (REV V3)
-- =============================================

-- 1) view_orders_with_customers
drop view if exists public.view_orders_with_customers;
create view public.view_orders_with_customers
with (security_invoker = true) as
select
  o.id as order_id,
  o.customer_id,
  c.name as customer_name,
  c.email as customer_email,
  o.created_at as order_created_at,
  to_char(o.created_at, 'DD/MM/YYYY HH24:MI') as order_date_formatted,
  o.status,
  o.total_amount,
  o.created_at,
  o.updated_at
from public.orders o
join public.customers c on c.id = o.customer_id;

comment on view public.view_orders_with_customers is
'Requests with basic customer data (quick for dashboards).';

-- 2) view_orders_detailed (without filtering p.active to keep history)
drop view if exists public.view_orders_detailed;
create view public.view_orders_detailed
with (security_invoker = true) as
select
  o.id as order_id,
  o.customer_id,
  c.name as customer_name,
  c.email as customer_email,
  o.created_at as order_created_at,
  to_char(o.created_at, 'DD/MM/YYYY HH24:MI') as order_date_formatted,
  o.status,
  o.total_amount  as order_total,
  i.id as item_id,
  i.quantity as item_quantity,
  i.unit_price as item_unit_price,
  (i.quantity * i.unit_price)::numeric(12,2) as item_total,
  p.id as product_id,
  p.name as product_name,
  p.price as product_price,
  p.active as product_active
from public.orders o
join public.customers c on c.id = o.customer_id
join public.order_items i on i.order_id = o.id
join public.products p on p.id = i.product_id;

comment on view public.view_orders_detailed is
'Requests with customer details, items and products (without hiding inactive products for history).';

-- 3) view_orders_summary (summary by customer)
drop view if exists public.view_orders_summary;
create view public.view_orders_summary
with (security_invoker = true) as
select
  c.id as customer_id,
  c.name as customer_name,
  c.email as customer_email,
  count(o.id) as total_orders,
  coalesce(sum(o.total_amount), 0)::numeric(12,2) as total_spent,
  max(o.created_at) as last_order_date
from public.customers c
left join public.orders o on o.customer_id = c.id
group by c.id, c.name, c.email;

comment on view public.view_orders_summary is
'Summary of orders and total spent by customer.';

-- 4) view_sales_by_product (aggregation by product)
drop view if exists public.view_sales_by_product;
create view public.view_sales_by_product
with (security_invoker = true) as
select
  p.id as product_id,
  p.name as product_name,
  count(i.id) as total_items_rows,
  coalesce(sum(i.quantity), 0) as total_units,
  coalesce(sum(i.quantity * i.unit_price), 0)::numeric(12,2) as total_revenue,
  p.price,
  p.active,
  max(o.created_at) as last_sale_date
from public.products p
left join public.order_items i on p.id = i.product_id
left join public.orders o on o.id = i.order_id
group by p.id, p.name, p.price, p.active;

comment on view public.view_sales_by_product is
'Aggregated sales statistics by product (units and revenue).';

-- =============================================
-- INDICES (help joins and common filters)
create index if not exists idx_orders_status              on public.orders(status);
create index if not exists idx_orders_created_at          on public.orders(created_at);
create index if not exists idx_orders_customer_id         on public.orders(customer_id);
create index if not exists idx_order_items_order_id       on public.order_items(order_id);
create index if not exists idx_order_items_product_id     on public.order_items(product_id);
create index if not exists idx_products_active            on public.products(active);
create index if not exists idx_customers_email            on public.customers(email);

-- =============================================
-- GRANTS (exposed for authenticated via PostgREST)
grant select on public.view_orders_with_customers to authenticated;
grant select on public.view_orders_detailed      to authenticated;
grant select on public.view_orders_summary       to authenticated;
grant select on public.view_sales_by_product     to authenticated;
