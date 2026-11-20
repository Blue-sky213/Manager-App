/// ที่เก็บกลางของบัญชี (รอบ 16): Supabase จริง หรือ ตัวในหน่วยความจำ (เทส)
library;

import 'merge.dart';

/// แถวที่ดึงมา + เลขลำดับบนเซิร์ฟเวอร์
class RemoteRow {
  const RemoteRow(this.row, this.rev);
  final SyncRow row;
  final int rev;
}

abstract class SyncRemote {
  /// แถวที่เปลี่ยนหลังเลขลำดับ [afterRev] (เรียงเก่า → ใหม่ · ครบทุกหน้า)
  Future<List<RemoteRow>> pull(int afterRev);

  /// ส่งแถวขึ้น (ทับแถวเดิมรหัสเดียวกัน)
  Future<void> push(List<SyncRow> rows);
}

/// ที่เก็บกลางในหน่วยความจำ · ใช้เทส 2 เครื่องโดยไม่ต่อเน็ต
class MemorySyncRemote implements SyncRemote {
  final _rows = <String, RemoteRow>{};
  var _rev = 0;

  /// ปิดเน็ต (จำลอง offline)
  bool offline = false;

  int get length => _rows.length;
  Iterable<SyncRow> get rows => _rows.values.map((r) => r.row);

  @override
  Future<List<RemoteRow>> pull(int afterRev) async {
    if (offline) throw StateError('offline');
    return _rows.values.where((r) => r.rev > afterRev).toList()..sort((a, b) => a.rev.compareTo(b.rev));
  }

  @override
  Future<void> push(List<SyncRow> rows) async {
    if (offline) throw StateError('offline');
    for (final r in rows) {
      _rows['${r.table}\t${r.id}'] = RemoteRow(r, ++_rev);
    }
  }
}
