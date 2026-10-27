begin;
select plan(26);

select tests.create_user('ann@test');
select tests.create_user('vi@test');
select tests.create_user('st@test');
select tests.create_user('dan@test');

-- as postgres: lists owned by ann
insert into public.lists(name, owner_id) values
  ('Home', tests.user_id('ann@test')),
  ('Work', tests.user_id('ann@test'));
insert into public.list_members(list_id, user_id, role) values
  (tests.list_id('Home'), tests.user_id('vi@test'), 'viewer');

select tests.authenticate_as('ann@test');
insert into public.task_statuses(owner_id, label, behavior) values
  (tests.user_id('ann@test'), 'Shipped', 'completed'),
  (tests.user_id('ann@test'), 'Waiting for parts', 'blocked'),
  (tests.user_id('ann@test'), 'Unused', 'todo');
insert into public.tasks(list_id, title) values (tests.list_id('Home'), 'T');

select results_eq($$select from_behavior::text, to_behavior::text from public.task_status_events where task_id = tests.task_id('T')$$,
  $$values (null::text, 'todo'::text)$$, 'insert writes one creation event');
update public.tasks set status_id = tests.status_id('Shipped') where title = 'T';
select isnt((select completed_at from public.tasks where title = 'T'), null, 'custom completed-like status sets completed_at');
select tests.clear_authentication();
update public.tasks set completed_at = '2000-01-01' where title = 'T';
select tests.authenticate_as('ann@test');
update public.tasks set status_id = tests.status_id('Cancelled') where title = 'T';
select is((select completed_at from public.tasks where title = 'T'), '2000-01-01'::timestamptz, 'terminal to terminal keeps completed_at');
update public.tasks set status_id = tests.status_id('To Do') where title = 'T';
select is((select completed_at from public.tasks where title = 'T'), null, 'back to To Do clears completed_at');
update public.tasks set status_id = tests.status_id('Blocked'), blocked_reason = 'parts' where title = 'T';
update public.tasks set status_id = tests.status_id('Waiting for parts') where title = 'T';
select is((select blocked_reason from public.tasks where title = 'T'), 'parts', 'blocked to blocked keeps reason');
update public.tasks set status_id = tests.status_id('In Progress') where title = 'T';
select is((select blocked_reason from public.tasks where title = 'T'), null, 'leaving blocked clears reason');
select is((select count(*) from public.task_status_events where task_id = tests.task_id('T')), 7::bigint, 'one event per change');
select results_eq($$select from_behavior::text, to_behavior::text from public.task_status_events
  where task_id = tests.task_id('T') order by id desc limit 1$$, $$values ('blocked','in_progress')$$, 'event snapshots behaviours');
select tests.clear_authentication();
update public.tasks set status_changed_at = '2000-01-01' where title = 'T';
select tests.authenticate_as('ann@test');
update public.tasks set status_id = status_id where title = 'T';
select is((select count(*) from public.task_status_events where task_id = tests.task_id('T')), 7::bigint, 'no-op status write: no event');
select is((select status_changed_at from public.tasks where title = 'T'), '2000-01-01'::timestamptz, 'no-op keeps status_changed_at');
update public.tasks set list_id = tests.list_id('Work') where title = 'T';
select is((select count(*) from public.task_status_events where task_id = tests.task_id('T')), 7::bigint, 'list move without status change: no event');
select throws_ok($$insert into public.task_status_events(task_id,to_status_id,to_behavior) values (tests.task_id('T'),tests.status_id('To Do'),'todo')$$, '42501', null, 'clients cannot insert events');
select throws_ok($$update public.task_status_events set to_behavior = 'todo'$$, '42501', null, 'clients cannot update events');
select throws_ok($$delete from public.task_status_events$$, '42501', null, 'clients cannot delete events');
update public.tasks set status_id = tests.status_id('Shipped') where title = 'T';
select throws_ok($$update public.task_statuses set behavior = 'todo' where label = 'Shipped'$$, 'P0001', 'status behavior cannot change while tasks use it');
select lives_ok($$update public.task_statuses set label = 'Shipped!' where label = 'Shipped'$$, 'label can change while used');
update public.tasks set status_id = tests.status_id('To Do') where title = 'T';
select throws_ok($$delete from public.task_statuses where label = 'Shipped!'$$, '23503', null, 'ever-used status cannot be hard-deleted');
select lives_ok($$update public.task_statuses set archived_at = now() where label = 'Shipped!'$$, 'used status can be archived');
select lives_ok($$delete from public.task_statuses where label = 'Unused'$$, 'never-used status can be deleted');
update public.tasks set list_id = tests.list_id('Home') where title = 'T';
insert into public.tasks(list_id, title, status_id) values (tests.list_id('Work'), 'W', tests.status_id('Waiting for parts'));
select tests.clear_authentication();

select tests.authenticate_as('vi@test');
select isnt_empty($$select 1 from public.task_status_events$$, 'viewer reads the list''s events');
select tests.clear_authentication();

select tests.authenticate_as('st@test');
select is_empty($$select 1 from public.task_status_events$$, 'non-member reads no events');
select tests.clear_authentication();

select tests.task_id('T') as t_id, tests.list_id('Home') as home_id \gset
delete from public.lists where id = :'home_id';
select is_empty(format('select 1 from public.task_status_events where task_id = %L', :'t_id'), 'deleting a list removes its tasks'' events');
select is_empty(format('select 1 from public.list_members where list_id = %L', :'home_id'), 'deleting a list removes its memberships');
select lives_ok($$delete from auth.users where id = tests.user_id('ann@test')$$, 'deleting a user with tasks in their custom status succeeds');

select sequence_privs_are('public', 'task_status_events_id_seq', 'anon', array[]::text[]);
select sequence_privs_are('public', 'task_status_events_id_seq', 'authenticated', array[]::text[]);

select * from finish();
rollback;
