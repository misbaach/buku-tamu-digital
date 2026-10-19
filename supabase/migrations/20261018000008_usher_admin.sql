-- M2 — Penerima Tamu: konfigurasi, kredensial, kelola usher dan perangkat (prd.md 7.4, 10.4, 11.5).
-- Pola sama dengan M1: logika di private.* (SECURITY DEFINER, search_path kosong), dibungkus public.* tipis.

-- =============================================================================================
-- Konfigurasi bersama (cermin DB_MIRRORED_CONFIG; tes paritas gagal bila berbeda)
-- =============================================================================================

create or replace function private.config()
returns jsonb
language sql
immutable
set search_path = ''
as $$
  select jsonb_build_object(
    'code_alphabet', 'ABCDEFGHJKMNPQRSTUVWXYZ23456789',
    'event_code_length', 6,
    'usher_selector_length', 2,
    'pin_secret_length', 8,
    'usher_login_pin_block_fails', 10,
    'usher_login_ip_block_fails', 50,
    'usher_login_event_warn_fails', 20,
    'usher_login_window_min', 15,
    'usher_session_end_day_offset', 1,
    'usher_session_end_local_time', '06:00',
    'session_grace_hours', 72,
    'quarantine_max_items_per_device', 500,
    'device_cleanup_schedule', '*/15 * * * *',
    'max_device_codes', 702,
    'qr_login_ttl_sec', 300,
    'qr_token_bytes', 18,
    'special_number_max_length', 20,
    'push_batch_max', 200,
    'snapshot_page_size', 1000,
    'sync_cursor_overlap_ms', 5000,
    'upload_max_bytes', 5242880,
    'import_max_rows', 5000
  ) || jsonb_build_object(
    'pin_bcrypt_cost', 10,
    'usher_login_qr_token_bytes', 32,
    'upload_mime', jsonb_build_array('image/png', 'image/jpeg', 'image/webp'),
    'greeting_photo_bucket', 'greeting-photos',
    'print_ticket_fields', jsonb_build_array(
      'event_name', 'couple_names', 'event_date', 'guest_name', 'category', 'group_name', 'ticket_number', 'pax',
      'checked_in_at'),
    'print_ticket_max_copies', 3,
    'greeting_title_max', 80,
    'greeting_body_max', 300,
    'greeting_layouts', jsonb_build_array('text', 'photo_wide', 'photo_round')
  );
$$;

-- =============================================================================================
-- Helper kredensial dan perangkat
-- =============================================================================================

create function private.sha256_hex(p_value text)
returns text
language sql
immutable
set search_path = ''
as $$
  select encode(sha256(convert_to(coalesce(p_value, ''), 'UTF8')), 'hex');
$$;

create function private.try_uuid(p_value text)
returns uuid
language plpgsql
immutable
set search_path = ''
as $$
begin
  return p_value::uuid;
exception when others then
  return null;
end;
$$;

create function private.try_timestamptz(p_value text)
returns timestamptz
language plpgsql
stable
set search_path = ''
as $$
begin
  return p_value::timestamptz;
exception when others then
  return null;
end;
$$;

-- Hash lambat rahasia PIN (bcrypt). Hanya 8 karakter rahasia yang di-hash; ID usher tidak rahasia (FR-R-02).
create function private.hash_secret(p_secret text)
returns text
language sql
volatile
set search_path = ''
as $$
  select extensions.crypt(p_secret, extensions.gen_salt('bf', (private.config() ->> 'pin_bcrypt_cost')::integer));
$$;

-- SATU-SATUNYA tempat verifikasi bcrypt. pgTAP 070 mengganti fungsi ini sementara untuk menghitung
-- panggilannya dan membuktikan "tepat satu bcrypt per percobaan".
create function private.verify_secret(p_secret text, p_hash text)
returns boolean
language sql
volatile
set search_path = ''
as $$
  select extensions.crypt(coalesce(p_secret, ''), p_hash) = p_hash;
$$;

-- Hash dummy untuk percobaan yang tidak menemukan usher, dengan biaya bcrypt yang sama. Dibuat saat migration
-- dari 32 byte acak yang langsung dibuang, sehingga tidak ada nilai hash di repo dan tidak ada rahasia yang cocok.
do $$
begin
  execute format(
    'create function private.dummy_secret_hash() returns text language sql immutable set search_path = %L as %L',
    '',
    format('select %L::text', extensions.crypt(
      encode(extensions.gen_random_bytes(32), 'hex'),
      extensions.gen_salt('bf', (private.config() ->> 'pin_bcrypt_cost')::integer)))
  );
end;
$$;

-- Sesi usher berakhir H+offset pukul HH:MM waktu lokal event (FR-R-10).
create function private.session_expiry(p_event_date date, p_timezone text)
returns timestamptz
language sql
stable
set search_path = ''
as $$
  select ((p_event_date + (private.config() ->> 'usher_session_end_day_offset')::integer)
          + (private.config() ->> 'usher_session_end_local_time')::time) at time zone p_timezone;
$$;

-- Kode perangkat: indeks 0..25 → A..Z, 26..701 → AA..ZZ. Sama dengan deviceCode() di packages/shared.
create function private.device_code(p_index integer)
returns text
language sql
immutable
set search_path = ''
as $$
  select case
    when p_index < 26 then chr(65 + p_index)
    else chr(65 + (p_index - 26) / 26) || chr(65 + (p_index - 26) % 26)
  end;
$$;

create function private.device_code_index(p_code text)
returns integer
language sql
immutable
set search_path = ''
as $$
  select case
    when length(p_code) = 1 then ascii(p_code) - 65
    else 26 + (ascii(substr(p_code, 1, 1)) - 65) * 26 + (ascii(substr(p_code, 2, 1)) - 65)
  end;
$$;

-- PIN tampilan `AB-XXXX-XXXX`.
create function private.format_pin(p_selector text, p_secret text)
returns text
language sql
immutable
set search_path = ''
as $$
  select p_selector || '-' || substr(p_secret, 1, 4) || '-' || substr(p_secret, 5, 4);
$$;

-- Token acak base64url tanpa padding.
create function private.random_token(p_bytes integer)
returns text
language sql
volatile
set search_path = ''
as $$
  select rtrim(translate(encode(extensions.gen_random_bytes(p_bytes), 'base64'), E'+/\n', '-_'), '=');
$$;

-- =============================================================================================
-- Perangkat: tingkat pencabutan hanya bisa naik (FR-R-08)
-- =============================================================================================

create function private.devices_guard_revoke()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if old.revoked_at is not null and new.revoked_at is null then
    raise exception 'Pencabutan perangkat tidak bisa dibatalkan.' using errcode = '22023';
  end if;
  if old.revoke_mode = 'terminate' and new.revoke_mode is distinct from 'terminate' then
    raise exception 'Tingkat pencabutan tidak bisa diturunkan.' using errcode = '22023';
  end if;
  if old.auth_user_deleted_at is not null and new.auth_user_deleted_at is distinct from old.auth_user_deleted_at then
    raise exception 'Status penghapusan user Auth tidak bisa diubah.' using errcode = '22023';
  end if;
  return new;
end;
$$;

create trigger devices_guard_revoke before update on public.devices
  for each row execute function private.devices_guard_revoke();

-- =============================================================================================
-- Validasi isi jsonb pengaturan dan sapaan (prd.md 10.4: server memvalidasi ulang)
-- =============================================================================================

-- Print Tiket Penomoran (FR-R-04). SECURITY DEFINER karena dipanggil CHECK saat Admin menulis lewat PostgREST
-- dan membaca private.config(), yang tidak di-GRANT ke authenticated.
create function private.print_ticket_issue(p jsonb)
returns text
language sql
immutable
security definer
set search_path = ''
as $$
  select case
    when jsonb_typeof(p) is distinct from 'object' then 'not_object'
    when exists (select 1 from jsonb_object_keys(p) k where k not in ('enabled', 'fields', 'categories', 'copies'))
      then 'unknown_key'
    when jsonb_typeof(p -> 'enabled') is distinct from 'boolean' then 'enabled'
    -- Setiap cast berada di cabang WHEN tersendiri setelah pemeriksaan tipe (urutan OR tidak dijamin).
    when jsonb_typeof(p -> 'fields') is distinct from 'array' then 'fields'
    when exists (select 1 from jsonb_array_elements(p -> 'fields') f
                 where jsonb_typeof(f) <> 'string' or not ((private.config() -> 'print_ticket_fields') ? (f #>> '{}')))
      then 'fields'
    when jsonb_typeof(p -> 'categories') is distinct from 'array' then 'categories'
    when exists (select 1 from jsonb_array_elements(p -> 'categories') c
                 where jsonb_typeof(c) <> 'string' or (c #>> '{}') not in ('regular', 'vip', 'vvip'))
      then 'categories'
    when jsonb_typeof(p -> 'copies') is distinct from 'number' then 'copies'
    when (p ->> 'copies')::numeric <> trunc((p ->> 'copies')::numeric)
      or (p ->> 'copies')::numeric not between 1 and (private.config() ->> 'print_ticket_max_copies')::numeric
      then 'copies'
    else null
  end;
$$;

-- Pop-up sapaan (FR-P-01). Foto harus berada di folder acara dan kategori yang sama, sehingga Admin tidak bisa
-- menautkan foto milik acara lain ke snapshot perangkatnya.
create function private.greeting_popup_issue(p_event_id uuid, p_category public.guest_category, p jsonb)
returns text
language sql
immutable
security definer
set search_path = ''
as $$
  select case
    when jsonb_typeof(p) is distinct from 'object' then 'not_object'
    when exists (select 1 from jsonb_object_keys(p) k
                 where k not in ('title', 'body', 'layout', 'photo_path', 'photo_version')) then 'unknown_key'
    when p ? 'title' and (jsonb_typeof(p -> 'title') <> 'string'
                          or char_length(p ->> 'title') > (private.config() ->> 'greeting_title_max')::integer) then 'title'
    when p ? 'body' and (jsonb_typeof(p -> 'body') <> 'string'
                         or char_length(p ->> 'body') > (private.config() ->> 'greeting_body_max')::integer) then 'body'
    when p ? 'layout' and (jsonb_typeof(p -> 'layout') <> 'string'
                           or not ((private.config() -> 'greeting_layouts') ? (p ->> 'layout'))) then 'layout'
    when p ? 'photo_path' and jsonb_typeof(p -> 'photo_path') <> 'null'
      and (jsonb_typeof(p -> 'photo_path') <> 'string'
           or (p ->> 'photo_path') !~ ('^' || p_event_id::text || '/' || p_category::text
                                        || '/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.(png|jpg|webp)$'))
      then 'photo_path'
    when p ? 'photo_version' and jsonb_typeof(p -> 'photo_version') <> 'number' then 'photo_version'
    when p ? 'photo_version' and ((p ->> 'photo_version')::numeric < 0
                                  or (p ->> 'photo_version')::numeric <> trunc((p ->> 'photo_version')::numeric))
      then 'photo_version'
    else null
  end;
$$;

alter table public.checkin_settings drop constraint checkin_settings_print_ticket_shape;
alter table public.checkin_settings
  add constraint checkin_settings_print_ticket_rule check (private.print_ticket_issue(print_ticket) is null);
alter table public.greeting_configs
  add constraint greeting_configs_popup_rule check (private.greeting_popup_issue(event_id, category, popup) is null);

-- =============================================================================================
-- Kelola Penerima Tamu (FR-R-01, FR-R-02)
-- =============================================================================================

create function private.assert_event_writable(p_event_id uuid)
returns void
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if exists (select 1 from public.events where id = p_event_id and archived_at is not null) then
    raise exception 'Acara sudah diarsipkan.' using errcode = '22023';
  end if;
end;
$$;

create function private.admin_create_usher(p_event_id uuid, p_name text, p_mode public.usher_mode)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_alphabet text := private.config() ->> 'code_alphabet';
  v_selector text;
  v_secret text := private.gen_code((private.config() ->> 'pin_secret_length')::integer);
  v_id uuid;
  v_attempt integer := 0;
begin
  perform private.assert_event_admin(p_event_id);
  perform private.assert_event_writable(p_event_id);

  -- ID usher acak yang belum pernah dipakai di acara ini (termasuk usher yang sudah dihapus).
  loop
    select a || b into v_selector
    from unnest(string_to_array(v_alphabet, null)) a, unnest(string_to_array(v_alphabet, null)) b
    where not exists (select 1 from public.ushers u where u.event_id = p_event_id and u.pin_selector = a || b)
    order by random()
    limit 1;
    if v_selector is null then
      raise exception 'ID Penerima Tamu untuk acara ini sudah habis.' using errcode = '22023';
    end if;
    begin
      insert into public.ushers (event_id, name, mode, pin_selector, pin_hash)
      values (p_event_id, btrim(p_name), p_mode, v_selector, private.hash_secret(v_secret))
      returning id into v_id;
      exit;
    exception when unique_violation then
      v_attempt := v_attempt + 1;
      if v_attempt >= 5 then raise; end if;
    end;
  end loop;

  perform private.audit(p_event_id, 'usher_created', 'ushers', v_id::text, null,
    jsonb_build_object('name', btrim(p_name), 'mode', p_mode, 'pin_selector', v_selector));
  -- PIN lengkap hanya dikembalikan di sini, sekali. Yang tersimpan hanya hash rahasianya.
  return jsonb_build_object('usher_id', v_id, 'pin_selector', v_selector, 'pin', private.format_pin(v_selector, v_secret));
end;
$$;

-- Cabut (tingkat quarantine) semua perangkat aktif seorang usher. Dipakai saat usher dinonaktifkan/dihapus.
create function private.revoke_usher_devices(p_usher_id uuid, p_cause text)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  d record;
  v_count integer := 0;
begin
  for d in
    update public.devices set revoked_at = now(), revoked_by = (select auth.uid()), revoke_mode = 'quarantine',
                              revoke_reason = p_cause
    where usher_id = p_usher_id and revoked_at is null
    returning id, event_id, code
  loop
    perform private.audit(d.event_id, 'device_revoked', 'devices', d.id::text, null,
      jsonb_build_object('code', d.code, 'mode', 'quarantine', 'reason', p_cause));
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;

create function private.admin_update_usher(p_usher_id uuid, p_patch jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_before public.ushers;
  v_after public.ushers;
  v_key text;
  v_revoked integer := 0;
begin
  select * into v_before from public.ushers where id = p_usher_id and deleted_at is null;
  if not found then
    raise exception 'Penerima Tamu tidak ditemukan.' using errcode = 'P0002';
  end if;
  perform private.assert_event_admin(v_before.event_id);
  if jsonb_typeof(p_patch) is distinct from 'object' then
    raise exception 'Data perubahan tidak valid.' using errcode = '22023';
  end if;
  for v_key in select jsonb_object_keys(p_patch) loop
    if not v_key = any (array['name', 'mode', 'is_active']) then
      raise exception 'Kolom "%" tidak bisa diubah.', v_key using errcode = '22023';
    end if;
  end loop;

  update public.ushers set
    name = case when p_patch ? 'name' then btrim(p_patch ->> 'name') else name end,
    mode = case when p_patch ? 'mode' then (p_patch ->> 'mode')::public.usher_mode else mode end,
    is_active = case when p_patch ? 'is_active' then (p_patch ->> 'is_active')::boolean else is_active end
  where id = p_usher_id
  returning * into v_after;

  -- Menonaktifkan usher mencabut semua perangkatnya dengan tingkat Cabut (FR-R-02).
  if v_before.is_active and not v_after.is_active then
    v_revoked := private.revoke_usher_devices(p_usher_id, 'Penerima Tamu dinonaktifkan');
  end if;

  perform private.audit(v_before.event_id, 'usher_updated', 'ushers', p_usher_id::text,
    jsonb_build_object('name', v_before.name, 'mode', v_before.mode, 'is_active', v_before.is_active),
    jsonb_build_object('name', v_after.name, 'mode', v_after.mode, 'is_active', v_after.is_active,
                       'revoked_devices', v_revoked));
  return jsonb_build_object('revoked_devices', v_revoked);
end;
$$;

create function private.admin_delete_usher(p_usher_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_usher public.ushers;
  v_revoked integer;
begin
  select * into v_usher from public.ushers where id = p_usher_id and deleted_at is null;
  if not found then
    raise exception 'Penerima Tamu tidak ditemukan.' using errcode = 'P0002';
  end if;
  perform private.assert_event_admin(v_usher.event_id);

  update public.ushers set deleted_at = now(), is_active = false where id = p_usher_id;
  update public.usher_login_tokens set expires_at = least(expires_at, now())
  where usher_id = p_usher_id and used_at is null;
  v_revoked := private.revoke_usher_devices(p_usher_id, 'Penerima Tamu dihapus');

  perform private.audit(v_usher.event_id, 'usher_deleted', 'ushers', p_usher_id::text,
    jsonb_build_object('name', v_usher.name, 'pin_selector', v_usher.pin_selector),
    jsonb_build_object('revoked_devices', v_revoked));
  return jsonb_build_object('revoked_devices', v_revoked);
end;
$$;

-- Reset PIN: rahasia baru, ID usher tetap; PIN lama langsung tidak berlaku (FR-R-02).
create function private.admin_reset_usher_pin(p_usher_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_usher public.ushers;
  v_secret text := private.gen_code((private.config() ->> 'pin_secret_length')::integer);
begin
  select * into v_usher from public.ushers where id = p_usher_id and deleted_at is null;
  if not found then
    raise exception 'Penerima Tamu tidak ditemukan.' using errcode = 'P0002';
  end if;
  perform private.assert_event_admin(v_usher.event_id);

  update public.ushers set pin_hash = private.hash_secret(v_secret) where id = p_usher_id;
  perform private.audit(v_usher.event_id, 'usher_pin_reset', 'ushers', p_usher_id::text, null,
    jsonb_build_object('pin_selector', v_usher.pin_selector));
  return jsonb_build_object('pin', private.format_pin(v_usher.pin_selector, v_secret));
end;
$$;

-- QR Login: token sekali pakai, berlaku 5 menit, hanya hash-nya yang disimpan (FR-R-02). Token lama yang belum
-- terpakai untuk usher yang sama langsung kedaluwarsa, sehingga hanya QR yang terakhir ditampilkan yang berlaku.
create function private.admin_create_login_qr(p_usher_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_usher public.ushers;
  v_token text := private.random_token((private.config() ->> 'usher_login_qr_token_bytes')::integer);
  v_expires timestamptz := now() + make_interval(secs => (private.config() ->> 'qr_login_ttl_sec')::integer);
begin
  select * into v_usher from public.ushers where id = p_usher_id and deleted_at is null;
  if not found then
    raise exception 'Penerima Tamu tidak ditemukan.' using errcode = 'P0002';
  end if;
  perform private.assert_event_admin(v_usher.event_id);
  perform private.assert_event_writable(v_usher.event_id);
  if not v_usher.is_active then
    raise exception 'Penerima Tamu nonaktif. Aktifkan dulu sebelum menampilkan QR Login.' using errcode = '22023';
  end if;

  update public.usher_login_tokens set expires_at = now()
  where usher_id = p_usher_id and used_at is null and expires_at > now();
  insert into public.usher_login_tokens (usher_id, token_hash, expires_at, created_by)
  values (p_usher_id, private.sha256_hex(v_token), v_expires, (select auth.uid()));

  perform private.audit(v_usher.event_id, 'usher_login_qr_created', 'ushers', p_usher_id::text, null,
    jsonb_build_object('expires_at', v_expires));
  return jsonb_build_object('token', v_token, 'expires_at', v_expires);
end;
$$;

-- Cabut (quarantine) atau Cabut & putus total (terminate). Terminate dipanggil Edge Function device-cleanup
-- dengan JWT Admin, lalu user Auth perangkat dihapus. Memanggil ulang tingkat yang sama tidak mengubah apa pun.
create function private.admin_revoke_device(p_device_id uuid, p_mode public.revoke_mode, p_reason text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_device public.devices;
  v_reason text := nullif(btrim(p_reason), '');
begin
  select * into v_device from public.devices where id = p_device_id;
  if not found then
    raise exception 'Perangkat tidak ditemukan.' using errcode = 'P0002';
  end if;
  perform private.assert_event_admin(v_device.event_id);
  if p_mode is null then
    raise exception 'Tingkat pencabutan wajib diisi.' using errcode = '22023';
  end if;
  if p_mode = 'terminate' and v_reason is null then
    raise exception 'Alasan wajib diisi untuk Cabut & putus total.' using errcode = '22023';
  end if;
  if v_device.revoke_mode = 'terminate' and p_mode = 'quarantine' then
    raise exception 'Tingkat pencabutan tidak bisa diturunkan.' using errcode = '22023';
  end if;
  if v_device.revoke_mode = p_mode then
    return jsonb_build_object('device_id', p_device_id, 'revoke_mode', p_mode, 'changed', false);
  end if;

  update public.devices set
    revoked_at = coalesce(revoked_at, now()),
    revoked_by = (select auth.uid()),
    revoke_mode = p_mode,
    revoke_reason = coalesce(v_reason, revoke_reason)
  where id = p_device_id;

  perform private.audit(v_device.event_id, 'device_revoked', 'devices', p_device_id::text,
    jsonb_build_object('mode', v_device.revoke_mode),
    jsonb_build_object('code', v_device.code, 'mode', p_mode, 'reason', v_reason));
  return jsonb_build_object('device_id', p_device_id, 'revoke_mode', p_mode, 'changed', true);
end;
$$;

-- =============================================================================================
-- Peringatan dashboard (FR-R-08, FR-R-09)
-- =============================================================================================

-- Kegagalan PIN yang dihitung untuk blokir: percobaan yang diblokir tidak ikut dihitung, agar blokir tidak
-- terus diperpanjang oleh percobaan yang memang sudah ditolak tanpa bcrypt.
create function private.login_failures(p_since timestamptz)
returns setof public.auth_attempts
language sql
stable
security definer
set search_path = ''
as $$
  select * from public.auth_attempts
  where kind = 'usher_login' and method = 'pin' and not success and reason not like 'blocked%'
    and created_at > p_since;
$$;

create function private.get_alerts(p_event_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  c jsonb := private.config();
  v_window interval := make_interval(mins => (c ->> 'usher_login_window_min')::integer);
  v_key_fails integer := (c ->> 'usher_login_pin_block_fails')::integer;
  v_ip_fails integer := (c ->> 'usher_login_ip_block_fails')::integer;
  v_warn integer := (c ->> 'usher_login_event_warn_fails')::integer;
  v_limit integer := (c ->> 'quarantine_max_items_per_device')::integer;
  v_code text;
  v_blocked jsonb;
  v_failures integer;
  v_quarantine jsonb;
begin
  perform private.assert_event_admin(p_event_id);
  select code into v_code from public.events where id = p_event_id;

  -- Blokir berakhir saat kegagalan ke-N terbaru keluar dari jendela waktu.
  with fails as (select ip, event_code, created_at from private.login_failures(now() - v_window)),
  key_blocks as (
    select ip, 'key' as scope, (array_agg(created_at order by created_at desc))[v_key_fails] + v_window as until
    from fails where event_code = v_code group by ip having count(*) >= v_key_fails
  ),
  ip_blocks as (
    select ip, 'ip' as scope, (array_agg(created_at order by created_at desc))[v_ip_fails] + v_window as until
    from fails group by ip having count(*) >= v_ip_fails
       -- IP yang mencoba Kode Acara ini, termasuk percobaan yang sudah ditolak blokir (usher di lokasi).
       and ip in (select a.ip from public.auth_attempts a
                  where a.kind = 'usher_login' and a.method = 'pin' and a.event_code = v_code
                    and a.created_at > now() - v_window)
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'ip', b.ip, 'scope', b.scope,
           'retryAfterSec', greatest(1, ceil(extract(epoch from b.until - now()))::integer)) order by b.until desc), '[]')
  into v_blocked
  from (select * from key_blocks union all select * from ip_blocks) b;

  select count(*)::integer into v_failures from private.login_failures(now() - v_window) f where f.event_id = p_event_id;

  select coalesce(jsonb_agg(jsonb_build_object('deviceId', q.device_id, 'code', q.code, 'count', q.n) order by q.code), '[]')
  into v_quarantine
  from (
    select d.id as device_id, d.code, count(ci.id)::integer as n
    from public.devices d join public.check_ins ci on ci.device_id = d.id and ci.status = 'quarantined'
    where d.event_id = p_event_id
    group by d.id, d.code
    having count(ci.id) >= v_limit
  ) q;

  return jsonb_build_object(
    'blocked', v_blocked,
    'loginFailures', jsonb_build_object('count', v_failures, 'threshold', v_warn,
                                        'windowMin', (c ->> 'usher_login_window_min')::integer,
                                        'warning', v_failures >= v_warn),
    'quarantineFull', v_quarantine);
end;
$$;

-- =============================================================================================
-- Pembungkus public (SECURITY INVOKER)
-- =============================================================================================

create function public.admin_create_usher(p_event_id uuid, p_name text, p_mode public.usher_mode default 'check_in')
returns jsonb language sql set search_path = ''
as $$ select private.admin_create_usher(p_event_id, p_name, p_mode) $$;

create function public.admin_update_usher(p_usher_id uuid, p_patch jsonb)
returns jsonb language sql set search_path = ''
as $$ select private.admin_update_usher(p_usher_id, p_patch) $$;

create function public.admin_delete_usher(p_usher_id uuid)
returns jsonb language sql set search_path = ''
as $$ select private.admin_delete_usher(p_usher_id) $$;

create function public.admin_reset_usher_pin(p_usher_id uuid)
returns jsonb language sql set search_path = ''
as $$ select private.admin_reset_usher_pin(p_usher_id) $$;

create function public.admin_create_login_qr(p_usher_id uuid)
returns jsonb language sql set search_path = ''
as $$ select private.admin_create_login_qr(p_usher_id) $$;

create function public.admin_revoke_device(p_device_id uuid, p_mode public.revoke_mode, p_reason text default null)
returns jsonb language sql set search_path = ''
as $$ select private.admin_revoke_device(p_device_id, p_mode, p_reason) $$;

create function public.get_alerts(p_event_id uuid)
returns jsonb language sql stable set search_path = ''
as $$ select private.get_alerts(p_event_id) $$;

-- =============================================================================================
-- Hak eksekusi (aturan 5): fungsi baru di-REVOKE eksplisit, lalu GRANT seperlunya.
-- CREATE OR REPLACE private.config() mempertahankan ACL lamanya (tanpa grant ke role API).
-- =============================================================================================

revoke all on function private.sha256_hex(text) from public, anon, authenticated, service_role;
revoke all on function private.try_uuid(text) from public, anon, authenticated, service_role;
revoke all on function private.try_timestamptz(text) from public, anon, authenticated, service_role;
revoke all on function private.hash_secret(text) from public, anon, authenticated, service_role;
revoke all on function private.verify_secret(text, text) from public, anon, authenticated, service_role;
revoke all on function private.dummy_secret_hash() from public, anon, authenticated, service_role;
revoke all on function private.session_expiry(date, text) from public, anon, authenticated, service_role;
revoke all on function private.device_code(integer) from public, anon, authenticated, service_role;
revoke all on function private.device_code_index(text) from public, anon, authenticated, service_role;
revoke all on function private.format_pin(text, text) from public, anon, authenticated, service_role;
revoke all on function private.random_token(integer) from public, anon, authenticated, service_role;
revoke all on function private.devices_guard_revoke() from public, anon, authenticated, service_role;
revoke all on function private.print_ticket_issue(jsonb) from public, anon, authenticated, service_role;
revoke all on function private.greeting_popup_issue(uuid, public.guest_category, jsonb) from public, anon, authenticated, service_role;
revoke all on function private.assert_event_writable(uuid) from public, anon, authenticated, service_role;
revoke all on function private.admin_create_usher(uuid, text, public.usher_mode) from public, anon, authenticated, service_role;
revoke all on function private.revoke_usher_devices(uuid, text) from public, anon, authenticated, service_role;
revoke all on function private.admin_update_usher(uuid, jsonb) from public, anon, authenticated, service_role;
revoke all on function private.admin_delete_usher(uuid) from public, anon, authenticated, service_role;
revoke all on function private.admin_reset_usher_pin(uuid) from public, anon, authenticated, service_role;
revoke all on function private.admin_create_login_qr(uuid) from public, anon, authenticated, service_role;
revoke all on function private.admin_revoke_device(uuid, public.revoke_mode, text) from public, anon, authenticated, service_role;
revoke all on function private.login_failures(timestamptz) from public, anon, authenticated, service_role;
revoke all on function private.get_alerts(uuid) from public, anon, authenticated, service_role;
revoke all on function public.admin_create_usher(uuid, text, public.usher_mode) from public, anon, authenticated, service_role;
revoke all on function public.admin_update_usher(uuid, jsonb) from public, anon, authenticated, service_role;
revoke all on function public.admin_delete_usher(uuid) from public, anon, authenticated, service_role;
revoke all on function public.admin_reset_usher_pin(uuid) from public, anon, authenticated, service_role;
revoke all on function public.admin_create_login_qr(uuid) from public, anon, authenticated, service_role;
revoke all on function public.admin_revoke_device(uuid, public.revoke_mode, text) from public, anon, authenticated, service_role;
revoke all on function public.get_alerts(uuid) from public, anon, authenticated, service_role;

-- CHECK constraint dievaluasi dengan hak role penulis (Admin lewat PostgREST).
grant execute on function private.print_ticket_issue(jsonb) to authenticated;
grant execute on function private.greeting_popup_issue(uuid, public.guest_category, jsonb) to authenticated;

grant execute on function public.admin_create_usher(uuid, text, public.usher_mode) to authenticated;
grant execute on function private.admin_create_usher(uuid, text, public.usher_mode) to authenticated;
grant execute on function public.admin_update_usher(uuid, jsonb) to authenticated;
grant execute on function private.admin_update_usher(uuid, jsonb) to authenticated;
grant execute on function public.admin_delete_usher(uuid) to authenticated;
grant execute on function private.admin_delete_usher(uuid) to authenticated;
grant execute on function public.admin_reset_usher_pin(uuid) to authenticated;
grant execute on function private.admin_reset_usher_pin(uuid) to authenticated;
grant execute on function public.admin_create_login_qr(uuid) to authenticated;
grant execute on function private.admin_create_login_qr(uuid) to authenticated;
grant execute on function public.admin_revoke_device(uuid, public.revoke_mode, text) to authenticated;
grant execute on function private.admin_revoke_device(uuid, public.revoke_mode, text) to authenticated;
grant execute on function public.get_alerts(uuid) to authenticated;
grant execute on function private.get_alerts(uuid) to authenticated;
