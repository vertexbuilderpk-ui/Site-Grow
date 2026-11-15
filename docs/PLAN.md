# SiteScout plan (v2: Gemini only, no paid APIs)

## Product in one line
Find why AI doesn't recommend a brand, find the sites AI learns from, reach out to them, then re-check visibility and show the improvement.

## Who does what
- Extension (user's browser): Gemini visibility check, sources, classification, Google SERP.
- Dashboard (web): gaps, CRM, pipeline, reports. Needs no Gemini.
- Supabase: auth, data, Row Level Security.

## Known risks of running Gemini through its web UI
- Page changes break selectors: keep selectors in one file, add a health check, fix fast.
- Rate limits / captcha: random delays, batch limits, pause and resume.
- User must be signed in to Gemini.
- Answers vary: run each query 2-3 times and show trends.
- Google ToS risk: distribute by zip first, get legal advice before store listing.
- No server-side scheduled re-checks (browser must be open).

## Phases
1. Foundation: auth, RLS, tables. DONE
2. Extension research engine: setup, queries, visibility (Gemini), sources, classify, stepper
3. Gaps page + shared domain layer (domain-level facts only)
4. CRM + pipeline
5. Re-check + before/after report
6. Billing and limits
7. Launch hardening: email confirmation, leaked-password protection, rate limits, privacy/terms, backups
8. Admin (aggregates) + more AI platforms

## Open decisions
1. Meaning of "Client": Client-type websites, or paying customers (brands)?
2. Admin access to private user data: none, aggregates only, or with user permission?
3. First target user: agencies or single brand owners?
4. Distribution: zip first, or Chrome Web Store?
