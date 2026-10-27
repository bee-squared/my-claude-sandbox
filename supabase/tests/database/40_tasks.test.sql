begin;
select plan(23);

select tests.create_user('ann@test');
select tests.create_user('bob@test');
select tests.create_user('cat@test');
select tests.create_user('dan@test');

select tests.authenticate_as('ann@test');
insert into public.lists(name) values ('Home'), ('Work');
select tests.clear_authentication();
insert into public.list_members(list_id, user_id, role) values
  (tests.list_id('Home'), tests.user_id('bob@test'), 'editor'),
  (tests.list_id('Home'), tests.user_id('cat@test'), 'viewer');

select tests.authenticate_as('ann@test');
insert into public.task_statuses(owner_id, label, behavior) values
  (tests.user_id('ann@test'), 'Waiting for parts', 'blocked'),
  (tests.user_id('ann@test'), 'Old way', 'todo');
select tests.clear_authentication();
select tests.authenticate_as('dan@test');
insert into public.task_statuses(owner_id, label, behavior) values (tests.user_id('dan@test'), 'Dan status', 'todo');
select tests.clear_authentication();
select tests.authenticate_as('cat@test');
insert into public.task_statuses(owner_id, label, behavior) values (tests.user_id('cat@test'), 'Cat status', 'todo');
select tests.clear_authentication();

-- as ann
select tests.authenticate_as('ann@test');
insert into public.tasks(list_id, title, status_id) values (tests.list_id('Home'), 'T-old', tests.status_id('Old way'));
update public.task_statuses set archived_at = now() where label = 'Old way';

insert into public.tasks(list_id, title) values (tests.list_id('Home'), 'T1');
select is((select behavior from public.tasks t join public.task_statuses s on s.id = t.status_id where t.title = 'T1'),
  'todo'::public.status_behavior, 'task without status lands in To Do');
select lives_ok($q$do $d$ declare a uuid; b uuid; begin
  for a in select id from public.task_statuses where owner_id is null loop
    for b in select id from public.task_statuses where owner_id is null loop
      update public.tasks set status_id = a where title = 'T1';
      update public.tasks set status_id = b where title = 'T1';
    end loop; end loop; end $d$$q$,'any status can move to any other');
select lives_ok($$insert into public.tasks(list_id,title,status_id) values
  (tests.list_id('Home'),'T2',tests.status_id('Waiting for parts')),(tests.list_id('Work'),'T3',tests.status_id('Waiting for parts'))$$,
  'own custom status works in any of my lists');
select throws_ok($$insert into public.tasks(list_id,title,status_id) values (tests.list_id('Home'),'X',tests.status_id('Dan status'))$$,
  'P0001', 'status cannot be used in this list');
select throws_ok($$insert into public.tasks(list_id,title,status_id) values (tests.list_id('Home'),'X',tests.status_id('Cat status'))$$,
  'P0001', 'status cannot be used in this list');  -- viewer's status
select throws_ok($$update public.tasks set status_id = tests.status_id('Old way') where title = 'T1'$$,
  'P0001', 'archived status cannot be chosen');
select lives_ok($$update public.tasks set list_id = tests.list_id('Work') where title = 'T-old'$$, 'archived status travels with its task');
select throws_ok($$update public.tasks set assignee_id = tests.user_id('dan@test') where title = 'T1'$$,
  'P0001', 'assignee must be a member of the list');
select lives_ok($$update public.tasks set assignee_id = tests.user_id('cat@test') where title = 'T1'$$, 'viewer can be assigned');
delete from public.list_members where user_id = tests.user_id('cat@test');
select is((select assignee_id from public.tasks where title = 'T1'), null, 'removing a member clears their assignments');
select lives_ok($$insert into public.tasks(list_id,title,status_id)
  select tests.list_id('Home'), 'P'||g, tests.status_id('In Progress') from generate_series(1,10) g$$, 'no column limit');
select is((select count(*) from public.tasks where status_id = tests.status_id('In Progress')), 10::bigint, '10 tasks in In Progress');
select throws_ok($$insert into public.tasks(list_id,title) values (tests.list_id('Home'),'  ')$$, '23514', null, 'blank title rejected');
select throws_ok($$insert into public.tasks(list_id,title,priority) values (tests.list_id('Home'),'X',4)$$, '23514', null, 'priority 1-3');
update public.lists set archived_at = now() where name = 'Home';
select tests.clear_authentication();

-- as bob (editor)
select tests.authenticate_as('bob@test');
select lives_ok($$insert into public.tasks(list_id,title,status_id) values (tests.list_id('Home'),'B1',tests.status_id('Waiting for parts'))$$,
  'editor can use the owner''s custom status (and archived list is editable)');
update public.tasks set title = 'B1 renamed' where title = 'B1';
select isnt_empty($$select 1 from public.tasks where title = 'B1 renamed'$$, 'editor updates tasks in an archived list');
select throws_ok($$update public.tasks set list_id = tests.list_id('Work') where title = 'B1 renamed'$$, '42501', null,
  'editor cannot move a task into a list they do not edit');
select tests.clear_authentication();

-- as cat (re-add cat as viewer first, as postgres)
insert into public.list_members(list_id, user_id, role) values (tests.list_id('Home'), tests.user_id('cat@test'), 'viewer');
select tests.authenticate_as('cat@test');
select isnt_empty($$select 1 from public.tasks$$, 'viewer can read tasks');
select throws_ok($$insert into public.tasks(list_id,title) values (tests.list_id('Home'),'C')$$, '42501', null, 'viewer cannot create');
update public.tasks set title = 'cat was here'; delete from public.tasks;
select tests.clear_authentication();

-- as postgres
select is((select count(*) from public.tasks where title = 'cat was here'), 0::bigint, 'viewer cannot update');
select is((select count(*) from public.tasks where list_id = tests.list_id('Home')) > 0, true, 'viewer cannot delete');

-- as dan
select tests.authenticate_as('dan@test');
select is_empty($$select 1 from public.tasks$$, 'non-member cannot read tasks');
select table_privs_are('public', 'tasks', 'anon', array[]::text[]);
select tests.clear_authentication();

select * from finish();
rollback;
