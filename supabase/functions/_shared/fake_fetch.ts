// Test helper: replaces globalThis.fetch with canned Razorpay replies and records each call.
export type Call = { method: string; url: string; headers: Headers; body: unknown };

export function fakeFetch(reply: (call: Call) => Response | Promise<Response>) {
  const calls: Call[] = [];
  const real = globalThis.fetch;
  Deno.env.set("RAZORPAY_KEY_ID", "rzp_test_fake");
  Deno.env.set("RAZORPAY_KEY_SECRET", "secret_fake");
  globalThis.fetch = async (input: string | URL | Request, init?: RequestInit) => {
    const call = {
      method: init?.method ?? "GET",
      url: String(input),
      headers: new Headers(init?.headers),
      body: init?.body ? JSON.parse(String(init.body)) : undefined,
    };
    calls.push(call);
    return await reply(call);
  };
  return { calls, restore: () => (globalThis.fetch = real) };
}

export const ok = (body: unknown) => Response.json(body);
export const refused = (status: number, description: string) =>
  Response.json({ error: { code: "BAD_REQUEST_ERROR", description } }, { status });
