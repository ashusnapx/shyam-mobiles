const encoder = new TextEncoder();

export async function hmacSha256Hex(secret: string, data: string | ArrayBuffer): Promise<string> {
  const key = await crypto.subtle.importKey("raw", encoder.encode(secret), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  const sig = new Uint8Array(await crypto.subtle.sign("HMAC", key, typeof data === "string" ? encoder.encode(data) : data));
  return Array.from(sig, (b) => b.toString(16).padStart(2, "0")).join("");
}

// Constant-time for equal lengths; a length mismatch leaks only the length, which is public (64 hex chars).
export function safeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

export async function verifySignature(secret: string, data: string | ArrayBuffer, signature: string): Promise<boolean> {
  return safeEqual(await hmacSha256Hex(secret, data), signature);
}
