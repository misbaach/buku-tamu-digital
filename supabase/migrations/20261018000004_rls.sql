-- RLS dan hak akses tabel (prd.md 10.4, 11.4).
-- - Otorisasi hanya dari app_metadata (ditulis service role) dan tabel event_members; user_metadata tidak dipakai.
-- - Usher tidak punya hak tabel apa pun: tidak ada GRANT yang berlaku untuknya, dan policy restrictive
--   mensyaratkan app_metadata.role = 'admin'. Akses usher hanya lewat RPC pull_snapshot/push_outbox (M2).
-- - Tulis langsung oleh Admin dibatasi lewat column grant; operasi sensitif lewat RPC yang diaudit.

-- Event yang boleh diakses pemanggil sebagai Admin. Dipakai policy dalam bentuk
-- `event_id in (select private.admin_event_ids())` agar dievaluasi sekali per query.
create function private.admin_event_ids()
returns setof uuid
language sql
stable
security definer
set search_path = ''
as $$
  select m.event_id
  from public.event_members m
  where m.user_id = (select auth.uid())
    and coalesce((select auth.jwt() -> 'app_metadata' ->> 'role'), '') = 'admin';
$$;

create function private.is_event_admin(p_event_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (select 1 from private.admin_event_ids() as e(id) where e.id = p_event_id);
$$;

revoke all on function private.admin_event_ids() from public, anon, authenticated, service_role;
revoke all on function private.is_event_admin(uuid) from public, anon, authenticated, service_role;
grant execute on function private.admin_event_ids() to authenticated;
grant execute on function private.is_event_admin(uuid) to authenticated;

-- ---------------------------------------------------------------------------------------------
-- Aktifkan RLS di semua tabel public, tanpa kecuali.
-- ---------------------------------------------------------------------------------------------
alter table public.events enable row level security;
alter table public.event_members enable row level security;
alter table public.guest_groups enable row level security;
alter table public.guests enable row level security;
alter table public.ticket_number_settings enable row level security;
alter table public.checkin_settings enable row level security;
alter table public.greeting_configs enable row level security;
alter table public.ushers enable row level security;
alter table public.usher_login_tokens enable row level security;
alter table public.devices enable row level security;
alter table public.check_ins enable row level security;
alter table public.auth_attempts enable row level security;
alter table public.audit_logs enable row level security;

-- ---------------------------------------------------------------------------------------------
-- Policy restrictive: hanya user dengan app_metadata.role = 'admin' yang bisa melewati RLS.
-- Policy ini di-AND-kan dengan semua policy permissive di bawah.
-- ---------------------------------------------------------------------------------------------
do $$
declare
  t text;
begin
  foreach t in array array[
    'events', 'event_members', 'guest_groups', 'guests', 'ticket_number_settings', 'checkin_settings',
    'greeting_configs', 'ushers', 'usher_login_tokens', 'devices', 'check_ins', 'auth_attempts', 'audit_logs'
  ] loop
    execute format(
      $f$create policy %I on public.%I as restrictive for all to authenticated
         using ((select auth.jwt() -> 'app_metadata' ->> 'role') = 'admin')
         with check ((select auth.jwt() -> 'app_metadata' ->> 'role') = 'admin')$f$,
      t || '_admin_role_only', t
    );
  end loop;
end;
$$;

-- ---------------------------------------------------------------------------------------------
-- Policy permissive per tabel (Admin anggota event).
-- ---------------------------------------------------------------------------------------------
create policy events_select on public.events for select to authenticated
  using (id in (select private.admin_event_ids()));

create policy event_members_select on public.event_members for select to authenticated
  using (event_id in (select private.admin_event_ids()));

create policy guest_groups_select on public.guest_groups for select to authenticated
  using (event_id in (select private.admin_event_ids()));
create policy guest_groups_insert on public.guest_groups for insert to authenticated
  with check (event_id in (select private.admin_event_ids()));
create policy guest_groups_update on public.guest_groups for update to authenticated
  using (event_id in (select private.admin_event_ids()))
  with check (event_id in (select private.admin_event_ids()));

create policy guests_select on public.guests for select to authenticated
  using (event_id in (select private.admin_event_ids()));
create policy guests_insert on public.guests for insert to authenticated
  with check (event_id in (select private.admin_event_ids()));
create policy guests_update on public.guests for update to authenticated
  using (event_id in (select private.admin_event_ids()))
  with check (event_id in (select private.admin_event_ids()));

create policy ticket_number_settings_select on public.ticket_number_settings for select to authenticated
  using (event_id in (select private.admin_event_ids()));
create policy ticket_number_settings_update on public.ticket_number_settings for update to authenticated
  using (event_id in (select private.admin_event_ids()))
  with check (event_id in (select private.admin_event_ids()));

create policy checkin_settings_select on public.checkin_settings for select to authenticated
  using (event_id in (select private.admin_event_ids()));
create policy checkin_settings_update on public.checkin_settings for update to authenticated
  using (event_id in (select private.admin_event_ids()))
  with check (event_id in (select private.admin_event_ids()));

create policy greeting_configs_select on public.greeting_configs for select to authenticated
  using (event_id in (select private.admin_event_ids()));
create policy greeting_configs_update on public.greeting_configs for update to authenticated
  using (event_id in (select private.admin_event_ids()))
  with check (event_id in (select private.admin_event_ids()));

create policy ushers_select on public.ushers for select to authenticated
  using (event_id in (select private.admin_event_ids()));

create policy devices_select on public.devices for select to authenticated
  using (event_id in (select private.admin_event_ids()));

create policy check_ins_select on public.check_ins for select to authenticated
  using (event_id in (select private.admin_event_ids()));

create policy audit_logs_select on public.audit_logs for select to authenticated
  using (event_id in (select private.admin_event_ids()));

-- usher_login_tokens dan auth_attempts: RLS aktif tanpa policy dan tanpa GRANT = tertutup untuk semua role API.

-- ---------------------------------------------------------------------------------------------
-- GRANT eksplisit. anon tidak mendapat apa pun. service_role tidak mendapat hak tabel; Edge Function
-- bekerja lewat fungsi svc_* (M2). Kolom yang tidak tercantum tidak bisa ditulis langsung.
-- ---------------------------------------------------------------------------------------------
grant select on public.events to authenticated;
grant select on public.event_members to authenticated;

grant select on public.guest_groups to authenticated;
grant insert (event_id, name, description) on public.guest_groups to authenticated;
grant update (name, description, deleted_at) on public.guest_groups to authenticated;

grant select on public.guests to authenticated;
grant insert (event_id, name, phone, category, group_id, invited_pax, special_number, rsvp_status, rsvp_pax, notes)
  on public.guests to authenticated;
grant update (name, phone, category, group_id, invited_pax, special_number, rsvp_status, rsvp_pax, notes, deleted_at)
  on public.guests to authenticated;

grant select on public.ticket_number_settings to authenticated;
grant update (prefix, start_number, digits) on public.ticket_number_settings to authenticated;

grant select on public.checkin_settings to authenticated;
grant update (show_verification, allow_multi_checkin, print_ticket) on public.checkin_settings to authenticated;

grant select on public.greeting_configs to authenticated;
grant update (popup) on public.greeting_configs to authenticated;

-- pin_hash tidak pernah bisa dibaca role API.
grant select (id, event_id, name, mode, pin_selector, is_active, created_at, updated_at, deleted_at)
  on public.ushers to authenticated;

-- auth_user_id hanya urusan internal.
grant select (id, event_id, usher_id, code, name, app_version, last_seen_at, clock_offset_ms, session_expires_at,
              revoked_at, revoked_by, revoke_mode, revoke_reason, auth_user_deleted_at, created_at)
  on public.devices to authenticated;

grant select on public.check_ins to authenticated;
grant select on public.audit_logs to authenticated;
