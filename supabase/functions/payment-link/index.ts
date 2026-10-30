import { handler, readJson } from "../_shared/http.ts";
import { requireAdmin, rpcOf } from "../_shared/supabase.ts";
import { type Link, type LinkStore, paymentLink } from "./handler.ts";

Deno.serve(handler(async (req) => {
  const { userId, db } = await requireAdmin(req);
  const links = () => db.from("payment_links");
  const store: LinkStore = {
    rpc: rpcOf(db),
    async get(id) {
      const { data, error } = await links().select("*").eq("id", id).maybeSingle();
      if (error) throw error;
      return data as Link | null;
    },
    async saved(id, razorpayLinkId, shortUrl) {
      const { error } = await links().update({ razorpay_link_id: razorpayLinkId, short_url: shortUrl }).eq("id", id);
      if (error) throw error;
    },
    async remove(id) {
      const { error } = await links().delete().eq("id", id).is("razorpay_link_id", null);
      if (error) console.error("payment-link cleanup:", error);
    },
  };
  return await paymentLink(await readJson(req), userId, store);
}));
