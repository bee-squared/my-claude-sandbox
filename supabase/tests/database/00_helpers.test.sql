create extension if not exists pgtap with schema extensions;
create schema if not exists tests;
grant usage on schema tests to authenticated;

create or replace function tests.create_user(email text, display_name text default null)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  uid uuid := gen_random_uuid();
begin
  insert into auth.users (id, instance_id, aud, role, email, raw_user_meta_data)
  values (
    uid,
    '00000000-0000-0000-0000-000000000000',
    'authenticated',
    'authenticated',
    email,
    case when display_name is null then '{}'::jsonb
         else jsonb_build_object('display_name', display_name) end
  );
  return uid;
end;
$$;

create or replace function tests.user_id(email text)
returns uuid
language sql
security definer
set search_path = ''
as $$
  select u.id from auth.users u where u.email = $1;
$$;

create or replace function tests.authenticate_as(email text)
returns void
language plpgsql
set search_path = ''
as $$
begin
  perform set_config(
    'request.jwt.claims',
    jsonb_build_object('sub', tests.user_id(email), 'role', 'authenticated')::text,
    true);
  perform set_config('role', 'authenticated', true);
end;
$$;

create or replace function tests.clear_authentication()
returns void
language plpgsql
set search_path = ''
as $$
begin
  perform set_config('request.jwt.claims', '', true);
  perform set_config('role', 'postgres', true);
end;
$$;

create or replace function tests.list_id(list_name text)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  ids uuid[];
begin
  select array_agg(id) into ids from public.lists where name = list_name;
  if coalesce(array_length(ids, 1), 0) <> 1 then
    raise exception 'tests.list_id: % lists named %', coalesce(array_length(ids, 1), 0), list_name;
  end if;
  return ids[1];
end;
$$;

create or replace function tests.status_id(status_label text)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  ids uuid[];
begin
  select array_agg(id) into ids from public.task_statuses where label = status_label;
  if coalesce(array_length(ids, 1), 0) <> 1 then
    raise exception 'tests.status_id: % statuses labelled %', coalesce(array_length(ids, 1), 0), status_label;
  end if;
  return ids[1];
end;
$$;

create or replace function tests.task_id(task_title text)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  ids uuid[];
begin
  select array_agg(id) into ids from public.tasks where title = task_title;
  if coalesce(array_length(ids, 1), 0) <> 1 then
    raise exception 'tests.task_id: % tasks titled %', coalesce(array_length(ids, 1), 0), task_title;
  end if;
  return ids[1];
end;
$$;

grant execute on all functions in schema tests to authenticated;

select plan(1);
select ok(tests.user_id('nobody@test') is null, 'helpers loaded');
select * from finish();
