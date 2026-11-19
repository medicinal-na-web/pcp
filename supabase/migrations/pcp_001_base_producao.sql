-- PCP: dados de produção (FC12100 x FC12500 x FC12540) carregados da réplica pelo n8n.
create table public.pcp_feriado (
  dia date primary key,
  descricao text
);
comment on table public.pcp_feriado is 'PCP - feriados para o cálculo de horas mortas. Feriado = dia inteiro sem expediente (das 21h da véspera às 8h do dia seguinte). Origem inicial: tabela Feriado_ do PCP_v19 (Power BI).';
insert into public.pcp_feriado (dia, descricao) values
('2023-01-01',null),
('2023-02-21',null),
('2023-04-07',null),
('2023-04-21',null),
('2023-05-01',null),
('2023-05-10',null),
('2023-06-08',null),
('2023-08-15',null),
('2023-09-07',null),
('2023-10-12',null),
('2023-11-02',null),
('2023-11-15',null),
('2023-12-25',null),
('2024-01-01','primeiro dia do ano'),
('2024-02-13','carnaval'),
('2024-03-29','sexta feira santa'),
('2024-04-21','tiradentes'),
('2024-05-01','dia do trabalhador'),
('2024-05-10','aniversario maringa'),
('2024-05-30','corpus christi'),
('2024-08-15','padroeira de maringa'),
('2024-09-07','independencia'),
('2024-10-12','dia das crianças'),
('2024-11-02','finados'),
('2024-11-15','proclamacao'),
('2024-12-25','natal'),
('2025-01-01','primeiro dia do ano'),
('2025-03-04','carnaval'),
('2025-04-18','sexta feira santa'),
('2025-04-21','tiradentes'),
('2025-05-01','dia do trabalhador'),
('2025-05-12','aniversario maringa'),
('2025-06-19','corpus christi'),
('2025-08-15','padroeira de maringa'),
('2025-09-07','independencia'),
('2025-10-12','dia das crianças'),
('2025-11-02','finados'),
('2025-11-15','proclamacao'),
('2025-11-20','consciencia negra'),
('2025-12-25','natal'),
('2026-01-01','primeiro dia do ano'),
('2026-02-16','carnaval'),
('2026-04-03','sexta feira santa'),
('2026-04-21','tiradentes'),
('2026-05-01','dia do trabalhador'),
('2026-05-11','aniversario maringa'),
('2026-06-04','corpus christi'),
('2026-08-15','padroeira de maringa'),
('2026-09-07','independencia'),
('2026-10-12','dia das crianças'),
('2026-11-02','finados'),
('2026-11-15','proclamacao'),
('2026-11-20','consciencia negra'),
('2026-12-25','natal')
;

create table public.pcp_etapa (
  cdetapa text primary key,
  descricao text,
  posicao integer,
  referencia text,
  obrigatoria text,
  finaliza text,
  producao integer,
  tppcp text,
  carregado_em timestamptz not null default now()
);
comment on table public.pcp_etapa is 'PCP - espelho do FC12540 (cadastro de etapas do PCP). Fonte de verdade: ERP. Carga pelo n8n.';

create table public.pcp_requisicao (
  requisicao text primary key,
  nrrqu integer not null,
  serier text not null,
  cdfil integer,
  dtentr date,
  dtret date,
  retirada timestamp,
  nrcrm integer,
  cdfunre integer,
  tpformafarma integer,
  volume numeric,
  qtfor integer,
  prcobr numeric,
  vrtxa numeric,
  vrdsc numeric,
  prreal numeric,
  prcusto numeric,
  prcompra numeric,
  max_posicao integer,
  max_operacao integer,
  atendimento_entrada timestamp,
  atendimento_saida timestamp,
  ficha_conf_entrada timestamp,
  ficha_conf_saida timestamp,
  ficha_imp_entrada timestamp,
  ficha_imp_saida timestamp,
  pesagem_entrada timestamp,
  pesagem_saida timestamp,
  homogeneizacao_entrada timestamp,
  homogeneizacao_saida timestamp,
  interno_entrada timestamp,
  interno_saida timestamp,
  conferencia_entrada timestamp,
  conferencia_saida timestamp,
  rotulo_conf_entrada timestamp,
  rotulo_conf_saida timestamp,
  rotulo_col_entrada timestamp,
  rotulo_col_saida timestamp,
  externo_entrada timestamp,
  externo_saida timestamp,
  sache_entrada timestamp,
  sache_saida timestamp,
  diferenciados_entrada timestamp,
  diferenciados_saida timestamp,
  atendimento_min numeric,
  limbo_atendimento_ficha_min numeric,
  ficha_conf_min numeric,
  ficha_imp_min numeric,
  limbo_ficha_pesagem_min numeric,
  pesagem_min numeric,
  limbo_pesagem_homogeneizacao_min numeric,
  homogeneizacao_min numeric,
  limbo_homogeneizacao_interno_min numeric,
  interno_min numeric,
  limbo_interno_conferencia_min numeric,
  conferencia_min numeric,
  limbo_conferencia_rotulo_min numeric,
  rotulo_min numeric,
  atendimento_min_util numeric,
  limbo_atendimento_ficha_min_util numeric,
  ficha_conf_min_util numeric,
  ficha_imp_min_util numeric,
  limbo_ficha_pesagem_min_util numeric,
  pesagem_min_util numeric,
  limbo_pesagem_homogeneizacao_min_util numeric,
  homogeneizacao_min_util numeric,
  limbo_homogeneizacao_interno_min_util numeric,
  interno_min_util numeric,
  limbo_interno_conferencia_min_util numeric,
  conferencia_min_util numeric,
  limbo_conferencia_rotulo_min_util numeric,
  rotulo_min_util numeric,
  carregado_em timestamptz not null default now()
);
comment on table public.pcp_requisicao is 'PCP - uma linha por requisição-série (FC12100) com entrada/saída por etapa (FC12500) e tempos, nas regras do PCP_v19 (Power BI). *_min = tempo corrido; *_min_util = só expediente (seg-sex 8h-21h, sáb 8h-12h, sem feriados de pcp_feriado). Carga diária pelo n8n (janela de 90 dias por DTENTR). Sem nome de paciente.';
create index pcp_requisicao_dtentr_idx on public.pcp_requisicao (dtentr);
create index pcp_requisicao_dtret_idx on public.pcp_requisicao (dtret);

-- Minutos de expediente entre dois instantes. Expediente: seg-sex 08:00-21:00, sábado 08:00-12:00.
-- Domingo e feriado (pcp_feriado) não têm expediente. Fora disso é hora morta.
create or replace function public.pcp_minutos_uteis(p_ini timestamp, p_fim timestamp)
returns numeric language plpgsql stable set search_path = public as $$
declare
  a timestamp; b timestamp; d date; ws timestamp; we timestamp; dow int;
  tot numeric := 0; sinal int := 1;
begin
  if p_ini is null or p_fim is null then return null; end if;
  if p_fim < p_ini then a := p_fim; b := p_ini; sinal := -1; else a := p_ini; b := p_fim; end if;
  d := a::date;
  while d <= b::date loop
    dow := extract(isodow from d);
    if dow <> 7 and not exists (select 1 from public.pcp_feriado f where f.dia = d) then
      ws := d + time '08:00';
      we := d + case when dow = 6 then time '12:00' else time '21:00' end;
      if least(b, we) > greatest(a, ws) then
        tot := tot + extract(epoch from (least(b, we) - greatest(a, ws))) / 60;
      end if;
    end if;
    d := d + 1;
  end loop;
  return round(sinal * tot, 4);
end $$;

create or replace function public.pcp_requisicao_calc_util()
returns trigger language plpgsql set search_path = public as $$
begin
  new.atendimento_min_util := public.pcp_minutos_uteis(new.atendimento_entrada, new.atendimento_saida);
  new.limbo_atendimento_ficha_min_util := public.pcp_minutos_uteis(new.atendimento_saida, new.ficha_imp_entrada);
  new.ficha_conf_min_util := public.pcp_minutos_uteis(new.ficha_conf_entrada, new.ficha_conf_saida);
  new.ficha_imp_min_util := public.pcp_minutos_uteis(new.ficha_imp_entrada, new.ficha_imp_saida);
  new.limbo_ficha_pesagem_min_util := public.pcp_minutos_uteis(new.ficha_imp_saida, new.pesagem_entrada);
  new.pesagem_min_util := public.pcp_minutos_uteis(new.pesagem_entrada, new.pesagem_saida);
  new.limbo_pesagem_homogeneizacao_min_util := public.pcp_minutos_uteis(new.pesagem_saida, new.homogeneizacao_entrada);
  new.homogeneizacao_min_util := public.pcp_minutos_uteis(new.homogeneizacao_entrada, new.homogeneizacao_saida);
  new.limbo_homogeneizacao_interno_min_util := public.pcp_minutos_uteis(new.homogeneizacao_saida, new.interno_entrada);
  new.interno_min_util := public.pcp_minutos_uteis(new.interno_entrada, new.interno_saida);
  new.limbo_interno_conferencia_min_util := public.pcp_minutos_uteis(new.interno_saida, new.conferencia_entrada);
  new.conferencia_min_util := public.pcp_minutos_uteis(new.conferencia_entrada, new.conferencia_saida);
  new.limbo_conferencia_rotulo_min_util := public.pcp_minutos_uteis(new.conferencia_saida, new.rotulo_conf_entrada);
  new.rotulo_min_util := public.pcp_minutos_uteis(new.rotulo_conf_entrada, new.rotulo_conf_saida);
  return new;
end $$;

create trigger pcp_requisicao_calc_util
before insert or update on public.pcp_requisicao
for each row execute function public.pcp_requisicao_calc_util();

-- Carga em lotes pelo n8n: upsert das linhas (json com os nomes das colunas).
create or replace function public.pcp_carga_lote(p_linhas jsonb, p_carga timestamptz)
returns integer language plpgsql set search_path = public as $$
declare n integer;
begin
  if p_linhas is null or jsonb_array_length(p_linhas) = 0 then
    raise exception 'pcp_carga_lote: lote vazio';
  end if;
  insert into public.pcp_requisicao (requisicao, nrrqu, serier, cdfil, dtentr, dtret, retirada, nrcrm, cdfunre, tpformafarma, volume, qtfor, prcobr, vrtxa, vrdsc, prreal, prcusto, prcompra, max_posicao, max_operacao, atendimento_entrada, atendimento_saida, ficha_conf_entrada, ficha_conf_saida, ficha_imp_entrada, ficha_imp_saida, pesagem_entrada, pesagem_saida, homogeneizacao_entrada, homogeneizacao_saida, interno_entrada, interno_saida, conferencia_entrada, conferencia_saida, rotulo_conf_entrada, rotulo_conf_saida, rotulo_col_entrada, rotulo_col_saida, externo_entrada, externo_saida, sache_entrada, sache_saida, diferenciados_entrada, diferenciados_saida, atendimento_min, limbo_atendimento_ficha_min, ficha_conf_min, ficha_imp_min, limbo_ficha_pesagem_min, pesagem_min, limbo_pesagem_homogeneizacao_min, homogeneizacao_min, limbo_homogeneizacao_interno_min, interno_min, limbo_interno_conferencia_min, conferencia_min, limbo_conferencia_rotulo_min, rotulo_min, atendimento_min_util, limbo_atendimento_ficha_min_util, ficha_conf_min_util, ficha_imp_min_util, limbo_ficha_pesagem_min_util, pesagem_min_util, limbo_pesagem_homogeneizacao_min_util, homogeneizacao_min_util, limbo_homogeneizacao_interno_min_util, interno_min_util, limbo_interno_conferencia_min_util, conferencia_min_util, limbo_conferencia_rotulo_min_util, rotulo_min_util, carregado_em)
  select r.requisicao, r.nrrqu, r.serier, r.cdfil, r.dtentr, r.dtret, r.retirada, r.nrcrm, r.cdfunre, r.tpformafarma, r.volume, r.qtfor, r.prcobr, r.vrtxa, r.vrdsc, r.prreal, r.prcusto, r.prcompra, r.max_posicao, r.max_operacao, r.atendimento_entrada, r.atendimento_saida, r.ficha_conf_entrada, r.ficha_conf_saida, r.ficha_imp_entrada, r.ficha_imp_saida, r.pesagem_entrada, r.pesagem_saida, r.homogeneizacao_entrada, r.homogeneizacao_saida, r.interno_entrada, r.interno_saida, r.conferencia_entrada, r.conferencia_saida, r.rotulo_conf_entrada, r.rotulo_conf_saida, r.rotulo_col_entrada, r.rotulo_col_saida, r.externo_entrada, r.externo_saida, r.sache_entrada, r.sache_saida, r.diferenciados_entrada, r.diferenciados_saida, r.atendimento_min, r.limbo_atendimento_ficha_min, r.ficha_conf_min, r.ficha_imp_min, r.limbo_ficha_pesagem_min, r.pesagem_min, r.limbo_pesagem_homogeneizacao_min, r.homogeneizacao_min, r.limbo_homogeneizacao_interno_min, r.interno_min, r.limbo_interno_conferencia_min, r.conferencia_min, r.limbo_conferencia_rotulo_min, r.rotulo_min, r.atendimento_min_util, r.limbo_atendimento_ficha_min_util, r.ficha_conf_min_util, r.ficha_imp_min_util, r.limbo_ficha_pesagem_min_util, r.pesagem_min_util, r.limbo_pesagem_homogeneizacao_min_util, r.homogeneizacao_min_util, r.limbo_homogeneizacao_interno_min_util, r.interno_min_util, r.limbo_interno_conferencia_min_util, r.conferencia_min_util, r.limbo_conferencia_rotulo_min_util, r.rotulo_min_util, p_carga
    from jsonb_populate_recordset(null::public.pcp_requisicao, p_linhas) r
  on conflict (requisicao) do update set
    nrrqu = excluded.nrrqu,
    serier = excluded.serier,
    cdfil = excluded.cdfil,
    dtentr = excluded.dtentr,
    dtret = excluded.dtret,
    retirada = excluded.retirada,
    nrcrm = excluded.nrcrm,
    cdfunre = excluded.cdfunre,
    tpformafarma = excluded.tpformafarma,
    volume = excluded.volume,
    qtfor = excluded.qtfor,
    prcobr = excluded.prcobr,
    vrtxa = excluded.vrtxa,
    vrdsc = excluded.vrdsc,
    prreal = excluded.prreal,
    prcusto = excluded.prcusto,
    prcompra = excluded.prcompra,
    max_posicao = excluded.max_posicao,
    max_operacao = excluded.max_operacao,
    atendimento_entrada = excluded.atendimento_entrada,
    atendimento_saida = excluded.atendimento_saida,
    ficha_conf_entrada = excluded.ficha_conf_entrada,
    ficha_conf_saida = excluded.ficha_conf_saida,
    ficha_imp_entrada = excluded.ficha_imp_entrada,
    ficha_imp_saida = excluded.ficha_imp_saida,
    pesagem_entrada = excluded.pesagem_entrada,
    pesagem_saida = excluded.pesagem_saida,
    homogeneizacao_entrada = excluded.homogeneizacao_entrada,
    homogeneizacao_saida = excluded.homogeneizacao_saida,
    interno_entrada = excluded.interno_entrada,
    interno_saida = excluded.interno_saida,
    conferencia_entrada = excluded.conferencia_entrada,
    conferencia_saida = excluded.conferencia_saida,
    rotulo_conf_entrada = excluded.rotulo_conf_entrada,
    rotulo_conf_saida = excluded.rotulo_conf_saida,
    rotulo_col_entrada = excluded.rotulo_col_entrada,
    rotulo_col_saida = excluded.rotulo_col_saida,
    externo_entrada = excluded.externo_entrada,
    externo_saida = excluded.externo_saida,
    sache_entrada = excluded.sache_entrada,
    sache_saida = excluded.sache_saida,
    diferenciados_entrada = excluded.diferenciados_entrada,
    diferenciados_saida = excluded.diferenciados_saida,
    atendimento_min = excluded.atendimento_min,
    limbo_atendimento_ficha_min = excluded.limbo_atendimento_ficha_min,
    ficha_conf_min = excluded.ficha_conf_min,
    ficha_imp_min = excluded.ficha_imp_min,
    limbo_ficha_pesagem_min = excluded.limbo_ficha_pesagem_min,
    pesagem_min = excluded.pesagem_min,
    limbo_pesagem_homogeneizacao_min = excluded.limbo_pesagem_homogeneizacao_min,
    homogeneizacao_min = excluded.homogeneizacao_min,
    limbo_homogeneizacao_interno_min = excluded.limbo_homogeneizacao_interno_min,
    interno_min = excluded.interno_min,
    limbo_interno_conferencia_min = excluded.limbo_interno_conferencia_min,
    conferencia_min = excluded.conferencia_min,
    limbo_conferencia_rotulo_min = excluded.limbo_conferencia_rotulo_min,
    rotulo_min = excluded.rotulo_min,
    atendimento_min_util = excluded.atendimento_min_util,
    limbo_atendimento_ficha_min_util = excluded.limbo_atendimento_ficha_min_util,
    ficha_conf_min_util = excluded.ficha_conf_min_util,
    ficha_imp_min_util = excluded.ficha_imp_min_util,
    limbo_ficha_pesagem_min_util = excluded.limbo_ficha_pesagem_min_util,
    pesagem_min_util = excluded.pesagem_min_util,
    limbo_pesagem_homogeneizacao_min_util = excluded.limbo_pesagem_homogeneizacao_min_util,
    homogeneizacao_min_util = excluded.homogeneizacao_min_util,
    limbo_homogeneizacao_interno_min_util = excluded.limbo_homogeneizacao_interno_min_util,
    interno_min_util = excluded.interno_min_util,
    limbo_interno_conferencia_min_util = excluded.limbo_interno_conferencia_min_util,
    conferencia_min_util = excluded.conferencia_min_util,
    limbo_conferencia_rotulo_min_util = excluded.limbo_conferencia_rotulo_min_util,
    rotulo_min_util = excluded.rotulo_min_util,
    carregado_em = excluded.carregado_em;
  get diagnostics n = row_count;
  return n;
end $$;

-- Fim da carga: remove da janela as requisições que não vieram nesta carga (ex.: excluídas no ERP).
create or replace function public.pcp_carga_fim(p_dtini date, p_dtfim date, p_carga timestamptz, p_total integer)
returns jsonb language plpgsql set search_path = public as $$
declare na_janela integer; removidas integer;
begin
  select count(*) into na_janela from public.pcp_requisicao
   where dtentr between p_dtini and p_dtfim and carregado_em = p_carga;
  if na_janela <> p_total then
    raise exception 'pcp_carga_fim: esperadas % linhas desta carga na janela, encontradas %. Nada removido.', p_total, na_janela;
  end if;
  delete from public.pcp_requisicao
   where dtentr between p_dtini and p_dtfim and carregado_em <> p_carga;
  get diagnostics removidas = row_count;
  return jsonb_build_object('carregadas', na_janela, 'removidas', removidas);
end $$;

-- Recalcula os tempos úteis (usar depois de alterar pcp_feriado).
create or replace function public.pcp_recalcula_uteis(p_dtini date default null)
returns integer language plpgsql set search_path = public as $$
declare n integer;
begin
  update public.pcp_requisicao set requisicao = requisicao
   where p_dtini is null or dtentr >= p_dtini;
  get diagnostics n = row_count;
  return n;
end $$;

create or replace view public.pcp_requisicao_v with (security_invoker = true) as
select r.*, e.cdetapa as etapa_atual_cd, e.descricao as etapa_atual,
       (r.retirada < r.rotulo_conf_saida) as atrasada
  from public.pcp_requisicao r
  left join public.pcp_etapa e on e.posicao = r.max_posicao;

alter table public.pcp_feriado enable row level security;
alter table public.pcp_etapa enable row level security;
alter table public.pcp_requisicao enable row level security;
revoke all on public.pcp_feriado, public.pcp_etapa, public.pcp_requisicao, public.pcp_requisicao_v from anon, authenticated;
revoke execute on function public.pcp_minutos_uteis(timestamp, timestamp), public.pcp_carga_lote(jsonb, timestamptz),
  public.pcp_carga_fim(date, date, timestamptz, integer), public.pcp_recalcula_uteis(date) from public, anon, authenticated;
grant all on public.pcp_feriado, public.pcp_etapa, public.pcp_requisicao, public.pcp_requisicao_v to service_role;
grant execute on function public.pcp_minutos_uteis(timestamp, timestamp), public.pcp_carga_lote(jsonb, timestamptz),
  public.pcp_carga_fim(date, date, timestamptz, integer), public.pcp_recalcula_uteis(date) to service_role;
