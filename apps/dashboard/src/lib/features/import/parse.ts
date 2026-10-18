import {
  IMPORT_COLUMNS,
  IMPORT_MAX_FILE_BYTES,
  IMPORT_MAX_ROWS,
  mapImportHeaders,
  validateImportRow,
  type ImportField,
  type ImportRowResult,
} from '@guestbook/shared';

const EXTENSIONS = ['xlsx', 'xls', 'csv'];

export class ImportFileError extends Error {}

/** Nilai sel → teks. Angka bulat ditulis utuh (telepon yang tersimpan sebagai angka tidak menjadi 6.28E+12). */
export function cellText(v: unknown): string {
  if (v == null) return '';
  if (typeof v === 'number') return Number.isInteger(v) ? v.toFixed(0) : String(v);
  return String(v).trim();
}

/**
 * Baris lembar pertama (header di baris 1) → hasil validasi per baris. Nomor baris mengikuti Excel
 * (data mulai baris 2); baris yang seluruhnya kosong dilewati tanpa menggeser nomor baris.
 */
export function rowsToResults(sheetRows: unknown[][]): ImportRowResult[] {
  const [header = [], ...body] = sheetRows;
  const { map, missing } = mapImportHeaders(header.map(cellText));
  if (missing.length > 0) {
    throw new ImportFileError('Kolom "Nama" tidak ditemukan di baris pertama. Pakai templat agar nama kolom sesuai.');
  }
  const results: ImportRowResult[] = [];
  body.forEach((cells, i) => {
    const texts = cells.map(cellText);
    if (texts.every((t) => t === '')) return;
    const record: Partial<Record<ImportField, string>> = {};
    for (const [col, key] of map) record[key] = texts[col] ?? '';
    results.push(validateImportRow(i + 2, record));
  });
  if (results.length === 0) throw new ImportFileError('Berkas tidak berisi data tamu.');
  if (results.length > IMPORT_MAX_ROWS) {
    throw new ImportFileError(
      `Maksimal ${IMPORT_MAX_ROWS.toLocaleString('id-ID')} baris per impor. Bagi berkas menjadi beberapa bagian.`,
    );
  }
  return results;
}

export async function parseGuestFile(file: File): Promise<ImportRowResult[]> {
  const ext = file.name.toLowerCase().split('.').pop() ?? '';
  if (!EXTENSIONS.includes(ext)) throw new ImportFileError('Format berkas harus .xlsx, .xls, atau .csv.');
  if (file.size > IMPORT_MAX_FILE_BYTES) throw new ImportFileError('Ukuran berkas maksimal 5 MB.');

  // SheetJS dari distribusi resmi (vendor/xlsx-0.20.3.tgz), dimuat hanya saat dibutuhkan.
  const XLSX = await import('xlsx');
  let workbook;
  try {
    // CSV dibaca apa adanya agar "007" tidak berubah menjadi angka 7.
    workbook = XLSX.read(await file.arrayBuffer(), { type: 'array', raw: ext === 'csv', dense: true });
  } catch {
    throw new ImportFileError('Berkas tidak bisa dibaca. Pastikan berkas tidak rusak dan tidak dilindungi kata sandi.');
  }
  const first = workbook.SheetNames[0];
  const sheet = first ? workbook.Sheets[first] : undefined;
  if (!sheet) throw new ImportFileError('Berkas tidak berisi lembar data.');
  const rows = XLSX.utils.sheet_to_json<unknown[]>(sheet, { header: 1, raw: true, defval: '', blankrows: true });
  return rowsToResults(rows);
}

export async function downloadTemplate() {
  const XLSX = await import('xlsx');
  const data = XLSX.utils.aoa_to_sheet([IMPORT_COLUMNS.map((c) => c.header), IMPORT_COLUMNS.map((c) => c.example)]);
  data['!cols'] = IMPORT_COLUMNS.map((c) => ({ wch: Math.max(14, c.header.length + 4) }));
  const help = XLSX.utils.aoa_to_sheet([
    ['Kolom', 'Keterangan'],
    ...IMPORT_COLUMNS.map((c) => [c.required ? `${c.header} (wajib)` : c.header, c.hint]),
    [],
    ['Tips', 'Format kolom Telepon dan Nomor Urut sebagai Teks agar angka 0 di depan tidak hilang.'],
    ['Tips', 'Hapus baris contoh sebelum mengisi data tamu.'],
  ]);
  help['!cols'] = [{ wch: 26 }, { wch: 90 }];
  const book = XLSX.utils.book_new();
  XLSX.utils.book_append_sheet(book, data, 'Tamu');
  XLSX.utils.book_append_sheet(book, help, 'Petunjuk');
  XLSX.writeFile(book, 'templat-impor-tamu.xlsx');
}
