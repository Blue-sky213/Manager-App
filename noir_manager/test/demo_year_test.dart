import 'package:flutter_test/flutter_test.dart';

import 'package:noir_manager/calendar/achievements.dart';
import 'package:noir_manager/calendar/calendar_models.dart';
import 'package:noir_manager/data/demo_year.dart';

Occurrence o(int id, DateTime d, OccurrenceStatus st, {String title = 'งาน'}) => Occurrence(
      id: id,
      activityId: id,
      title: title,
      categoryId: 1,
      importance: 2,
      repeats: false,
      day: d,
      startAt: null,
      endAt: null,
      status: st,
      reason: null,
      movedFromId: null,
    );

void main() {
  test('ข้อมูลตัวอย่าง 1 ปี: ผ่านตัวตรวจกฎ · seed เดิมได้ผลเดิม · มีข้อมูลทั้งปี', () async {
    final today = DateTime(2026, 11, 12);
    final a = await buildDemoYear(today: today);
    expect(await checkDemoYear(a.calendar, today, a.sessions), isEmpty);
    expect(a.sessions, isNotEmpty);

    // ย้อนหลัง 300 วันยังมีงาน + มีที่ทำแล้ว
    final old = await a.calendar.occurrencesOn(today.subtract(const Duration(days: 300)));
    final all = <Occurrence>[];
    for (var i = 1; i <= 365; i += 7) {
      all.addAll(await a.calendar.occurrencesOn(today.subtract(Duration(days: i))));
    }
    expect(old.isNotEmpty || all.isNotEmpty, isTrue);
    expect(all.any((x) => x.status == OccurrenceStatus.done), isTrue);

    final b = await buildDemoYear(today: today);
    final da = await a.calendar.occurrencesOn(today.subtract(const Duration(days: 100)));
    final db = await b.calendar.occurrencesOn(today.subtract(const Duration(days: 100)));
    expect(da.map((x) => '${x.title}${x.status}'), db.map((x) => '${x.title}${x.status}'));
  });

  test('ตัวตรวจกฎจับผิดได้: ทำแล้วล่วงหน้า', () async {
    final today = DateTime(2026, 11, 12);
    final y = await buildDemoYear(today: today);
    final future = await y.calendar.occurrencesOn(today.add(const Duration(days: 3)));
    if (future.isNotEmpty) {
      await y.calendar.setDone(future.first.id, true);
      expect((await checkDemoYear(y.calendar, today, y.sessions)).join(), contains('ทำแล้วล่วงหน้า'));
    }
  });

  test('เหรียญ 3 ขั้น: เกณฑ์สูง · ขั้นถัดไป', () {
    final today = DateTime(2026, 11, 12);
    final days = {
      for (var i = 0; i < 20; i++)
        DateTime(2026, 11, 12 - i): [o(i, DateTime(2026, 11, 12 - i), OccurrenceStatus.done)],
    };
    final m = medalTracks(days, today);
    final streak = m.firstWhere((t) => t.name == 'Streak');
    expect(streak.level, 1); // 20 วัน ≥ 14 = ทองแดง
    expect(streak.next, (20, 45));
    final whole = m.firstWhere((t) => t.name == 'ครบทั้งวัน');
    expect(whole.level, 0); // 20 < 30
    expect(m.firstWhere((t) => t.name == 'เข้าใจจริง').level, 0);
  });
}
