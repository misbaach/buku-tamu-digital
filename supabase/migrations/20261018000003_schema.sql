-- Skema inti (prd.md 12.1, 12.4). Tabel fase P1 (gifts, screen_tokens, invitation_*, message_*) belum dibuat.

create type public.guest_category as enum ('regular', 'vip', 'vvip');
create type public.rsvp_status as enum ('going', 'not_going', 'unconfirmed');
create type public.attendance_status as enum ('not_arrived', 'checked_in', 'checked_out');
create type public.usher_mode as enum ('check_in', 'check_out');
create type public.check_in_status as enum ('accepted', 'repeat', 'duplicate', 'conflict', 'quarantined');
create type public.check_in_source as enum ('device', 'admin', 'outbox_upload');
create type public.quarantine_reason as enum ('device_revoked', 'session_expired');
create type public.revoke_mode as enum ('quarantine', 'terminate');
create type public.auth_attempt_kind as enum ('usher_login', 'invitation_url', 'screen_token');
create type public.login_method as enum ('pin', 'qr');

-- ---------------------------------------------------------------------------------------------
-- events, event_members
-- ---------------------------------------------------------------------------------------------
create table public.events (
  id uuid primary key default gen_random_uuid(),
  code text not null default private.gen_code(6)
    constraint events_code_format check (code ~ '^[ABCDEFGHJKMNPQRSTUVWXYZ23456789]{6}$'),
  name text not null constraint events_name_len check (char_length(btrim(name)) between 1 and 120),
  couple_names text constraint events_couple_names_len check (char_length(couple_names) <= 200),
  event_date date not null,
  timezone text not null default 'Asia/Jakarta' constraint events_timezone_len check (char_length(timezone) <= 64),
  venue text constraint events_venue_len check (char_length(venue) <= 200),
  attendance_limit integer constraint events_attendance_limit_positive check (attendance_limit > 0),
  settings jsonb not null default '{}'::jsonb,
  archived_at timestamptz,
  created_by uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint events_code_key unique (code)
);

create table public.event_members (
  event_id uuid not null references public.events (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  role text not null default 'admin' constraint event_members_role check (role = 'admin'),
  created_at timestamptz not null default now(),
  primary key (event_id, user_id)
);
create index event_members_user_idx on public.event_members (user_id);

-- ---------------------------------------------------------------------------------------------
-- guest_groups, guests
-- ---------------------------------------------------------------------------------------------
create table public.guest_groups (
  id uuid primary key default gen_random_uuid(),
  event_id uuid not null references public.events (id) on delete cascade,
  name text not null constraint guest_groups_name_len check (char_length(btrim(name)) between 1 and 80),
  description text constraint guest_groups_description_len check (char_length(description) <= 300),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  constraint guest_groups_event_id_id_key unique (event_id, id)
);
create unique index guest_groups_event_name_key on public.guest_groups (event_id, lower(btrim(name))) where deleted_at is null;
create index guest_groups_event_updated_idx on public.guest_groups (event_id, updated_at, id);

create table public.guests (
  id uuid primary key default gen_random_uuid(),
  event_id uuid not null references public.events (id) on delete cascade,
  name text not null constraint guests_name_len check (char_length(btrim(name)) between 1 and 120),
  phone text constraint guests_phone_format check (phone ~ '^\+?[0-9][0-9 ().-]{4,22}$'),
  category public.guest_category not null default 'regular',
  group_id uuid,
  invited_pax smallint not null default 1 constraint guests_invited_pax_range check (invited_pax between 1 and 50),
  -- Nomor Urut khusus (FR-C-02): huruf besar, aturan sama dengan Zod lewat private.special_number_issue().
  special_number text constraint guests_special_number_rule
    check (special_number = upper(special_number) and private.special_number_issue(special_number) is null),
  -- Token QR mentah tidak pernah dikirim ke perangkat usher; perangkat hanya menerima hash-nya (FR-HM-01).
  qr_token text not null default private.gen_qr_token(),
  qr_token_hash text not null generated always as (encode(sha256(qr_token::bytea), 'hex')) stored,
  rsvp_status public.rsvp_status not null default 'unconfirmed',
  rsvp_pax smallint constraint guests_rsvp_pax_range check (rsvp_pax between 0 and 50),
  attendance_status public.attendance_status not null default 'not_arrived',
  is_additional boolean not null default false,
  created_device_id uuid,
  notes text constraint guests_notes_len check (char_length(notes) <= 500),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  constraint guests_rsvp_pax_only_if_going check (rsvp_pax is null or rsvp_status = 'going'),
  constraint guests_qr_token_key unique (qr_token),
  constraint guests_event_id_id_key unique (event_id, id),
  constraint guests_group_same_event foreign key (event_id, group_id)
    references public.guest_groups (event_id, id) on delete set null (group_id)
);
create unique index guests_event_qr_token_hash_key on public.guests (event_id, qr_token_hash);
create unique index guests_event_special_number_key on public.guests (event_id, special_number)
  where special_number is not null and deleted_at is null;
create index guests_event_updated_idx on public.guests (event_id, updated_at, id);
create index guests_event_category_attendance_idx on public.guests (event_id, category, attendance_status);
create index guests_event_group_idx on public.guests (event_id, group_id);
create index guests_event_rsvp_idx on public.guests (event_id, rsvp_status);
create index guests_name_trgm_idx on public.guests using gin (name extensions.gin_trgm_ops);

-- ---------------------------------------------------------------------------------------------
-- Pengaturan per event
-- ---------------------------------------------------------------------------------------------
create table public.ticket_number_settings (
  event_id uuid not null references public.events (id) on delete cascade,
  category public.guest_category not null constraint ticket_number_settings_category check (category in ('vip', 'vvip')),
  prefix text not null,
  start_number integer not null default 1 constraint ticket_number_settings_start_range check (start_number between 0 and 999999),
  digits smallint not null default 3 constraint ticket_number_settings_digits_range check (digits between 1 and 6),
  updated_at timestamptz not null default now(),
  primary key (event_id, category),
  -- FR-C-03: prefix + angka harus menghasilkan Nomor Urut yang sah menurut FR-C-02.
  constraint ticket_number_settings_prefix_rule
    check (prefix = upper(prefix) and private.special_number_issue(prefix || lpad('1', digits, '0')) is null)
);

create table public.checkin_settings (
  event_id uuid primary key references public.events (id) on delete cascade,
  show_verification boolean not null default true,
  allow_multi_checkin boolean not null default false,
  print_ticket jsonb not null default
    '{"enabled": true, "fields": ["event_name", "guest_name", "category", "ticket_number"], "categories": ["regular", "vip", "vvip"], "copies": 1}'::jsonb,
  print_entrusted_gift jsonb not null default '{"enabled": false}'::jsonb,
  updated_at timestamptz not null default now(),
  constraint checkin_settings_print_ticket_shape check (
    jsonb_typeof(print_ticket -> 'enabled') = 'boolean'
    and jsonb_typeof(print_ticket -> 'fields') = 'array'
    and jsonb_typeof(print_ticket -> 'categories') = 'array'
    and jsonb_typeof(print_ticket -> 'copies') = 'number'
    and (print_ticket ->> 'copies')::numeric between 1 and 3
  )
);

create table public.greeting_configs (
  event_id uuid not null references public.events (id) on delete cascade,
  category public.guest_category not null,
  popup jsonb not null default '{}'::jsonb,
  screen jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now(),
  primary key (event_id, category)
);

-- ---------------------------------------------------------------------------------------------
-- Usher, token QR Login, perangkat
-- ---------------------------------------------------------------------------------------------
create table public.ushers (
  id uuid primary key default gen_random_uuid(),
  event_id uuid not null references public.events (id) on delete cascade,
  name text not null constraint ushers_name_len check (char_length(btrim(name)) between 1 and 60),
  mode public.usher_mode not null default 'check_in',
  -- ID usher (selector) tidak rahasia; hanya rahasia 8 karakter yang di-hash (FR-R-02).
  pin_selector text not null constraint ushers_pin_selector_format check (pin_selector ~ '^[ABCDEFGHJKMNPQRSTUVWXYZ23456789]{2}$'),
  pin_hash text not null,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  constraint ushers_event_selector_key unique (event_id, pin_selector),
  constraint ushers_event_id_id_key unique (event_id, id)
);

create table public.usher_login_tokens (
  id uuid primary key default gen_random_uuid(),
  usher_id uuid not null references public.ushers (id) on delete cascade,
  token_hash text not null constraint usher_login_tokens_token_hash_key unique,
  expires_at timestamptz not null,
  used_at timestamptz,
  created_by uuid not null,
  created_at timestamptz not null default now()
);

create table public.devices (
  id uuid primary key,
  event_id uuid not null references public.events (id) on delete cascade,
  usher_id uuid not null,
  code text not null constraint devices_code_format check (code ~ '^[A-Z]{1,2}$'),
  auth_user_id uuid constraint devices_auth_user_id_key unique,
  name text constraint devices_name_len check (char_length(name) <= 80),
  app_version text constraint devices_app_version_len check (char_length(app_version) <= 40),
  last_seen_at timestamptz,
  clock_offset_ms integer,
  session_expires_at timestamptz not null,
  revoked_at timestamptz,
  revoked_by uuid,
  revoke_mode public.revoke_mode,
  revoke_reason text constraint devices_revoke_reason_len check (char_length(revoke_reason) <= 300),
  auth_user_deleted_at timestamptz,
  created_at timestamptz not null default now(),
  constraint devices_event_code_key unique (event_id, code),
  constraint devices_event_id_id_key unique (event_id, id),
  constraint devices_usher_same_event foreign key (event_id, usher_id) references public.ushers (event_id, id),
  constraint devices_revoke_consistent check ((revoked_at is null) = (revoke_mode is null))
);
create index devices_cleanup_idx on public.devices (session_expires_at) where auth_user_deleted_at is null;

alter table public.guests
  add constraint guests_created_device_same_event foreign key (event_id, created_device_id)
    references public.devices (event_id, id);

-- ---------------------------------------------------------------------------------------------
-- check_ins (12.3)
-- ---------------------------------------------------------------------------------------------
create table public.check_ins (
  -- UUID dari klien = kunci idempotensi push_outbox.
  id uuid primary key,
  event_id uuid not null references public.events (id) on delete cascade,
  guest_id uuid,
  -- Data tamu tambahan yang menunggu persetujuan karantina; tamu baru dibuat saat disetujui.
  pending_guest jsonb,
  actual_pax smallint not null constraint check_ins_actual_pax_range check (actual_pax between 0 and 50),
  ticket_number text constraint check_ins_ticket_number_format
    check (char_length(ticket_number) between 1 and 20 and ticket_number ~ '^[A-Z0-9-]+$'),
  status public.check_in_status not null,
  quarantine_reason public.quarantine_reason,
  source public.check_in_source not null,
  device_id uuid,
  usher_id uuid,
  created_by uuid,
  checked_in_at timestamptz not null,
  received_at timestamptz not null default now(),
  checked_out_at timestamptz,
  voided_at timestamptz,
  voided_by uuid,
  void_reason text constraint check_ins_void_reason_len check (char_length(void_reason) <= 300),
  reviewed_at timestamptz,
  reviewed_by uuid,
  updated_at timestamptz not null default now(),
  constraint check_ins_guest_same_event foreign key (event_id, guest_id) references public.guests (event_id, id),
  constraint check_ins_device_same_event foreign key (event_id, device_id) references public.devices (event_id, id),
  constraint check_ins_usher_same_event foreign key (event_id, usher_id) references public.ushers (event_id, id),
  -- Tanpa guest_id hanya untuk karantina yang membawa data tamu baru.
  constraint check_ins_guest_or_pending check (guest_id is not null or (status = 'quarantined' and pending_guest is not null)),
  -- Nomor tiket kosong hanya untuk tandai hadir manual Admin (12.3 poin 15).
  constraint check_ins_ticket_required check (ticket_number is not null or source = 'admin'),
  constraint check_ins_quarantine_reason_required check (status <> 'quarantined' or quarantine_reason is not null),
  constraint check_ins_device_source check (source <> 'device' or (device_id is not null and usher_id is not null)),
  constraint check_ins_void_reason_required check (voided_at is null or void_reason is not null)
);
-- 12.3 poin 6: nomor tiket unik hanya untuk check-in accepted yang aktif. NULL dianggap berbeda
-- (perilaku bawaan Postgres, ditulis eksplisit) sehingga tandai hadir manual tanpa nomor tidak bentrok.
create unique index check_ins_event_ticket_accepted_key on public.check_ins (event_id, ticket_number) nulls distinct
  where status = 'accepted' and voided_at is null;
-- Jaring pengaman: satu check-in accepted aktif per tamu.
create unique index check_ins_event_guest_accepted_key on public.check_ins (event_id, guest_id)
  where status = 'accepted' and voided_at is null;
create index check_ins_event_checked_in_idx on public.check_ins (event_id, checked_in_at desc);
create index check_ins_event_guest_idx on public.check_ins (event_id, guest_id);
create index check_ins_event_updated_idx on public.check_ins (event_id, updated_at, id);
create index check_ins_event_review_idx on public.check_ins (event_id, status)
  where status in ('duplicate', 'conflict', 'quarantined');
create index check_ins_device_quarantine_idx on public.check_ins (device_id) where status = 'quarantined';

-- ---------------------------------------------------------------------------------------------
-- auth_attempts, audit_logs
-- ---------------------------------------------------------------------------------------------
create table public.auth_attempts (
  id bigint generated always as identity primary key,
  kind public.auth_attempt_kind not null,
  method public.login_method,
  ip text constraint auth_attempts_ip_len check (char_length(ip) <= 64),
  -- Kode Acara yang dikirim (dinormalisasi), bagian dari kunci blokir (IP + Kode Acara).
  event_code text constraint auth_attempts_event_code_len check (char_length(event_code) <= 32),
  event_id uuid references public.events (id) on delete set null,
  usher_id uuid references public.ushers (id) on delete set null,
  success boolean not null,
  reason text constraint auth_attempts_reason_len check (char_length(reason) <= 64),
  created_at timestamptz not null default now()
);
create index auth_attempts_ip_code_idx on public.auth_attempts (kind, ip, event_code, created_at desc);
create index auth_attempts_ip_idx on public.auth_attempts (kind, ip, created_at desc);
create index auth_attempts_event_idx on public.auth_attempts (kind, event_id, created_at desc);

create table public.audit_logs (
  id bigint generated always as identity primary key,
  event_id uuid references public.events (id) on delete cascade,
  actor_id uuid,
  actor_kind text not null constraint audit_logs_actor_kind check (actor_kind in ('admin', 'usher', 'system')),
  action text not null,
  entity text not null,
  entity_id text,
  before jsonb,
  after jsonb,
  created_at timestamptz not null default now()
);
create index audit_logs_event_created_idx on public.audit_logs (event_id, created_at desc);

-- ---------------------------------------------------------------------------------------------
-- updated_at otomatis
-- ---------------------------------------------------------------------------------------------
create trigger events_set_updated_at before update on public.events
  for each row execute function private.set_updated_at();
create trigger guest_groups_set_updated_at before update on public.guest_groups
  for each row execute function private.set_updated_at();
create trigger guests_set_updated_at before update on public.guests
  for each row execute function private.set_updated_at();
create trigger ticket_number_settings_set_updated_at before update on public.ticket_number_settings
  for each row execute function private.set_updated_at();
create trigger checkin_settings_set_updated_at before update on public.checkin_settings
  for each row execute function private.set_updated_at();
create trigger greeting_configs_set_updated_at before update on public.greeting_configs
  for each row execute function private.set_updated_at();
create trigger ushers_set_updated_at before update on public.ushers
  for each row execute function private.set_updated_at();
create trigger check_ins_set_updated_at before update on public.check_ins
  for each row execute function private.set_updated_at();
