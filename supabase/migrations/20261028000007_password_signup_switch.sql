-- On/off switch for the temporary email + password patient sign-up
-- (used until WhatsApp login codes are set up). Platform admins can flip it.
alter table public.app_settings
  add column password_signup_enabled boolean not null default false;
