// Simulator check-in (docs/plan.md bagian 17). Hanya memakai publishable key, login Admin, dan Edge Function
// usher-login; TIDAK PERNAH memakai service role.
//
//   pnpm sim                                   skenario lengkap 14 langkah; exit code ≠ 0 bila ada yang menyimpang
//   pnpm sim -- --scenario quarantine-limit    + batas 500 item karantina per perangkat
//   pnpm sim -- --live --rate 2 --duration 120 [--event <id>]   check-in terus-menerus untuk demo statistik
//
// Target bawaan: Supabase lokal (`supabase status`). Target lain lewat env SIM_SUPABASE_URL,
// SIM_PUBLISHABLE_KEY, SIM_ADMIN_EMAIL, SIM_ADMIN_PASSWORD (jangan arahkan ke produksi).
import { randomUUID } from 'node:crypto';
import { parseArgs } from 'node:util';
import {
  GUEST_SNAPSHOT_KEYS,
  QUARANTINE_MAX_ITEMS_PER_DEVICE,
  pullResponseSchema,
  pushResponseSchema,
  type PushItem,
  type PushItemResult,
  type PushResponse,
  type SnapshotOk,
} from '@guestbook/shared';

// `pnpm sim -- --opsi` meneruskan '--' apa adanya.
const { values: args } = parseArgs({
  args: process.argv.slice(2).filter((a) => a !== '--'),
  options: {
    scenario: { type: 'string' },
    live: { type: 'boolean', default: false },
    rate: { type: 'string', default: '2' },
    duration: { type: 'string', default: '120' },
    event: { type: 'string' },
  },
});

// --- Koneksi ------------------------------------------------------------------------------------

async function target() {
  if (process.env.SIM_SUPABASE_URL) {
    return {
      url: process.env.SIM_SUPABASE_URL,
      key: process.env.SIM_PUBLISHABLE_KEY ?? '',
      email: process.env.SIM_ADMIN_EMAIL ?? '',
      password: process.env.SIM_ADMIN_PASSWORD ?? '',
    };
  }
  const { localSupabaseEnv } = await import('./local-supabase-env.mjs');
  const env = localSupabaseEnv();
  return { url: env.API_URL, key: env.PUBLISHABLE_KEY, email: 'admin@buku-tamu.test', password: 'admin-lokal-2026' };
}
const T = await target();

async function http(
  path: string,
  init: { method?: string; token?: string; body?: unknown; headers?: Record<string, string> } = {},
) {
  const res = await fetch(T.url + path, {
    method: init.method ?? 'POST',
    headers: {
      apikey: T.key,
      'content-type': 'application/json',
      ...(init.token ? { authorization: `Bearer ${init.token}` } : {}),
      ...init.headers,
    },
    body: init.body === undefined ? undefined : JSON.stringify(init.body),
  });
  const text = await res.text();
  return { status: res.status, data: text ? (JSON.parse(text) as unknown) : null };
}
const rpc = (token: string, fn: string, body: Record<string, unknown> = {}) =>
  http(`/rest/v1/rpc/${fn}`, { token, body });

// --- Pencatatan hasil ---------------------------------------------------------------------------

const checks: { step: string; ok: boolean; detail: string }[] = [];
const statusCount = new Map<string, number>();
function check(step: string, ok: boolean, detail = '') {
  checks.push({ step, ok, detail });
  console.log(`${ok ? '  ✓' : '  ✗'} ${step}${detail ? ` — ${detail}` : ''}`);
}
function tally(results: PushItemResult[]) {
  for (const r of results) {
    const k = r.outcome === 'stored' ? r.status : `galat:${r.code}`;
    statusCount.set(k, (statusCount.get(k) ?? 0) + 1);
  }
}

// --- Aktor --------------------------------------------------------------------------------------

async function adminLogin(): Promise<string> {
  const r = await http('/auth/v1/token?grant_type=password', { body: { email: T.email, password: T.password } });
  if (r.status !== 200) throw new Error(`Login Admin gagal (${r.status}).`);
  return (r.data as { access_token: string }).access_token;
}

interface Device {
  label: string;
  id: string;
  code: string;
  token: string;
  refresh: string;
}

async function usherLogin(label: string, body: Record<string, unknown>): Promise<Device> {
  const r = await http('/functions/v1/usher-login', {
    body: { ...body, device: { name: `Simulator ${label}`, appVersion: 'sim' } },
  });
  if (r.status !== 200) throw new Error(`Login perangkat ${label} gagal (${r.status}): ${JSON.stringify(r.data)}`);
  const d = r.data as { device: { id: string; code: string }; session: { accessToken: string; refreshToken: string } };
  return { label, id: d.device.id, code: d.device.code, token: d.session.accessToken, refresh: d.session.refreshToken };
}

function item(device: Device, guestId: string | null, ticketNumber: string, extra: Partial<PushItem> = {}): PushItem {
  return {
    id: randomUUID(),
    guestId,
    actualPax: 1,
    ticketNumber,
    deviceId: device.id,
    checkedInAt: new Date().toISOString(),
    ...extra,
  };
}

async function push(device: Device, items: PushItem[]): Promise<PushResponse> {
  const r = await rpc(device.token, 'push_outbox', { p_items: items, p_client_now: new Date().toISOString() });
  const parsed = pushResponseSchema.parse(r.data);
  tally(parsed.results);
  return parsed;
}

async function pullAll(device: Device, cursor: string | null = null, limit = 25) {
  const pages: SnapshotOk[] = [];
  let next = cursor;
  for (;;) {
    const r = await rpc(device.token, 'pull_snapshot', { p_cursor: next, p_limit: limit });
    const parsed = pullResponseSchema.parse(r.data); // .strict(): kunci terlarang membuat parse gagal
    if (parsed.status !== 'ok') return { status: parsed.status, pages, cursor: next };
    pages.push(parsed);
    next = parsed.nextCursor;
    if (!parsed.hasMore) return { status: 'ok' as const, pages, cursor: next };
  }
}

const outcomes = (r: PushResponse) => r.results.map((x) => (x.outcome === 'stored' ? x.status : x.code));
const pad = (n: number) => String(n).padStart(3, '0');

// --- Persiapan acara ----------------------------------------------------------------------------

async function prepareEvent(admin: string, name: string) {
  const today = new Date().toISOString().slice(0, 10);
  const created = await rpc(admin, 'admin_create_event', { p_name: name, p_event_date: today });
  if (created.status !== 200) throw new Error(`Acara gagal dibuat: ${JSON.stringify(created.data)}`);
  const eventId = created.data as string;
  const rows = [
    ...Array.from({ length: 40 }, (_, i) => ({ row: i + 2, name: `Tamu Regular ${pad(i + 1)}` })),
    ...Array.from({ length: 10 }, (_, i) => ({
      row: i + 42,
      name: `Tamu VIP ${pad(i + 1)}`,
      category: 'vip',
      special_number: `VIP-${pad(i + 1)}`,
    })),
    ...Array.from({ length: 10 }, (_, i) => ({
      row: i + 52,
      name: `Tamu VVIP ${pad(i + 1)}`,
      category: 'vvip',
      special_number: `VVIP-${pad(i + 1)}`,
      rsvp_status: 'going',
      rsvp_pax: 2,
    })),
  ];
  const imported = await rpc(admin, 'admin_import_guests', { p_event_id: eventId, p_rows: rows });
  if (imported.status !== 200) throw new Error(`Impor tamu gagal: ${JSON.stringify(imported.data)}`);
  const code = await http(`/rest/v1/events?id=eq.${eventId}&select=code`, { method: 'GET', token: admin });
  const guests = await http(`/rest/v1/guests?event_id=eq.${eventId}&select=id,name,special_number&order=name`, {
    method: 'GET',
    token: admin,
  });
  return {
    eventId,
    code: (code.data as { code: string }[])[0]!.code,
    guests: guests.data as { id: string; name: string; special_number: string | null }[],
  };
}

async function createUsher(admin: string, eventId: string, name: string) {
  const r = await rpc(admin, 'admin_create_usher', { p_event_id: eventId, p_name: name });
  if (r.status !== 200) throw new Error(`Usher gagal dibuat: ${JSON.stringify(r.data)}`);
  return r.data as { usher_id: string; pin: string };
}

// --- Skenario lengkap ---------------------------------------------------------------------------

async function scenario() {
  console.log('1. Persiapan: Admin, acara, 60 tamu, 4 usher, 1 QR Login');
  const admin = await adminLogin();
  const ev = await prepareEvent(admin, `Simulasi ${new Date().toISOString().slice(0, 19)}`);
  const byName = (n: string) => ev.guests.find((g) => g.name === n)!;
  const regular = ev.guests.filter((g) => g.name.startsWith('Tamu Regular'));
  const vip = ev.guests.filter((g) => g.name.startsWith('Tamu VIP'));
  const ushers = await Promise.all(
    ['Usher A', 'Usher B', 'Usher C', 'Usher D'].map((n) => createUsher(admin, ev.eventId, n)),
  );
  const qr = await rpc(admin, 'admin_create_login_qr', { p_usher_id: ushers[2]!.usher_id });
  check('persiapan', ev.guests.length === 60 && qr.status === 200, `Kode Acara ${ev.code}`);

  console.log('2. Login: A, B, D lewat Kode Acara + PIN; C lewat QR');
  const A = await usherLogin('A', { method: 'pin', eventCode: ev.code, pin: ushers[0]!.pin });
  const B = await usherLogin('B', { method: 'pin', eventCode: ev.code, pin: ushers[1]!.pin });
  const C = await usherLogin('C', { method: 'qr', token: (qr.data as { token: string }).token });
  const D = await usherLogin('D', { method: 'pin', eventCode: ev.code, pin: ushers[3]!.pin });
  check('login', [A, B, C, D].map((d) => d.code).join('') === 'ABCD', 'kode perangkat A, B, C, D');

  console.log('3. Snapshot penuh (paginasi 25)');
  const full = await pullAll(A);
  const allGuests = full.pages.flatMap((p) => p.guests);
  check(
    'snapshot penuh',
    full.status === 'ok' && allGuests.length === 60,
    `${full.pages.length} halaman, ${allGuests.length} tamu`,
  );
  check(
    'kunci GuestSnapshot',
    allGuests.every((g) => Object.keys(g).sort().join() === [...GUEST_SNAPSHOT_KEYS].sort().join()),
    'tanpa phone/notes/qr_token',
  );
  check(
    'checkIn awal',
    allGuests.every((g) => g.checkIn === null),
  );

  console.log('4. Online: A mengirim 20 check-in satu per satu');
  const aItems: PushItem[] = [];
  const aResults: PushItemResult[] = [];
  for (let i = 0; i < 20; i++) {
    const it = item(A, regular[i]!.id, `A-${pad(i + 1)}`);
    aItems.push(it);
    aResults.push(...(await push(A, [it])).results);
  }
  check(
    'online',
    aResults.every((r) => r.outcome === 'stored' && r.status === 'accepted'),
    '20 accepted',
  );

  console.log('5. Batch offline: B mengirim 30 item sekaligus');
  const batch = [
    ...regular.slice(20, 40).map((g, i) => item(B, g.id, `B-${pad(i + 1)}`)),
    ...vip.map((g) => item(B, g.id, g.special_number!)),
  ];
  const rB = await push(B, batch);
  check('batch offline', outcomes(rB).every((s) => s === 'accepted') && rB.results.length === 30, '30 accepted');

  console.log('6. Retry: A mengirim ulang 5 item');
  const retry = await push(A, aItems.slice(0, 5));
  check('retry idempoten', JSON.stringify(retry.results) === JSON.stringify(aResults.slice(0, 5)), 'hasil identik');

  console.log('7. Tamu sama di dua perangkat (VVIP bernomor)');
  const v1 = byName('Tamu VVIP 001');
  const s1 = [
    ...outcomes(await push(A, [item(A, v1.id, 'VVIP-001')])),
    ...outcomes(await push(C, [item(C, v1.id, 'VVIP-001')])),
  ];
  check('Lebih 1 Kali nonaktif', s1.join() === 'accepted,duplicate', s1.join(' + '));
  await http(`/rest/v1/checkin_settings?event_id=eq.${ev.eventId}`, {
    method: 'PATCH',
    token: admin,
    body: { allow_multi_checkin: true },
  });
  const v2 = byName('Tamu VVIP 002');
  const s2 = [
    ...outcomes(await push(A, [item(A, v2.id, 'VVIP-002')])),
    ...outcomes(await push(C, [item(C, v2.id, 'VVIP-002')])),
  ];
  check('Lebih 1 Kali aktif', s2.join() === 'accepted,repeat', s2.join(' + '));

  console.log('8. Tamu tambahan: C mengirim 3 newGuest');
  const extra = await push(
    C,
    [1, 2, 3].map((i) =>
      item(C, null, `C-${pad(i)}`, {
        newGuest: { name: `Tamu Tambahan ${i}`, phone: null, category: 'regular', invitedPax: 1, notes: null },
      }),
    ),
  );
  check(
    'tamu tambahan',
    outcomes(extra).every((s) => s === 'accepted') && extra.results.every((r) => r.outcome === 'stored' && r.guestId),
  );

  console.log('9. Conflict: nomor tiket yang sudah dipakai check-in sah lain');
  await push(A, [item(A, byName('Tamu VVIP 003').id, 'VVIP-003')]);
  const conflict = await push(D, [item(D, byName('Tamu VVIP 004').id, 'VVIP-003')]);
  check('conflict', outcomes(conflict).join() === 'conflict');

  console.log('10. Delta + tombstone');
  const removed = byName('Tamu Regular 040');
  await http(`/rest/v1/guests?id=eq.${removed.id}`, {
    method: 'PATCH',
    token: admin,
    body: { deleted_at: new Date().toISOString() },
  });
  const delta = await pullAll(A, full.cursor);
  const deltaGuests = delta.pages.flatMap((p) => p.guests);
  const tomb = deltaGuests.find((g) => g.id === removed.id);
  const v1Delta = deltaGuests.find((g) => g.id === v1.id);
  check(
    'delta',
    delta.status === 'ok' && deltaGuests.length > 0 && deltaGuests.length < 70,
    `${deltaGuests.length} tamu berubah`,
  );
  check('tombstone', !!tomb?.deletedAt);
  check('checkIn di delta', v1Delta?.checkIn?.status === 'accepted' && v1Delta.checkIn.ticketNumber === 'VVIP-001');

  console.log('11. Cabut perangkat B');
  await rpc(admin, 'admin_revoke_device', { p_device_id: B.id, p_mode: 'quarantine' });
  const pullB = await rpc(B.token, 'pull_snapshot', { p_cursor: delta.cursor });
  check('pull setelah Cabut', JSON.stringify(pullB.data) === '{"status":"revoked"}', 'tanpa data, termasuk delta');
  const target = byName('Tamu Regular 039');
  const before = await http(`/rest/v1/guests?id=eq.${target.id}&select=attendance_status`, {
    method: 'GET',
    token: admin,
  });
  const qB = await push(B, [
    item(B, byName('Tamu VVIP 005').id, 'VVIP-005'),
    item(B, null, 'B-900', {
      newGuest: { name: 'Tamu Karantina', phone: null, category: 'vip', invitedPax: 4, notes: null },
    }),
  ]);
  check(
    'push setelah Cabut',
    qB.status === 'revoked' && outcomes(qB).every((s) => s === 'quarantined'),
    'quarantined (device_revoked)',
  );
  const after = await http(`/rest/v1/guests?select=id&name=eq.Tamu%20Karantina&event_id=eq.${ev.eventId}`, {
    method: 'GET',
    token: admin,
  });
  const vvip5 = await http(`/rest/v1/guests?id=eq.${byName('Tamu VVIP 005').id}&select=attendance_status`, {
    method: 'GET',
    token: admin,
  });
  check(
    'karantina tidak dihitung',
    (after.data as unknown[]).length === 0 &&
      (vvip5.data as { attendance_status: string }[])[0]?.attendance_status === 'not_arrived' &&
      JSON.stringify(before.data) ===
        JSON.stringify(
          (await http(`/rest/v1/guests?id=eq.${target.id}&select=attendance_status`, { method: 'GET', token: admin }))
            .data,
        ),
    'tamu tambahan belum dibuat, kehadiran tidak berubah',
  );
  // Admin menyetujui sebagian dan menolak sebagian (FR-RW-05).
  const statsBefore = (await rpc(admin, 'get_event_stats', { p_event_id: ev.eventId })).data as {
    peoplePresent: number;
  };
  const [qVvip, qNew] = qB.results;
  const approved = await rpc(admin, 'admin_decide_quarantine', {
    p_event_id: ev.eventId,
    p_decision: 'approve',
    p_ids: [qVvip!.id],
  });
  const rejected = await rpc(admin, 'admin_decide_quarantine', {
    p_event_id: ev.eventId,
    p_decision: 'reject',
    p_ids: [qNew!.id],
    p_reason: 'Simulasi: tamu tidak dikenal',
  });
  const statsAfter = (await rpc(admin, 'get_event_stats', { p_event_id: ev.eventId })).data as {
    peoplePresent: number;
  };
  const vvip5After = await http(`/rest/v1/guests?id=eq.${byName('Tamu VVIP 005').id}&select=attendance_status`, {
    method: 'GET',
    token: admin,
  });
  check(
    'setujui karantina',
    (approved.data as { results: { status: string }[] }).results[0]?.status === 'accepted' &&
      (vvip5After.data as { attendance_status: string }[])[0]?.attendance_status === 'checked_in' &&
      statsAfter.peoplePresent === statsBefore.peoplePresent + 1,
    'accepted, tamu Hadir, statistik +1 orang',
  );
  const stillNoGuest = await http(`/rest/v1/guests?select=id&name=eq.Tamu%20Karantina&event_id=eq.${ev.eventId}`, {
    method: 'GET',
    token: admin,
  });
  check(
    'tolak karantina',
    (rejected.data as { decided: number }).decided === 1 && (stillNoGuest.data as unknown[]).length === 0,
    'tamu tambahan tidak dibuat, data tetap tersimpan',
  );

  if (args.scenario === 'quarantine-limit') {
    console.log('12. Batas karantina: B mengirim sampai item karantina ke-501');
    // Karantina B yang tersisa: yang disetujui berpindah status, yang ditolak tetap terhitung (T-057).
    const existing = qB.results.length - 1;
    const many = Array.from({ length: QUARANTINE_MAX_ITEMS_PER_DEVICE + 1 - existing }, (_, i) =>
      item(B, regular[i % 20]!.id, `B-${pad(i + 100)}`),
    );
    let last: PushResponse | undefined;
    for (let i = 0; i < many.length; i += 200) last = await push(B, many.slice(i, i + 200));
    const lastCode = last?.results.at(-1);
    check('item ke-501 ditolak', lastCode?.outcome === 'error' && lastCode.code === 'quarantine_limit');
    const alerts = await rpc(admin, 'get_alerts', { p_event_id: ev.eventId });
    check(
      'peringatan batas karantina',
      (alerts.data as { quarantineFull: { code: string }[] }).quarantineFull.some((q) => q.code === 'B'),
    );
  }

  console.log('13. Cabut & putus total perangkat D');
  const term = await http('/functions/v1/device-cleanup', {
    token: admin,
    body: { mode: 'terminate', deviceId: D.id, reason: 'Simulasi HP hilang' },
  });
  check('putus total', term.status === 200, JSON.stringify(term.data));
  const pD = await push(D, [item(D, byName('Tamu VVIP 006').id, 'VVIP-006')]);
  check('push setelah putus total', pD.status === 'rejected' && pD.reason === 'terminated');
  const refresh = await http('/auth/v1/token?grant_type=refresh_token', { body: { refresh_token: D.refresh } });
  check('refresh token gagal', refresh.status >= 400, `HTTP ${refresh.status}`);

  console.log('\n14. Ringkasan');
  console.table(Object.fromEntries([...statusCount.entries()].sort()));
  const failed = checks.filter((c) => !c.ok);
  console.log(`${checks.length - failed.length}/${checks.length} pemeriksaan sesuai ekspektasi. Acara: ${ev.eventId}`);
  if (failed.length) {
    console.error(`Menyimpang: ${failed.map((f) => f.step).join(', ')}`);
    process.exit(1);
  }
}

// --- Mode live (demo statistik M3) --------------------------------------------------------------

async function live() {
  const admin = await adminLogin();
  const rate = Math.max(0.1, Number(args.rate));
  const duration = Math.max(1, Number(args.duration));
  let ev: { eventId: string; code: string; guests: { id: string; special_number: string | null }[] };
  if (args.event) {
    const code = await http(`/rest/v1/events?id=eq.${args.event}&select=code`, { method: 'GET', token: admin });
    const guests = await http(
      `/rest/v1/guests?event_id=eq.${args.event}&deleted_at=is.null&attendance_status=eq.not_arrived&select=id,special_number&limit=1000`,
      { method: 'GET', token: admin },
    );
    ev = {
      eventId: args.event,
      code: (code.data as { code: string }[])[0]!.code,
      guests: guests.data as { id: string; special_number: string | null }[],
    };
  } else {
    ev = await prepareEvent(admin, `Simulasi live ${new Date().toISOString().slice(0, 19)}`);
  }
  const ushers = await Promise.all(['Live A', 'Live B'].map((n) => createUsher(admin, ev.eventId, n)));
  const devices = [
    await usherLogin('A', { method: 'pin', eventCode: ev.code, pin: ushers[0]!.pin }),
    await usherLogin('B', { method: 'pin', eventCode: ev.code, pin: ushers[1]!.pin }),
  ];
  const queue = [...ev.guests].sort(() => Math.random() - 0.5);
  const counters = new Map(devices.map((d) => [d.id, 0]));
  console.log(`Live: ${rate} check-in/detik selama ${duration} detik ke acara ${ev.eventId} (Kode ${ev.code}).`);
  const end = Date.now() + duration * 1000;
  let sent = 0;
  while (Date.now() < end && queue.length) {
    const guest = queue.shift()!;
    const d = devices[sent % devices.length]!;
    const n = (counters.get(d.id) ?? 0) + 1;
    counters.set(d.id, n);
    const r = await push(d, [
      item(d, guest.id, guest.special_number ?? `${d.code}-${pad(n)}`, {
        actualPax: 1 + Math.floor(Math.random() * 3),
      }),
    ]);
    sent++;
    process.stdout.write(`\r${sent} terkirim · terakhir ${outcomes(r).join()}      `);
    await new Promise((resolve) => setTimeout(resolve, 1000 / rate));
  }
  console.log(`\nSelesai: ${sent} check-in.`);
  console.table(Object.fromEntries(statusCount));
}

try {
  await (args.live ? live() : scenario());
} catch (e) {
  console.error(e instanceof Error ? e.message : e);
  process.exit(1);
}
