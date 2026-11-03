import { z } from "zod";
import { contract } from "../shared/callable.js";

export const health = contract("health", z.strictObject({}), z.object({ ok: z.literal(true), region: z.string(), at: z.string() }));
