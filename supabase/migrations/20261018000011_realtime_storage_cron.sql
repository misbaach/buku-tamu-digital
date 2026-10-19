-- M2 — Sinyal Realtime usher, Storage foto sapaan, dan job pembersihan perangkat.

-- =============================================================================================
-- Realtime: Broadcast privat `event:{id}:usher` yang dipicu trigger DB (aturan 9, FR-R-06).
-- Payload hanya `{kind: 'sync'}`; perangkat lalu memanggil pull_snapshot dengan kursornya. Postgres Changes
-- tidak dipakai.
-- =============================================================================================

-- Satu sinyal per transaksi per event (docs/decisions.md T-014): impor 1.000 tamu = satu sinyal.
create function private.signal_usher(p_event_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_key text := 'bukutamu.usher_signal_' || replace(p_event_id::text, '-', '');
begin
  if p_event_id is null or current_setting(v_key, true) = '1' then
    return;
  end if;
  perform set_config(v_key, '1', true);
  -- realtime.send menelan galatnya sendiri (WARNING), sehingga penulisan data tidak pernah gagal karena sinyal.
  perform realtime.send(jsonb_build_object('kind', 'sync'), 'sync', 'event:' || p_event_id::text || ':usher', true);
end;
$$;

create function private.on_usher_data_change()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  -- IF (bukan CASE SQL): kolom NEW baru di-resolve pada cabang yang dijalankan.
  if tg_table_name = 'events' then
    perform private.signal_usher(new.id);
  else
    perform private.signal_usher(new.event_id);
  end if;
  return null;
end;
$$;

create trigger guests_signal_usher after insert or update on public.guests
  for each row execute function private.on_usher_data_change();
create trigger guest_groups_signal_usher after insert or update on public.guest_groups
  for each row execute function private.on_usher_data_change();
create trigger checkin_settings_signal_usher after update on public.checkin_settings
  for each row execute function private.on_usher_data_change();
create trigger greeting_configs_signal_usher after update on public.greeting_configs
  for each row execute function private.on_usher_data_change();
create trigger events_signal_usher after update on public.events
  for each row execute function private.on_usher_data_change();

-- Hanya perangkat SAH event tersebut yang boleh mendengarkan; perangkat dicabut, sesi habis, atau acara
-- diarsipkan tidak menerima apa pun (plan.md bagian 11).
create function private.usher_can_listen(p_topic text)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  ctx record;
begin
  select * into ctx from private.usher_context(now());
  return ctx.access_state = 'active' and p_topic = 'event:' || ctx.event_id::text || ':usher';
exception when others then
  return false;
end;
$$;

create policy usher_receive_own_event on realtime.messages for select to authenticated
  using (
    realtime.messages.extension = 'broadcast'
    and (select private.usher_can_listen((select realtime.topic())))
  );

-- =============================================================================================
-- Storage: bucket privat foto pop-up sapaan (FR-P-01, prd.md 10.4). Tanpa policy untuk anon, tanpa akses
-- publik; dashboard memakai signed URL berumur pendek. Batas ukuran dan MIME dari private.config().
-- =============================================================================================

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  private.config() ->> 'greeting_photo_bucket',
  private.config() ->> 'greeting_photo_bucket',
  false,
  (private.config() ->> 'upload_max_bytes')::bigint,
  array(select jsonb_array_elements_text(private.config() -> 'upload_mime'))
);

-- Path wajib `{event_id}/{kategori}/{uuid}.{png|jpg|webp}` dan event_id harus acara milik Admin pemanggil.
create function private.greeting_photo_allowed(p_bucket text, p_name text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  -- CASE menjamin cast ke uuid hanya dijalankan setelah bucket dan bentuk path cocok (policy berlaku untuk
  -- semua bucket).
  select case
    when p_bucket = (private.config() ->> 'greeting_photo_bucket')
     and p_name ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/(regular|vip|vvip)/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.(png|jpg|webp)$'
      then private.is_event_admin(split_part(p_name, '/', 1)::uuid)
    else false
  end;
$$;

create policy greeting_photos_admin_select on storage.objects for select to authenticated
  using (private.greeting_photo_allowed(bucket_id, name));
create policy greeting_photos_admin_insert on storage.objects for insert to authenticated
  with check (private.greeting_photo_allowed(bucket_id, name));
create policy greeting_photos_admin_update on storage.objects for update to authenticated
  using (private.greeting_photo_allowed(bucket_id, name))
  with check (private.greeting_photo_allowed(bucket_id, name));
create policy greeting_photos_admin_delete on storage.objects for delete to authenticated
  using (private.greeting_photo_allowed(bucket_id, name));

-- =============================================================================================
-- Job pembersihan user Auth perangkat (11.5 langkah 7, K26, K34).
-- pg_cron → private.invoke_device_cleanup() → pg_net → Edge Function device-cleanup (mode sweep).
-- URL dan secret job dibaca dari Supabase Vault, bukan service role key; tidak ada nilai rahasia di migration.
-- Lokal: scripts/local-secrets.mjs mengisi Vault. Produksi: diisi operator (docs/progress.md).
-- =============================================================================================

create function private.invoke_device_cleanup()
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_url text;
  v_secret text;
  v_request_id bigint;
begin
  select decrypted_secret into v_url from vault.decrypted_secrets where name = 'device_cleanup_url';
  select decrypted_secret into v_secret from vault.decrypted_secrets where name = 'device_cleanup_cron_secret';
  if v_url is null or v_secret is null then
    raise warning 'device-cleanup: secret Vault device_cleanup_url / device_cleanup_cron_secret belum diisi.';
    return null;
  end if;
  select net.http_post(
    url := v_url,
    body := jsonb_build_object('mode', 'sweep'),
    headers := jsonb_build_object('Content-Type', 'application/json', 'x-cron-secret', v_secret),
    timeout_milliseconds := 30000
  ) into v_request_id;
  return v_request_id;
end;
$$;

select cron.schedule('device-cleanup-sweep', private.config() ->> 'device_cleanup_schedule',
                     'select private.invoke_device_cleanup()');

-- =============================================================================================
-- Hak eksekusi
-- =============================================================================================

revoke all on function private.signal_usher(uuid) from public, anon, authenticated, service_role;
revoke all on function private.on_usher_data_change() from public, anon, authenticated, service_role;
revoke all on function private.usher_can_listen(text) from public, anon, authenticated, service_role;
revoke all on function private.greeting_photo_allowed(text, text) from public, anon, authenticated, service_role;
revoke all on function private.invoke_device_cleanup() from public, anon, authenticated, service_role;

-- Dievaluasi policy dengan hak role pemanggil.
grant execute on function private.usher_can_listen(text) to authenticated;
grant execute on function private.greeting_photo_allowed(text, text) to authenticated;
