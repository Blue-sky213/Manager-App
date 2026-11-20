import 'package:flutter_test/flutter_test.dart';

import 'package:noir_manager/sync/merge.dart';

SyncRow row(Map<String, Object?> v, Map<String, int> t, {int? del}) =>
    SyncRow(table: 'occurrence', id: '7', values: v, stamps: t, deletedAt: del);

void main() {
  const base = 100; // ซิงก์ครั้งก่อน

  test('ค่าเหมือนกัน = ใช้เลย ไม่เตือน (มือถือกับคอมติ๊กทำแล้วทั้งคู่)', () {
    final phone = row({'status': 'done', 'start': 1140}, {'status': 150, 'start': 50});
    final pc = row({'status': 'done', 'start': 1140}, {'status': 170, 'start': 50});
    final r = mergeRow(pc, phone, lastSync: base);
    expect(r.conflicts, isEmpty);
    expect(r.row!.values, {'status': 'done', 'start': 1140});
    expect(conflictToast(r.conflicts), isNull);
  });

  test('แก้คนละช่อง = เก็บทั้งคู่ ไม่เตือน', () {
    final phone = row({'status': 'done', 'start': 1140}, {'status': 150, 'start': 50});
    final pc = row({'status': 'planned', 'start': 1200}, {'status': 50, 'start': 160});
    final r = mergeRow(pc, phone, lastSync: base);
    expect(r.conflicts, isEmpty);
    expect(r.row!.values, {'status': 'done', 'start': 1200});
  });

  test('ช่องเดียวกันคนละค่า = ใช้ค่าที่กดแก้ทีหลัง + เตือน (มือถือออนไลน์ทีหลังก็ไม่ทับ)', () {
    // มือถือแก้ 10:12 (offline) · คอมแก้ 11:05 · มือถือกลับมาออนไลน์ 12:00
    final phone = row({'start': 1140}, {'start': 612});
    final pc = row({'start': 1200}, {'start': 665});
    final r = mergeRow(pc, phone, lastSync: base);
    expect(r.row!.values['start'], 1200);
    expect(r.conflicts.single.field, 'start');
    expect(r.conflicts.single.keptLocal, isTrue);
    expect(conflictToast(r.conflicts), '⚠ 1 รายการแก้ต่างกันบน 2 เครื่อง · ใช้ค่าล่าสุดแล้ว');
    // ผลเหมือนกันไม่ว่าเครื่องไหนเป็นฝั่ง local
    expect(mergeRow(phone, pc, lastSync: base).row!.values['start'], 1200);
    // กดใช้อีกค่า → ค่ามือถือ + เวลาใหม่ (ชนะรอบถัดไป)
    final back = useOther(r.row!, r.conflicts.single, now: 700);
    expect(back.values['start'], 1140);
    expect(back.stamps['start'], 700);
  });

  test('ฝั่งเดียวแก้ (อีกฝั่งค่าเก่า) = ไม่ใช่ค่าต่าง ไม่เตือน', () {
    final phone = row({'note': 'เก่า'}, {'note': 40});
    final pc = row({'note': 'ใหม่'}, {'note': 160});
    final r = mergeRow(phone, pc, lastSync: base);
    expect(r.row!.values['note'], 'ใหม่');
    expect(r.conflicts, isEmpty);
  });

  test('ลบ vs แก้ = ล่าสุดชนะ + เตือน · มีฝั่งเดียว = ใช้ฝั่งนั้น', () {
    final pc = row({'title': 'ไลฟ์'}, {'title': 50}, del: 180);
    final phone = row({'title': 'ไลฟ์ RE4'}, {'title': 150});
    final r = mergeRow(pc, phone, lastSync: base);
    expect(r.row!.deleted, isTrue);
    expect(r.conflicts.single.field, isNull);
    final undo = useOther(r.row!, r.conflicts.single, now: 200);
    expect(undo.deleted, isFalse);

    final all = mergeAll({'a': pc}, {'b': phone}, lastSync: base);
    expect(all.rows.keys, {'a', 'b'});
    expect(all.conflicts, isEmpty);
  });
}
