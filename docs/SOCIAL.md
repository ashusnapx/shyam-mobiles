# Facebook and Instagram

The backend's `social` domain (`firebase/functions/src/social/`) does two things:

1. **The Instagram strip in the app.** `socialHourly` runs every 60 minutes in asia-south1. It fetches the shop's
   latest 12 posts and writes them to `social/instagram`, which anyone can read:

   ```
   social/instagram = {
     posts: [{ id, mediaUrl, thumbUrl, permalink, caption, mediaType, takenAt }],  // newest first, at most 12
     updatedAt
   }
   ```

   `thumbUrl` is the video's thumbnail for a video, otherwise the image itself. `mediaUrl` is null when Instagram leaves
   it out (some videos with licensed music). `caption` is cut to 200 characters. `mediaType` is `IMAGE`, `VIDEO` or
   `CAROUSEL_ALBUM`. `takenAt` and `updatedAt` are timestamps. Posts with nothing to show are skipped.
2. **Posting offers.** When a banner goes live (a staff banner, or the banner `savePromotion` makes for a promotion
   with "show banner" on), `autoPostBanner` posts its photo to the shop's Facebook Page and to Instagram with the
   caption `<headline> · <offer line> · Shop on the Shyam Mobiles app`. That is the banner's title and subtitle.
   - It is **off** until staff set `settings/social.autoPost` to true.
   - Each banner is posted **once**. `socialPosts/{bannerId}` records the Facebook post id and the Instagram media id.
     If one network fails, the next try posts only to the network that failed.
   - A failed post is tried again by `socialHourly`, **at most 3 attempts** in all. The reason is kept in
     `socialPosts/{bannerId}.lastError`, and staff can read that doc.
   - A banner scheduled for later is posted within an hour of its start time. Turning auto-post on posts every banner
     that is live at that moment, each one once.

## Photos must be JPEG

Instagram accepts only JPEG ("JPEG is the only image format supported", content publishing docs). Facebook's list
doesn't include WebP either. The admin app uploads banner photos as **WebP**, so it also uploads a JPEG copy and
stores its Storage key (under `product-images/`) on the banner as `socialImagePath`. Auto-post uses that copy when
it's there, otherwise `imagePath` if that is a `.jpg`. A banner with neither is skipped (`social auto-post …
outcome: "not jpeg"` in the logs).

## Where the tokens live

- `INSTAGRAM_TOKEN` (Secret Manager): the first long-lived Instagram token, which you set once.
- `FB_PAGE_TOKEN` (Secret Manager): the Page access token. A long-lived Page token has no expiry date.
- `FB_PAGE_ID` (plain param, optional): the Page id. When it's left unset, posts go to `me`, which is the Page the
  Page token belongs to.
- An Instagram token lasts 60 days. `socialHourly` refreshes it every 7 days with `refresh_access_token` (Meta
  refuses tokens under 24 hours old) and stores the new one in Firestore at **`private/instagramToken`**.
  - **Why not Secret Manager:** adding a secret version from a function needs an extra IAM grant
    (`secretmanager.secretVersionAdder`) on the runtime service account, and every version is billed. The Firestore
    doc is closed by the Rules to every client, staff included (nothing in `firestore.rules` opens `private/*`). Only
    the Admin SDK can read it.
  - **What that costs:** anyone with Firestore access in the Google Cloud console or a Firestore export can read it.
    Keep both of those limited to the owner.
- The stored token remembers which `INSTAGRAM_TOKEN` it came from. If you ever set `INSTAGRAM_TOKEN` again (say,
  the token died because the functions were off for more than 60 days), the new secret takes over on the next run.
- Meta's error messages go to the logs. Tokens and URLs never do.
- The Meta app ID and app secret aren't needed. Nothing the functions call asks for them, so they aren't secrets
  here. The dashboard's "Generate token" already gives a long-lived Instagram token.

## Owner setup

You need the Firebase project on the **Blaze** plan. Cloud Functions, Secret Manager and Cloud Scheduler all require
it (docs/FIREBASE.md, "Upgrade to Blaze"). Pricing: https://firebase.google.com/pricing

1. **Make the shop's Instagram a Professional (Business) account.** In the Instagram app, go to Profile → menu →
   Settings and activity → For professionals: Account type and tools → Switch to professional account. Pick a
   category, then pick **Business**. Help page: https://help.instagram.com/502981923235522
2. **Link Instagram to the shop's Facebook Page.** On a computer, open Facebook and switch to the Page (profile
   photo → See all profiles → the Page). Then go to the Page's profile photo → Settings & privacy → Settings →
   Permissions: Linked accounts → Instagram → Connect account. Help page:
   https://www.facebook.com/help/1148909221857370
3. **Create the Meta developer app.** Go to https://developers.facebook.com/apps → Create app. Pick the use case
   **Other**, then the app type **Business**. Your Facebook account becomes the app's admin.
4. **Add the Instagram product.** In the app dashboard, add **Instagram**. Then open Instagram → **API setup with
   Instagram business login** in the left menu.
5. **Add the shop's Instagram account to the app.** On that page, under "Generate access tokens", add the account and
   log in to Instagram when asked. The account must be public. To manage it later, use App roles → Roles, or the same
   page.
6. **Generate the long-lived Instagram token.** Click **Generate token** next to the account, log in, and copy the
   token. It lasts 60 days, and the functions keep it fresh from then on.
7. **Get the Page token.**
   - Open the Graph API Explorer: https://developers.facebook.com/tools/explorer/
   - Pick your app, and request a User token with `pages_show_list`, `pages_read_engagement` and `pages_manage_posts`.
   - Paste that token into the Access Token Debugger (https://developers.facebook.com/tools/debug/accesstoken/) and
     click **Extend Access Token**.
   - Back in the Explorer, use the extended token to run `GET me/accounts`. Copy the shop Page's `access_token`
     (that's the Page token) and its `id`.
   - In the Debugger, the Page token should say "Expires: Never".
8. **Store the secrets.** Run these from `firebase/`, or from Cloud Shell. Each command asks for the value and hides
   it as you type:

   ```sh
   firebase functions:secrets:set INSTAGRAM_TOKEN --project shyam-mobiles
   firebase functions:secrets:set FB_PAGE_TOKEN --project shyam-mobiles
   ```

   Never paste a token into chat, an issue, a commit or any file in this repo. **The repo is public.**
9. **Optional: pin the Page id.** Give the deploy `FB_PAGE_ID=<the Page id>` in `firebase/functions/.env.shyam-mobiles`
   (gitignored), or leave it unset to post as the token's Page.
10. **Deploy through CI** (firebase/README.md). `social/instagram` fills within the hour.
11. **Turn auto-post on when you want it.** In the Firebase console's Firestore, create `settings/social` with
    `autoPost: true` (boolean) and `updatedAt` (timestamp). Set it to false to stop.

If the Page token stops working (a password change, a lost Page role, or the app removed), repeat step 7 and step 8
for `FB_PAGE_TOKEN`. If the Instagram token dies, repeat steps 6 and 8 for `INSTAGRAM_TOKEN`.

## Meta app review

**None is expected.** Keep the app in **Development** mode and use it only with the shop's own accounts, which have a
role on the app:

- Development mode "can only request permissions from role users", and only permissions with standard or advanced
  access: https://developers.facebook.com/docs/development/build-and-test/app-modes
- Standard Access is for "Instagram professional accounts you own or manage":
  https://developers.facebook.com/docs/instagram-platform/instagram-api-with-instagram-login/business-login

There is one caveat. Meta's app-setup page also says "Instagram requires successful completion of the App Review
process before your app can access live data"
(https://developers.facebook.com/docs/instagram-platform/create-an-instagram-app). If a call ever fails with a
permission error, submit App Review for `instagram_business_basic`, `instagram_business_content_publish` and
`pages_manage_posts`. Don't switch the app to Live without that review.

## Limits and references

- Instagram allows 100 API-published posts per account in any 24 hours. A shop's banners never get close.
- Endpoints (Graph API v27.0, 4 Nov 2026, https://developers.facebook.com/docs/graph-api/changelog):
  - `GET graph.instagram.com/v27.0/me/media`
  - `GET graph.instagram.com/refresh_access_token`
  - `GET graph.instagram.com/v27.0/me?fields=user_id`
  - `POST graph.instagram.com/v27.0/{ig-id}/media`
  - `POST graph.instagram.com/v27.0/{ig-id}/media_publish`
  - `POST graph.facebook.com/v27.0/{page-id}/photos` (`url`, `caption`)
- Docs:
  - https://developers.facebook.com/docs/instagram-platform/content-publishing
  - https://developers.facebook.com/docs/instagram-platform/reference/instagram-media
  - https://developers.facebook.com/docs/graph-api/reference/page/photos/
  - https://developers.facebook.com/docs/facebook-login/guides/access-tokens/get-long-lived
