-- =============================================
-- FUNCTIONS: E-COMMERCE BACKEND (FINAL V3)
-- =============================================

-- 1️⃣ Função: calculate_order_total(p_order_id)
-- Recalcula o valor total do pedido baseado nos itens.
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

comment on function calculate_order_total(uuid)
is 'Recalcula o valor total do pedido com base nos itens vinculados.';

-- =============================================
-- 2️⃣ Função: recalculate_order_total_func()
-- Trigger que chama calculate_order_total automaticamente.
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
is 'Recalcula automaticamente o total do pedido quando itens são criados, atualizados ou deletados.';

-- =============================================
-- 3️⃣ Função: update_order_status(p_order_id, p_status)
-- Atualiza o status de um pedido e retorna o registro atualizado.
create or replace function update_order_status(p_order_id uuid, p_status order_status)
returns orders
language plpgsql
security definer
as $$
declare
  v_order orders;
begin
  if not exists (select 1 from orders where id = p_order_id) then
    raise exception 'Order not found for ID: %', p_order_id;
  end if;

  update orders
  set status = p_status,
      updated_at = now()
  where id = p_order_id
  returning * into v_order;

  return v_order;
end;
$$;

comment on function update_order_status(uuid, order_status)
is 'Atualiza o status de um pedido e retorna o registro atualizado.';

-- =============================================
-- 4️⃣ Função: create_order(p_customer_id, p_status)
-- Cria um novo pedido vazio para um cliente.
create or replace function create_order(p_customer_id uuid, p_status order_status default 'pending')
returns orders
language plpgsql
security definer
as $$
declare
  new_order orders;
begin
  insert into orders (customer_id, status)
  values (p_customer_id, p_status)
  returning * into new_order;

  return new_order;
end;
$$;

comment on function create_order(uuid, order_status)
is 'Cria um novo pedido vinculado a um cliente.';

-- =============================================
-- 5️⃣ Função: create_customer_from_user()
-- Garante sincronização entre a tabela users e customers.
create or replace function create_customer_from_user()
returns trigger
language plpgsql
security definer
as $$
begin
  insert into customers (name, email)
  values (new.name, new.email)
  on conflict (email) do nothing;

  return new;
end;
$$;

drop trigger if exists trg_create_customer_from_user on users;

create trigger trg_create_customer_from_user
after insert on users
for each row
execute procedure create_customer_from_user();

comment on function create_customer_from_user()
is 'Cria automaticamente um registro em customers quando um novo usuário é inserido.';

-- =============================================
-- 6️⃣ Função: verify_user_credentials(email, password)
-- Valida credenciais de login verificando o hash bcrypt.
-- 🔒 Essa função usa a extensão `pgcrypto` para validação de senha.
create or replace function verify_user_credentials(p_email text, p_password text)
returns table (
  user_id uuid,
  user_name text,
  user_email text,
  user_role text
)
language plpgsql
security definer
as $$
declare
  v_user users;
begin
  select * into v_user from users where email = p_email;
  
  if not found then
    raise exception 'Invalid email or password';
  end if;

  -- Validação via função de comparação do hash bcrypt
  if crypt(p_password, v_user.password_hash) <> v_user.password_hash then
    raise exception 'Invalid email or password';
  end if;

  return query
  select v_user.id, v_user.name, v_user.email, v_user.role;
end;
$$;

comment on function verify_user_credentials(text, text)
is 'Valida e retorna dados de um usuário ao confirmar credenciais com bcrypt.';
