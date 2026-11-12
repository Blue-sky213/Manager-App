import 'package:flutter_test/flutter_test.dart';

import 'package:noir_manager/calendar/achievements.dart';
import 'package:noir_manager/calendar/calendar_models.dart';

Occurrence occ(int id, DateTime day, OccurrenceStatus st) => Occurrence(
      id: id,
      activityId: id,
      title: 'งาน $id',
      categoryId: 1,
      importance: 2,
      repeats: false,
      day: day,
      startAt: null,
      endAt: null,
      status: st,
      reason: null,
      movedFromId: null,
    );

void main() {
  final today = DateTime(2026, 11, 12);
  DateTime d(int back) => DateTime(2026, 11, 12 - back);

  test('ครบทั้งวัน: ทำแล้ว + ยกเลิกมีเหตุผล = ครบ · ถูกเลื่อนออกไม่นับ', () {
    final items = [
      occ(1, today, OccurrenceStatus.done),
      occ(2, today, OccurrenceStatus.cancelled),
      occ(3, today, OccurrenceStatus.moved),
    ];
    expect(dayProgress(items), (2, 2));
    expect(dayComplete(items), isTrue);
    expect(dayComplete([occ(4, today, OccurrenceStatus.planned)]), isFalse);
    expect(dayComplete([]), isFalse);
  });

  test('สตรีค: วันนี้ยังไม่ครบไม่ตัด · วันว่างไม่ตัด · ดีที่สุดนับต่อเนื่อง', () {
    final s = streakOf({
      d(0): [occ(1, d(0), OccurrenceStatus.planned)], // วันนี้ยังไม่จบ
      d(1): [occ(2, d(1), OccurrenceStatus.done)],
      d(2): [], // วันว่าง
      d(3): [occ(3, d(3), OccurrenceStatus.done)],
      d(4): [occ(4, d(4), OccurrenceStatus.planned)], // ตัดสตรีค
      d(5): [occ(5, d(5), OccurrenceStatus.done)],
      d(6): [occ(6, d(6), OccurrenceStatus.done)],
      d(7): [occ(7, d(7), OccurrenceStatus.done)],
    }, today);
    expect(s.current, 2);
    expect(s.best, 3);
    expect(s.completeDays.length, 5);
  });
}
