-- Portal PCP: acesso por e-mail com código (mesmo molde do Portal do Orçamentista) e leitura só por funções.
create table public.pcp_acesso (
  id bigserial primary key,
  email text not null unique,
  nome text,
  papel text not null default 'leitor' check (papel in ('leitor', 'admin')),
  ativo boolean not null default true,
  user_id uuid,
  criado_em timestamptz not null default now()
);
comment on table public.pcp_acesso is 'Acesso ao Portal PCP. Uma linha por e-mail. leitor vê o painel; admin também cadastra acessos.';
create table public.pcp_acesso_hist (
  id bigserial primary key,
  em timestamptz not null default now(),
  por text,
  email text,
  de jsonb,
  para jsonb
);
comment on table public.pcp_acesso_hist is 'Append-only: toda alteração de acesso do Portal PCP.';
create table public._brasa_parts_pcp (part integer primary key, b text not null);
comment on table public._brasa_parts_pcp is 'App do Portal PCP em pedaços base64, remontados por brasa_loader_pcp(). Mesmo molde de _brasa_parts_orc.';

alter table public.pcp_acesso enable row level security;
alter table public.pcp_acesso_hist enable row level security;
alter table public._brasa_parts_pcp enable row level security;
revoke all on public.pcp_acesso, public.pcp_acesso_hist, public._brasa_parts_pcp from anon, authenticated;

create or replace function public.brasa_loader_pcp() returns text language sql stable security definer set search_path = public as $$
  select convert_from(decode(string_agg(b, '' order by part), 'base64'), 'UTF8') from public._brasa_parts_pcp;
$$;
comment on function public.brasa_loader_pcp() is 'Serve o app do Portal PCP (fragmento para a rota /pcp* no Brasa), remontado de _brasa_parts_pcp.';

create or replace function public.pcp_email_autorizado(p_email text) returns boolean language sql stable security definer set search_path = public as $$
  select exists(select 1 from public.pcp_acesso where ativo and lower(email) = lower(btrim(p_email)));
$$;

create or replace function public.pcp_meu_papel() returns text language sql stable security definer set search_path = public as $$
  select coalesce((select papel from public.pcp_acesso where user_id = auth.uid() and ativo), 'nenhum');
$$;

create or replace function public.pcp_vincular() returns table(email text, nome text, papel text) language plpgsql security definer set search_path = public as $$
begin
  update public.pcp_acesso a set user_id = null
   where a.user_id = auth.uid() and lower(a.email) <> lower(coalesce(auth.email(), ''));
  update public.pcp_acesso a set user_id = auth.uid()
   where lower(a.email) = lower(auth.email()) and a.ativo and a.user_id is null;
  return query select a.email, a.nome, a.papel from public.pcp_acesso a where a.user_id = auth.uid() and a.ativo;
end $$;

-- Painel: fórmulas em produção por laboratório, data e faixa de retirada (mesma regra do painel validado).
create or replace function public.pcp_painel() returns jsonb language plpgsql stable security definer set search_path = public as $$
declare v jsonb;
begin
  if public.pcp_meu_papel() = 'nenhum' then raise exception 'Sem acesso ao Portal PCP.'; end if;
  select jsonb_build_object(
    'atualizado_em', (select max(carregado_em) from public.pcp_requisicao),
    'agora', now(),
    'linhas', coalesce((select jsonb_agg(to_jsonb(x)) from (
with hoje as (select (now() at time zone 'America/Sao_Paulo')::date as d),
base as (
  select r.dtret - (select d from hoje) as dias,
         case
           when r.retirada is null then null
           when date_trunc('minute', r.retirada)::time <= time '16:00' then '16h · Loja'
           when date_trunc('minute', r.retirada)::time <= time '18:00' then '18h · Entrega manhã'
           when date_trunc('minute', r.retirada)::time <= time '19:00' then '19h · Entrega tarde'
           when date_trunc('minute', r.retirada)::time <= time '20:00' then '20h · Sedex 67'
           when date_trunc('minute', r.retirada)::time <= time '21:00' then '21h · Sedex MaisCabello'
           else '22h · Sedex' end as horario,
         r.tpformafarma as especie,
         case when r.tpformafarma = 1 then 'Interno' when r.tpformafarma in (5, 6) then 'Diferenciados' when r.tpformafarma in (2, 3, 4) then 'Externo' else 'Sachês' end as grupo,
         r.max_posicao as pos, r.max_operacao as op
    from pcp_requisicao r
   where r.dtret >= (select d from hoje) - 7
     and r.tpformafarma in (1, 2, 3, 4, 5, 6, 15)
     and r.max_posicao between 11 and 50
     and not (r.max_posicao = 50 and r.max_operacao = 2)
),
mapa as (
  select b.*,
         case
           when pos in (11, 20, 21) then 'Ficha'
           when pos in (41, 50) then 'Rótulo'
           when grupo = 'Externo' then 'Manip. externo'
           when pos = 30 then 'Pesagem'
           when pos = 31 then 'Homogeneiz.'
           when pos = 35 then 'Conferência'
           else 'Manipulação' end as setor,
         case
           when pos in (11, 20, 21) then 1
           when pos in (41, 50) then 9
           when grupo = 'Externo' then 2
           when pos = 30 then 2
           when pos = 31 then 3
           when pos = 35 then 5
           else 4 end as col_ordem,
         case
           when pos in (41, 50) then 'setor'
           when pos = 11 then 'setor'
           when op = 2 then 'limbo'
           else 'setor' end as tipo
    from base b
)
select grupo, case grupo when 'Interno' then 1 when 'Diferenciados' then 2 when 'Externo' then 3 else 4 end as grupo_ordem,
       case when dias < 0 then 'Atrasada' when dias > 5 then 'D6+' else 'D' || dias end as retirada,
       case when dias < 0 then 7 when dias > 5 then 6 else dias end as ordem,
       coalesce(horario, 'sem horário') as horario, col_ordem, setor, tipo, count(*)::int as n
  from mapa
 group by 1, 2, 3, 4, 5, 6, 7, 8
 order by 2, 4, 5, 6, 8
    ) x), '[]'::jsonb),
    'especies', coalesce((select jsonb_agg(to_jsonb(y)) from (
select case when r.tpformafarma = 1 then 'Interno' when r.tpformafarma in (5, 6) then 'Diferenciados' when r.tpformafarma in (2, 3, 4) then 'Externo' else 'Sachês' end as grupo,
       r.tpformafarma as especie, count(*)::int as n
  from pcp_requisicao r
 where r.dtret >= (now() at time zone 'America/Sao_Paulo')::date - 7
   and r.tpformafarma in (1, 2, 3, 4, 5, 6, 15)
   and r.max_posicao between 11 and 50
   and not (r.max_posicao = 50 and r.max_operacao = 2)
 group by 1, 2
 order by 1, 2
    ) y), '[]'::jsonb)
  ) into v;
  return v;
end $$;

create or replace function public.pcp_acessos_ler() returns setof public.pcp_acesso language plpgsql stable security definer set search_path = public as $$
begin
  if public.pcp_meu_papel() <> 'admin' then raise exception 'Só o administrador vê os acessos.'; end if;
  return query select * from public.pcp_acesso order by ativo desc, email;
end $$;

create or replace function public.pcp_acesso_gravar(p_email text, p_nome text, p_papel text, p_ativo boolean)
returns void language plpgsql security definer set search_path = public as $$
declare antes jsonb; e text := lower(btrim(p_email));
begin
  if public.pcp_meu_papel() <> 'admin' then raise exception 'Só o administrador cadastra acessos.'; end if;
  if e is null or position('@' in e) < 2 then raise exception 'E-mail inválido.'; end if;
  if p_papel not in ('leitor', 'admin') then raise exception 'Papel inválido.'; end if;
  select to_jsonb(a) - 'user_id' - 'id' into antes from public.pcp_acesso a where lower(a.email) = e;
  insert into public.pcp_acesso (email, nome, papel, ativo) values (e, nullif(btrim(p_nome), ''), p_papel, coalesce(p_ativo, true))
  on conflict (email) do update set nome = excluded.nome, papel = excluded.papel, ativo = excluded.ativo;
  insert into public.pcp_acesso_hist (por, email, de, para)
  values (auth.email(), e, antes, jsonb_build_object('nome', p_nome, 'papel', p_papel, 'ativo', p_ativo));
end $$;

create or replace function public.pcp_trg_provisionar_login() returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.email is not null and new.ativo
     and (tg_op = 'INSERT' or lower(coalesce(old.email, '')) <> lower(new.email) or coalesce(old.ativo, false) is distinct from new.ativo)
     and not exists (select 1 from auth.users u where lower(u.email) = lower(new.email))
  then
    perform net.http_post(
      url     := 'https://mwhlnlqxtudcgbggkqud.supabase.co/functions/v1/pcp-provisionar-login',
      body    := jsonb_build_object('email', lower(new.email)),
      headers := '{"Content-Type":"application/json"}'::jsonb);
  end if;
  return new;
exception when others then
  raise warning 'provisionar login (pcp) falhou para %: %', new.email, sqlerrm;
  return new;
end $$;
create trigger pcp_acesso_provisionar after insert or update on public.pcp_acesso
for each row execute function public.pcp_trg_provisionar_login();

revoke execute on function public.brasa_loader_pcp(), public.pcp_email_autorizado(text), public.pcp_meu_papel(), public.pcp_vincular(),
  public.pcp_painel(), public.pcp_acessos_ler(), public.pcp_acesso_gravar(text, text, text, boolean), public.pcp_trg_provisionar_login() from public;
grant execute on function public.brasa_loader_pcp(), public.pcp_email_autorizado(text) to anon, authenticated, service_role;
grant execute on function public.pcp_meu_papel(), public.pcp_vincular(), public.pcp_painel(), public.pcp_acessos_ler(),
  public.pcp_acesso_gravar(text, text, text, boolean) to authenticated, service_role;
