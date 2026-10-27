begin;
select plan(13);

select tests.create_user('ann@test');
select tests.create_user('bob@test');

select tests.authenticate_as('ann@test');
insert into public.lists(name) values ('Home');
select tests.clear_authentication();

select results_eq($$select behavior::text, label, sort_order::int from public.task_statuses where owner_id is null order by sort_order$$,
  $$values ('backlog','Backlog',10),('todo','To Do',20),('in_progress','In Progress',30),('blocked','Blocked',40),
           ('in_review','In Review',50),('completed','Completed',60),('cancelled','Cancelled',70)$$, 'seven built-ins seeded');

select tests.authenticate_as('ann@test');
insert into public.task_statuses(owner_id, label, behavior) values (tests.user_id('ann@test'), '  Waiting for parts ', 'blocked');
select is((select sort_order::int from public.task_statuses where label = 'Waiting for parts'), 41, 'custom sorts after its built-in, label trimmed');
select throws_ok($$insert into public.task_statuses(owner_id,label,behavior) values (tests.user_id('ann@test'),' to do ','todo')$$,
  'P0001', 'status label matches a built-in status');
select throws_ok($$insert into public.task_statuses(owner_id,label,behavior) values (tests.user_id('ann@test'),'WAITING FOR PARTS ','blocked')$$,
  '23505', null, 'duplicate custom label rejected case- and space-insensitively');
select throws_ok($$insert into public.task_statuses(owner_id,label,behavior) values (null,'Mine','todo')$$, '42501', null, 'cannot insert built-ins');
select throws_ok($$insert into public.task_statuses(owner_id,label,behavior) values (tests.user_id('bob@test'),'X','todo')$$, '42501', null, 'cannot create for others');
select throws_ok($$insert into public.task_statuses(owner_id,label,behavior) values (tests.user_id('ann@test'),repeat('x',51),'todo')$$, '23514', null, 'label max 50');
update public.task_statuses set label = 'Hacked' where owner_id is null;
delete from public.task_statuses where owner_id is null;
select tests.clear_authentication();
select is((select count(*) from public.task_statuses where owner_id is null and label <> 'Hacked'), 7::bigint, 'clients cannot change or delete built-ins');

select tests.authenticate_as('bob@test');
select lives_ok($$insert into public.task_statuses(owner_id,label,behavior) values (tests.user_id('bob@test'),'Waiting for parts','blocked')$$, 'labels unique per owner only');
select is((select count(*) from public.task_statuses where owner_id = tests.user_id('ann@test')), 0::bigint, 'strangers cannot see my statuses');
select tests.clear_authentication();
insert into public.list_members(list_id, user_id, role) values (tests.list_id('Home'), tests.user_id('bob@test'), 'editor');
select tests.authenticate_as('bob@test');
select is((select count(*) from public.task_statuses where owner_id = tests.user_id('ann@test')), 1::bigint, 'co-members can see my statuses');
select table_privs_are('public', 'task_statuses', 'anon', array[]::text[]);
select ok((select count(*) from public.task_statuses where owner_id is null) = 7, 'built-ins visible to everyone');
select tests.clear_authentication();

select * from finish();
rollback;
