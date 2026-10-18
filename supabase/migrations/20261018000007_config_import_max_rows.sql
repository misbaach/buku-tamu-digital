-- Batas baris impor dipindahkan ke konfigurasi bersama (config.ts IMPORT_MAX_ROWS) alih-alih angka tetap.

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
  );
$$;

create or replace function private.admin_import_guests(p_event_id uuid, p_rows jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  r jsonb;
  v_row text := '?';
  v_group_name text;
  v_group_id uuid;
  v_inserted integer := 0;
  v_groups_created integer := 0;
  v_max integer := (private.config() ->> 'import_max_rows')::integer;
begin
  perform private.assert_event_admin(p_event_id);
  if jsonb_typeof(p_rows) is distinct from 'array' then
    raise exception 'Data impor tidak valid.' using errcode = '22023';
  end if;
  if jsonb_array_length(p_rows) > v_max then
    raise exception 'Maksimal % baris per impor.', v_max using errcode = '22023';
  end if;

  begin
    for r in select value from jsonb_array_elements(p_rows) loop
      v_row := coalesce(r ->> 'row', '?');
      v_group_id := null;
      v_group_name := nullif(btrim(r ->> 'group'), '');
      if v_group_name is not null then
        select id into v_group_id from public.guest_groups
        where event_id = p_event_id and deleted_at is null and lower(btrim(name)) = lower(v_group_name);
        if v_group_id is null then
          insert into public.guest_groups (event_id, name) values (p_event_id, v_group_name) returning id into v_group_id;
          v_groups_created := v_groups_created + 1;
        end if;
      end if;

      insert into public.guests (
        event_id, name, phone, category, group_id, invited_pax, special_number, rsvp_status, rsvp_pax, notes
      ) values (
        p_event_id,
        btrim(r ->> 'name'),
        nullif(btrim(r ->> 'phone'), ''),
        coalesce((r ->> 'category')::public.guest_category, 'regular'),
        v_group_id,
        coalesce((r ->> 'invited_pax')::smallint, 1),
        nullif(btrim(r ->> 'special_number'), ''),
        coalesce((r ->> 'rsvp_status')::public.rsvp_status, 'unconfirmed'),
        (r ->> 'rsvp_pax')::smallint,
        nullif(btrim(r ->> 'notes'), '')
      );
      v_inserted := v_inserted + 1;
    end loop;
  exception when others then
    raise exception 'Baris %: %', v_row, sqlerrm using errcode = sqlstate;
  end;

  perform private.audit(p_event_id, 'guests_imported', 'guests', null, null,
    jsonb_build_object('inserted', v_inserted, 'groups_created', v_groups_created));
  return jsonb_build_object('inserted', v_inserted, 'groups_created', v_groups_created);
end;
$$;

-- CREATE OR REPLACE mempertahankan ACL fungsi yang sudah ada; REVOKE ulang untuk berjaga-jaga (aturan 5).
revoke all on function private.config() from public, anon, authenticated, service_role;
revoke all on function private.admin_import_guests(uuid, jsonb) from public, anon, service_role;
grant execute on function private.admin_import_guests(uuid, jsonb) to authenticated;
