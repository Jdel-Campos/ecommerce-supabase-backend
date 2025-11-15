-- =============================================
-- FUNCTIONS: E-COMMERCE BACKEND (REV V3)
-- =============================================

-- Convenção: funções expostas como RPC ficam no schema public.
-- Em funções SECURITY DEFINER, fixamos search_path.
-- Em RPCs, preferimos SECURITY INVOKER (default), com checagem de ownership.

-- 1) Recalcula total do pedido e retorna o novo total
create or replace function public.calculate_order_total(p_order_id uuid)
returns numeric
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

comment on function public.calculate_order_total(uuid)
is 'Recalcula e retorna o total do pedido com base em order_items.';

-- 2) Trigger para recalcular automaticamente
create or replace function public.recalculate_order_total_func()
returns trigger
language plpgsql
as $$
declare
  v_order_id uuid;
begin
  v_order_id := coalesce(new.order_id, old.order_id);
  perform public.calculate_order_total(v_order_id);
  -- AFTER trigger: valor retornado é ignorado, mas retornamos NEW para insert/update e OLD para delete por clareza
  if (tg_op = 'DELETE') then
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
is 'Recalcula o total do pedido quando itens são criados/atualizados/deletados.';

-- 3) Atualiza o status do pedido (checa ownership via auth.uid())
--    RPC segura: só permite alterar pedidos do próprio usuário, a menos que role seja 'service'/'admin'
create or replace function public.update_order_status(p_order_id uuid, p_status public.order_status)
returns public.orders
language plpgsql
as $$
declare
  v_order public.orders;
  v_is_admin boolean := false;
begin
  -- Exemplo simples de elevação: se quiser permitir o service_role/admin ignorar a checagem
  -- Você pode trocar por uma flag vinda de public.users.role = 'admin'
  select exists (
    select 1
    from public.users u
    where u.id = auth.uid() and u.role in ('admin', 'manager')
  ) into v_is_admin;

  -- Checagem de ownership (RLS defensiva por aplicação)
  if not v_is_admin then
    perform 1
    from public.orders o
    join public.customers c on c.id = o.customer_id
    where o.id = p_order_id
      and c.user_id = auth.uid();

    if not found then
      raise exception 'Pedido não pertence ao usuário autenticado.' using errcode = '42501';
    end if;
  end if;

  -- (Opcional) validação de transição
  -- Exemplo: só permitir paid -> shipped, pending -> paid, etc.
  -- Remova ou ajuste conforme seu workflow
  -- perform 1 from unnest(ARRAY['pending','paid','shipped','cancelled']::public.order_status[]) s(x) where s.x = p_status;
  -- if not found then raise exception 'Status inválido: %', p_status; end if;

  update public.orders
     set status = p_status,
         updated_at = now()
   where id = p_order_id
  returning * into v_order;

  if not found then
    raise exception 'Order not found for ID: %', p_order_id using errcode = 'P0002';
  end if;

  return v_order;
end;
$$;

comment on function public.update_order_status(uuid, public.order_status)
is 'Atualiza o status de um pedido do usuário atual (ou admin) e retorna o registro.';

-- 4) Cria pedido para o usuário autenticado (sem permitir spoof de customer)
create or replace function public.create_order(p_status public.order_status default 'pending')
returns public.orders
language plpgsql
as $$
declare
  v_customer_id uuid;
  v_order public.orders;
begin
  select c.id into v_customer_id
  from public.customers c
  where c.user_id = auth.uid();

  if v_customer_id is null then
    raise exception 'Cliente não encontrado para o usuário atual.' using errcode = 'P0002';
  end if;

  insert into public.orders (customer_id, status)
  values (v_customer_id, p_status)
  returning * into v_order;

  return v_order;
end;
$$;

comment on function public.create_order(public.order_status)
is 'Cria um novo pedido vinculado ao cliente do usuário autenticado.';

-- 5) Trigger: cria customers quando surgir novo public.users
--    Garante o vínculo por user_id
create or replace function public.create_customer_from_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.customers (user_id, name, email)
  values (new.id, new.name, new.email)
  on conflict (user_id) do nothing; -- requer UNIQUE(user_id) em customers

  return new;
end;
$$;

-- Higiene: privilégios (evita que qualquer um execute funções definidoras)
revoke all on function public.create_customer_from_user() from public;
grant execute on function public.create_customer_from_user() to authenticated;

drop trigger if exists trg_create_customer_from_user on public.users;

create trigger trg_create_customer_from_user
after insert on public.users
for each row
execute function public.create_customer_from_user();

comment on function public.create_customer_from_user()
is 'Cria automaticamente customers ao inserir em public.users (vincula por user_id).';

-- 6) REMOVIDO: verify_user_credentials (não usar, Auth é do GoTrue)
--    Em vez disso, se precisar de dados do usuário atual numa RPC:
create or replace function public.get_current_user_profile()
returns table (
  id uuid,
  email text,
  role text,
  name text
)
language sql
stable
as $$
  select u.id, u.email, u.role, u.name
  from public.users u
  where u.id = auth.uid()
$$;

comment on function public.get_current_user_profile()
is 'Retorna o perfil (public.users) do usuário autenticado.';
