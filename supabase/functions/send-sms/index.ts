import { env } from "../_shared/http.ts";
import { handleSendSms } from "./handler.ts";
import { msg91Sender } from "./msg91.ts";

const send = msg91Sender(env("MSG91_AUTH_KEY"), env("MSG91_TEMPLATE_ID"));

// verify_jwt = false (config.toml): Auth calls this hook and signs it with SEND_SMS_HOOK_SECRET instead.
Deno.serve((req) => handleSendSms(req, env("SEND_SMS_HOOK_SECRET"), send));
