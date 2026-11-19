-- Tempos corridos (*_min) também passam a ser calculados no banco, junto com os úteis (*_min_util).
create or replace function public.pcp_requisicao_calc_util()
returns trigger language plpgsql set search_path = public as $$
declare
  t constant text[][] := array[
    ['atendimento','atendimento_entrada','atendimento_saida'],
    ['limbo_atendimento_ficha','atendimento_saida','ficha_imp_entrada'],
    ['ficha_conf','ficha_conf_entrada','ficha_conf_saida'],
    ['ficha_imp','ficha_imp_entrada','ficha_imp_saida'],
    ['limbo_ficha_pesagem','ficha_imp_saida','pesagem_entrada'],
    ['pesagem','pesagem_entrada','pesagem_saida'],
    ['limbo_pesagem_homogeneizacao','pesagem_saida','homogeneizacao_entrada'],
    ['homogeneizacao','homogeneizacao_entrada','homogeneizacao_saida'],
    ['limbo_homogeneizacao_interno','homogeneizacao_saida','interno_entrada'],
    ['interno','interno_entrada','interno_saida'],
    ['limbo_interno_conferencia','interno_saida','conferencia_entrada'],
    ['conferencia','conferencia_entrada','conferencia_saida'],
    ['limbo_conferencia_rotulo','conferencia_saida','rotulo_conf_entrada'],
    ['rotulo','rotulo_conf_entrada','rotulo_conf_saida']];
  j jsonb := to_jsonb(new);
  i int; ini timestamp; fim timestamp;
begin
  for i in 1 .. array_length(t, 1) loop
    ini := (j ->> t[i][2])::timestamp;
    fim := (j ->> t[i][3])::timestamp;
    j := j || jsonb_build_object(
      t[i][1] || '_min', case when ini is null or fim is null then null else round(extract(epoch from (fim - ini)) / 60, 4) end,
      t[i][1] || '_min_util', public.pcp_minutos_uteis(ini, fim));
  end loop;
  new := jsonb_populate_record(new, j);
  return new;
end $$;
