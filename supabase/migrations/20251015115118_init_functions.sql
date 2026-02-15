-- =============================================
-- FUNCTIONS: E-COMMERCE BACKEND (VERSÃO ENXUTA P/ TESTE JR)
-- =============================================

-- Convenção:
-- - Funções expostas como RPC ficam no schema public.
-- - Usamos SECURITY INVOKER (default), deixando RLS fazer o trabalho de segurança.
-- - Onde fizer sentido, reforçamos ownership via customers.user_id = auth.uid().

-- 1) Recalcula total do pedido e retorna o novo total
create or replace function public.calculate_order_total(p_order_id uuid)
returns numeric(12,2)
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

-- 2) Trigger: recalcula automaticamente após mudanças em order_items
create or replace function public.recalculate_order_total_func()
returns trigger
language plpgsql
as $$
declare
  v_order_id uuid;
begin
  v_order_id := coalesce(new.order_id, old.order_id);
  perform public.calculate_order_total(v_order_id);

  -- AFTER trigger: retorno é ignorado, mas mantemos NEW/OLD por clareza
  if tg_op = 'DELETE' then
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

-- 3) Atualiza o status do pedido (com checagem simples de ownership)
--    Regra: só pode alterar pedidos vinculados ao cliente do auth.uid().
--    RLS já protege, mas reforçamos a regra na função para clareza.
create or replace function public.update_order_status(
  p_order_id uuid,
  p_status   public.order_status
)
returns public.orders
language plpgsql
as $$
declare
  v_order public.orders;
begin
  -- Checagem de ownership: o pedido precisa pertencer ao usuário autenticado
  perform 1
  from public.orders o
  join public.customers c on c.id = o.customer_id
  where o.id = p_order_id
    and c.user_id = auth.uid();

  if not found then
    raise exception 'Pedido não pertence ao usuário autenticado.'
      using errcode = '42501';
  end if;

  -- Atualiza o status do pedido
  update public.orders
     set status     = p_status,
         updated_at = now()
   where id = p_order_id
  returning * into v_order;

  if not found then
    raise exception 'Pedido não encontrado para ID: %', p_order_id
      using errcode = 'P0002';
  end if;

  return v_order;
end;
$$;

comment on function public.update_order_status(uuid, public.order_status)
is 'Atualiza o status de um pedido pertencente ao usuário autenticado e retorna o registro.';

-- 4) Cria pedido para o usuário autenticado (sem spoof de customer_id)
create or replace function public.create_order(
  p_status public.order_status default 'pending'
)
returns public.orders
language plpgsql
as $$
declare
  v_customer_id uuid;
  v_order       public.orders;
begin
  -- Descobre o customer vinculado ao usuário atual
  select c.id
    into v_customer_id
  from public.customers c
  where c.user_id = auth.uid();

  if v_customer_id is null then
    raise exception 'Cliente não encontrado para o usuário atual.'
      using errcode = 'P0002';
  end if;

  -- Cria o pedido sem permitir que o client "escolha" o customer_id
  insert into public.orders (customer_id, status)
  values (v_customer_id, p_status)
  returning * into v_order;

  return v_order;
end;
$$;

comment on function public.create_order(public.order_status)
is 'Cria um novo pedido vinculado ao cliente do usuário autenticado.';