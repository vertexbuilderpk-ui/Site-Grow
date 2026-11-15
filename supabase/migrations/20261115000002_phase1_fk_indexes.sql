create index crm_contacts_domain_idx on public.crm_contacts (domain_id, user_id);
create index crm_events_user_id_idx on public.crm_events (user_id);
create index queries_user_id_idx on public.queries (user_id);
