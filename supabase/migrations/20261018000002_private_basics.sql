-- Fungsi dasar di schema private (tidak diekspos API).

-- Cermin DB_MIRRORED_CONFIG di packages/shared/src/config.ts.
-- tests/integration/config-parity.test.ts gagal bila nilainya berbeda; ubah lewat migration baru.
create function private.config()
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
    'upload_max_bytes', 5242880
  );
$$;

-- Kode acak dari alfabet tanpa karakter mirip (Kode Acara, ID usher, rahasia PIN).
-- Satu byte acak per karakter; byte >= 248 dibuang agar sebaran tetap merata (248 = 31 * 8).
create function private.gen_code(p_length integer)
returns text
language plpgsql
volatile
set search_path = ''
as $$
declare
  v_alphabet constant text := (private.config() ->> 'code_alphabet');
  v_result text := '';
  v_byte integer;
begin
  while length(v_result) < p_length loop
    v_byte := get_byte(extensions.gen_random_bytes(1), 0);
    if v_byte < 248 then
      v_result := v_result || substr(v_alphabet, (v_byte % 31) + 1, 1);
    end if;
  end loop;
  return v_result;
end;
$$;

-- Token QR tamu: 18 byte acak (144 bit) dalam base64url tanpa padding (24 karakter). FR-G-07
create function private.gen_qr_token()
returns text
language sql
volatile
set search_path = ''
as $$
  select translate(encode(extensions.gen_random_bytes(18), 'base64'), '+/', '-_');
$$;

-- Aturan Nomor Urut khusus (FR-C-02) untuk nilai yang sudah dinormalisasi.
-- Kode masalahnya sama dengan checkSpecialNumber() di packages/shared/src/patterns.ts.
create function private.special_number_issue(p_value text)
returns text
language sql
immutable
set search_path = ''
as $$
  select case
    when p_value is null then null
    when p_value = '' then 'empty'
    when char_length(p_value) > 20 then 'too_long'
    when p_value !~ '^[A-Z0-9-]+$' then 'invalid_chars'
    when p_value ~ '^[A-Z]{1,2}-[0-9]+$' then 'device_pattern'
    when p_value ~ '^[A-Z]{1,2}-H[0-9]+$' then 'gift_pattern'
    else null
  end;
$$;

-- Trigger umum: updated_at selalu jam server. Kursor delta sync memakai kolom ini (12.3 poin 8).
create function private.set_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

revoke all on all functions in schema private from public, anon, authenticated, service_role;

-- Dipakai CHECK constraint dan default kolom pada tabel yang ditulis Admin lewat PostgREST,
-- sehingga role pemanggil perlu EXECUTE. Fungsi lain hanya dipanggil fungsi SECURITY DEFINER.
grant execute on function private.special_number_issue(text) to authenticated;
grant execute on function private.gen_qr_token() to authenticated;
