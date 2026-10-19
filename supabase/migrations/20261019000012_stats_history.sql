-- M3 — Statistik dan Riwayat (prd.md 7.5, 7.7, FR-S-07; docs/plan.md 10.3, 11, 12).
-- Definisi (plan.md 10.3):
--   Hadir          = ada check-in yang tidak dibatalkan dan bukan quarantined.
--   Jumlah orang   = Σ actual_pax check-in accepted + conflict yang tidak dibatalkan (repeat, duplicate,
--                    quarantined, dan yang dibatalkan tidak dihitung; D11).
--   Jumlah tercatat per tamu = rsvp_pax bila Akan hadir, selain itu invited_pax.

-- =============================================================================================
-- Statistik (FR-S-01..05)
-- =============================================================================================

create function private.get_event_stats(p_event_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_event public.events;
  v_result jsonb;
begin
  perform private.assert_event_admin(p_event_id);
  select * into v_event from public.events where id = p_event_id;

  with counted as (
    -- Check-in yang menambah jumlah orang. Tamu yang sudah dihapus tetap dihitung: orangnya tetap datang.
    select c.guest_id, c.actual_pax, g.category, g.is_additional
    from public.check_ins c join public.guests g on g.id = c.guest_id
    where c.event_id = p_event_id and c.voided_at is null and c.status in ('accepted', 'conflict')
  ),
  per_guest as (
    select guest_id, sum(actual_pax)::integer as pax from counted group by guest_id
  ),
  invited as (
    select g.*, case when g.rsvp_status = 'going' then coalesce(g.rsvp_pax, g.invited_pax) else g.invited_pax end as recorded
    from public.guests g where g.event_id = p_event_id and g.deleted_at is null and not g.is_additional
  ),
  categories as (
    select cat.category,
      coalesce((select sum(actual_pax) from counted c where c.category = cat.category), 0)::integer as people,
      coalesce((select sum(coalesce(i.rsvp_pax, i.invited_pax)) from invited i
                where i.category = cat.category and i.rsvp_status = 'going'), 0)::integer as rsvp_pax,
      (select count(*) from public.guests g where g.event_id = p_event_id and g.deleted_at is null
         and g.category = cat.category and g.attendance_status <> 'not_arrived')::integer as guests_present
    from unnest(enum_range(null::public.guest_category)) as cat(category)
  )
  select jsonb_build_object(
    'serverTime', now(),
    -- FR-S-01
    'peoplePresent', coalesce((select sum(actual_pax) from counted), 0),
    'rsvpGoingGuests', (select count(*) from invited where rsvp_status = 'going'),
    'rsvpGoingPax', coalesce((select sum(coalesce(rsvp_pax, invited_pax)) from invited where rsvp_status = 'going'), 0),
    'invitedTotal', coalesce((select sum(invited_pax) from invited), 0),
    'limit', coalesce(v_event.attendance_limit, (select sum(invited_pax) from invited), 0),
    'limitSource', case when v_event.attendance_limit is not null then 'manual' else 'invited_total' end,
    -- FR-S-02
    'categories', (select jsonb_agg(jsonb_build_object('category', category, 'people', people, 'rsvpPax', rsvp_pax,
                                                       'guestsPresent', guests_present) order by category desc)
                   from categories),
    -- FR-S-03
    'invitedCheckedIn', (select count(*) from invited where attendance_status <> 'not_arrived'),
    -- FR-S-04
    'guestsPresent', (select count(*) from public.guests g where g.event_id = p_event_id and g.deleted_at is null
                        and g.attendance_status <> 'not_arrived'),
    'guestsCheckedOut', (select count(*) from public.guests g where g.event_id = p_event_id and g.deleted_at is null
                           and g.attendance_status = 'checked_out'),
    -- FR-S-05
    'additionalGuests', (select count(*) from public.guests g where g.event_id = p_event_id and g.deleted_at is null
                           and g.is_additional and g.attendance_status <> 'not_arrived'),
    'additionalPeople', coalesce((select sum(actual_pax) from counted where is_additional), 0),
    'beyondRecorded', coalesce((select sum(greatest(0, pg.pax - i.recorded)) from per_guest pg join invited i on i.id = pg.guest_id), 0),
    -- Perlu ditinjau (tautan ke Riwayat)
    'review', jsonb_build_object(
      'quarantined', (select count(*) from public.check_ins c where c.event_id = p_event_id
                        and c.status = 'quarantined' and c.voided_at is null),
      'duplicate', (select count(*) from public.check_ins c where c.event_id = p_event_id
                      and c.status = 'duplicate' and c.voided_at is null and c.reviewed_at is null),
      'conflict', (select count(*) from public.check_ins c where c.event_id = p_event_id
                     and c.status = 'conflict' and c.voided_at is null and c.reviewed_at is null))
  ) into v_result;

  return v_result || jsonb_build_object('overLimit', (v_result ->> 'peoplePresent')::integer > (v_result ->> 'limit')::integer
                                                     and (v_result ->> 'limit')::integer > 0);
end;
$$;

-- Linimasa kedatangan (FR-S-03): tamu dan orang per interval, menurut jam check-in perangkat (untuk tampilan;
-- urutan resmi tetap received_at, 12.3 poin 9). Hanya check-in yang dihitung sebagai kedatangan.
create function private.get_arrival_timeline(p_event_id uuid, p_bucket_min integer)
returns table (bucket_start timestamptz, guests integer, people integer)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_stride interval := make_interval(mins => least(greatest(coalesce(p_bucket_min, 15), 5), 60));
begin
  perform private.assert_event_admin(p_event_id);
  return query
    select date_bin(v_stride, c.checked_in_at, timestamptz '2000-01-01 00:00:00+00') as b,
           count(distinct c.guest_id)::integer, sum(c.actual_pax)::integer
    from public.check_ins c
    where c.event_id = p_event_id and c.voided_at is null and c.status in ('accepted', 'conflict')
    group by b
    order by b;
end;
$$;

-- =============================================================================================
-- Riwayat: undo, tinjau, setujui/tolak karantina (FR-RW-03, FR-RW-05)
-- =============================================================================================

-- Undo check-in (alasan wajib). Karantina diputuskan lewat admin_decide_quarantine.
create function private.admin_void_check_in(p_check_in_id uuid, p_reason text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row public.check_ins;
  v_reason text := nullif(btrim(p_reason), '');
begin
  select * into v_row from public.check_ins where id = p_check_in_id;
  if not found then
    raise exception 'Check-in tidak ditemukan.' using errcode = 'P0002';
  end if;
  perform private.assert_event_admin(v_row.event_id);
  perform private.lock_event(v_row.event_id);
  if v_reason is null then
    raise exception 'Alasan pembatalan wajib diisi.' using errcode = '22023';
  end if;
  if v_row.voided_at is not null then
    raise exception 'Check-in ini sudah dibatalkan.' using errcode = '22023';
  end if;
  if v_row.status = 'quarantined' then
    raise exception 'Check-in karantina disetujui atau ditolak lewat tinjauan karantina.' using errcode = '22023';
  end if;

  update public.check_ins set voided_at = now(), voided_by = (select auth.uid()), void_reason = left(v_reason, 300)
  where id = p_check_in_id;
  perform private.audit(v_row.event_id, 'check_in_voided', 'check_ins', p_check_in_id::text,
    jsonb_build_object('status', v_row.status, 'ticket_number', v_row.ticket_number, 'actual_pax', v_row.actual_pax),
    jsonb_build_object('reason', v_reason));
  return jsonb_build_object('id', p_check_in_id, 'voided', true);
end;
$$;

-- Tandai Ganda / Nomor bentrok sudah ditinjau (label "· ditinjau", K32).
create function private.admin_review_check_in(p_check_in_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row public.check_ins;
begin
  select * into v_row from public.check_ins where id = p_check_in_id;
  if not found then
    raise exception 'Check-in tidak ditemukan.' using errcode = 'P0002';
  end if;
  perform private.assert_event_admin(v_row.event_id);
  if v_row.status not in ('duplicate', 'conflict') or v_row.voided_at is not null then
    raise exception 'Hanya check-in Ganda atau Nomor bentrok yang aktif yang bisa ditandai ditinjau.' using errcode = '22023';
  end if;
  if v_row.reviewed_at is not null then
    return jsonb_build_object('id', p_check_in_id, 'changed', false);
  end if;
  update public.check_ins set reviewed_at = now(), reviewed_by = (select auth.uid()) where id = p_check_in_id;
  perform private.audit(v_row.event_id, 'check_in_reviewed', 'check_ins', p_check_in_id::text, null,
    jsonb_build_object('status', v_row.status));
  return jsonb_build_object('id', p_check_in_id, 'changed', true);
end;
$$;

-- Setujui atau tolak karantina, per baris (p_ids) atau semua dari satu perangkat (p_device_id) (FR-RW-05, 12.3).
-- Setujui: tamu tambahan dari pending_guest baru dibuat sekarang, lalu status dievaluasi ulang dengan aturan
--          12.3 poin 5–8 pada saat persetujuan. received_at dan quarantine_reason tetap (jejak asal).
-- Tolak:   alasan wajib; baris tetap tersimpan sebagai dibatalkan.
create function private.admin_decide_quarantine(
  p_event_id uuid, p_decision text, p_ids uuid[], p_device_id uuid, p_reason text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_reason text := nullif(btrim(p_reason), '');
  v_row public.check_ins;
  v_guest uuid;
  v_status public.check_in_status;
  v_results jsonb := '[]'::jsonb;
begin
  perform private.assert_event_admin(p_event_id);
  if p_decision is null or p_decision not in ('approve', 'reject') then
    raise exception 'Keputusan harus approve atau reject.' using errcode = '22023';
  end if;
  if (p_ids is null) = (p_device_id is null) then
    raise exception 'Pilih baris karantina atau satu perangkat.' using errcode = '22023';
  end if;
  if p_decision = 'reject' and v_reason is null then
    raise exception 'Alasan penolakan wajib diisi.' using errcode = '22023';
  end if;
  perform private.lock_event(p_event_id);

  for v_row in
    select * from public.check_ins c
    where c.event_id = p_event_id and c.status = 'quarantined' and c.voided_at is null
      and (c.id = any (p_ids) or c.device_id = p_device_id)
    order by c.received_at, c.id
  loop
    if p_decision = 'approve' then
      v_guest := v_row.guest_id;
      if v_guest is null then
        insert into public.guests (event_id, name, phone, category, invited_pax, notes, is_additional, created_device_id)
        values (p_event_id, v_row.pending_guest ->> 'name', v_row.pending_guest ->> 'phone',
                (v_row.pending_guest ->> 'category')::public.guest_category,
                (v_row.pending_guest ->> 'invitedPax')::smallint, v_row.pending_guest ->> 'notes', true, v_row.device_id)
        returning id into v_guest;
      end if;
      v_status := private.evaluate_check_in_status(p_event_id, v_guest, v_row.ticket_number, v_row.id);
      -- reviewed_at sengaja tidak diisi: bila hasilnya Ganda/Nomor bentrok, baris itu tetap perlu ditinjau.
      update public.check_ins set guest_id = v_guest, status = v_status where id = v_row.id;
      perform private.audit(p_event_id, 'quarantine_approved', 'check_ins', v_row.id::text,
        jsonb_build_object('status', 'quarantined', 'quarantine_reason', v_row.quarantine_reason),
        jsonb_build_object('status', v_status, 'guest_id', v_guest));
      v_results := v_results || jsonb_build_array(jsonb_build_object('id', v_row.id, 'status', v_status));
    else
      update public.check_ins set voided_at = now(), voided_by = (select auth.uid()), void_reason = left(v_reason, 300),
                                  reviewed_at = now(), reviewed_by = (select auth.uid())
      where id = v_row.id;
      perform private.audit(p_event_id, 'quarantine_rejected', 'check_ins', v_row.id::text,
        jsonb_build_object('quarantine_reason', v_row.quarantine_reason), jsonb_build_object('reason', v_reason));
      v_results := v_results || jsonb_build_array(jsonb_build_object('id', v_row.id, 'status', 'rejected'));
    end if;
  end loop;

  return jsonb_build_object('decided', jsonb_array_length(v_results), 'results', v_results);
end;
$$;

-- =============================================================================================
-- Realtime statistik: Broadcast privat `event:{id}:stats` untuk Admin acara (FR-S-07, aturan 9)
-- =============================================================================================

create function private.signal_stats(p_event_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_key text := 'bukutamu.stats_signal_' || replace(p_event_id::text, '-', '');
begin
  if p_event_id is null or current_setting(v_key, true) = '1' then
    return;
  end if;
  perform set_config(v_key, '1', true);
  perform realtime.send(jsonb_build_object('kind', 'stats'), 'stats', 'event:' || p_event_id::text || ':stats', true);
end;
$$;

create function private.on_stats_change()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_table_name = 'events' then
    perform private.signal_stats(new.id);
  else
    perform private.signal_stats(new.event_id);
  end if;
  return null;
end;
$$;

create trigger check_ins_signal_stats after insert or update on public.check_ins
  for each row execute function private.on_stats_change();
create trigger guests_signal_stats after insert or update on public.guests
  for each row execute function private.on_stats_change();
create trigger events_signal_stats after update on public.events
  for each row execute function private.on_stats_change();

create function private.admin_can_listen(p_topic text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select case
    when p_topic ~ '^event:[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}:stats$'
      then private.is_event_admin(split_part(p_topic, ':', 2)::uuid)
    else false
  end;
$$;

create policy admin_receive_stats on realtime.messages for select to authenticated
  using (
    realtime.messages.extension = 'broadcast'
    and (select private.admin_can_listen((select realtime.topic())))
  );

-- =============================================================================================
-- Pembungkus public
-- =============================================================================================

create function public.get_event_stats(p_event_id uuid)
returns jsonb language sql stable set search_path = ''
as $$ select private.get_event_stats(p_event_id) $$;

create function public.get_arrival_timeline(p_event_id uuid, p_bucket_min integer default 15)
returns table (bucket_start timestamptz, guests integer, people integer) language sql stable set search_path = ''
as $$ select * from private.get_arrival_timeline(p_event_id, p_bucket_min) $$;

create function public.admin_void_check_in(p_check_in_id uuid, p_reason text)
returns jsonb language sql set search_path = ''
as $$ select private.admin_void_check_in(p_check_in_id, p_reason) $$;

create function public.admin_review_check_in(p_check_in_id uuid)
returns jsonb language sql set search_path = ''
as $$ select private.admin_review_check_in(p_check_in_id) $$;

create function public.admin_decide_quarantine(
  p_event_id uuid, p_decision text, p_ids uuid[] default null, p_device_id uuid default null, p_reason text default null
)
returns jsonb language sql set search_path = ''
as $$ select private.admin_decide_quarantine(p_event_id, p_decision, p_ids, p_device_id, p_reason) $$;

-- =============================================================================================
-- Hak eksekusi
-- =============================================================================================

revoke all on function private.get_event_stats(uuid) from public, anon, authenticated, service_role;
revoke all on function private.get_arrival_timeline(uuid, integer) from public, anon, authenticated, service_role;
revoke all on function private.admin_void_check_in(uuid, text) from public, anon, authenticated, service_role;
revoke all on function private.admin_review_check_in(uuid) from public, anon, authenticated, service_role;
revoke all on function private.admin_decide_quarantine(uuid, text, uuid[], uuid, text) from public, anon, authenticated, service_role;
revoke all on function private.signal_stats(uuid) from public, anon, authenticated, service_role;
revoke all on function private.on_stats_change() from public, anon, authenticated, service_role;
revoke all on function private.admin_can_listen(text) from public, anon, authenticated, service_role;
revoke all on function public.get_event_stats(uuid) from public, anon, authenticated, service_role;
revoke all on function public.get_arrival_timeline(uuid, integer) from public, anon, authenticated, service_role;
revoke all on function public.admin_void_check_in(uuid, text) from public, anon, authenticated, service_role;
revoke all on function public.admin_review_check_in(uuid) from public, anon, authenticated, service_role;
revoke all on function public.admin_decide_quarantine(uuid, text, uuid[], uuid, text) from public, anon, authenticated, service_role;

grant execute on function private.admin_can_listen(text) to authenticated;
grant execute on function public.get_event_stats(uuid) to authenticated;
grant execute on function private.get_event_stats(uuid) to authenticated;
grant execute on function public.get_arrival_timeline(uuid, integer) to authenticated;
grant execute on function private.get_arrival_timeline(uuid, integer) to authenticated;
grant execute on function public.admin_void_check_in(uuid, text) to authenticated;
grant execute on function private.admin_void_check_in(uuid, text) to authenticated;
grant execute on function public.admin_review_check_in(uuid) to authenticated;
grant execute on function private.admin_review_check_in(uuid) to authenticated;
grant execute on function public.admin_decide_quarantine(uuid, text, uuid[], uuid, text) to authenticated;
grant execute on function private.admin_decide_quarantine(uuid, text, uuid[], uuid, text) to authenticated;
