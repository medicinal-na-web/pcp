# PCP — Portal PCP da Medicinal

Painel de produção: quantas fórmulas estão em cada setor e em cada limbo, por laboratório, data e faixa de retirada. Os dados vêm do FórmulaCerta (réplica Firebird), passam pelo n8n e ficam no Supabase **formulaCerta**. O app fica no Supabase, no mesmo molde dos outros portais da casa (`_brasa_parts_*` + `brasa_loader_*()`), e é aberto por uma página estática hospedada na **Infalltech** (CloudPanel). O servidor antigo da Brasa não é mais usado.

## Como funciona

```
FórmulaCerta (réplica Firebird)
  │  n8n "PCP - Carga da réplica para o Portal PCP (15 min)"  — só SELECT
  ▼
Supabase formulaCerta: pcp_requisicao (+ pcp_etapa, pcp_feriado)
  │  funções rpc (pcp_painel etc.), só para quem tem acesso
  ▼
Portal PCP: app em _brasa_parts_pcp, servido por brasa_loader_pcp()
  │  portal/index.html (página estática na Infalltech/CloudPanel) busca o app e o abre
  ▼
endereço do portal na Infalltech  (login por e-mail com código)
```

## Regras de negócio

- **Fonte:** FC12100 (requisições), FC12500 (eventos de etapa) e FC12540 (cadastro de etapas).
- **Etapa atual da fórmula:** regra do PCP_v19 (Power BI). Cada requisição-série conta uma vez, na etapa de **maior POSICAO** já registrada.
- **Situação na etapa:** vem da maior operação (CDOPERA) nessa posição. A **02** quer dizer "limbo": saiu da etapa e ainda não entrou na próxima. A **01** (e a **03**) conta como "no setor".
- **Laboratórios (TPFORMAFARMA):** Interno = espécie 1; Diferenciados = espécies 5 e 6; Externo = espécies 2, 3 e 4; Sachês = espécie 15.
- **Fluxo:**
  - Interno, Diferenciados e Sachês: Ficha › Pesagem › Homogeneização › Manipulação › Conferência › Rótulo.
  - Externo: Ficha › Manipulação externa › Rótulo.
- **Etapas agrupadas:**
  - Ficha = Ficha impressão + Ficha conferência + B.O.
  - Rótulo = Rótulo coleta + Rótulo conferência.
  - Manipulação = I_MANI, I_SACHE, I_DIFE e E_MANI. No bloco Externo, qualquer etapa de laboratório conta como Manipulação externa.
- **Fora da conta:** a fórmula que saiu do Rótulo conferência está pronta e sai da conta, assim como as etapas de logística (posição acima de 50).
- **Faixas fixas de retirada:** o horário é comparado até o minuto e entra na próxima faixa.

  | Faixa | Uso |
  |---|---|
  | 16h | Loja |
  | 18h | Entrega manhã |
  | 19h | Entrega tarde |
  | 20h | Sedex 67 |
  | 21h | Sedex MaisCabello |
  | 22h | Sedex (também tudo o que passar das 22h) |

- **Horas mortas:** o tempo útil conta só o expediente: seg–sex 8h–21h e sábado 8h–12h. Domingo e feriado (tabela `pcp_feriado`) não contam. A função é `pcp_minutos_uteis`. Depois de alterar feriados, rode `select pcp_recalcula_uteis();`.

## Rotina de publicação de um portal (molde da casa)

1. **Banco** (`supabase/migrations`):
   - tabela de acessos (`<x>_acesso`) e histórico append-only;
   - funções `security definer`: `<x>_email_autorizado` (anon), `<x>_vincular`, `<x>_meu_papel` e as rpc de leitura e gravação (authenticated);
   - RLS ligado e grants revogados de anon/authenticated nas tabelas.
2. **Login:** gatilho em `<x>_acesso` chama a edge function `<x>-provisionar-login`, que cria a conta sem senha. O app pede o código por e-mail (`/auth/v1/otp` com `create_user: false`) e valida em `/auth/v1/verify`.
3. **App:** um único fragmento HTML+CSS+JS (`portal/<x>.html`), todo escopado num `#<x>root` com `position:fixed`, para não vazar CSS no site. Ele fala com o banco só por `rpc`.
4. **Publicação do app:**
   - mandar o HTML em texto puro para `_<x>_stage` em partes, conferindo o md5 de cada parte;
   - rodar o bloco de `pcp_004_publica_portal.sql`, que confere o md5 total, grava o base64 em `_brasa_parts_<x>` e confere `md5(brasa_loader_<x>())`.
5. **Hospedagem (Infalltech/CloudPanel):** publicar uma única vez o arquivo `portal/index.html` como site estático (ex.: `pcp.medicinalnaweb.com.br`), com DNS apontando para o servidor da Infalltech e certificado Let's Encrypt. Essa página só busca o app em `brasa_loader_pcp()`. Por isso as atualizações do portal são feitas só no banco (passo 4), sem mexer no servidor.
6. **Acessos:** o administrador cadastra os e-mails na aba "Acessos" do portal.

## Carga de dados (n8n, instância principal)

- **Workflow:** `PCP - Carga da réplica para o Portal PCP (15 min)` (id `ZrCGzMDq4xds1O7d`), ativo.
- **Quando roda:** nos minutos 3, 18, 33 e 48, de segunda a sábado, das 7h às 21h (America/Sao_Paulo).
- **Janela:** requisições com DTENTR nos últimos 15 dias. Duas consultas simples na réplica (FC12100 e FC12500×FC12540); o pivô é feito no nó Code.
- **Gravação:** `rpc/pcp_carga_lote` em lotes de 500. Os tempos são calculados no banco, pelo gatilho de `pcp_requisicao`.
- **Credenciais:** réplica "Firebird (WIN1252) Replica Producao"; Supabase "Supabase FormulaCerta".
- **Lições aprendidas:**
  - uma consulta única com CTE e window function em 90 dias estourou o tempo-limite;
  - o Firebird devolve os nomes de coluna em maiúsculas;
  - nós HTTP criados pelo MCP não recebem a credencial sozinhos: use `setNodeCredential`.

## Arquivos

- `portal/pcp.html`: app do portal (fonte da publicação).
- `supabase/migrations/`: estrutura do banco, em ordem.
- `supabase/functions/pcp-provisionar-login/`: edge function de login.
