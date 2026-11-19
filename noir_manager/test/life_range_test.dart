// สถิติ › ชีวิต: ข้อมูลเริ่มทีหลังต้นช่วง → บอกว่า "มีข้อมูลตั้งแต่" (สัปดาห์กับเดือนจะได้ไม่งงว่าทำไมเท่ากัน)
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:noir_manager/app.dart';
import 'package:noir_manager/calendar/calendar_models.dart';
import 'package:noir_manager/calendar/memory_calendar_repository.dart';
import 'package:noir_manager/data/memory_study_repository.dart';
import 'package:noir_manager/utils/thai_date.dart';

void main() {
  test('ชื่อวันย่อ', () {
    expect([for (var i = 0; i < 7; i++) thaiWeekdayShort(DateTime(2026, 11, 16 + i))], ['จ.', 'อ.', 'พ.', 'พฤ.', 'ศ.', 'ส.', 'อา.']);
  });

  testWidgets('งานเพิ่งเริ่มเมื่อวาน → เดือน: "มีข้อมูลตั้งแต่ … นับได้ 2 วัน"', (tester) async {
    tester.view.physicalSize = const Size(1400, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final cal = MemoryCalendarRepository();
    final now = DateTime.now();
    final y = DateTime(now.year, now.month, now.day - 1);
    final cat = (await cal.categories()).first.id;
    await cal.addActivity(NewActivity(name: 'งานเมื่อวาน', categoryId: cat, importance: 2, timed: false, day: y));
    await tester.pumpWidget(NoirManagerApp(studyRepository: MemoryStudyRepository(), calendarRepository: cal));
    await tester.pumpAndSettle();
    await tester.tap(find.text('สถิติ').last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('tab-ชีวิต')));
    await tester.tap(find.byKey(const ValueKey('tab-ชีวิต')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('เดือน'));
    await tester.pumpAndSettle();
    final t = tester.widget<Text>(find.byKey(const Key('life-short-data'))).data!;
    expect(t, contains(thaiShortDate(y)));
    expect(t, endsWith('นับได้ 2 วัน'));
  });
}
