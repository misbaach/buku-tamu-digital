-- M2 — Sinkronisasi usher: pull_snapshot dan push_outbox (prd.md 11.5 langkah 5, 12.2, 12.3; plan.md bagian 10).
-- Usher tidak punya hak tabel; dua RPC ini satu-satunya jalur, dan keduanya memeriksa ulang devices/events di
-- setiap panggilan karena JWT tetap valid sampai kedaluwarsa.

-- Konteks perangkat pemanggil. `access_state`:
--   active | quarantine:device_revoked | quarantine:session_expired
--   rejected:terminated | rejected:event_archived | rejected:quarantine_window_closed
create function private.usher_context(
  p_now timestamptz,
  out device_id uuid, out event_id uuid, out usher_id uuid, out device_code text, out usher_mode public.usher_mode,
  out session_expires_at timestamptz, out revoke_mode public.revoke_mode, out access_state text
)
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_meta jsonb := coalesce((select auth.jwt()) -> 'app_metadata', '{}'::jsonb);
  v_grace interval := make_interval(hours => (private.config() ->> 'session_grace_hours')::integer);
  v_device public.devices;
  v_event public.events;
  v_usher public.ushers;
begin
  -- Klaim hanya dari app_metadata (ditulis service role), lalu dicocokkan dengan tabel devices (aturan 3).
  if v_meta ->> 'role' is distinct from 'usher' then
    raise exception 'Hanya perangkat Penerima Tamu yang bisa memanggil fungsi ini.' using errcode = '42501';
  end if;
  select * into v_device from public.devices d where d.id = private.try_uuid(v_meta ->> 'device_id');
  if v_device.id is null
     or v_device.auth_user_id is distinct from (select auth.uid())
     or v_device.event_id is distinct from private.try_uuid(v_meta ->> 'event_id')
     or v_device.usher_id is distinct from private.try_uuid(v_meta ->> 'usher_id') then
    raise exception 'Perangkat tidak dikenal.' using errcode = '42501';
  end if;
  select * into v_event from public.events e where e.id = v_device.event_id;
  select * into v_usher from public.ushers u where u.id = v_device.usher_id;

  device_id := v_device.id;
  event_id := v_device.event_id;
  usher_id := v_device.usher_id;
  device_code := v_device.code;
  usher_mode := v_usher.mode;
  session_expires_at := v_device.session_expires_at;
  revoke_mode := v_device.revoke_mode;
  access_state := case
    when v_device.revoke_mode = 'terminate' then 'rejected:terminated'
    when v_event.archived_at is not null then 'rejected:event_archived'
    -- Perangkat dicabut memakai jendela sampai session_expires_at, tanpa masa tenggang (K31).
    when v_device.revoke_mode = 'quarantine' and p_now >= v_device.session_expires_at
      then 'rejected:quarantine_window_closed'
    when v_device.revoke_mode is null and p_now >= v_device.session_expires_at + v_grace
      then 'rejected:quarantine_window_closed'
    when v_device.revoke_mode = 'quarantine' then 'quarantine:device_revoked'
    when p_now >= v_device.session_expires_at then 'quarantine:session_expired'
    else 'active'
  end;
end;
$$;

-- last_seen_at dan selisih jam perangkat (FR-R-08 daftar perangkat, 12.3 poin 9).
create function private.touch_device(p_device_id uuid, p_now timestamptz, p_client_now timestamptz)
returns void
language sql
security definer
set search_path = ''
as $$
  update public.devices set
    last_seen_at = p_now,
    clock_offset_ms = case when p_client_now is null then clock_offset_ms
      else greatest(least(round(extract(epoch from (p_client_now - p_now)) * 1000), 2147483647), -2147483648)::integer end
  where id = p_device_id;
$$;

-- Kursor delta sync: teks base64url opak berisi {v, e, s, p, a, i}.
--   e = event; s = batas bawah updated_at (inklusif; null = snapshot penuh); p = jam server awal putaran;
--   a/i = posisi keyset (updated_at, id) di dalam putaran.
create function private.encode_cursor(p jsonb)
returns text
language sql
immutable
set search_path = ''
as $$
  select rtrim(translate(encode(convert_to(p::text, 'UTF8'), 'base64'), E'+/\n', '-_'), '=');
$$;

create function private.decode_cursor(p text)
returns jsonb
language plpgsql
immutable
set search_path = ''
as $$
declare
  v text := translate(p, '-_', '+/');
begin
  v := v || repeat('=', (4 - length(v) % 4) % 4);
  return convert_from(decode(v, 'base64'), 'UTF8')::jsonb;
exception when others then
  return null;
end;
$$;

-- GuestSnapshot (12.2): 14 kunci persis. Tanpa phone, notes, qr_token, id usher/perangkat, actual_pax,
-- void_reason (FR-HM-01, aturan 7).
create function private.guest_snapshot_json(g public.guests)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'id', g.id,
    'name', g.name,
    'category', g.category,
    'groupId', g.group_id,
    'invitedPax', g.invited_pax,
    'specialNumber', g.special_number,
    'qrTokenHash', g.qr_token_hash,
    'rsvpStatus', g.rsvp_status,
    'rsvpPax', g.rsvp_pax,
    'attendanceStatus', g.attendance_status,
    'isAdditional', g.is_additional,
    -- check-in accepted aktif; bila tidak ada, yang terbaru yang tidak dibatalkan dan bukan karantina.
    'checkIn', (
      select jsonb_build_object('status', ci.status, 'ticketNumber', ci.ticket_number,
                                'checkedInAt', ci.checked_in_at, 'usherName', u.name)
      from public.check_ins ci left join public.ushers u on u.id = ci.usher_id
      where ci.event_id = g.event_id and ci.guest_id = g.id and ci.voided_at is null and ci.status <> 'quarantined'
      order by (ci.status = 'accepted') desc, ci.received_at desc, ci.id desc
      limit 1
    ),
    'updatedAt', g.updated_at,
    'deletedAt', g.deleted_at
  );
$$;

create function private.pull_snapshot(p_cursor text, p_limit integer, p_client_now timestamptz)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  c jsonb := private.config();
  v_now timestamptz := now();
  v_page_max integer := (c ->> 'snapshot_page_size')::integer;
  v_page integer := least(greatest(coalesce(p_limit, v_page_max), 1), v_page_max);
  ctx record;
  v_cur jsonb;
  v_since timestamptz;
  v_pass timestamptz;
  v_after_ts timestamptz;
  v_after_id uuid;
  v_guests jsonb;
  v_last_ts timestamptz;
  v_last_id uuid;
  v_has_more boolean := false;
  v_next jsonb;
  v_groups jsonb := '[]'::jsonb;
begin
  select * into ctx from private.usher_context(v_now);
  perform private.touch_device(ctx.device_id, v_now, p_client_now);

  -- Dicabut (tingkat apa pun) → revoked; sesi berakhir / acara diarsipkan → expired. Tanpa data apa pun,
  -- termasuk delta, dan sebelum kursor diperiksa (FR-R-08, FR-R-10).
  if ctx.revoke_mode is not null then
    return jsonb_build_object('status', 'revoked');
  end if;
  if ctx.access_state <> 'active' then
    return jsonb_build_object('status', 'expired');
  end if;

  if p_cursor is not null then
    v_cur := private.decode_cursor(p_cursor);
    begin
      if v_cur ->> 'v' is distinct from '1' or v_cur ->> 'e' is distinct from ctx.event_id::text then
        raise exception 'cursor';
      end if;
      v_since := (v_cur ->> 's')::timestamptz;
      v_pass := (v_cur ->> 'p')::timestamptz;
      v_after_ts := (v_cur ->> 'a')::timestamptz;
      v_after_id := (v_cur ->> 'i')::uuid;
    exception when others then
      raise exception 'Kursor sinkronisasi tidak valid.' using errcode = '22023';
    end;
  end if;
  v_pass := coalesce(v_pass, v_now);

  -- Snapshot penuh (s null) tanpa tamu terhapus; delta (s terisi) termasuk tombstone (12.3 poin 8).
  select coalesce(jsonb_agg(private.guest_snapshot_json(p) order by p.updated_at, p.id), '[]'::jsonb),
         (array_agg(p.updated_at order by p.updated_at desc, p.id desc))[1],
         (array_agg(p.id order by p.updated_at desc, p.id desc))[1]
  into v_guests, v_last_ts, v_last_id
  from (
    select g.* from public.guests g
    where g.event_id = ctx.event_id
      and case when v_since is null then g.deleted_at is null else g.updated_at >= v_since end
      and (v_after_ts is null or (g.updated_at, g.id) > (v_after_ts, v_after_id))
    order by g.updated_at, g.id
    limit v_page
  ) p;

  if v_last_ts is not null then
    v_has_more := exists (
      select 1 from public.guests g
      where g.event_id = ctx.event_id
        and case when v_since is null then g.deleted_at is null else g.updated_at >= v_since end
        and (g.updated_at, g.id) > (v_last_ts, v_last_id));
  end if;

  v_next := case
    when v_has_more then jsonb_build_object('v', 1, 'e', ctx.event_id, 's', v_since, 'p', v_pass,
                                            'a', v_last_ts, 'i', v_last_id)
    -- Putaran selesai: putaran berikutnya mulai dari jam server awal putaran ini dikurangi overlap.
    else jsonb_build_object('v', 1, 'e', ctx.event_id,
                            's', v_pass - make_interval(secs => (c ->> 'sync_cursor_overlap_ms')::numeric / 1000),
                            'p', null, 'a', null, 'i', null)
  end;

  -- Grup dikirim di halaman pertama setiap putaran.
  if v_after_ts is null then
    select coalesce(jsonb_agg(jsonb_build_object('id', gg.id, 'name', gg.name, 'updatedAt', gg.updated_at,
                                                 'deletedAt', gg.deleted_at) order by gg.updated_at, gg.id), '[]'::jsonb)
    into v_groups
    from public.guest_groups gg
    where gg.event_id = ctx.event_id
      and case when v_since is null then gg.deleted_at is null else gg.updated_at >= v_since end;
  end if;

  return jsonb_build_object(
    'status', 'ok',
    'serverTime', v_now,
    'nextCursor', private.encode_cursor(v_next),
    'hasMore', v_has_more,
    'event', (select jsonb_build_object('id', e.id, 'name', e.name, 'coupleNames', e.couple_names,
                                        'eventDate', e.event_date, 'timezone', e.timezone,
                                        'sessionExpiresAt', ctx.session_expires_at)
              from public.events e where e.id = ctx.event_id),
    'device', jsonb_build_object('code', ctx.device_code),
    'settings', (select jsonb_build_object('showVerification', s.show_verification,
                                           'allowMultiCheckin', s.allow_multi_checkin,
                                           'printTicket', s.print_ticket)
                 from public.checkin_settings s where s.event_id = ctx.event_id),
    'greetings', (select coalesce(jsonb_agg(jsonb_build_object(
                    'category', gc.category, 'title', gc.popup ->> 'title', 'body', gc.popup ->> 'body',
                    'layout', gc.popup ->> 'layout', 'photoPath', gc.popup ->> 'photo_path',
                    'photoVersion', coalesce((gc.popup ->> 'photo_version')::integer, 0)) order by gc.category), '[]'::jsonb)
                  from public.greeting_configs gc where gc.event_id = ctx.event_id),
    'groups', v_groups,
    'guests', v_guests
  );
end;
$$;

-- Data tamu tambahan dari perangkat (newGuest). Aturannya sama dengan constraint tabel guests.
create function private.new_guest_issue(p jsonb)
returns text
language sql
immutable
set search_path = ''
as $$
  select case
    when jsonb_typeof(p) is distinct from 'object' then 'not_object'
    when jsonb_typeof(p -> 'name') is distinct from 'string' then 'name'
    when char_length(btrim(p ->> 'name')) not between 1 and 120 then 'name'
    when jsonb_typeof(p -> 'phone') not in ('null', 'string') then 'phone'
    when nullif(btrim(p ->> 'phone'), '') !~ '^\+?[0-9][0-9 ().-]{4,22}$' then 'phone'
    when jsonb_typeof(p -> 'category') is distinct from 'string' then 'category'
    when p ->> 'category' not in ('regular', 'vip', 'vvip') then 'category'
    when jsonb_typeof(p -> 'invitedPax') is distinct from 'number' then 'invitedPax'
    when (p ->> 'invitedPax')::numeric <> trunc((p ->> 'invitedPax')::numeric)
      or (p ->> 'invitedPax')::numeric not between 1 and 50 then 'invitedPax'
    when jsonb_typeof(p -> 'notes') not in ('null', 'string') then 'notes'
    when char_length(p ->> 'notes') > 500 then 'notes'
    else null
  end;
$$;

create function private.push_stored(p_row public.check_ins)
returns jsonb
language sql
immutable
set search_path = ''
as $$
  select jsonb_build_object('id', p_row.id, 'outcome', 'stored', 'status', p_row.status, 'guestId', p_row.guest_id,
                            'ticketNumber', p_row.ticket_number, 'receivedAt', p_row.received_at);
$$;

create function private.push_outbox(p_items jsonb, p_client_now timestamptz)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  c jsonb := private.config();
  v_now timestamptz := now();
  v_qlimit integer := (c ->> 'quarantine_max_items_per_device')::integer;
  ctx record;
  v_quarantine boolean;
  v_qreason public.quarantine_reason;
  v_qcount integer := 0;
  v_limit_hit boolean := false;
  v_item jsonb;
  v_results jsonb := '[]'::jsonb;
  v_result jsonb;
  v_id uuid;
  v_existing public.check_ins;
  v_row public.check_ins;
  v_ticket text;
  v_pax integer;
  v_checked_at timestamptz;
  v_guest_id uuid;
  v_new jsonb;
  v_has_guest boolean;
  v_has_new boolean;
  v_error text;
begin
  select * into ctx from private.usher_context(v_now);
  perform private.touch_device(ctx.device_id, v_now, p_client_now);

  -- (1) Ditolak seluruhnya; tidak ada item yang disimpan, perangkat mempertahankan outbox-nya (12.3 poin 5).
  if ctx.access_state like 'rejected:%' then
    return jsonb_build_object('status', 'rejected', 'reason', split_part(ctx.access_state, ':', 2), 'results', '[]'::jsonb);
  end if;
  if ctx.usher_mode = 'check_out' then
    return jsonb_build_object('status', 'rejected', 'reason', 'mode_mismatch', 'results', '[]'::jsonb);
  end if;
  if jsonb_typeof(p_items) is distinct from 'array' then
    raise exception 'Data push tidak valid.' using errcode = '22023';
  end if;
  if jsonb_array_length(p_items) > (c ->> 'push_batch_max')::integer then
    raise exception 'Maksimal % item per push.', (c ->> 'push_batch_max') using errcode = '22023';
  end if;

  perform private.lock_event(ctx.event_id);
  v_quarantine := ctx.access_state like 'quarantine:%';
  if v_quarantine then
    v_qreason := split_part(ctx.access_state, ':', 2)::public.quarantine_reason;
    select count(*)::integer into v_qcount from public.check_ins ci
    where ci.device_id = ctx.device_id and ci.status = 'quarantined';
  end if;

  for v_item in select value from jsonb_array_elements(p_items) loop
    v_result := null;
    v_error := null;
    v_id := private.try_uuid(v_item ->> 'id');
    begin
      if jsonb_typeof(v_item) is distinct from 'object' or v_id is null then
        v_error := 'invalid_item';
      end if;

      -- (2) Idempotensi: id yang sudah ada mengembalikan status tersimpan.
      if v_error is null then
        select * into v_existing from public.check_ins ci where ci.id = v_id;
        if found then
          if v_existing.event_id <> ctx.event_id or v_existing.device_id is distinct from ctx.device_id then
            v_error := 'id_conflict';
          else
            v_result := private.push_stored(v_existing);
          end if;
        end if;
      end if;

      -- (3) Validasi. Item yang galat tidak disimpan dan tetap di outbox perangkat.
      if v_error is null and v_result is null then
        v_has_guest := coalesce(jsonb_typeof(v_item -> 'guestId') = 'string', false);
        v_has_new := coalesce(jsonb_typeof(v_item -> 'newGuest') = 'object', false);
        v_ticket := case when jsonb_typeof(v_item -> 'ticketNumber') = 'string'
                         then upper(btrim(v_item ->> 'ticketNumber')) end;
        v_checked_at := case when jsonb_typeof(v_item -> 'checkedInAt') = 'string'
                             then private.try_timestamptz(v_item ->> 'checkedInAt') end;
        v_pax := case
          when jsonb_typeof(v_item -> 'actualPax') is distinct from 'number' then null
          when (v_item ->> 'actualPax')::numeric = trunc((v_item ->> 'actualPax')::numeric)
           and (v_item ->> 'actualPax')::numeric between 0 and 50 then (v_item ->> 'actualPax')::integer
        end;

        v_error := case
          when jsonb_typeof(v_item -> 'gift') not in ('null') then 'gift_not_supported'
          when private.try_uuid(v_item ->> 'deviceId') is distinct from ctx.device_id then 'device_mismatch'
          when v_pax is null or v_checked_at is null or v_ticket is null or v_has_guest = v_has_new then 'invalid_item'
          when v_ticket !~ '^[A-Z0-9-]{1,20}$' or v_ticket ~ '^[A-Z]{1,2}-H[0-9]+$' then 'invalid_ticket_number'
          -- Nomor otomatis harus memakai kode perangkat pemanggil (12.3 poin 2–3).
          when v_ticket ~ '^[A-Z]{1,2}-[0-9]+$' and split_part(v_ticket, '-', 1) <> ctx.device_code
            then 'ticket_device_mismatch'
          when v_has_guest and not exists (
            select 1 from public.guests g
            where g.event_id = ctx.event_id and g.id = private.try_uuid(v_item ->> 'guestId')) then 'guest_not_found'
          when v_has_new and private.new_guest_issue(v_item -> 'newGuest') is not null then 'invalid_new_guest'
          when v_quarantine and v_qcount >= v_qlimit then 'quarantine_limit'
          else null
        end;
        if v_error = 'quarantine_limit' then
          v_limit_hit := true;
        end if;
      end if;

      if v_error is null and v_result is null then
        v_guest_id := case when v_has_guest then private.try_uuid(v_item ->> 'guestId') end;
        v_new := case when v_has_new then jsonb_build_object(
          'name', btrim(v_item -> 'newGuest' ->> 'name'),
          'phone', nullif(btrim(v_item -> 'newGuest' ->> 'phone'), ''),
          'category', v_item -> 'newGuest' ->> 'category',
          'invitedPax', (v_item -> 'newGuest' ->> 'invitedPax')::integer,
          'notes', nullif(btrim(v_item -> 'newGuest' ->> 'notes'), '')) end;

        if v_quarantine then
          -- (4) Karantina dievaluasi lebih dulu: disimpan apa adanya, tidak dihitung, tidak membuat tamu baru.
          insert into public.check_ins (
            id, event_id, guest_id, pending_guest, actual_pax, ticket_number, status, quarantine_reason, source,
            device_id, usher_id, created_by, checked_in_at
          ) values (
            v_id, ctx.event_id, v_guest_id, v_new, v_pax, v_ticket, 'quarantined', v_qreason, 'device',
            ctx.device_id, ctx.usher_id, (select auth.uid()), v_checked_at
          );
          v_qcount := v_qcount + 1;
        else
          -- (5) Tamu tambahan dibuat lebih dulu, lalu (6)–(8) lewat jalur status yang sama dengan Admin.
          if v_has_new then
            insert into public.guests (event_id, name, phone, category, invited_pax, notes, is_additional, created_device_id)
            values (ctx.event_id, v_new ->> 'name', v_new ->> 'phone', (v_new ->> 'category')::public.guest_category,
                    (v_new ->> 'invitedPax')::smallint, v_new ->> 'notes', true, ctx.device_id)
            returning id into v_guest_id;
          end if;
          perform private.store_check_in(v_id, ctx.event_id, v_guest_id, v_pax, v_ticket, 'device',
                                         ctx.device_id, ctx.usher_id, (select auth.uid()), v_checked_at);
        end if;
        select * into v_row from public.check_ins ci where ci.id = v_id;
        v_result := private.push_stored(v_row);
      end if;
    exception
      when check_violation or not_null_violation or foreign_key_violation or invalid_text_representation
        or numeric_value_out_of_range or invalid_datetime_format or datetime_field_overflow
        or string_data_right_truncation then
      v_error := 'invalid_item';
      v_result := null;
    end;

    v_results := v_results || jsonb_build_array(coalesce(v_result,
      jsonb_build_object('id', coalesce(v_item ->> 'id', ''), 'outcome', 'error', 'code', v_error)));
  end loop;

  -- Batas karantina terlampaui: peringatan di dashboard (get_alerts) dan audit, sekali per perangkat.
  if v_limit_hit and not exists (
    select 1 from public.audit_logs a
    where a.event_id = ctx.event_id and a.action = 'quarantine_limit_reached' and a.entity_id = ctx.device_id::text
  ) then
    perform private.audit(ctx.event_id, 'quarantine_limit_reached', 'devices', ctx.device_id::text, null,
      jsonb_build_object('code', ctx.device_code, 'limit', v_qlimit));
  end if;

  return jsonb_build_object(
    'status', case when not v_quarantine then 'ok' when v_qreason = 'device_revoked' then 'revoked' else 'expired' end,
    'results', v_results);
end;
$$;

-- =============================================================================================
-- Pembungkus public. Dipanggil perangkat usher (role authenticated + app_metadata.role = 'usher');
-- pemanggil lain ditolak 42501 di usher_context.
-- =============================================================================================

create function public.pull_snapshot(p_cursor text default null, p_limit integer default null,
                                     p_client_now timestamptz default null)
returns jsonb language sql volatile set search_path = ''
as $$ select private.pull_snapshot(p_cursor, p_limit, p_client_now) $$;

create function public.push_outbox(p_items jsonb, p_client_now timestamptz default null)
returns jsonb language sql volatile set search_path = ''
as $$ select private.push_outbox(p_items, p_client_now) $$;

-- =============================================================================================
-- Hak eksekusi
-- =============================================================================================

revoke all on function private.usher_context(timestamptz) from public, anon, authenticated, service_role;
revoke all on function private.touch_device(uuid, timestamptz, timestamptz) from public, anon, authenticated, service_role;
revoke all on function private.encode_cursor(jsonb) from public, anon, authenticated, service_role;
revoke all on function private.decode_cursor(text) from public, anon, authenticated, service_role;
revoke all on function private.guest_snapshot_json(public.guests) from public, anon, authenticated, service_role;
revoke all on function private.pull_snapshot(text, integer, timestamptz) from public, anon, authenticated, service_role;
revoke all on function private.new_guest_issue(jsonb) from public, anon, authenticated, service_role;
revoke all on function private.push_stored(public.check_ins) from public, anon, authenticated, service_role;
revoke all on function private.push_outbox(jsonb, timestamptz) from public, anon, authenticated, service_role;
revoke all on function public.pull_snapshot(text, integer, timestamptz) from public, anon, authenticated, service_role;
revoke all on function public.push_outbox(jsonb, timestamptz) from public, anon, authenticated, service_role;

grant execute on function public.pull_snapshot(text, integer, timestamptz) to authenticated;
grant execute on function private.pull_snapshot(text, integer, timestamptz) to authenticated;
grant execute on function public.push_outbox(jsonb, timestamptz) to authenticated;
grant execute on function private.push_outbox(jsonb, timestamptz) to authenticated;
