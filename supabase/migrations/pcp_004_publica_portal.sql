-- Publicação do app do Portal PCP (rotina usada em 19/11/2026).
-- 1) O HTML de portal/pcp.html é enviado em TEXTO PURO para public._pcp_stage, em partes (id 1, 2, 3...),
--    cada uma conferida por md5 contra o arquivo local.
-- 2) Este bloco remonta o texto, confere o md5 do arquivo inteiro e grava o base64 em _brasa_parts_pcp.
--    Troque o md5 abaixo pelo do arquivo que está sendo publicado (md5sum portal/pcp.html).
do $$
declare h text; b text;
begin
  select string_agg(txt, '' order by id) into h from public._pcp_stage;
  if md5(h) <> 'e2cddc497e6bd66ff3bd7d0ae04ed76c' then raise exception 'md5 do app não confere: %', md5(h); end if;
  b := replace(encode(convert_to(h, 'UTF8'), 'base64'), E'\n', '');
  delete from public._brasa_parts_pcp;
  insert into public._brasa_parts_pcp (part, b)
  select n, substr(b, (n - 1) * 8000 + 1, 8000) from generate_series(1, ceil(length(b) / 8000.0)::int) n;
end $$;
-- Conferência: deve devolver o mesmo md5 do arquivo.
select md5(public.brasa_loader_pcp()) md5, length(public.brasa_loader_pcp()) tam;
