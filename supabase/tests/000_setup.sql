-- Helper tes pgTAP. File ini di-commit (bukan rollback) agar helper tersedia untuk file tes berikutnya.
-- Schema `tests` hanya ada di database lokal/CI, tidak diekspos API, dan tidak pernah dibuat oleh migration.
begin;
create extension if not exists pgtap with schema extensions;
create schema if not exists tests;
revoke all on schema tests from public, anon, authenticated;

-- User uji. Pola insert ke auth.users hanya untuk tes lokal (docs/decisions.md T-031).
create or replace function tests.create_user(
  p_email text,
  p_app_metadata jsonb default '{}'::jsonb,
  p_user_metadata jsonb default '{}'::jsonb
)
returns uuid
language plpgsql
set search_path = ''
as $$
declare
  v_id uuid := gen_random_uuid();
begin
  insert into auth.users (
    instance_id, id, aud, role, email, encrypted_password, raw_app_meta_data, raw_user_meta_data,
    created_at, updated_at, confirmation_token, email_change, email_change_token_new, recovery_token
  ) values (
    '00000000-0000-0000-0000-000000000000', v_id, 'authenticated', 'authenticated', p_email, '',
    p_app_metadata, p_user_metadata, now(), now(), '', '', '', ''
  );
  return v_id;
end;
$$;

-- Meniru request PostgREST dari user tersebut: role authenticated + klaim JWT dari auth.users.
-- Kembali ke postgres dengan `reset role`.
create or replace function tests.authenticate_as(p_user_id uuid)
returns void
language plpgsql
set search_path = ''
as $$
declare
  v_user auth.users;
begin
  select * into v_user from auth.users where id = p_user_id;
  if not found then
    raise exception 'tests.authenticate_as: user % tidak ada', p_user_id;
  end if;
  perform set_config('request.jwt.claims', jsonb_build_object(
    'sub', v_user.id, 'role', 'authenticated', 'aud', 'authenticated', 'email', v_user.email,
    'app_metadata', coalesce(v_user.raw_app_meta_data, '{}'::jsonb),
    'user_metadata', coalesce(v_user.raw_user_meta_data, '{}'::jsonb)
  )::text, true);
  execute 'set local role authenticated';
end;
$$;

-- Klaim JWT bebas (mis. untuk menguji klaim yang dimanipulasi) dengan role authenticated.
create or replace function tests.authenticate_with_claims(p_claims jsonb)
returns void
language plpgsql
set search_path = ''
as $$
begin
  perform set_config('request.jwt.claims', (p_claims || jsonb_build_object('role', 'authenticated'))::text, true);
  execute 'set local role authenticated';
end;
$$;

create or replace function tests.authenticate_as_anon()
returns void
language plpgsql
set search_path = ''
as $$
begin
  perform set_config('request.jwt.claims', '{"role": "anon"}', true);
  execute 'set local role anon';
end;
$$;

-- Event uji lengkap dengan Admin sebagai anggota.
create or replace function tests.create_event(p_name text, p_admin uuid)
returns uuid
language plpgsql
set search_path = ''
as $$
declare
  v_event uuid;
begin
  insert into public.events (name, event_date, created_by) values (p_name, current_date, p_admin) returning id into v_event;
  if p_admin is not null then
    insert into public.event_members (event_id, user_id) values (v_event, p_admin);
  end if;
  insert into public.checkin_settings (event_id) values (v_event);
  insert into public.ticket_number_settings (event_id, category, prefix) values (v_event, 'vip', 'VIP-'), (v_event, 'vvip', 'VVIP-');
  insert into public.greeting_configs (event_id, category) values (v_event, 'regular'), (v_event, 'vip'), (v_event, 'vvip');
  return v_event;
end;
$$;

-- Usher dengan rahasia PIN yang diketahui tes (bcrypt lewat fungsi yang sama dengan produksi).
create or replace function tests.create_usher(
  p_event uuid, p_name text, p_selector text, p_secret text default 'ABCDEFGH',
  p_mode public.usher_mode default 'check_in'
)
returns uuid
language sql
set search_path = ''
as $$
  insert into public.ushers (event_id, name, mode, pin_selector, pin_hash)
  values (p_event, p_name, p_mode, p_selector, private.hash_secret(p_secret))
  returning id;
$$;

-- Perangkat terdaftar beserta user Auth-nya, persis seperti hasil usher-login (app_metadata ditulis server).
create or replace function tests.create_device(
  p_event uuid, p_usher uuid, p_code text, p_expires timestamptz default now() + interval '1 day'
)
returns uuid
language plpgsql
set search_path = ''
as $$
declare
  v_device uuid := gen_random_uuid();
  v_user uuid;
begin
  insert into public.devices (id, event_id, usher_id, code, session_expires_at)
  values (v_device, p_event, p_usher, p_code, p_expires);
  v_user := tests.create_user(v_device || '@device.test', jsonb_build_object(
    'role', 'usher', 'event_id', p_event, 'usher_id', p_usher, 'device_id', v_device));
  update public.devices set auth_user_id = v_user where id = v_device;
  return v_device;
end;
$$;

create or replace function tests.authenticate_as_device(p_device uuid)
returns void
language sql
set search_path = ''
as $$
  select tests.authenticate_as((select auth_user_id from public.devices where id = p_device));
$$;

-- Item outbox minimal untuk push_outbox.
create or replace function tests.push_item(
  p_id uuid, p_device uuid, p_guest uuid, p_ticket text, p_pax integer default 1
)
returns jsonb
language sql
immutable
set search_path = ''
as $$
  select jsonb_build_object('id', p_id, 'guestId', p_guest, 'actualPax', p_pax, 'ticketNumber', p_ticket,
                            'deviceId', p_device, 'checkedInAt', '2026-10-18T19:00:00+07:00');
$$;

select plan(1);
select pass('helper tes tersedia');
select * from finish();
commit;
