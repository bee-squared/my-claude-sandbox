create type public.list_role as enum ('viewer', 'editor', 'owner');

create type public.status_behavior as enum (
  'backlog', 'todo', 'in_progress', 'blocked', 'in_review', 'completed', 'cancelled'
);
