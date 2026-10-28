# App configuration

`public.json` is the configuration the published app and website are built
with. Everything in it is **meant to be public**: the Supabase URL and its
*publishable* key ship inside every copy of the app anyway, and the database
permissions (see `supabase/migrations`) are what keep data safe.

Never put the Supabase **service role** key, database password, WhatsApp
token or any other secret in this folder.

- `PATIENT_LOGIN`: `password` = patients sign up with email + password
  (temporary). Change to `whatsapp` once WhatsApp login codes are set up
  (see SETUP.md), and switch the password sign-up off in the database:
  `update public.app_settings set password_signup_enabled = false;`
- `example.json`: template for a local `dev.json` (git-ignored).
