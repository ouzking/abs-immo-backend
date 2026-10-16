// POST /functions/v1/submit-viewing-request — demande de visite depuis le site public.
// Contrat : docs/INTEGRATION_CONTRACT.md § « Formulaires publics ».
import { servePublicForm } from "../_shared/public-form.ts";
import { validateViewingRequest } from "../_shared/validation.ts";

Deno.serve(servePublicForm({
  validate: (body) => validateViewingRequest(body),
  rpc: "submit_viewing_request",
  idKey: "viewing_request_id",
  toParams: (d, ipHash, meta) => ({
    p_full_name: d.full_name,
    p_property_id: d.property_id,
    p_email: d.email,
    p_phone: d.phone,
    p_preferred_date: d.preferred_date,
    p_preferred_time_slot: d.preferred_time_slot,
    p_alternative_date: d.alternative_date,
    p_message: d.message,
    p_preferred_contact: d.preferred_contact,
    p_consent_marketing: d.consent_marketing,
    p_ip_hash: ipHash,
    p_submission_meta: meta,
  }),
}));
