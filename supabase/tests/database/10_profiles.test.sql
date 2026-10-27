begin;
select plan(7);
select tests.create_user('ann@test', 'Ann');
select tests.create_user('bob@test');

select enum_has_labels('public', 'status_behavior',
  array['backlog','todo','in_progress','blocked','in_review','completed','cancelled']);
select enum_has_labels('public', 'list_role', array['viewer','editor','owner']);
select ok(public.is_terminal('completed') and public.is_terminal('cancelled')
  and not public.is_terminal('blocked') and not public.is_terminal('todo'),
  'is_terminal is true only for completed and cancelled');
select is((select display_name from public.profiles where id = tests.user_id('ann@test')),
  'Ann', 'signup creates a profile with display_name from metadata');

select tests.authenticate_as('ann@test');
select results_eq($$select display_name from public.profiles$$, $$values ('Ann'::text)$$,
  'a user sharing no list sees only their own profile');
update public.profiles set display_name = 'hacked' where id = tests.user_id('bob@test');
select tests.clear_authentication();
select is((select display_name from public.profiles where id = tests.user_id('bob@test')),
  null, 'cannot update another user''s profile');
select table_privs_are('public', 'profiles', 'anon', array[]::text[]);

select * from finish();
rollback;
