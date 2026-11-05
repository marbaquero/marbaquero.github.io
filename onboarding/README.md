# Customer onboarding foundation

This folder adds the first secure onboarding workflow for Cuidar a Distancia.

## Important separation

Create a **new Supabase project dedicated to commercial customers**. Do not reuse the Supabase project used by the personal/family-care applications. The GitHub Pages repository is public, so it must contain no service-role key, database password, or private customer records.

## Files

- `index.html`: bilingual customer onboarding page. Customers sign in through an email magic link, complete their profile, and optionally upload files.
- `config.example.js`: example public client configuration. Copy it to `config.js` locally after creating the new Supabase project. Do not commit the real config file if you prefer to keep project identifiers out of the repository; the anon/publishable key is designed for browser use but must always be protected by RLS.
- `schema.sql`: tables, row-level security, and a private Storage bucket.

## Setup steps (owner)

1. Create a new Supabase project for customer onboarding, separate from personal app data.
2. In that project's SQL Editor, run `schema.sql`.
3. In Authentication > URL Configuration, add the published onboarding URL to the allowed redirect URLs.
4. Copy `config.example.js` to `config.js` and enter the new project's Project URL and publishable/anon key.
5. Deploy the site, then test with two separate customer test accounts. Confirm each account can read only its own onboarding record and files.
6. In Supabase Auth, set the owner's user `app_metadata` to include `{"role":"admin"}`. Refresh the owner's session after changing claims. Never set this role in user-editable metadata.
7. Test that an unauthenticated visitor cannot read or upload anything, that a customer cannot access another customer's records, and that the bucket remains private.

## Safety notes

- Never put the Supabase service-role key in browser code or GitHub Pages.
- Keep Storage private. Do not create anonymous read/write policies.
- RLS is the security boundary; the browser's publishable key is not a secret.
- This starter limits uploads to 10 MB and PDF, CSV, Excel, Word, JPEG, and PNG.
- Ask customers to share only records needed for setup. Do not collect passwords, payment-card details, or government ID numbers.
- This is a technical starter, not a legal/compliance certification. Before accepting medical records or other highly sensitive data at scale, review applicable privacy, data-processing, retention, breach-response, and healthcare requirements with qualified counsel and your hosting provider.
- The current form saves onboarding data and private file metadata. A separate authenticated admin dashboard and operational customer provisioning workflow are the next phase; the owner can inspect records through the Supabase dashboard in the meantime.
