/// รวมข้อมูลหลายเครื่อง (รอบ 16 · แกนกลาง ยังไม่ต่อเน็ต)
///
/// กติกาที่นัวร์เลือก (20 พ.ย. · ข้อ ก):
/// - เทียบทีละช่อง · ค่าเหมือนกัน = ใช้เลย ไม่เตือน
/// - แก้คนละช่อง = เก็บทั้งสองฝั่ง ไม่เตือน
/// - แก้ช่องเดียวกันคนละค่า (ทั้งสองเครื่องแก้หลังซิงก์ครั้งก่อน) = ใช้ค่าที่ "กดแก้" ทีหลัง + เตือน (สลับกลับได้)
/// "ทีหลัง" = เวลาที่กดแก้บนเครื่องนั้น ไม่ใช่เวลาที่เน็ตกลับมา
library;

/// 1 แถวข้อมูล + เวลาที่แก้แต่ละช่อง (ms นับจาก epoch)
class SyncRow {
  const SyncRow({
    required this.table,
    required this.id,
    required this.values,
    required this.stamps,
    this.deletedAt,
  });

  final String table;
  final String id;
  final Map<String, Object?> values;
  final Map<String, int> stamps;

  /// ลบเมื่อไหร่ · null = ยังอยู่
  final int? deletedAt;

  bool get deleted => deletedAt != null;

  /// แก้ล่าสุดเมื่อไหร่ (ช่องไหนก็ได้ รวมการลบ)
  int get lastTouched => [deletedAt ?? 0, ...stamps.values].fold(0, (a, b) => a > b ? a : b);

  SyncRow copyWith({Map<String, Object?>? values, Map<String, int>? stamps, int? deletedAt, bool undelete = false}) =>
      SyncRow(
        table: table,
        id: id,
        values: values ?? this.values,
        stamps: stamps ?? this.stamps,
        deletedAt: undelete ? null : (deletedAt ?? this.deletedAt),
      );
}

/// ค่าที่ต่างกันจริง (ทั้งสองเครื่องแก้) · [field] null = ฝั่งหนึ่งลบ อีกฝั่งแก้
class SyncConflict {
  const SyncConflict({
    required this.table,
    required this.id,
    required this.field,
    required this.local,
    required this.remote,
    required this.localAt,
    required this.remoteAt,
  });

  final String table;
  final String id;
  final String? field;
  final Object? local;
  final Object? remote;
  final int localAt;
  final int remoteAt;

  /// ใช้ฝั่งไหน (ล่าสุดชนะ · เท่ากัน = ฝั่งบัญชี เพื่อให้ทุกเครื่องได้ผลเดียวกัน)
  bool get keptLocal => localAt > remoteAt;
}

class MergeResult {
  const MergeResult(this.row, this.conflicts);
  final SyncRow? row;
  final List<SyncConflict> conflicts;
}

bool _same(Object? a, Object? b) => a == b;

/// รวม 1 แถว · [lastSync] = เวลาซิงก์สำเร็จครั้งก่อนของเครื่องนี้ (0 = ยังไม่เคย)
MergeResult mergeRow(SyncRow? local, SyncRow? remote, {required int lastSync}) {
  if (local == null) return MergeResult(remote, const []);
  if (remote == null) return MergeResult(local, const []);
  assert(local.table == remote.table && local.id == remote.id);

  bool changedSince(int? t) => t != null && t > lastSync;
  final conflicts = <SyncConflict>[];

  // ลบ vs แก้
  if (local.deleted || remote.deleted) {
    if (local.deleted && remote.deleted) {
      return MergeResult(local.deletedAt! >= remote.deletedAt! ? local : remote, const []);
    }
    final del = local.deleted ? local : remote;
    final kept = local.deleted ? remote : local;
    final editedAfter = kept.stamps.values.any(changedSince);
    final win = kept.lastTouched > del.deletedAt! ? kept : del;
    if (changedSince(del.deletedAt) && editedAfter) {
      conflicts.add(SyncConflict(
        table: local.table,
        id: local.id,
        field: null,
        local: local.deleted ? null : 'แก้',
        remote: remote.deleted ? null : 'แก้',
        localAt: local.lastTouched,
        remoteAt: remote.lastTouched,
      ));
    }
    return MergeResult(win, conflicts);
  }

  final values = <String, Object?>{};
  final stamps = <String, int>{};
  for (final f in {...local.values.keys, ...remote.values.keys}) {
    final lt = local.stamps[f] ?? 0, rt = remote.stamps[f] ?? 0;
    final lv = local.values[f], rv = remote.values[f];
    final useLocal = lt > rt;
    values[f] = useLocal ? lv : rv;
    stamps[f] = useLocal ? lt : rt;
    if (!_same(lv, rv) && changedSince(lt) && changedSince(rt)) {
      conflicts.add(SyncConflict(
        table: local.table,
        id: local.id,
        field: f,
        local: lv,
        remote: rv,
        localAt: lt,
        remoteAt: rt,
      ));
    }
  }
  return MergeResult(local.copyWith(values: values, stamps: stamps), conflicts);
}

/// รวมทั้งชุด (key = table/id)
({Map<String, SyncRow> rows, List<SyncConflict> conflicts}) mergeAll(
  Map<String, SyncRow> local,
  Map<String, SyncRow> remote, {
  required int lastSync,
}) {
  final rows = <String, SyncRow>{};
  final conflicts = <SyncConflict>[];
  for (final k in {...local.keys, ...remote.keys}) {
    final r = mergeRow(local[k], remote[k], lastSync: lastSync);
    if (r.row != null) rows[k] = r.row!;
    conflicts.addAll(r.conflicts);
  }
  return (rows: rows, conflicts: conflicts);
}

/// ข้อความเตือนหลังรวม · null = ไม่ต้องเตือน
String? conflictToast(List<SyncConflict> c) =>
    c.isEmpty ? null : '⚠ ${c.length} รายการแก้ต่างกันบน 2 เครื่อง · ใช้ค่าล่าสุดแล้ว';

/// กด "ใช้อีกค่า" → แถวที่สลับช่องนั้นกลับ (เวลาแก้ = ตอนกด จะได้ชนะรอบถัดไป)
SyncRow useOther(SyncRow merged, SyncConflict c, {required int now}) {
  final other = c.keptLocal ? c.remote : c.local;
  if (c.field == null) {
    // ลบ vs แก้: ถ้าตอนนี้ลบอยู่ → กู้คืน · ถ้ายังอยู่ → ลบ
    return merged.deleted ? merged.copyWith(undelete: true, stamps: {for (final k in merged.stamps.keys) k: now}) : merged.copyWith(deletedAt: now);
  }
  return merged.copyWith(
    values: {...merged.values, c.field!: other},
    stamps: {...merged.stamps, c.field!: now},
  );
}

/// รอบ 21 (ออนไลน์ก่อน · นัวร์เลือก): ของที่ถึงบัญชีทีหลังชนะ
/// [local] = ค่าในเครื่องที่ยังไม่ได้ส่ง (null = ไม่มี) · ช่องที่เครื่องนี้แก้หลังซิงก์ครั้งก่อน = เก็บไว้แล้วส่งตาม
/// ช่องอื่นทั้งหมด = ค่าในบัญชี · ไม่มี "ค่าต่างกันให้เลือก" อีก
SyncRow serverFirst(SyncRow? local, SyncRow remote, {required int lastSync}) {
  if (local == null) return remote;
  bool mineNew(int? t) => t != null && t > lastSync;
  // ลบในเครื่อง (ยังไม่ส่ง) → ลบตาม · บัญชีลบ แต่เครื่องนี้แก้ทีหลัง → ยังอยู่ (ส่งตามไป)
  if (local.deleted && mineNew(local.deletedAt)) return local;
  final mine = {for (final e in local.stamps.entries) if (mineNew(e.value)) e.key};
  if (mine.isEmpty) return remote;
  return SyncRow(
    table: remote.table,
    id: remote.id,
    values: {...remote.values, for (final f in mine) f: local.values[f]},
    stamps: {...remote.stamps, for (final f in mine) f: local.stamps[f]!},
    deletedAt: null,
  );
}
