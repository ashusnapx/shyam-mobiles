// Error contract: {"error": "CODE", "message": "short human text"} with a matching status.
export class HttpError extends Error {
  status: number;
  code: string;
  constructor(status: number, code: string, message: string) {
    super(message);
    this.status = status;
    this.code = code;
  }
}

export const json = (body: unknown, status = 200) => Response.json(body, { status });

export const fail = (status: number, code: string, message: string) => json({ error: code, message }, status);

// POST only; HttpError -> its status, anything else -> 500 (logged).
export function handler(fn: (req: Request) => Promise<Response>) {
  return async (req: Request): Promise<Response> => {
    if (req.method !== "POST") return fail(405, "METHOD_NOT_ALLOWED", "Use POST.");
    try {
      return await fn(req);
    } catch (e) {
      if (e instanceof HttpError) return fail(e.status, e.code, e.message);
      console.error(e);
      return fail(500, "INTERNAL", "Something went wrong. Try again.");
    }
  };
}

export async function readJson(req: Request): Promise<Record<string, unknown>> {
  const body = await req.json().catch(() => null);
  if (!body || typeof body !== "object" || Array.isArray(body)) {
    throw new HttpError(400, "BAD_REQUEST", "Body must be a JSON object.");
  }
  return body;
}

export function env(name: string): string {
  const value = Deno.env.get(name);
  if (!value) throw new Error(`Missing secret ${name}`);
  return value;
}

export const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
