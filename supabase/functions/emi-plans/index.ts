import { handler } from "../_shared/http.ts";
import { emiPlans } from "./handler.ts";

// verify_jwt = false (config.toml): EMI plans are public, and the product page shows them signed out too.
Deno.serve(handler(() => emiPlans()));
