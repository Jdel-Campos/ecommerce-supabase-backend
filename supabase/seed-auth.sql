-- =============================================
-- SEED AUTH USERS (SUPABASE AUTH + PUBLIC.USERS)
-- =============================================
-- Executar no Supabase SQL Editor ou via CLI:
-- supabase db seed --file supabase/seed_auth.sql
-- =============================================

-- ✅ Cria usuários diretamente em auth.users
-- Senhas padrão: admin_secure_password / user_secure_password
-- (usa função interna crypt() para gerar o hash localmente)

insert into auth.users (id, email, encrypted_password, email_confirmed_at, raw_user_meta_data)
values
  (
    '00000000-0000-0000-0000-000000000001',
    'admin@exemplo.com',
    crypt('admin_secure_password', gen_salt('bf')),
    now(),
    jsonb_build_object('name', 'Admin User')
  ),
  (
    '00000000-0000-0000-0000-000000000002',
    'alice@example.com',
    crypt('user_secure_password', gen_salt('bf')),
    now(),
    jsonb_build_object('name', 'Alice Doe')
  ),
  (
    '00000000-0000-0000-0000-000000000003',
    'bob@example.com',
    crypt('user_secure_password', gen_salt('bf')),
    now(),
    jsonb_build_object('name', 'Bob Smith')
  ),
  (
    '00000000-0000-0000-0000-000000000004',
    'charlie@example.com',
    crypt('user_secure_password', gen_salt('bf')),
    now(),
    jsonb_build_object('name', 'Charlie Brown')
  )
on conflict (id) do nothing;

-- =============================================
-- 🧩 FORÇA EXECUÇÃO DO TRIGGER handle_new_user()
-- (Se já estiver ativo, ele vai inserir automaticamente na public.users)
-- =============================================
do $$
begin
  perform public.handle_new_user() from auth.users;
exception
  when others then
    raise notice 'Trigger handle_new_user já existe ou foi executado.';
end;
$$;

-- =============================================
-- 🔍 VERIFICA SINCRONIZAÇÃO
-- =============================================
-- Deve mostrar os 4 usuários em public.users
select id, email, role from public.users;

-- =============================================
-- ✅ Ajusta role do admin manualmente (caso necessário)
-- =============================================
update public.users
set role = 'admin'
where email = 'admin@exemplo.com';

-- =============================================
-- ✅ Exibe resumo final
-- =============================================
select
  u.id,
  u.email,
  u.role,
  a.created_at as auth_created_at
from public.users u
join auth.users a on a.id = u.id;
