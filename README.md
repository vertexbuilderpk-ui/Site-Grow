# SiteScout

Find out why AI platforms don't recommend a brand, find the websites the AI learns from, and run outreach to get placements. Then re-check visibility and prove the change.

## Core flow

1. Brand setup
2. Queries (what customers ask AI)
3. AI visibility check (Gemini, via the browser extension)
4. Gaps (competitor appears, brand does not)
5. Sources (websites the AI cited)
6. Classify (Publisher / Client / Other)
7. Outreach CRM (New, Contacted, Replied, Negotiating, Won, Rejected)
8. Placement won
9. Re-check visibility
10. Before/after report

## Architecture

- **Extension (Chrome):** runs Gemini in the user's own browser, plus Google SERP. No paid AI API is used.
- **Backend:** Supabase (Postgres, Auth, Row Level Security).
- **Dashboard (web):** gaps, CRM, pipeline, reports. Hosted on Vercel.

## Rules

- Every user sees only their own data (Row Level Security on every user table).
- CRM data lives in its own tables, never inside the synced snapshot.
- Shared layer (later phase) holds domain-level facts only. No user, project or query information.

## Repo layout

```
docs/                 plans and specs
supabase/migrations/  database migrations (applied in filename order)
supabase/tests/       SQL tests (rolled back after running)
extension/            Chrome extension (planned)
dashboard/            web dashboard (planned)
```

## Status

- Phase 1 (database foundation): done and tested.
- Next: Phase 2 (extension research engine and sync).
