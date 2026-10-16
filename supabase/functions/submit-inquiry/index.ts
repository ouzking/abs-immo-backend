// POST /functions/v1/submit-inquiry — demande de renseignement depuis le site public.
// Contrat : docs/INTEGRATION_CONTRACT.md § « Formulaires publics ».
import { servePublicForm } from "../_shared/public-form.ts";
import { validateInquiry } from "../_shared/validation.ts";

Deno.serve(servePublicForm({
  validate: validateInquiry,
  rpc: "submit_inquiry",
  idKey: "inquiry_id",
  toParams: (d, ipHash, meta) => ({
    p_full_name: d.full_name,
    p_email: d.email,
    p_phone: d.phone,
    p_message: d.message,
    p_property_id: d.property_id,
    p_inquiry_type: d.inquiry_type,
    p_preferred_contact: d.preferred_contact,
    p_consent_marketing: d.consent_marketing,
    p_ip_hash: ipHash,
    p_submission_meta: meta,
  }),
}));
