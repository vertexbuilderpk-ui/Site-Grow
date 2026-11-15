-- SiteScout Phase 1: foundation (tables + Row Level Security)

-- updated_at helper (trigger only, not callable by users)
create or replace function public.set_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;
revoke all on function public.set_updated_at() from public, anon, authenticated;

-- admins: created only in Supabase, no signup path
create table public.admins (
  user_id uuid primary key references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);
alter table public.admins enable row level security;
create policy admins_select_self on public.admins
  for select to authenticated using ((select auth.uid()) = user_id);

-- projects
create table public.projects (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  brand_name text not null check (length(trim(brand_name)) > 0),
  website text,
  industry text check (industry in ('saas','crypto','casino','igaming','sports')),
  country text,
  competitors text[] not null default '{}',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (id, user_id)
);
create index projects_user_id_idx on public.projects (user_id);
create trigger projects_set_updated_at before update on public.projects
  for each row execute function public.set_updated_at();

-- queries (what customers ask AI)
create table public.queries (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  project_id uuid not null,
  query_text text not null check (length(trim(query_text)) > 0),
  category text,
  sort_order int not null default 0,
  created_at timestamptz not null default now(),
  unique (id, user_id),
  foreign key (project_id, user_id) references public.projects (id, user_id) on delete cascade
);
create index queries_project_idx on public.queries (project_id, user_id);

-- visibility results (one row per query run on a platform)
create table public.visibility_results (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  project_id uuid not null,
  query_id uuid not null,
  platform text not null default 'gemini' check (platform in ('gemini','chatgpt','perplexity')),
  run_at timestamptz not null default now(),
  brand_mentioned boolean not null,
  competitors_mentioned text[] not null default '{}',
  answer_text text,
  unique (id, user_id),
  foreign key (project_id, user_id) references public.projects (id, user_id) on delete cascade,
  foreign key (query_id, user_id) references public.queries (id, user_id) on delete cascade
);
create index visibility_results_project_idx on public.visibility_results (project_id, user_id);
create index visibility_results_query_idx on public.visibility_results (query_id, user_id);
create index visibility_results_user_run_idx on public.visibility_results (user_id, run_at desc);

-- sources (sites the AI cited, plus search results)
create table public.sources (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  project_id uuid not null,
  query_id uuid,
  result_id uuid,
  url text not null,
  domain text not null,
  origin text not null check (origin in ('ai_citation','serp')),
  created_at timestamptz not null default now(),
  foreign key (project_id, user_id) references public.projects (id, user_id) on delete cascade,
  foreign key (query_id, user_id) references public.queries (id, user_id) on delete cascade,
  foreign key (result_id, user_id) references public.visibility_results (id, user_id) on delete cascade
);
create index sources_project_idx on public.sources (project_id, user_id);
create index sources_query_idx on public.sources (query_id, user_id);
create index sources_result_idx on public.sources (result_id, user_id);
create index sources_user_domain_idx on public.sources (user_id, domain);

-- domains (the user's own classified domains)
create table public.domains (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  domain text not null check (length(domain) > 0 and domain = lower(domain)),
  type text not null default 'unclassified'
    check (type in ('unclassified','publisher','client','other','failed')),
  niche text,
  emails text[] not null default '{}',
  contact_page text,
  socials jsonb not null default '{}'::jsonb,
  classified_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id, domain),
  unique (id, user_id)
);
create trigger domains_set_updated_at before update on public.domains
  for each row execute function public.set_updated_at();

-- crm_contacts (one row per domain the user works)
create table public.crm_contacts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  domain_id uuid not null,
  kind text not null check (kind in ('publisher','client')),
  status text not null default 'new'
    check (status in ('new','contacted','replied','negotiating','won','rejected')),
  contact_name text,
  contact_email text,
  deal_type text,
  price numeric(12,2) check (price is null or price >= 0),
  placement_url text,
  last_contact_at timestamptz,
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (id, user_id),
  unique (user_id, domain_id),
  foreign key (domain_id, user_id) references public.domains (id, user_id) on delete cascade
);
create trigger crm_contacts_set_updated_at before update on public.crm_contacts
  for each row execute function public.set_updated_at();

-- crm_events (history of one contact)
create table public.crm_events (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  contact_id uuid not null,
  event_type text not null check (event_type in ('note','status_change','email','call','meeting')),
  old_status text,
  new_status text,
  body text,
  occurred_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  foreign key (contact_id, user_id) references public.crm_contacts (id, user_id) on delete cascade
);
create index crm_events_contact_idx on public.crm_events (contact_id, user_id, occurred_at desc);

-- every status change writes a status event
create or replace function public.log_crm_status_change()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.status is distinct from old.status then
    insert into public.crm_events (user_id, contact_id, event_type, old_status, new_status)
    values (new.user_id, new.id, 'status_change', old.status, new.status);
  end if;
  return new;
end;
$$;
revoke all on function public.log_crm_status_change() from public, anon, authenticated;
create trigger crm_contacts_status_event after update of status on public.crm_contacts
  for each row execute function public.log_crm_status_change();

-- Row Level Security: a user reads and writes only their own rows
do $$
declare t text;
begin
  foreach t in array array['projects','queries','visibility_results','sources','domains','crm_contacts','crm_events'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('create policy %I on public.%I for select to authenticated using ((select auth.uid()) = user_id)', t || '_select_own', t);
    execute format('create policy %I on public.%I for insert to authenticated with check ((select auth.uid()) = user_id)', t || '_insert_own', t);
    execute format('create policy %I on public.%I for update to authenticated using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id)', t || '_update_own', t);
    execute format('create policy %I on public.%I for delete to authenticated using ((select auth.uid()) = user_id)', t || '_delete_own', t);
  end loop;
end
$$;

-- anonymous visitors get nothing
revoke all on all tables in schema public from anon;
alter default privileges in schema public revoke all on tables from anon;
