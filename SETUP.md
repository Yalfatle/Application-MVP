# Setting up Mukhtabarat

This walks through everything needed to go from this repo to a working app.
Do the steps in order. Nothing here costs money until you have real users,
except a WhatsApp Business number (Meta charges per conversation).

---

## 1. Supabase (database, accounts, files)

1. Create a project at [supabase.com](https://supabase.com). Region: **Frankfurt
   (eu-central-1)**, the closest to Iraq.
2. Install the [Supabase CLI](https://supabase.com/docs/guides/cli), then from
   the repo root:
   ```bash
   supabase login
   supabase link --project-ref YOUR_PROJECT_REF
   supabase db push          # creates every table, permission and function
   ```
3. Make yourself and your brother **super admins**. Sign in to the app once
   (so the accounts exist), then in Supabase → SQL editor:
   ```sql
   update public.profiles set role = 'super_admin', lab_id = null
   where id in (select id from auth.users where email in ('you@example.com', 'brother@example.com')
                                         or phone in ('9647700000000'));
   ```
   This is the **only** way to become a super admin. Nothing in the app can grant it.

4. Authentication settings (Dashboard → Authentication):
   - **Providers → Phone**: enable. (Leave the SMS provider unset; the WhatsApp hook in step 3 replaces it.)
   - **Providers → Email**: enable (staff can sign in with email + password).
     Staff accounts are only ever created through invite links.
   - **URL configuration → Site URL**: the address of the admin website (step 4).

## 2. WhatsApp Business (login codes, order updates, messages)

Your brother should own this account, since it's tied to the business.

1. In [Meta for Developers](https://developers.facebook.com/), create an app of
   type **Business**, add the **WhatsApp** product, and register the platform's
   phone number.
2. Create a **permanent access token** (System user → generate token with
   `whatsapp_business_messaging`).
3. Get these templates approved (WhatsApp Manager → Message templates), each in
   **Arabic (ar)** and **English (en)**:

   | Name | Category | Body |
   |---|---|---|
   | `login_code` | Authentication | (Meta's standard code template, with a "Copy code" button) |
   | `order_update` | Utility | `{{1}} {{2}}.` e.g. "مختبر النور قبل حجزك." |
   | `new_lab_message` | Utility | `You have a new message from {{1}}. Open the app to read and reply.` |

   Why templates: WhatsApp only lets a business send free text within 24 hours
   of the patient's last message. Outside that window it must use an approved
   template. The backend picks the right one automatically.

## 3. Backend functions

Set the secrets (use your own values):

```bash
supabase secrets set \
  WA_PHONE_NUMBER_ID=123456789 \
  WA_ACCESS_TOKEN=EAAG... \
  WA_APP_SECRET=abc123... \
  WA_VERIFY_TOKEN=pick-any-long-random-string \
  DISPATCH_SECRET=another-long-random-string \
  SEND_SMS_HOOK_SECRET="v1,whsec_..."      # from step 3c below
```

Deploy:

```bash
supabase functions deploy redeem-invite      --no-verify-jwt
supabase functions deploy auth-send-sms      --no-verify-jwt
supabase functions deploy whatsapp-dispatch  --no-verify-jwt
supabase functions deploy whatsapp-webhook   --no-verify-jwt
```

(Each function checks its own secret or signature, so Supabase's own token check is turned off.)

Then:

a. **Let the database wake the dispatcher.** SQL editor:
   ```sql
   select vault.create_secret('https://YOUR_PROJECT_REF.supabase.co', 'project_url');
   select vault.create_secret('another-long-random-string', 'dispatch_secret'); -- same as DISPATCH_SECRET
   ```

b. **Receive patient replies.** In Meta → WhatsApp → Configuration → Webhook:
   callback URL `https://YOUR_PROJECT_REF.supabase.co/functions/v1/whatsapp-webhook`,
   verify token = `WA_VERIFY_TOKEN`, subscribe to **messages**.

c. **Send login codes on WhatsApp.** Supabase → Authentication → Hooks →
   **Send SMS hook** → HTTPS → URL
   `https://YOUR_PROJECT_REF.supabase.co/functions/v1/auth-send-sms`.
   Copy the generated secret into `SEND_SMS_HOOK_SECRET` and redeploy that function.

## 4. The app

Create `app/config/prod.json` (never commit it; it's git-ignored):

```json
{
  "SUPABASE_URL": "https://YOUR_PROJECT_REF.supabase.co",
  "SUPABASE_ANON_KEY": "your publishable key from Project Settings → API",
  "ADMIN_WEB_URL": "https://admin.your-domain.com"
}
```

Create `app/android/secrets.properties` (also git-ignored):

```
MAPS_API_KEY=AIza...   # restricted to com.mukhtabarat.app + your signing SHA-1
```

**Android app (patients and runners):**
```bash
cd app
flutter build appbundle --release --dart-define-from-file=config/prod.json
```

**Admin website (lab owners, clerks, you):**
```bash
flutter build web --release --dart-define-from-file=config/prod.json
```
Upload `app/build/web` to any static host (Cloudflare Pages, Netlify, Firebase
Hosting, all free). Point `ADMIN_WEB_URL` at it; invite links use that address.

**Before publishing to Google Play**, create a real release signing key
(the build currently signs release builds with the debug key). See
<https://docs.flutter.dev/deployment/android#signing-the-app>.

## 5. First run

1. Sign in on the website as a super admin → **All labs → Add lab**.
2. Open the lab → **Employees → Invite lab owner** → send the link to the owner
   on WhatsApp. It works for 1 hour, for one account.
3. The owner signs in, fills in **Lab details**, adds **Tests & prices**, and
   invites runners and clerks the same way.
4. Patients install the Android app, sign in with their number, and book.

---

## How it fits together

- **Roles** are enforced inside the database, not just hidden in the app. Even
  a modified app can't read another lab's patients or change its own role.
  `supabase/tests/permissions_test.py` checks this (136 checks, run on every push).
- **Patient numbers are never shown to labs.** Staff message patients from the
  app; it goes out from the platform's WhatsApp number. Replies come back into
  the lab's inbox.
- **Weak connections:** labs, tests and bookings are cached on the phone. A
  booking made with no signal is saved and sent automatically when the
  connection returns, and can never be sent twice.
- **Live tracking** only runs while the runner's order is "on the way", and
  stops the moment the sample is collected.
- **Commission:** 15% by default, changeable in Platform settings, and can be
  set per lab. Each order keeps the rate it was booked at.
- **Medical files** live in a private bucket and open through links that expire
  after 10 minutes. Deleting a document hides it; super admins can still recover it.
