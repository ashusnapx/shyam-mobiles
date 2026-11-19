// Growth (docs/GROWTH.md §2a). Pure rules for verified-purchase reviews: who may review, the name shown, and the
// numbers the product page and tiles show.

/** "Ravi Kumar Sharma" → "Ravi S.", "Ravi" → "Ravi", nothing → "Customer". The full name is never published. */
export function reviewerName(fullName: unknown): string {
  const words = typeof fullName === "string" ? fullName.trim().split(/\s+/u).filter(Boolean) : [];
  const first = words[0];
  if (!first) return "Customer";
  const last = words.length > 1 ? Array.from(words.at(-1) ?? "")[0] : undefined;
  return last ? `${first} ${last.toUpperCase()}.` : first;
}

/** The first of the customer's delivered orders that holds [productId]: what makes the review a verified purchase. */
export function verifiedOrder(orders: { id: string; status: unknown; items: unknown }[], productId: string): string | null {
  for (const o of orders) {
    if (o.status !== "delivered" || !Array.isArray(o.items)) continue;
    if (o.items.some((i) => (i as { productId?: unknown }).productId === productId)) return o.id;
  }
  return null;
}

/** Count, sum, the 1★..5★ breakdown and the tile's average × 10 (4.3 → 43, rounded half up) of visible ratings. */
export function ratingStats(ratings: readonly unknown[]): { count: number; sum: number; stars: number[]; avg10: number } {
  const stars = [0, 0, 0, 0, 0];
  let sum = 0;
  for (const r of ratings) {
    if (typeof r !== "number" || !Number.isInteger(r) || r < 1 || r > 5) continue;
    stars[r - 1] = (stars[r - 1] ?? 0) + 1;
    sum += r;
  }
  const count = stars.reduce((a, b) => a + b, 0);
  return { count, sum, stars, avg10: count === 0 ? 0 : Math.floor((sum * 10 * 2 + count) / (count * 2)) };
}
