begin;
select plan(8);

select tests.create_user('own@test');
select tests.create_user('ed@test');
select tests.create_user('st@test');

select tests.authenticate_as('own@test');
insert into public.lists(name) values ('Home');
insert into public.list_members(list_id, user_id, role)
  values (tests.list_id('Home'), tests.user_id('ed@test'), 'editor');

select tests.authenticate_as('ed@test');
select throws_ok($$select public.transfer_list_ownership(tests.list_id('Home'), tests.user_id('ed@test'))$$,
  'P0001', 'only the list owner can transfer ownership', 'non-owner cannot transfer');

select tests.authenticate_as('own@test');
select throws_ok($$select public.transfer_list_ownership(tests.list_id('Home'), tests.user_id('st@test'))$$,
  'P0001', 'new owner must already be a member of the list', 'target must be a member');
select lives_ok($$select public.transfer_list_ownership(tests.list_id('Home'), tests.user_id('own@test'))$$,
  'transfer to self is a no-op');
select lives_ok($$select public.transfer_list_ownership(tests.list_id('Home'), tests.user_id('ed@test'))$$,
  'owner transfers to editor');

select tests.clear_authentication();
select is((select count(*) from public.list_members where list_id = tests.list_id('Home') and role = 'owner'),
  1::bigint, 'exactly one owner');
select is((select owner_id from public.lists where id = tests.list_id('Home')),
  tests.user_id('ed@test'), 'lists.owner_id updated');
select is((select role from public.list_members where list_id = tests.list_id('Home') and user_id = tests.user_id('own@test')),
  'editor'::public.list_role, 'old owner is editor');
select function_privs_are('public', 'transfer_list_ownership', array['uuid','uuid'], 'anon', array[]::text[]);

select * from finish();
rollback;
