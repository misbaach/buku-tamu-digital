-- M2 — Login usher dan siklus hidup perangkat (prd.md FR-R-02, FR-R-08..10, 11.5; docs/plan.md bagian 9).
-- Fungsi svc_* hanya bisa dieksekusi service_role, yaitu Edge Function usher-login dan device-cleanup.

-- Peringatan kegagalan per event dan blokir per kunci/IP dicatat ke audit log (prd.md 10.4), sekali per jendela.
create function private.audit_login_alerts(p_event_id uuid, p_ip text, p_event_code text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  c jsonb := private.config();
  v_window interval := make_interval(mins => (c ->> 'usher_login_window_min')::integer);
  v_since timestamptz := now() - v_window;
  v_event_fails integer;
  v_key_fails integer;
  v_ip_fails integer;
begin
  select count(*) filter (where f.event_id = p_event_id),
         count(*) filter (where f.ip = p_ip and f.event_code = p_event_code),
         count(*) filter (where f.ip = p_ip)
  into v_event_fails, v_key_fails, v_ip_fails
  from private.login_failures(v_since) f;

  if p_event_id is not null and v_event_fails >= (c ->> 'usher_login_event_warn_fails')::integer
     and not exists (select 1 from public.audit_logs a where a.event_id = p_event_id
                     and a.action = 'usher_login_burst' and a.created_at > v_since) then
    perform private.audit(p_event_id, 'usher_login_burst', 'events', p_event_id::text, null,
      jsonb_build_object('failures', v_event_fails, 'window_min', (c ->> 'usher_login_window_min')::integer));
  end if;
  -- Tepat saat ambang tercapai, agar tercatat sekali per blokir.
  if v_key_fails = (c ->> 'usher_login_pin_block_fails')::integer then
    perform private.audit(p_event_id, 'usher_login_blocked', 'auth_attempts', null, null,
      jsonb_build_object('scope', 'key', 'ip', p_ip, 'event_code', p_event_code));
  end if;
  if v_ip_fails = (c ->> 'usher_login_ip_block_fails')::integer then
    perform private.audit(p_event_id, 'usher_login_blocked', 'auth_attempts', null, null,
      jsonb_build_object('scope', 'ip', 'ip', p_ip));
  end if;
end;
$$;

-- Login usher (11.5 langkah 3–4, sisi database). Mengembalikan salah satu:
--   {"outcome": "invalid"}                       — identik untuk SEMUA penyebab gagal kredensial
--   {"outcome": "blocked", "retry_after": n}     — blokir (IP + Kode Acara) atau IP, tanpa bcrypt
--   {"outcome": "archived" | "session_ended" | "capacity"} — hanya setelah kredensial terbukti sah
--   {"outcome": "ok", ...}                       — perangkat baru terdaftar
create function private.svc_usher_login(
  p_method public.login_method, p_ip text, p_event_code text, p_selector text, p_secret text, p_token text,
  p_device_name text, p_app_version text
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  c jsonb := private.config();
  v_window interval := make_interval(mins => (c ->> 'usher_login_window_min')::integer);
  v_key_limit integer := (c ->> 'usher_login_pin_block_fails')::integer;
  v_ip_limit integer := (c ->> 'usher_login_ip_block_fails')::integer;
  v_ip text := left(coalesce(nullif(btrim(p_ip), ''), 'unknown'), 64);
  v_code text := left(upper(regexp_replace(coalesce(p_event_code, ''), '[\s-]', '', 'g')), 32);
  v_selector text := left(upper(coalesce(p_selector, '')), 2);
  v_event public.events;
  v_usher public.ushers;
  v_usher_id uuid;
  v_hash text;
  v_match boolean;
  v_ok boolean;
  v_reason text;
  v_key_fails integer;
  v_ip_fails integer;
  v_until timestamptz;
  v_expires timestamptz;
  v_index integer;
  v_device_id uuid := gen_random_uuid();
  v_device_code text;
begin
  if p_method = 'pin' then
    -- (1) Blokir diperiksa SEBELUM bcrypt (FR-R-09).
    select count(*) filter (where f.event_code = v_code), count(*)
    into v_key_fails, v_ip_fails
    from private.login_failures(now() - v_window) f
    where f.ip = v_ip;

    if v_key_fails >= v_key_limit or v_ip_fails >= v_ip_limit then
      select greatest(
        case when v_key_fails >= v_key_limit then (
          select f.created_at from private.login_failures(now() - v_window) f
          where f.ip = v_ip and f.event_code = v_code order by f.created_at desc offset v_key_limit - 1 limit 1) end,
        case when v_ip_fails >= v_ip_limit then (
          select f.created_at from private.login_failures(now() - v_window) f
          where f.ip = v_ip order by f.created_at desc offset v_ip_limit - 1 limit 1) end
      ) + v_window into v_until;
      insert into public.auth_attempts (kind, method, ip, event_code, success, reason)
      values ('usher_login', 'pin', v_ip, v_code, false,
              case when v_ip_fails >= v_ip_limit then 'blocked_ip' else 'blocked_key' end);
      return jsonb_build_object('outcome', 'blocked',
                                'retry_after', greatest(1, ceil(extract(epoch from v_until - now()))::integer));
    end if;

    -- (2) Lookup lewat (Kode Acara, ID usher). Keduanya tidak rahasia.
    select * into v_event from public.events where code = v_code;
    if v_event.id is not null then
      select * into v_usher from public.ushers
      where event_id = v_event.id and pin_selector = v_selector and deleted_at is null;
    end if;

    -- (3) TEPAT SATU bcrypt di setiap jalur: hash usher aktif, atau hash dummy.
    v_hash := case when v_usher.id is not null and v_usher.is_active then v_usher.pin_hash
                   else private.dummy_secret_hash() end;
    -- Pernyataan tersendiri: di dalam ekspresi AND, Postgres boleh melewatkan pemanggilan fungsi.
    v_match := private.verify_secret(p_secret, v_hash);
    v_ok := v_match and v_usher.id is not null and v_usher.is_active;
    v_reason := case
      when v_event.id is null then 'unknown_event'
      when v_usher.id is null then 'unknown_usher'
      when not v_usher.is_active then 'inactive_usher'
      when not v_ok then 'bad_secret'
      else 'ok'
    end;

    insert into public.auth_attempts (kind, method, ip, event_code, event_id, usher_id, success, reason)
    values ('usher_login', 'pin', v_ip, v_code, v_event.id, v_usher.id, v_ok, v_reason);

    if not v_ok then
      perform private.audit_login_alerts(v_event.id, v_ip, v_code);
      return jsonb_build_object('outcome', 'invalid');
    end if;
  else
    -- QR Login: token ditandai terpakai secara atomik; tidak ada blokir (FR-R-09).
    update public.usher_login_tokens set used_at = now()
    where token_hash = private.sha256_hex(p_token) and used_at is null and expires_at > now()
    returning usher_id into v_usher_id;
    if v_usher_id is not null then
      select * into v_usher from public.ushers where id = v_usher_id and deleted_at is null;
      select * into v_event from public.events where id = v_usher.event_id;
    end if;
    v_ok := v_usher.id is not null and v_usher.is_active;
    v_reason := case when v_usher_id is null then 'invalid_token'
                     when not v_ok then 'inactive_usher' else 'ok' end;

    insert into public.auth_attempts (kind, method, ip, event_code, event_id, usher_id, success, reason)
    values ('usher_login', 'qr', v_ip, v_event.code, v_event.id, v_usher.id, v_ok, v_reason);

    if not v_ok then
      return jsonb_build_object('outcome', 'invalid');
    end if;
  end if;

  -- (4) Kredensial sah. Respons berbeda baru boleh muncul dari sini.
  if v_event.archived_at is not null then
    return jsonb_build_object('outcome', 'archived');
  end if;
  v_expires := private.session_expiry(v_event.event_date, v_event.timezone);
  if v_expires <= now() then
    return jsonb_build_object('outcome', 'session_ended');
  end if;

  perform private.lock_event(v_event.id);
  select coalesce(max(private.device_code_index(code)) + 1, 0) into v_index from public.devices where event_id = v_event.id;
  if v_index >= (c ->> 'max_device_codes')::integer then
    return jsonb_build_object('outcome', 'capacity');
  end if;
  v_device_code := private.device_code(v_index);

  insert into public.devices (id, event_id, usher_id, code, name, app_version, last_seen_at, session_expires_at)
  values (v_device_id, v_event.id, v_usher.id, v_device_code, nullif(left(btrim(p_device_name), 80), ''),
          nullif(left(btrim(p_app_version), 40), ''), now(), v_expires);

  perform private.audit(v_event.id, 'device_login', 'devices', v_device_id::text, null,
    jsonb_build_object('code', v_device_code, 'usher_id', v_usher.id, 'method', p_method));

  return jsonb_build_object(
    'outcome', 'ok',
    'device_id', v_device_id, 'device_code', v_device_code,
    'event_id', v_event.id, 'event_name', v_event.name,
    'usher_id', v_usher.id, 'usher_name', v_usher.name, 'usher_mode', v_usher.mode,
    'session_expires_at', v_expires);
end;
$$;

-- Menautkan user Auth perangkat setelah dibuat Edge Function (11.5 langkah 4).
create function private.svc_attach_device_user(p_device_id uuid, p_auth_user_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.devices set auth_user_id = p_auth_user_id where id = p_device_id and auth_user_id is null;
  if not found then
    raise exception 'Perangkat tidak ditemukan atau sudah tertaut.' using errcode = 'P0002';
  end if;
end;
$$;

-- Membatalkan pendaftaran perangkat bila pembuatan user Auth atau sesi gagal. Perangkat yang sudah pernah
-- mengirim check-in tidak pernah dihapus.
create function private.svc_abort_device(p_device_id uuid)
returns void
language sql
security definer
set search_path = ''
as $$
  delete from public.devices d
  where d.id = p_device_id and not exists (select 1 from public.check_ins c where c.device_id = d.id);
$$;

-- Perangkat yang user Auth-nya harus dihapus (11.5 langkah 7): tingkat terminate yang belum dibersihkan, atau
-- sesi berakhir (session_expires_at atau waktu arsip, mana yang lebih dulu) lebih dari masa tenggang.
create function private.devices_due_for_cleanup(p_now timestamptz)
returns table (device_id uuid, auth_user_id uuid)
language sql
stable
security definer
set search_path = ''
as $$
  select d.id, d.auth_user_id
  from public.devices d join public.events e on e.id = d.event_id
  where d.auth_user_deleted_at is null
    and (d.revoke_mode = 'terminate'
         or least(d.session_expires_at, coalesce(e.archived_at, 'infinity'::timestamptz))
            + make_interval(hours => (private.config() ->> 'session_grace_hours')::integer) < p_now)
  order by d.created_at, d.id;
$$;

create function private.svc_devices_due_for_cleanup(p_limit integer)
returns table (device_id uuid, auth_user_id uuid)
language sql
stable
security definer
set search_path = ''
as $$
  select * from private.devices_due_for_cleanup(now()) limit greatest(1, least(coalesce(p_limit, 100), 500));
$$;

-- User Auth perangkat untuk mode terminate. Hanya mengembalikan nilai setelah Admin menetapkan terminate lewat
-- admin_revoke_device, sehingga Edge Function tidak bisa menghapus user perangkat yang tidak dicabut.
create function private.svc_terminated_device_user(p_device_id uuid)
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select auth_user_id from public.devices where id = p_device_id and revoke_mode = 'terminate';
$$;

create function private.svc_mark_auth_user_deleted(p_device_id uuid)
returns void
language sql
security definer
set search_path = ''
as $$
  update public.devices set auth_user_deleted_at = now() where id = p_device_id and auth_user_deleted_at is null;
$$;

-- =============================================================================================
-- Pembungkus public untuk service_role
-- =============================================================================================

create function public.svc_usher_login(
  p_method public.login_method, p_ip text, p_event_code text default null, p_selector text default null,
  p_secret text default null, p_token text default null, p_device_name text default null, p_app_version text default null
)
returns jsonb language sql set search_path = ''
as $$ select private.svc_usher_login(p_method, p_ip, p_event_code, p_selector, p_secret, p_token, p_device_name, p_app_version) $$;

create function public.svc_attach_device_user(p_device_id uuid, p_auth_user_id uuid)
returns void language sql set search_path = ''
as $$ select private.svc_attach_device_user(p_device_id, p_auth_user_id) $$;

create function public.svc_abort_device(p_device_id uuid)
returns void language sql set search_path = ''
as $$ select private.svc_abort_device(p_device_id) $$;

create function public.svc_devices_due_for_cleanup(p_limit integer default 100)
returns table (device_id uuid, auth_user_id uuid) language sql stable set search_path = ''
as $$ select * from private.svc_devices_due_for_cleanup(p_limit) $$;

create function public.svc_terminated_device_user(p_device_id uuid)
returns uuid language sql stable set search_path = ''
as $$ select private.svc_terminated_device_user(p_device_id) $$;

create function public.svc_mark_auth_user_deleted(p_device_id uuid)
returns void language sql set search_path = ''
as $$ select private.svc_mark_auth_user_deleted(p_device_id) $$;

-- =============================================================================================
-- Hak eksekusi
-- =============================================================================================

revoke all on function private.audit_login_alerts(uuid, text, text) from public, anon, authenticated, service_role;
revoke all on function private.svc_usher_login(public.login_method, text, text, text, text, text, text, text) from public, anon, authenticated, service_role;
revoke all on function private.svc_attach_device_user(uuid, uuid) from public, anon, authenticated, service_role;
revoke all on function private.svc_abort_device(uuid) from public, anon, authenticated, service_role;
revoke all on function private.devices_due_for_cleanup(timestamptz) from public, anon, authenticated, service_role;
revoke all on function private.svc_devices_due_for_cleanup(integer) from public, anon, authenticated, service_role;
revoke all on function private.svc_terminated_device_user(uuid) from public, anon, authenticated, service_role;
revoke all on function private.svc_mark_auth_user_deleted(uuid) from public, anon, authenticated, service_role;
revoke all on function public.svc_usher_login(public.login_method, text, text, text, text, text, text, text) from public, anon, authenticated, service_role;
revoke all on function public.svc_attach_device_user(uuid, uuid) from public, anon, authenticated, service_role;
revoke all on function public.svc_abort_device(uuid) from public, anon, authenticated, service_role;
revoke all on function public.svc_devices_due_for_cleanup(integer) from public, anon, authenticated, service_role;
revoke all on function public.svc_terminated_device_user(uuid) from public, anon, authenticated, service_role;
revoke all on function public.svc_mark_auth_user_deleted(uuid) from public, anon, authenticated, service_role;

grant execute on function public.svc_usher_login(public.login_method, text, text, text, text, text, text, text) to service_role;
grant execute on function private.svc_usher_login(public.login_method, text, text, text, text, text, text, text) to service_role;
grant execute on function public.svc_attach_device_user(uuid, uuid) to service_role;
grant execute on function private.svc_attach_device_user(uuid, uuid) to service_role;
grant execute on function public.svc_abort_device(uuid) to service_role;
grant execute on function private.svc_abort_device(uuid) to service_role;
grant execute on function public.svc_devices_due_for_cleanup(integer) to service_role;
grant execute on function private.svc_devices_due_for_cleanup(integer) to service_role;
grant execute on function public.svc_terminated_device_user(uuid) to service_role;
grant execute on function private.svc_terminated_device_user(uuid) to service_role;
grant execute on function public.svc_mark_auth_user_deleted(uuid) to service_role;
grant execute on function private.svc_mark_auth_user_deleted(uuid) to service_role;
