-- ============================================================
-- COZINHA 48 — montagem do banco de dados (rodar UMA vez)
-- Onde rodar: painel do Supabase → SQL Editor → New query →
-- cole este arquivo inteiro → Run
-- ============================================================

-- ---------- PERFIS (um por usuário) ----------
create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  nome text,
  is_admin boolean not null default false,
  created_at timestamptz not null default now()
);
alter table public.profiles enable row level security;

-- função que diz se quem está logado é dono/mestre
create or replace function public.is_admin()
returns boolean language sql security definer stable
set search_path = public as $$
  select coalesce((select is_admin from public.profiles where id = auth.uid()), false);
$$;

create policy "perfis visiveis a todos" on public.profiles
  for select using (true);
create policy "cada um edita o proprio perfil" on public.profiles
  for update using (auth.uid() = id) with check (auth.uid() = id and is_admin = (select p.is_admin from public.profiles p where p.id = auth.uid()));

-- cria o perfil automaticamente quando alguém se cadastra
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer
set search_path = public as $$
begin
  insert into public.profiles (id, nome)
  values (new.id, coalesce(new.raw_user_meta_data->>'nome', 'Fã da Cozinha'));
  return new;
end; $$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ---------- CANDIDATURAS "QUERO TOCAR" ----------
create table public.candidaturas (
  id bigint generated always as identity primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  nome_artistico text not null,
  estilo text,
  link_som text,
  mensagem text,
  status text not null default 'recebida', -- recebida | aprovada | recusada
  created_at timestamptz not null default now()
);
alter table public.candidaturas enable row level security;

create policy "enviar a propria candidatura" on public.candidaturas
  for insert with check (auth.uid() = user_id);
create policy "ver a propria candidatura ou ser mestre" on public.candidaturas
  for select using (auth.uid() = user_id or public.is_admin());
create policy "mestres mudam o status" on public.candidaturas
  for update using (public.is_admin());
create policy "mestres apagam candidaturas" on public.candidaturas
  for delete using (public.is_admin());

-- ---------- MURAL DE RECADOS ----------
create table public.recados (
  id bigint generated always as identity primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  nome text not null,
  texto text not null check (char_length(texto) between 1 and 280),
  created_at timestamptz not null default now()
);
alter table public.recados enable row level security;

create policy "todos leem o mural" on public.recados
  for select using (true);
create policy "logado escreve no mural" on public.recados
  for insert with check (auth.uid() = user_id);
create policy "apagar o proprio recado ou ser mestre" on public.recados
  for delete using (auth.uid() = user_id or public.is_admin());

-- ============================================================
-- DEPOIS de criar a SUA conta pelo site, rode a linha abaixo
-- (trocando o e-mail) pra virar DONO/MESTRE. Repita pra cada dono:
--
-- update public.profiles set is_admin = true
--   where id = (select id from auth.users where email = 'SEU_EMAIL_AQUI');
-- ============================================================
