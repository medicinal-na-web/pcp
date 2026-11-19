// Portal PCP — provisionamento de login (mesmo molde do orc-provisionar-login)
// Cria a conta de login (auth.users) SEM SENHA para e-mails cadastrados e ativos em pcp_acesso
// (pcp_email_autorizado). Idempotente. Nunca cria conta para e-mail fora do cadastro. Nao envia e-mail.
import { createClient } from "npm:@supabase/supabase-js@2";

const sb = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  { auth: { persistSession: false, autoRefreshToken: false } },
);

const json = (b: unknown, s = 200) =>
  new Response(JSON.stringify(b), { status: s, headers: { "Content-Type": "application/json" } });

async function provisionar(email: string) {
  const e = email.trim().toLowerCase();
  const { data: ok, error: e1 } = await sb.rpc("pcp_email_autorizado", { p_email: e });
  if (e1) return { email: e, status: "erro", detalhe: e1.message };
  if (!ok) return { email: e, status: "ignorado", detalhe: "nao autorizado" };
  const { error } = await sb.auth.admin.createUser({ email: e, email_confirm: true });
  if (!error) return { email: e, status: "criado" };
  if (/already|registered|exists/i.test(error.message)) return { email: e, status: "ja_existia" };
  return { email: e, status: "erro", detalhe: error.message };
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ erro: "use POST" }, 405);
  let body: { email?: string } = {};
  try { body = await req.json(); } catch { /* vazio */ }
  if (!body.email) return json({ erro: "informe email" }, 400);
  return json({ resultado: [await provisionar(body.email)] });
});
