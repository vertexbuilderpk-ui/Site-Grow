-- Phase 1 isolation test. Always ends with an exception so everything is rolled back.
-- Expected result (all good):
--   A_status_event=1; A_sees_projects=1; B_sees_* = 0 for all 7 tables;
--   B_insert_project_as_A=blocked; B_query_into_A_project=blocked;
--   B_event_on_A_contact=blocked; B_contact_on_A_domain=blocked;
--   B_update_A_rows=0; B_delete_A_rows=0; anon_read_projects=blocked;
--   A_project_intact=1; A_cascade_leftover_rows=0
do $$
declare
  a uuid := gen_random_uuid();
  b uuid := gen_random_uuid();
  pa uuid; qa uuid; ra uuid; da uuid; ca uuid;
  n int; res text := '';
  t text;
begin
  insert into auth.users (id, aud, role, email) values
    (a,'authenticated','authenticated','a@test.local'),
    (b,'authenticated','authenticated','b@test.local');

  -- user A writes
  perform set_config('request.jwt.claims', json_build_object('sub',a,'role','authenticated')::text, true);
  set local role authenticated;
  insert into public.projects (brand_name, industry, competitors) values ('BrandA','saas','{x,y}') returning id into pa;
  insert into public.queries (project_id, query_text) values (pa,'best crm') returning id into qa;
  insert into public.visibility_results (project_id, query_id, brand_mentioned, competitors_mentioned) values (pa,qa,false,'{x}') returning id into ra;
  insert into public.sources (project_id, query_id, result_id, url, domain, origin) values (pa,qa,ra,'https://blog.example.com/p','blog.example.com','ai_citation');
  insert into public.domains (domain, type) values ('blog.example.com','publisher') returning id into da;
  insert into public.crm_contacts (domain_id, kind) values (da,'publisher') returning id into ca;
  update public.crm_contacts set status='contacted' where id=ca;
  select count(*) into n from public.crm_events where contact_id=ca and event_type='status_change' and old_status='new' and new_status='contacted';
  res := res || 'A_status_event=' || n || '; ';
  select count(*) into n from public.projects;
  res := res || 'A_sees_projects=' || n || '; ';

  -- user B
  reset role;
  perform set_config('request.jwt.claims', json_build_object('sub',b,'role','authenticated')::text, true);
  set local role authenticated;
  foreach t in array array['projects','queries','visibility_results','sources','domains','crm_contacts','crm_events'] loop
    execute format('select count(*) from public.%I', t) into n;
    res := res || 'B_sees_' || t || '=' || n || '; ';
  end loop;

  begin
    insert into public.projects (user_id, brand_name) values (a,'hack');
    res := res || 'B_insert_project_as_A=ALLOWED(BAD); ';
  exception when others then res := res || 'B_insert_project_as_A=blocked; ';
  end;
  begin
    insert into public.queries (project_id, query_text) values (pa,'x');
    res := res || 'B_query_into_A_project=ALLOWED(BAD); ';
  exception when others then res := res || 'B_query_into_A_project=blocked; ';
  end;
  begin
    insert into public.crm_events (contact_id, event_type, body) values (ca,'note','x');
    res := res || 'B_event_on_A_contact=ALLOWED(BAD); ';
  exception when others then res := res || 'B_event_on_A_contact=blocked; ';
  end;
  begin
    insert into public.crm_contacts (domain_id, kind) values (da,'publisher');
    res := res || 'B_contact_on_A_domain=ALLOWED(BAD); ';
  exception when others then res := res || 'B_contact_on_A_domain=blocked; ';
  end;
  update public.projects set brand_name='pwn' where id=pa;
  get diagnostics n = row_count;
  res := res || 'B_update_A_rows=' || n || '; ';
  delete from public.projects where id=pa;
  get diagnostics n = row_count;
  res := res || 'B_delete_A_rows=' || n || '; ';

  -- anonymous
  reset role;
  set local role anon;
  begin
    perform 1 from public.projects;
    res := res || 'anon_read_projects=ALLOWED(BAD); ';
  exception when others then res := res || 'anon_read_projects=blocked; ';
  end;

  -- A again: data intact, cascade delete works
  reset role;
  perform set_config('request.jwt.claims', json_build_object('sub',a,'role','authenticated')::text, true);
  set local role authenticated;
  select count(*) into n from public.projects where id=pa and brand_name='BrandA';
  res := res || 'A_project_intact=' || n || '; ';
  delete from public.projects where id=pa;
  select (select count(*) from public.queries) + (select count(*) from public.visibility_results) + (select count(*) from public.sources) into n;
  res := res || 'A_cascade_leftover_rows=' || n || '; ';

  reset role;
  raise exception 'RESULT: %', res;
end
$$;
