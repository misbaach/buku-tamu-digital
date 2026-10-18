-- M1 — RPC Admin inti (prd.md 7.1–7.3, 9; docs/plan.md 8.1).
-- Pola: logika di private.* (SECURITY DEFINER, search_path kosong, memeriksa keanggotaan sendiri),
-- dibungkus fungsi public.* SECURITY INVOKER yang tipis. Semua aksi sensitif diaudit (prd.md 10.4).

-- =============================================================================================
-- Helper
-- =============================================================================================

create function private.assert_event_admin(p_event_id uuid)
returns void
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if p_event_id is null or not private.is_event_admin(p_event_id) then
    raise exception 'Anda bukan Admin acara ini.' using errcode = '42501';
  end if;
end;
$$;

create function private.audit(
  p_event_id uuid, p_action text, p_entity text, p_entity_id text, p_before jsonb, p_after jsonb
)
returns void
language sql
security definer
set search_path = ''
as $$
  insert into public.audit_logs (event_id, actor_id, actor_kind, action, entity, entity_id, before, after)
  values (
    p_event_id,
    (select auth.uid()),
    case
      when (select auth.jwt() -> 'app_metadata' ->> 'role') = 'usher' then 'usher'
      when (select auth.uid()) is null then 'system'
      else 'admin'
    end,
    p_action, p_entity, p_entity_id, p_before, p_after
  );
$$;

-- Serialisasi penulisan check-in per event (docs/decisions.md T-013).
create function private.lock_event(p_event_id uuid)
returns void
language sql
security definer
set search_path = ''
as $$
  select pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_event_id::text, 7701));
$$;

-- =============================================================================================
-- Acara
-- =============================================================================================

create function private.admin_create_event(
  p_name text, p_event_date date, p_couple_names text, p_venue text, p_timezone text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
  v_id uuid;
  v_attempt integer := 0;
begin
  if v_uid is null or coalesce((select auth.jwt() -> 'app_metadata' ->> 'role'), '') <> 'admin' then
    raise exception 'Hanya Admin yang bisa membuat acara.' using errcode = '42501';
  end if;
  if not exists (select 1 from pg_catalog.pg_timezone_names where name = p_timezone) then
    raise exception 'Zona waktu "%" tidak dikenal.', p_timezone using errcode = '22023';
  end if;

  -- Kode Acara acak; tabrakan dengan kode yang sudah ada sangat jarang, tetapi tetap dicoba ulang.
  loop
    begin
      insert into public.events (name, couple_names, event_date, venue, timezone, created_by)
      values (btrim(p_name), nullif(btrim(p_couple_names), ''), p_event_date, nullif(btrim(p_venue), ''), p_timezone, v_uid)
      returning id into v_id;
      exit;
    exception when unique_violation then
      v_attempt := v_attempt + 1;
      if v_attempt >= 5 then raise; end if;
    end;
  end loop;

  insert into public.event_members (event_id, user_id) values (v_id, v_uid);
  insert into public.checkin_settings (event_id) values (v_id);
  insert into public.ticket_number_settings (event_id, category, prefix) values (v_id, 'vip', 'VIP-'), (v_id, 'vvip', 'VVIP-');
  insert into public.greeting_configs (event_id, category) values (v_id, 'regular'), (v_id, 'vip'), (v_id, 'vvip');

  perform private.audit(v_id, 'event_created', 'events', v_id::text, null,
    jsonb_build_object('name', btrim(p_name), 'event_date', p_event_date, 'timezone', p_timezone));
  return v_id;
end;
$$;

-- Patch parsial. Kunci yang diizinkan: name, couple_names, event_date, venue, timezone, attendance_limit.
create function private.admin_update_event(p_event_id uuid, p_patch jsonb)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_key text;
  v_before jsonb;
begin
  perform private.assert_event_admin(p_event_id);
  if jsonb_typeof(p_patch) is distinct from 'object' then
    raise exception 'Data perubahan tidak valid.' using errcode = '22023';
  end if;
  for v_key in select jsonb_object_keys(p_patch) loop
    if not v_key = any (array['name', 'couple_names', 'event_date', 'venue', 'timezone', 'attendance_limit']) then
      raise exception 'Kolom "%" tidak bisa diubah.', v_key using errcode = '22023';
    end if;
  end loop;
  if p_patch ? 'timezone' and not exists (select 1 from pg_catalog.pg_timezone_names where name = p_patch ->> 'timezone') then
    raise exception 'Zona waktu "%" tidak dikenal.', p_patch ->> 'timezone' using errcode = '22023';
  end if;

  select jsonb_build_object('name', name, 'couple_names', couple_names, 'event_date', event_date, 'venue', venue,
                            'timezone', timezone, 'attendance_limit', attendance_limit)
  into v_before from public.events where id = p_event_id;

  update public.events set
    name = case when p_patch ? 'name' then btrim(p_patch ->> 'name') else name end,
    couple_names = case when p_patch ? 'couple_names' then nullif(btrim(p_patch ->> 'couple_names'), '') else couple_names end,
    event_date = case when p_patch ? 'event_date' then (p_patch ->> 'event_date')::date else event_date end,
    venue = case when p_patch ? 'venue' then nullif(btrim(p_patch ->> 'venue'), '') else venue end,
    timezone = case when p_patch ? 'timezone' then p_patch ->> 'timezone' else timezone end,
    attendance_limit = case when p_patch ? 'attendance_limit' then (p_patch ->> 'attendance_limit')::integer else attendance_limit end
  where id = p_event_id;

  perform private.audit(p_event_id, 'event_updated', 'events', p_event_id::text, v_before, p_patch);
end;
$$;

-- Arsip mengakhiri sesi semua perangkat usher (prd.md FR-R-10); pemeriksaannya ada di RPC usher (M2).
create function private.admin_archive_event(p_event_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform private.assert_event_admin(p_event_id);
  update public.events set archived_at = now() where id = p_event_id and archived_at is null;
  if found then
    perform private.audit(p_event_id, 'event_archived', 'events', p_event_id::text, null, null);
  end if;
end;
$$;

-- =============================================================================================
-- Grup: soft delete melepas tamu dari grup (tetap tercatat untuk delta sync lewat updated_at tamu).
-- =============================================================================================

create function private.on_group_soft_delete()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.deleted_at is not null and old.deleted_at is null then
    update public.guests set group_id = null where event_id = new.event_id and group_id = new.id;
  end if;
  return new;
end;
$$;

create trigger guest_groups_release_guests after update of deleted_at on public.guest_groups
  for each row execute function private.on_group_soft_delete();

-- =============================================================================================
-- Nomor Urut khusus (FR-C-02..05)
-- =============================================================================================

create function private.admin_check_special_numbers(p_event_id uuid, p_numbers text[])
returns table (special_number text, guest_name text)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  perform private.assert_event_admin(p_event_id);
  return query
    select g.special_number, g.name
    from public.guests g
    where g.event_id = p_event_id and g.deleted_at is null and g.special_number = any (p_numbers);
end;
$$;

-- Rencana Terapkan Nomor Urut. Urutan: 'name' (nama A–Z), 'group' (grup lalu nama), 'input' (urutan input).
-- Tanpa overwrite, hanya tamu yang belum bernomor yang diberi nomor; nomor yang sudah dipakai siapa pun dilewati.
create function private.special_number_plan(
  p_event_id uuid, p_category public.guest_category, p_order text, p_overwrite boolean
)
returns table (guest_id uuid, guest_name text, group_name text, old_number text, new_number text)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_setting public.ticket_number_settings;
  v_used text[];
  v_next integer;
  v_number text;
  r record;
begin
  if p_order is null or p_order not in ('name', 'group', 'input') then
    raise exception 'Urutan "%" tidak dikenal.', p_order using errcode = '22023';
  end if;
  select * into v_setting from public.ticket_number_settings where event_id = p_event_id and category = p_category;
  if not found then
    raise exception 'Setting Nomor Urut untuk kategori ini belum ada.' using errcode = '22023';
  end if;

  select coalesce(array_agg(g.special_number), '{}') into v_used
  from public.guests g
  where g.event_id = p_event_id and g.deleted_at is null and g.special_number is not null
    and not (p_overwrite and g.category = p_category);

  v_next := v_setting.start_number;
  for r in
    select g.id, g.name, gg.name as gname, g.special_number
    from public.guests g
    left join public.guest_groups gg on gg.id = g.group_id and gg.deleted_at is null
    where g.event_id = p_event_id and g.deleted_at is null and g.category = p_category
      and (p_overwrite or g.special_number is null)
    order by
      case when p_order = 'group' then gg.name is null end,
      case when p_order = 'group' then lower(gg.name) end,
      case when p_order in ('name', 'group') then lower(g.name) end,
      g.created_at, g.id
  loop
    loop
      v_number := v_setting.prefix
        || case when length(v_next::text) >= v_setting.digits then v_next::text
                else lpad(v_next::text, v_setting.digits, '0') end;
      v_next := v_next + 1;
      exit when not (v_number = any (v_used));
    end loop;
    if private.special_number_issue(v_number) is not null then
      raise exception 'Nomor "%" tidak sah (mis. lebih dari 20 karakter). Ubah setting Nomor Urut.', v_number
        using errcode = '22023';
    end if;
    guest_id := r.id;
    guest_name := r.name;
    group_name := r.gname;
    old_number := r.special_number;
    new_number := v_number;
    return next;
  end loop;
end;
$$;

create function private.special_number_plan_hash(
  p_event_id uuid, p_category public.guest_category, p_order text, p_overwrite boolean
)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select md5(coalesce(string_agg(p.guest_id::text || '=' || p.new_number, ',' order by p.guest_id), ''))
  from private.special_number_plan(p_event_id, p_category, p_order, p_overwrite) p;
$$;

create function private.admin_preview_special_numbers(
  p_event_id uuid, p_category public.guest_category, p_order text, p_overwrite boolean
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_rows jsonb;
begin
  perform private.assert_event_admin(p_event_id);
  select coalesce(jsonb_agg(jsonb_build_object(
           'guest_id', p.guest_id, 'guest_name', p.guest_name, 'group_name', p.group_name,
           'old_number', p.old_number, 'new_number', p.new_number)), '[]'::jsonb)
  into v_rows
  from private.special_number_plan(p_event_id, p_category, p_order, p_overwrite) p;
  return jsonb_build_object(
    'hash', private.special_number_plan_hash(p_event_id, p_category, p_order, p_overwrite),
    'rows', v_rows
  );
end;
$$;

-- Menyimpan hasil pratinjau. Ditolak bila data berubah sejak pratinjau (hash berbeda). FR-C-04
create function private.admin_apply_special_numbers(
  p_event_id uuid, p_category public.guest_category, p_order text, p_overwrite boolean, p_expected_hash text
)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_plan jsonb;
  v_count integer;
begin
  perform private.assert_event_admin(p_event_id);
  perform private.lock_event(p_event_id);
  if private.special_number_plan_hash(p_event_id, p_category, p_order, p_overwrite) is distinct from p_expected_hash then
    raise exception 'Data tamu berubah sejak pratinjau dibuat. Buat pratinjau ulang.' using errcode = '40001';
  end if;

  select coalesce(jsonb_agg(jsonb_build_object('guest_id', p.guest_id, 'old_number', p.old_number, 'new_number', p.new_number)), '[]'::jsonb)
  into v_plan
  from private.special_number_plan(p_event_id, p_category, p_order, p_overwrite) p;
  v_count := jsonb_array_length(v_plan);
  if v_count = 0 then
    return 0;
  end if;

  -- Dua tahap agar nomor yang bertukar pemilik tidak melanggar unique index di tengah jalan.
  update public.guests g set special_number = null
  from jsonb_to_recordset(v_plan) as p(guest_id uuid, old_number text, new_number text)
  where g.id = p.guest_id and g.special_number is not null;
  update public.guests g set special_number = p.new_number
  from jsonb_to_recordset(v_plan) as p(guest_id uuid, old_number text, new_number text)
  where g.id = p.guest_id;

  perform private.audit(p_event_id, 'special_numbers_applied', 'guests', null, null,
    jsonb_build_object('category', p_category, 'order', p_order, 'overwrite', p_overwrite, 'count', v_count, 'changes', v_plan));
  return v_count;
end;
$$;

create function private.admin_clear_special_numbers(p_event_id uuid, p_guest_ids uuid[])
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_before jsonb;
  v_count integer;
begin
  perform private.assert_event_admin(p_event_id);
  select coalesce(jsonb_agg(jsonb_build_object('guest_id', g.id, 'old_number', g.special_number)), '[]'::jsonb)
  into v_before
  from public.guests g
  where g.event_id = p_event_id and g.id = any (p_guest_ids) and g.special_number is not null;

  update public.guests set special_number = null
  where event_id = p_event_id and id = any (p_guest_ids) and special_number is not null;
  get diagnostics v_count = row_count;

  if v_count > 0 then
    perform private.audit(p_event_id, 'special_numbers_cleared', 'guests', null, v_before, jsonb_build_object('count', v_count));
  end if;
  return v_count;
end;
$$;

-- =============================================================================================
-- Impor tamu (FR-G-03): satu transaksi; baris bermasalah membatalkan seluruh impor.
-- p_rows: [{ row, name, phone, category, group, invited_pax, special_number, rsvp_status, rsvp_pax, notes }]
-- =============================================================================================

create function private.admin_import_guests(p_event_id uuid, p_rows jsonb)
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
begin
  perform private.assert_event_admin(p_event_id);
  if jsonb_typeof(p_rows) is distinct from 'array' then
    raise exception 'Data impor tidak valid.' using errcode = '22023';
  end if;
  if jsonb_array_length(p_rows) > 5000 then
    raise exception 'Maksimal 5.000 baris per impor.' using errcode = '22023';
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

-- =============================================================================================
-- Check-in: evaluasi status (12.3 poin 5–7), simpan, hitung ulang kehadiran
-- =============================================================================================

-- Status untuk check-in yang BUKAN karantina. NULL nomor tiket tidak pernah dianggap bentrok (12.3 poin 15).
create function private.evaluate_check_in_status(
  p_event_id uuid, p_guest_id uuid, p_ticket_number text, p_exclude_id uuid
)
returns public.check_in_status
language sql
stable
security definer
set search_path = ''
as $$
  select case
    when exists (
      select 1 from public.check_ins c
      where c.event_id = p_event_id and c.guest_id = p_guest_id and c.status = 'accepted'
        and c.voided_at is null and c.id is distinct from p_exclude_id
    ) then
      case when coalesce((select s.allow_multi_checkin from public.checkin_settings s where s.event_id = p_event_id), false)
           then 'repeat' else 'duplicate' end
    when p_ticket_number is not null and exists (
      select 1 from public.check_ins c
      where c.event_id = p_event_id and c.ticket_number = p_ticket_number and c.status = 'accepted'
        and c.voided_at is null and c.id is distinct from p_exclude_id
    ) then 'conflict'
    else 'accepted'
  end::public.check_in_status;
$$;

-- Jalur penyimpanan bersama untuk check-in manual Admin (M1) dan push_outbox (M2). Pemanggil wajib
-- memegang private.lock_event(event) lebih dulu.
create function private.store_check_in(
  p_id uuid, p_event_id uuid, p_guest_id uuid, p_actual_pax integer, p_ticket_number text,
  p_source public.check_in_source, p_device_id uuid, p_usher_id uuid, p_created_by uuid, p_checked_in_at timestamptz
)
returns public.check_in_status
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_status public.check_in_status;
begin
  v_status := private.evaluate_check_in_status(p_event_id, p_guest_id, p_ticket_number, null);
  insert into public.check_ins (
    id, event_id, guest_id, actual_pax, ticket_number, status, source, device_id, usher_id, created_by, checked_in_at
  ) values (
    p_id, p_event_id, p_guest_id, p_actual_pax, p_ticket_number, v_status, p_source, p_device_id, p_usher_id,
    p_created_by, p_checked_in_at
  );
  return v_status;
end;
$$;

-- Kehadiran tamu = turunan dari check-in aktif (bukan dibatalkan, bukan karantina). Selalu menyentuh
-- updated_at tamu agar ringkasan check-in ikut terkirim lewat delta sync (12.3 poin 17).
create function private.recompute_attendance(p_guest_id uuid)
returns void
language sql
security definer
set search_path = ''
as $$
  update public.guests g set
    attendance_status = (
      select case
        when count(*) = 0 then 'not_arrived'
        when bool_and(c.checked_out_at is not null) then 'checked_out'
        else 'checked_in'
      end::public.attendance_status
      from public.check_ins c
      where c.guest_id = g.id and c.voided_at is null and c.status <> 'quarantined'
    ),
    updated_at = now()
  where g.id = p_guest_id;
$$;

create function private.on_check_in_change()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.guest_id is not null then
    perform private.recompute_attendance(new.guest_id);
  end if;
  if tg_op = 'UPDATE' and old.guest_id is not null and old.guest_id is distinct from new.guest_id then
    perform private.recompute_attendance(old.guest_id);
  end if;
  return null;
end;
$$;

create trigger check_ins_recompute_attendance after insert or update on public.check_ins
  for each row execute function private.on_check_in_change();

-- Tandai hadir manual (FR-A-02, 12.3 poin 15). Nomor tiket = Nomor Urut khusus tamu, atau NULL.
create function private.admin_manual_check_in(p_guest_id uuid, p_actual_pax integer)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_guest public.guests;
  v_id uuid := gen_random_uuid();
  v_status public.check_in_status;
begin
  select * into v_guest from public.guests where id = p_guest_id;
  if not found or v_guest.deleted_at is not null then
    raise exception 'Tamu tidak ditemukan.' using errcode = 'P0002';
  end if;
  perform private.assert_event_admin(v_guest.event_id);
  perform private.lock_event(v_guest.event_id);

  v_status := private.store_check_in(v_id, v_guest.event_id, v_guest.id, p_actual_pax, v_guest.special_number,
                                     'admin', null, null, (select auth.uid()), now());
  perform private.audit(v_guest.event_id, 'manual_check_in', 'check_ins', v_id::text, null, jsonb_build_object(
    'guest_id', v_guest.id, 'status', v_status, 'ticket_number', v_guest.special_number, 'actual_pax', p_actual_pax));
  return jsonb_build_object('id', v_id, 'status', v_status, 'ticket_number', v_guest.special_number);
end;
$$;

-- Ubah Detail Kehadiran (FR-A-02, FR-C-07). Kunci patch: actual_pax, ticket_number, checked_out_at.
-- Mengganti nomor pada check-in `conflict` memicu evaluasi ulang status (12.3, FR-RW-05).
create function private.admin_update_check_in(p_check_in_id uuid, p_patch jsonb, p_reason text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row public.check_ins;
  v_key text;
  v_ticket text;
  v_status public.check_in_status;
  v_after public.check_ins;
begin
  select * into v_row from public.check_ins where id = p_check_in_id;
  if not found then
    raise exception 'Check-in tidak ditemukan.' using errcode = 'P0002';
  end if;
  perform private.assert_event_admin(v_row.event_id);
  perform private.lock_event(v_row.event_id);
  select * into v_row from public.check_ins where id = p_check_in_id;

  if v_row.voided_at is not null then
    raise exception 'Check-in yang sudah dibatalkan tidak bisa diubah.' using errcode = '22023';
  end if;
  if v_row.status = 'quarantined' then
    raise exception 'Check-in karantina harus disetujui atau ditolak lebih dulu.' using errcode = '22023';
  end if;
  if jsonb_typeof(p_patch) is distinct from 'object' then
    raise exception 'Data perubahan tidak valid.' using errcode = '22023';
  end if;
  for v_key in select jsonb_object_keys(p_patch) loop
    if not v_key = any (array['actual_pax', 'ticket_number', 'checked_out_at']) then
      raise exception 'Kolom "%" tidak bisa diubah.', v_key using errcode = '22023';
    end if;
  end loop;

  v_ticket := case when p_patch ? 'ticket_number' then nullif(upper(btrim(p_patch ->> 'ticket_number')), '')
                   else v_row.ticket_number end;
  v_status := v_row.status;
  if v_row.status = 'conflict' and v_ticket is distinct from v_row.ticket_number then
    v_status := private.evaluate_check_in_status(v_row.event_id, v_row.guest_id, v_ticket, v_row.id);
  end if;

  begin
    update public.check_ins set
      actual_pax = case when p_patch ? 'actual_pax' then (p_patch ->> 'actual_pax')::smallint else actual_pax end,
      ticket_number = v_ticket,
      checked_out_at = case when p_patch ? 'checked_out_at' then (p_patch ->> 'checked_out_at')::timestamptz
                            else checked_out_at end,
      status = v_status
    where id = p_check_in_id
    returning * into v_after;
  exception when unique_violation then
    raise exception 'Nomor tiket "%" sudah dipakai check-in lain yang sah.', v_ticket using errcode = '23505';
  end;

  perform private.audit(v_row.event_id, 'check_in_updated', 'check_ins', p_check_in_id::text,
    jsonb_build_object('actual_pax', v_row.actual_pax, 'ticket_number', v_row.ticket_number,
                       'checked_out_at', v_row.checked_out_at, 'status', v_row.status),
    jsonb_build_object('actual_pax', v_after.actual_pax, 'ticket_number', v_after.ticket_number,
                       'checked_out_at', v_after.checked_out_at, 'status', v_after.status, 'reason', p_reason));
  return jsonb_build_object('id', v_after.id, 'status', v_after.status, 'ticket_number', v_after.ticket_number);
end;
$$;

-- =============================================================================================
-- Pembungkus public (SECURITY INVOKER). Hanya ini yang diekspos API.
-- =============================================================================================

create function public.admin_create_event(
  p_name text, p_event_date date, p_couple_names text default null, p_venue text default null,
  p_timezone text default 'Asia/Jakarta'
)
returns uuid language sql set search_path = ''
as $$ select private.admin_create_event(p_name, p_event_date, p_couple_names, p_venue, p_timezone) $$;

create function public.admin_update_event(p_event_id uuid, p_patch jsonb)
returns void language sql set search_path = ''
as $$ select private.admin_update_event(p_event_id, p_patch) $$;

create function public.admin_archive_event(p_event_id uuid)
returns void language sql set search_path = ''
as $$ select private.admin_archive_event(p_event_id) $$;

create function public.admin_check_special_numbers(p_event_id uuid, p_numbers text[])
returns table (special_number text, guest_name text) language sql set search_path = ''
as $$ select * from private.admin_check_special_numbers(p_event_id, p_numbers) $$;

create function public.admin_preview_special_numbers(
  p_event_id uuid, p_category public.guest_category, p_order text, p_overwrite boolean default false
)
returns jsonb language sql set search_path = ''
as $$ select private.admin_preview_special_numbers(p_event_id, p_category, p_order, p_overwrite) $$;

create function public.admin_apply_special_numbers(
  p_event_id uuid, p_category public.guest_category, p_order text, p_overwrite boolean, p_expected_hash text
)
returns integer language sql set search_path = ''
as $$ select private.admin_apply_special_numbers(p_event_id, p_category, p_order, p_overwrite, p_expected_hash) $$;

create function public.admin_clear_special_numbers(p_event_id uuid, p_guest_ids uuid[])
returns integer language sql set search_path = ''
as $$ select private.admin_clear_special_numbers(p_event_id, p_guest_ids) $$;

create function public.admin_import_guests(p_event_id uuid, p_rows jsonb)
returns jsonb language sql set search_path = ''
as $$ select private.admin_import_guests(p_event_id, p_rows) $$;

create function public.admin_manual_check_in(p_guest_id uuid, p_actual_pax integer)
returns jsonb language sql set search_path = ''
as $$ select private.admin_manual_check_in(p_guest_id, p_actual_pax) $$;

create function public.admin_update_check_in(p_check_in_id uuid, p_patch jsonb, p_reason text default null)
returns jsonb language sql set search_path = ''
as $$ select private.admin_update_check_in(p_check_in_id, p_patch, p_reason) $$;

-- =============================================================================================
-- Hak eksekusi (aturan 5): REVOKE eksplisit, lalu GRANT seperlunya.
-- =============================================================================================

revoke all on all functions in schema private from public, anon, authenticated, service_role;
revoke all on all functions in schema public from public, anon, authenticated, service_role;

-- Dipakai CHECK/default/policy saat Admin menulis lewat PostgREST (dari migration sebelumnya).
grant execute on function private.special_number_issue(text) to authenticated;
grant execute on function private.gen_qr_token() to authenticated;
grant execute on function private.admin_event_ids() to authenticated;
grant execute on function private.is_event_admin(uuid) to authenticated;

-- Pembungkus public dan fungsi private yang dipanggilnya (SECURITY INVOKER → pemanggil butuh EXECUTE keduanya).
grant execute on function public.admin_create_event(text, date, text, text, text) to authenticated;
grant execute on function private.admin_create_event(text, date, text, text, text) to authenticated;
grant execute on function public.admin_update_event(uuid, jsonb) to authenticated;
grant execute on function private.admin_update_event(uuid, jsonb) to authenticated;
grant execute on function public.admin_archive_event(uuid) to authenticated;
grant execute on function private.admin_archive_event(uuid) to authenticated;
grant execute on function public.admin_check_special_numbers(uuid, text[]) to authenticated;
grant execute on function private.admin_check_special_numbers(uuid, text[]) to authenticated;
grant execute on function public.admin_preview_special_numbers(uuid, public.guest_category, text, boolean) to authenticated;
grant execute on function private.admin_preview_special_numbers(uuid, public.guest_category, text, boolean) to authenticated;
grant execute on function public.admin_apply_special_numbers(uuid, public.guest_category, text, boolean, text) to authenticated;
grant execute on function private.admin_apply_special_numbers(uuid, public.guest_category, text, boolean, text) to authenticated;
grant execute on function public.admin_clear_special_numbers(uuid, uuid[]) to authenticated;
grant execute on function private.admin_clear_special_numbers(uuid, uuid[]) to authenticated;
grant execute on function public.admin_import_guests(uuid, jsonb) to authenticated;
grant execute on function private.admin_import_guests(uuid, jsonb) to authenticated;
grant execute on function public.admin_manual_check_in(uuid, integer) to authenticated;
grant execute on function private.admin_manual_check_in(uuid, integer) to authenticated;
grant execute on function public.admin_update_check_in(uuid, jsonb, text) to authenticated;
grant execute on function private.admin_update_check_in(uuid, jsonb, text) to authenticated;
