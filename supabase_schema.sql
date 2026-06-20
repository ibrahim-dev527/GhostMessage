-- ============================================================
-- GHOSTMESSAGE — SUPABASE SCHEMA
-- ============================================================
-- Run this entire file in: Supabase Dashboard → SQL Editor → New Query
-- This sets up tables, security policies, and helper functions.
-- Safe to re-run (uses IF NOT EXISTS / DROP IF EXISTS where needed).
-- ============================================================

-- Required for password hashing
create extension if not exists pgcrypto;

-- ============================================================
-- 1. USERS TABLE
-- ============================================================
create table if not exists public.users (
  id uuid primary key default gen_random_uuid(),
  username text unique not null check (username ~ '^[a-zA-Z0-9_]{3,20}$'),
  display_name text not null,
  password_hash text not null,
  avatar_color text default '#e63946',
  avatar_letter text not null,
  sound_enabled boolean default true,
  animations_enabled boolean default true,
  notif_enabled boolean default true,
  is_first_login boolean default true,
  link_visits integer default 0,
  is_banned boolean default false,
  created_at timestamptz default now()
);

-- ============================================================
-- 2. MESSAGES TABLE
-- ============================================================
create table if not exists public.messages (
  id uuid primary key default gen_random_uuid(),
  recipient_username text not null references public.users(username) on delete cascade,
  text text not null check (char_length(text) between 1 and 500),
  is_read boolean default false,
  created_at timestamptz default now()
);

create index if not exists idx_messages_recipient on public.messages(recipient_username);

-- ============================================================
-- 3. ENABLE ROW LEVEL SECURITY (locks down direct table access)
-- ============================================================
alter table public.users enable row level security;
alter table public.messages enable row level security;

-- Drop old policies if re-running this script
drop policy if exists "no_direct_select_users" on public.users;
drop policy if exists "no_direct_insert_users" on public.users;
drop policy if exists "no_direct_update_users" on public.users;
drop policy if exists "no_direct_delete_users" on public.users;
drop policy if exists "public_can_insert_messages" on public.messages;
drop policy if exists "no_direct_select_messages" on public.messages;
drop policy if exists "no_direct_update_messages" on public.messages;
drop policy if exists "no_direct_delete_messages" on public.messages;

-- USERS: block all direct table access. Everything goes through functions below.
create policy "no_direct_select_users" on public.users for select using (false);
create policy "no_direct_insert_users" on public.users for insert with check (false);
create policy "no_direct_update_users" on public.users for update using (false);
create policy "no_direct_delete_users" on public.users for delete using (false);

-- MESSAGES: anyone can INSERT (this is what makes anonymous sending possible).
-- SELECT/UPDATE/DELETE are blocked directly — only via verified functions below.
create policy "public_can_insert_messages" on public.messages for insert with check (true);
create policy "no_direct_select_messages" on public.messages for select using (false);
create policy "no_direct_update_messages" on public.messages for update using (false);
create policy "no_direct_delete_messages" on public.messages for delete using (false);

-- ============================================================
-- 4. FUNCTIONS (all password checks happen here, server-side)
-- ============================================================

-- ---- SIGNUP ----
create or replace function public.gm_signup(
  p_username text,
  p_password text,
  p_display_name text,
  p_avatar_color text
) returns json
language plpgsql security definer as $$
declare
  v_user record;
begin
  if exists (select 1 from public.users where username = lower(p_username)) then
    return json_build_object('success', false, 'error', 'Username already taken.');
  end if;

  if length(p_password) < 6 then
    return json_build_object('success', false, 'error', 'Password must be at least 6 characters.');
  end if;

  insert into public.users (username, display_name, password_hash, avatar_color, avatar_letter)
  values (
    lower(p_username),
    p_display_name,
    crypt(p_password, gen_salt('bf')),
    p_avatar_color,
    upper(left(p_display_name, 1))
  )
  returning * into v_user;

  return json_build_object(
    'success', true,
    'user', json_build_object(
      'username', v_user.username,
      'display_name', v_user.display_name,
      'avatar_color', v_user.avatar_color,
      'avatar_letter', v_user.avatar_letter,
      'is_first_login', v_user.is_first_login,
      'sound_enabled', v_user.sound_enabled,
      'animations_enabled', v_user.animations_enabled,
      'notif_enabled', v_user.notif_enabled
    )
  );
end;
$$;

-- ---- LOGIN ----
create or replace function public.gm_login(
  p_username text,
  p_password text
) returns json
language plpgsql security definer as $$
declare
  v_user record;
begin
  select * into v_user from public.users where username = lower(p_username);

  if v_user is null or v_user.password_hash != crypt(p_password, v_user.password_hash) then
    return json_build_object('success', false, 'error', 'Incorrect username or password.');
  end if;

  if v_user.is_banned then
    return json_build_object('success', false, 'error', 'This account has been suspended.');
  end if;

  return json_build_object(
    'success', true,
    'user', json_build_object(
      'username', v_user.username,
      'display_name', v_user.display_name,
      'avatar_color', v_user.avatar_color,
      'avatar_letter', v_user.avatar_letter,
      'is_first_login', v_user.is_first_login,
      'sound_enabled', v_user.sound_enabled,
      'animations_enabled', v_user.animations_enabled,
      'notif_enabled', v_user.notif_enabled
    )
  );
end;
$$;

-- ---- VERIFY SESSION (re-check password matches before any sensitive action) ----
create or replace function public.gm_verify(
  p_username text,
  p_password text
) returns boolean
language plpgsql security definer as $$
declare
  v_hash text;
begin
  select password_hash into v_hash from public.users where username = lower(p_username);
  if v_hash is null then return false; end if;
  return v_hash = crypt(p_password, v_hash);
end;
$$;

-- ---- GET PUBLIC PROFILE (for message.html — no password needed, just public info) ----
create or replace function public.gm_get_profile(p_username text)
returns json
language plpgsql security definer as $$
declare
  v_user record;
begin
  select * into v_user from public.users where username = lower(p_username);
  if v_user is null then
    return json_build_object('success', false, 'error', 'User not found.');
  end if;

  update public.users set link_visits = link_visits + 1 where username = lower(p_username);

  return json_build_object(
    'success', true,
    'username', v_user.username,
    'display_name', v_user.display_name,
    'avatar_color', v_user.avatar_color,
    'avatar_letter', v_user.avatar_letter
  );
end;
$$;

-- ---- SEND ANONYMOUS MESSAGE ----
create or replace function public.gm_send_message(
  p_recipient_username text,
  p_text text
) returns json
language plpgsql security definer as $$
begin
  if not exists (select 1 from public.users where username = lower(p_recipient_username)) then
    return json_build_object('success', false, 'error', 'Recipient not found.');
  end if;

  if length(trim(p_text)) < 1 or length(p_text) > 500 then
    return json_build_object('success', false, 'error', 'Message must be 1-500 characters.');
  end if;

  insert into public.messages (recipient_username, text)
  values (lower(p_recipient_username), p_text);

  return json_build_object('success', true);
end;
$$;

-- ---- GET MY MESSAGES (requires password verification) ----
create or replace function public.gm_get_messages(
  p_username text,
  p_password text
) returns json
language plpgsql security definer as $$
begin
  if not public.gm_verify(p_username, p_password) then
    return json_build_object('success', false, 'error', 'Authentication failed.');
  end if;

  return json_build_object(
    'success', true,
    'messages', coalesce(
      (select json_agg(json_build_object(
        'id', m.id,
        'text', m.text,
        'is_read', m.is_read,
        'created_at', m.created_at
      ) order by m.created_at desc)
      from public.messages m
      where m.recipient_username = lower(p_username)),
      '[]'::json
    )
  );
end;
$$;

-- ---- MARK MESSAGE READ ----
create or replace function public.gm_mark_read(
  p_username text,
  p_password text,
  p_message_id uuid
) returns json
language plpgsql security definer as $$
begin
  if not public.gm_verify(p_username, p_password) then
    return json_build_object('success', false, 'error', 'Authentication failed.');
  end if;

  update public.messages
  set is_read = true
  where id = p_message_id and recipient_username = lower(p_username);

  return json_build_object('success', true);
end;
$$;

-- ---- DELETE MESSAGE ----
create or replace function public.gm_delete_message(
  p_username text,
  p_password text,
  p_message_id uuid
) returns json
language plpgsql security definer as $$
begin
  if not public.gm_verify(p_username, p_password) then
    return json_build_object('success', false, 'error', 'Authentication failed.');
  end if;

  delete from public.messages
  where id = p_message_id and recipient_username = lower(p_username);

  return json_build_object('success', true);
end;
$$;

-- ---- CLEAR ALL MESSAGES ----
create or replace function public.gm_clear_messages(
  p_username text,
  p_password text
) returns json
language plpgsql security definer as $$
begin
  if not public.gm_verify(p_username, p_password) then
    return json_build_object('success', false, 'error', 'Authentication failed.');
  end if;

  delete from public.messages where recipient_username = lower(p_username);
  return json_build_object('success', true);
end;
$$;

-- ---- UPDATE PROFILE (display name, avatar color, preferences) ----
create or replace function public.gm_update_profile(
  p_username text,
  p_password text,
  p_display_name text,
  p_avatar_color text,
  p_sound_enabled boolean,
  p_animations_enabled boolean,
  p_notif_enabled boolean
) returns json
language plpgsql security definer as $$
begin
  if not public.gm_verify(p_username, p_password) then
    return json_build_object('success', false, 'error', 'Authentication failed.');
  end if;

  update public.users set
    display_name = p_display_name,
    avatar_letter = upper(left(p_display_name, 1)),
    avatar_color = p_avatar_color,
    sound_enabled = p_sound_enabled,
    animations_enabled = p_animations_enabled,
    notif_enabled = p_notif_enabled
  where username = lower(p_username);

  return json_build_object('success', true);
end;
$$;

-- ---- CHANGE PASSWORD ----
create or replace function public.gm_change_password(
  p_username text,
  p_current_password text,
  p_new_password text
) returns json
language plpgsql security definer as $$
begin
  if not public.gm_verify(p_username, p_current_password) then
    return json_build_object('success', false, 'error', 'Current password is incorrect.');
  end if;

  if length(p_new_password) < 6 then
    return json_build_object('success', false, 'error', 'New password must be at least 6 characters.');
  end if;

  update public.users
  set password_hash = crypt(p_new_password, gen_salt('bf'))
  where username = lower(p_username);

  return json_build_object('success', true);
end;
$$;

-- ---- MARK WALKTHROUGH SEEN ----
create or replace function public.gm_mark_walkthrough_seen(
  p_username text,
  p_password text
) returns json
language plpgsql security definer as $$
begin
  if not public.gm_verify(p_username, p_password) then
    return json_build_object('success', false, 'error', 'Authentication failed.');
  end if;

  update public.users set is_first_login = false where username = lower(p_username);
  return json_build_object('success', true);
end;
$$;

-- ---- DELETE ACCOUNT ----
create or replace function public.gm_delete_account(
  p_username text,
  p_password text
) returns json
language plpgsql security definer as $$
begin
  if not public.gm_verify(p_username, p_password) then
    return json_build_object('success', false, 'error', 'Authentication failed.');
  end if;

  delete from public.users where username = lower(p_username);
  return json_build_object('success', true);
end;
$$;

-- ============================================================
-- 5. ADMIN FUNCTIONS (protected by a separate admin password)
-- ============================================================
-- IMPORTANT: change this admin password immediately after running this script!
-- This is stored in plaintext here only because it's a single shared secret
-- for one admin (you). Change it via the UPDATE statement at the bottom.

create table if not exists public.admin_config (
  id integer primary key default 1,
  admin_password_hash text not null,
  constraint single_row check (id = 1)
);

insert into public.admin_config (id, admin_password_hash)
values (1, crypt('changeme123', gen_salt('bf')))
on conflict (id) do nothing;

alter table public.admin_config enable row level security;
drop policy if exists "no_direct_access_admin_config" on public.admin_config;
create policy "no_direct_access_admin_config" on public.admin_config for all using (false);

create or replace function public.gm_admin_login(p_password text)
returns json
language plpgsql security definer as $$
declare
  v_hash text;
begin
  select admin_password_hash into v_hash from public.admin_config where id = 1;
  if v_hash = crypt(p_password, v_hash) then
    return json_build_object('success', true);
  end if;
  return json_build_object('success', false, 'error', 'Incorrect admin password.');
end;
$$;

create or replace function public.gm_admin_change_password(p_current_password text, p_new_password text)
returns json
language plpgsql security definer as $$
declare
  v_hash text;
begin
  select admin_password_hash into v_hash from public.admin_config where id = 1;
  if v_hash != crypt(p_current_password, v_hash) then
    return json_build_object('success', false, 'error', 'Current admin password incorrect.');
  end if;
  update public.admin_config set admin_password_hash = crypt(p_new_password, gen_salt('bf')) where id = 1;
  return json_build_object('success', true);
end;
$$;

-- ---- ADMIN: GET ALL USERS ----
create or replace function public.gm_admin_get_users(p_password text)
returns json
language plpgsql security definer as $$
declare
  v_hash text;
begin
  select admin_password_hash into v_hash from public.admin_config where id = 1;
  if v_hash != crypt(p_password, v_hash) then
    return json_build_object('success', false, 'error', 'Unauthorized.');
  end if;

  return json_build_object(
    'success', true,
    'users', coalesce(
      (select json_agg(json_build_object(
        'username', u.username,
        'display_name', u.display_name,
        'avatar_color', u.avatar_color,
        'avatar_letter', u.avatar_letter,
        'link_visits', u.link_visits,
        'is_banned', u.is_banned,
        'created_at', u.created_at,
        'message_count', (select count(*) from public.messages m where m.recipient_username = u.username)
      ) order by u.created_at desc)
      from public.users u),
      '[]'::json
    )
  );
end;
$$;

-- ---- ADMIN: GET ALL MESSAGES (across all users) ----
create or replace function public.gm_admin_get_messages(p_password text)
returns json
language plpgsql security definer as $$
declare
  v_hash text;
begin
  select admin_password_hash into v_hash from public.admin_config where id = 1;
  if v_hash != crypt(p_password, v_hash) then
    return json_build_object('success', false, 'error', 'Unauthorized.');
  end if;

  return json_build_object(
    'success', true,
    'messages', coalesce(
      (select json_agg(json_build_object(
        'id', m.id,
        'recipient_username', m.recipient_username,
        'text', m.text,
        'is_read', m.is_read,
        'created_at', m.created_at
      ) order by m.created_at desc limit 500)
      from public.messages m),
      '[]'::json
    )
  );
end;
$$;

-- ---- ADMIN: GET STATS ----
create or replace function public.gm_admin_get_stats(p_password text)
returns json
language plpgsql security definer as $$
declare
  v_hash text;
  v_total_users int;
  v_total_messages int;
  v_unread_messages int;
  v_total_visits bigint;
  v_signups_today int;
  v_messages_today int;
begin
  select admin_password_hash into v_hash from public.admin_config where id = 1;
  if v_hash != crypt(p_password, v_hash) then
    return json_build_object('success', false, 'error', 'Unauthorized.');
  end if;

  select count(*) into v_total_users from public.users;
  select count(*) into v_total_messages from public.messages;
  select count(*) into v_unread_messages from public.messages where is_read = false;
  select coalesce(sum(link_visits),0) into v_total_visits from public.users;
  select count(*) into v_signups_today from public.users where created_at >= current_date;
  select count(*) into v_messages_today from public.messages where created_at >= current_date;

  return json_build_object(
    'success', true,
    'total_users', v_total_users,
    'total_messages', v_total_messages,
    'unread_messages', v_unread_messages,
    'total_visits', v_total_visits,
    'signups_today', v_signups_today,
    'messages_today', v_messages_today
  );
end;
$$;

-- ---- ADMIN: BAN / UNBAN USER ----
create or replace function public.gm_admin_set_ban(p_password text, p_username text, p_banned boolean)
returns json
language plpgsql security definer as $$
declare
  v_hash text;
begin
  select admin_password_hash into v_hash from public.admin_config where id = 1;
  if v_hash != crypt(p_password, v_hash) then
    return json_build_object('success', false, 'error', 'Unauthorized.');
  end if;

  update public.users set is_banned = p_banned where username = lower(p_username);
  return json_build_object('success', true);
end;
$$;

-- ---- ADMIN: DELETE ANY USER ----
create or replace function public.gm_admin_delete_user(p_password text, p_username text)
returns json
language plpgsql security definer as $$
declare
  v_hash text;
begin
  select admin_password_hash into v_hash from public.admin_config where id = 1;
  if v_hash != crypt(p_password, v_hash) then
    return json_build_object('success', false, 'error', 'Unauthorized.');
  end if;

  delete from public.users where username = lower(p_username);
  return json_build_object('success', true);
end;
$$;

-- ---- ADMIN: DELETE ANY MESSAGE ----
create or replace function public.gm_admin_delete_message(p_password text, p_message_id uuid)
returns json
language plpgsql security definer as $$
declare
  v_hash text;
begin
  select admin_password_hash into v_hash from public.admin_config where id = 1;
  if v_hash != crypt(p_password, v_hash) then
    return json_build_object('success', false, 'error', 'Unauthorized.');
  end if;

  delete from public.messages where id = p_message_id;
  return json_build_object('success', true);
end;
$$;

-- ============================================================
-- 6. IMPORTANT: SET YOUR OWN ADMIN PASSWORD NOW
-- ============================================================
-- The default admin password is 'changeme123'. Change it immediately by
-- running this line (replace 'YourNewSecurePassword' with your real password):
--
-- update public.admin_config set admin_password_hash = crypt('YourNewSecurePassword', gen_salt('bf')) where id = 1;
--
-- ============================================================
-- DONE. Your GhostMessage database is ready.
-- ============================================================
