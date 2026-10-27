create or replace function public.is_terminal(b public.status_behavior)
returns boolean
language sql
immutable
set search_path = ''
as $$
  select b in ('completed'::public.status_behavior, 'cancelled'::public.status_behavior);
$$;

revoke execute on function public.is_terminal(public.status_behavior) from public, anon;
grant execute on function public.is_terminal(public.status_behavior) to authenticated;
