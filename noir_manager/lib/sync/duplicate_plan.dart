/// หางานซ้ำ (รอบ 20 · นัวร์ย้ายเครื่องแล้วเห็นงานเดียวกัน 2 อันทุกวัน)
/// สาเหตุ: เครื่องเก่ามีแผนอยู่แล้ว + เครื่องใหม่สร้างแผนชุดเดียวกันอีกรอบ (คนละวัน) ก่อนเข้าบัญชี
/// → ตอนรวมข้อมูล ทั้งสองชุดไม่เหมือนกันทุกช่อง เลยกลายเป็น 2 งาน
/// กติกา: ชื่อ + การทำซ้ำ + เวลา เหมือนกัน = ซ้ำ · เก็บตัวที่มีประวัติมากสุด · ลบเฉพาะตัวที่ยังไม่มีประวัติเลย (ไม่เสียข้อมูล)
library;

import 'package:sqflite/sqflite.dart';

class DuplicateActivity {
  const DuplicateActivity({required this.name, required this.keepId, required this.removeIds, required this.keepWithHistory});

  final String name;
  final int keepId;

  /// ลบได้ปลอดภัย (ไม่มีครั้งไหนติ๊ก / เลื่อน / ยกเลิก / บันทึก)
  final List<int> removeIds;

  /// ตัวซ้ำที่มีประวัติด้วย → ไม่ลบให้ (นัวร์ดูเอง)
  final List<int> keepWithHistory;
}

Future<List<DuplicateActivity>> findDuplicateActivities(DatabaseExecutor db) async {
  final rows = await db.rawQuery('''
    SELECT a.id, a.name, a.repeat, a.weekdays, a.timed, a.start_minute, a.duration_min, a.kind, a.start_date,
           (SELECT COUNT(*) FROM occurrence o WHERE o.activity_id = a.id AND o.status != 'planned') AS history
    FROM activity a
    WHERE a.repeat != 'none'
    ORDER BY a.start_date, a.id''');
  final groups = <String, List<Map<String, Object?>>>{};
  for (final r in rows) {
    final key = [r['name'], r['repeat'], r['weekdays'], r['timed'], r['start_minute'], r['duration_min'], r['kind']].join('|');
    (groups[key] ??= []).add(r);
  }
  final out = <DuplicateActivity>[];
  for (final g in groups.values.where((g) => g.length > 1)) {
    // ประวัติมากสุดก่อน · เท่ากัน = เริ่มก่อน (เรียงมาแล้ว)
    final sorted = [...g]..sort((a, b) => (b['history'] as int).compareTo(a['history'] as int));
    final keep = sorted.first;
    final rest = sorted.skip(1);
    out.add(DuplicateActivity(
      name: keep['name'] as String,
      keepId: keep['id'] as int,
      removeIds: [for (final r in rest) if (r['history'] == 0) r['id'] as int],
      keepWithHistory: [for (final r in rest) if (r['history'] != 0) r['id'] as int],
    ));
  }
  return out;
}
