begin;
select plan(16);

select tests.create_user('owner@test');
select tests.create_user('ed@test');
select tests.create_user('vi@test');
select tests.create_user('stranger@test');

select tests.authenticate_as('owner@test');
insert into public.lists(name) values ('Home');
insert into public.list_members(list_id, user_id, role) values
  (tests.list_id('Home'), tests.user_id('ed@test'), 'editor'),
  (tests.list_id('Home'), tests.user_id('vi@test'), 'viewer');
select tests.clear_authentication();

select is((select role from public.list_members where list_id = tests.list_id('Home')
  and user_id = tests.user_id('owner@test')), 'owner'::public.list_role, 'creator becomes owner member');

select tests.authenticate_as('stranger@test');
select is_empty($$select 1 from public.lists$$, 'non-member cannot read the list');
select is_empty($$select 1 from public.list_members$$, 'non-member cannot read members');

select tests.authenticate_as('ed@test');
select throws_ok($$insert into public.list_members(list_id,user_id,role)
  values (tests.list_id('Home'), tests.user_id('stranger@test'), 'viewer')$$, '42501', null, 'editor cannot add members');
update public.list_members set role = 'editor' where user_id = tests.user_id('vi@test');
delete from public.list_members where user_id = tests.user_id('vi@test');
update public.lists set name = 'Renamed by editor';
select is((select name from public.lists where id = tests.list_id('Home')), 'Home', 'only the owner updates the list');
select tests.clear_authentication();
select is((select role from public.list_members where user_id = tests.user_id('vi@test')),
  'viewer'::public.list_role, 'editor cannot change or remove members');

select tests.authenticate_as('vi@test');
delete from public.list_members where user_id = tests.user_id('vi@test');
select is_empty($$select 1 from public.list_members where user_id = tests.user_id('vi@test')$$, 'a member can leave');

select tests.authenticate_as('owner@test');
select throws_ok($$delete from public.list_members where user_id = tests.user_id('owner@test')$$,
  'P0001', 'list owner cannot be removed');
select throws_ok($$update public.list_members set role = 'editor' where user_id = tests.user_id('owner@test')$$,
  'P0001', 'list owner cannot be downgraded');
select throws_ok($$update public.list_members set role = 'owner' where user_id = tests.user_id('ed@test')$$,
  'P0001', 'only the list owner can have the owner role');
select throws_ok($$update public.lists set owner_id = tests.user_id('ed@test')$$, '42501', null,
  'owner_id cannot be changed directly');
select throws_ok($$insert into public.lists(name) values ('   ')$$, '23514', null, 'blank list name rejected');
select isnt_empty($$select 1 from public.profiles where id = tests.user_id('ed@test')$$, 'owner sees a co-member''s profile');

select tests.clear_authentication();
set local session_replication_role = replica;
update public.lists set updated_at = '2000-01-01' where id = tests.list_id('Home');
set local session_replication_role = origin;
select tests.authenticate_as('owner@test');
update public.lists set description = 'touched' where id = tests.list_id('Home');
select tests.clear_authentication();
select ok((select updated_at > '2000-01-02' from public.lists where id = tests.list_id('Home')), 'updated_at maintained');
select table_privs_are('public', 'lists', 'anon', array[]::text[]);

select lives_ok($$delete from auth.users where id = tests.user_id('owner@test')$$, 'deleting an owning user succeeds');

select * from finish();
rollback;
