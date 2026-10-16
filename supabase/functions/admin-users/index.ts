// =============================================================================
// POST /functions/v1/admin-users — administration des comptes du personnel.
// Authentification : en-tête `Authorization: Bearer <access_token>` de l'acteur.
//
// Actions (champ `action`) :
//   invite               { email, full_name, role, phone?, create_agent_profile?, redirect_to? }
//   create               { email, password, full_name, role, phone?, create_agent_profile? }
//   deactivate           { user_id }
//   reactivate           { user_id }
//   send_password_reset  { user_id, redirect_to? }
//
// Les contrôles d'autorisation sont faits EN BASE avec le JWT de l'acteur
// (assign_role, admin_set_user_active appliquent la règle de rang). La clé
// service_role n'est utilisée que pour les opérations Auth qui l'exigent,
// après que la base a accepté l'opération.
// =============================================================================
import { adminClient, anonClient, bearerToken, userClient } from "../_shared/supabase.ts";
import { corsHeaders, errorResponse, json, mapDbError, readJsonBody } from "../_shared/http.ts";
import { agentSlug, validateAdminAction } from "../_shared/admin-validation.ts";

interface MyAccess {
  user_id: string;
  is_active: boolean;
  rank: number;
  roles: string[];
  permissions: string[];
}

const BAN_FOREVER = "876000h"; // ~100 ans

Deno.serve(async (req) => {
  const cors = corsHeaders(req.headers.get("origin"), Deno.env.get("BACKOFFICE_ORIGINS") ?? Deno.env.get("ALLOWED_ORIGINS"));
  if (req.method === "OPTIONS") return new Response(null, { status: 204, headers: cors });
  if (req.method !== "POST") {
    return errorResponse(405, { code: "METHOD_NOT_ALLOWED", message: "Méthode non autorisée." }, cors);
  }

  // 1. Identité de l'acteur
  const token = bearerToken(req);
  if (!token) return errorResponse(401, { code: "UNAUTHENTICATED", message: "Authentification requise." }, cors);
  const admin = adminClient();
  const { data: authData, error: authError } = await admin.auth.getUser(token);
  if (authError || !authData?.user) {
    return errorResponse(401, { code: "UNAUTHENTICATED", message: "Session invalide ou expirée." }, cors);
  }
  const uc = userClient(token);
  const { data: accessData, error: accessError } = await uc.rpc("get_my_access");
  const access = accessData as MyAccess | null;
  if (accessError || !access || !access.is_active) {
    return errorResponse(403, { code: "FORBIDDEN", message: "Compte inactif ou sans accès." }, cors);
  }
  const can = (p: string) => access.permissions.includes(p);

  // 2. Requête
  const parsed = await readJsonBody(req, 8 * 1024);
  if (!parsed.ok) return errorResponse(parsed.status, parsed.error, cors);
  const v = validateAdminAction(parsed.body);
  if (!v.ok) {
    return errorResponse(422, { code: "VALIDATION_ERROR", message: "Requête invalide.", fields: v.errors }, cors);
  }
  const input = v.data;

  const fail = (err: { code?: string; message?: string; hint?: string | null }) => {
    const m = mapDbError(err);
    if (m.status >= 500) console.error("[admin-users]", err);
    return errorResponse(m.status, m.error, cors);
  };

  // 3. Actions
  switch (input.action) {
    case "invite":
    case "create": {
      if (!can("users.manage") || !can("roles.assign")) {
        return errorResponse(403, { code: "FORBIDDEN", message: "Permissions users.manage et roles.assign requises." }, cors);
      }
      if (input.create_agent_profile && !can("agents.manage")) {
        return errorResponse(403, { code: "FORBIDDEN", message: "Permission agents.manage requise pour créer une fiche agent." }, cors);
      }
      // Pré-contrôle du rang (la base le revérifie dans assign_role).
      const { data: role } = await uc.from("roles").select("rank").eq("code", input.role).single();
      if (!role) return errorResponse(422, { code: "VALIDATION_ERROR", message: "Rôle inconnu.", fields: { role: "Rôle inconnu." } }, cors);
      if (!access.roles.includes("super_admin") && role.rank >= access.rank) {
        return errorResponse(403, { code: "FORBIDDEN", message: "Vous ne pouvez attribuer que des rôles de rang inférieur au vôtre." }, cors);
      }

      const created = input.action === "create"
        ? await admin.auth.admin.createUser({
          email: input.email,
          password: input.password!,
          email_confirm: true,
          user_metadata: { full_name: input.full_name },
        })
        : await admin.auth.admin.inviteUserByEmail(input.email, {
          data: { full_name: input.full_name },
          redirectTo: input.redirect_to ?? undefined,
        });
      if (created.error || !created.data?.user) {
        const msg = created.error?.message ?? "Création impossible.";
        const conflict = /already|registered|exists/i.test(msg);
        return errorResponse(conflict ? 409 : 400, {
          code: conflict ? "CONFLICT" : "VALIDATION_ERROR",
          message: conflict ? "Un compte existe déjà avec cet e-mail." : msg,
        }, cors);
      }
      const newId = created.data.user.id;

      const { error: roleError } = await uc.rpc("assign_role", { p_user_id: newId, p_role_code: input.role });
      if (roleError) {
        await admin.auth.admin.deleteUser(newId); // annulation : pas de compte orphelin
        return fail(roleError);
      }
      if (input.phone) {
        await admin.from("profiles").update({ phone: input.phone }).eq("id", newId);
      }

      let agentProfileCreated = false;
      let warning: string | undefined;
      if (input.create_agent_profile) {
        const { error: agentError } = await uc.from("agents").insert({
          profile_id: newId,
          slug: agentSlug(input.full_name, newId),
          display_name: input.full_name,
          public_phone: input.phone,
          whatsapp_phone: input.phone,
        });
        agentProfileCreated = !agentError;
        if (agentError) warning = `Compte créé mais fiche agent non créée : ${agentError.message}`;
      }

      return json({
        data: { user_id: newId, email: input.email, role: input.role, agent_profile_created: agentProfileCreated, warning },
      }, 201, cors);
    }

    case "deactivate":
    case "reactivate": {
      if (!can("users.manage")) {
        return errorResponse(403, { code: "FORBIDDEN", message: "Permission users.manage requise." }, cors);
      }
      const active = input.action === "reactivate";
      const { error: dbError } = await uc.rpc("admin_set_user_active", { p_user_id: input.user_id, p_active: active });
      if (dbError) return fail(dbError);

      const { error: banError } = await admin.auth.admin.updateUserById(input.user_id, {
        ban_duration: active ? "none" : BAN_FOREVER,
      });
      if (banError) {
        // Annulation de l'état en base pour rester cohérent avec Supabase Auth.
        await admin.rpc("admin_set_user_active", { p_user_id: input.user_id, p_active: !active });
        console.error("[admin-users] ban", banError);
        return errorResponse(502, { code: "INTERNAL_ERROR", message: "Échec de la mise à jour du compte d'authentification." }, cors);
      }
      return json({ data: { user_id: input.user_id, is_active: active } }, 200, cors);
    }

    case "send_password_reset": {
      if (!can("users.manage")) {
        return errorResponse(403, { code: "FORBIDDEN", message: "Permission users.manage requise." }, cors);
      }
      const { data: users, error: listError } = await uc.rpc("list_users");
      if (listError) return fail(listError);
      const target = (users as Array<{ id: string; email: string | null; can_manage: boolean }>)
        .find((u) => u.id === input.user_id);
      if (!target) return errorResponse(404, { code: "NOT_FOUND", message: "Utilisateur introuvable." }, cors);
      if (!target.can_manage || !target.email) {
        return errorResponse(403, { code: "FORBIDDEN", message: "Vous ne pouvez pas gérer ce compte." }, cors);
      }
      const { error: resetError } = await anonClient().auth.resetPasswordForEmail(target.email, {
        redirectTo: input.redirect_to ?? undefined,
      });
      if (resetError) {
        console.error("[admin-users] reset", resetError);
        return errorResponse(502, { code: "INTERNAL_ERROR", message: "Envoi de l'e-mail impossible." }, cors);
      }
      return json({ data: { user_id: input.user_id, email_sent: true } }, 202, cors);
    }
  }
});
