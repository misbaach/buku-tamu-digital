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

select plan(1);
select pass('helper tes tersedia');
select * from finish();
commit;
