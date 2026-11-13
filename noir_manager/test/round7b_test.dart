import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:noir_manager/app.dart';
import 'package:noir_manager/calendar/achievements.dart';
import 'package:noir_manager/calendar/calendar_models.dart';
import 'package:noir_manager/calendar/calendar_repository.dart';
import 'package:noir_manager/calendar/free_slots.dart';
import 'package:noir_manager/calendar/memory_calendar_repository.dart';
import 'package:noir_manager/calendar/sqlite_calendar_repository.dart';
import 'package:noir_manager/data/app_database.dart';
import 'package:noir_manager/data/memory_study_repository.dart';

/// กฎหมวด + งานยืดหยุ่น · ต้องเหมือนกันทั้ง RAM และ SQLite
Future<void> round7Rules(CalendarRepository repo) async {
  var cats = await repo.categories();
  final study = cats.firstWhere((c) => c.isSystem);
  expect(study.icon, '🎓'); // ไอคอนตั้งต้น

  final id = await repo.addCategory(const ActivityCategory(
    id: 0,
    name: 'อ่านหนังสือ',
    colorKey: 'pink',
    icon: '📖',
    defaultImportance: 3,
    defaultMinutes: 90,
    replaceable: false,
    lockOnStart: true,
    statsGroup: 'study',
  ));
  cats = await repo.categories();
  final read = cats.firstWhere((c) => c.id == id);
  expect(read.icon, '📖');
  expect(read.colorKey, 'pink');
  expect(read.defaultMinutes, 90);
  expect(read.replaceable, isFalse);
  expect(read.lockOnStart, isTrue);
  expect(read.statsGroup, 'study');

  // งานในหมวดนี้ → ลบหมวด = ย้ายงานไปหมวดอื่นก่อน
  final day = DateTime(2026, 11, 16);
  final aid = await repo.addActivity(NewActivity(
    name: 'อ่านบท 2',
    categoryId: id,
    importance: 2,
    timed: true,
    day: day,
    startMinute: 20 * 60,
    durationMin: 60,
  ));
  expect((await repo.categoryUsage())[id], 1);
  final other = cats.firstWhere((c) => c.name == 'อื่น ๆ').id;
  await repo.deleteCategory(id, moveTo: other);
  expect((await repo.categories()).any((c) => c.id == id), isFalse);
  expect((await repo.activity(aid)).categoryId, other);
  // หมวดระบบลบไม่ได้
  await repo.deleteCategory(study.id);
  expect((await repo.categories()).any((c) => c.id == study.id), isTrue);

  // งานยืดหยุ่น: ทำงาน จ–ส 08–17 · วันนี้ว่างทั้งช่วง = ไม่นับว่าต้องทำ
  final work = await repo.addActivity(NewActivity(
    name: 'ทำงาน',
    categoryId: other,
    importance: 3,
    timed: true,
    day: day,
    startMinute: 8 * 60,
    durationMin: 9 * 60,
    repeat: RepeatKind.weekly,
    weekdays: const {1, 2, 3, 4, 5, 6},
    flexible: true,
  ));
  expect((await repo.activity(work)).flexible, isTrue);
  var items = await repo.occurrencesOn(day);
  final w = items.firstWhere((o) => o.activityId == work);
  expect(w.flexible, isTrue);
  expect(dayProgress(items).$2, 2);
  await repo.setFree(w.id, DateTime(2026, 11, 16, 8), DateTime(2026, 11, 16, 17));
  items = await repo.occurrencesOn(day);
  expect(items.firstWhere((o) => o.activityId == work).freeAll, isTrue);
  expect(dayProgress(items).$2, 1); // เหลือแค่อ่านบท 2

  // ว่างบางช่วง → ยังต้องทำ แต่ช่วงนั้นว่าง
  await repo.setFree(w.id, DateTime(2026, 11, 16, 10), DateTime(2026, 11, 16, 15));
  final part = (await repo.occurrencesOn(day)).firstWhere((o) => o.activityId == work);
  expect(part.hasFree, isTrue);
  expect(part.freeAll, isFalse);
  expect(part.required, isTrue);
  await repo.setFree(w.id, null, null);
  expect((await repo.occurrencesOn(day)).firstWhere((o) => o.activityId == work).hasFree, isFalse);
}

void main() {
  test('RAM: หมวดสร้างเอง + งานยืดหยุ่น', () => round7Rules(MemoryCalendarRepository()));

  test('SQLite: migration v17 + กฎเหมือน RAM · รันซ้ำได้', () async {
    sqfliteFfiInit();
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath,
        options: OpenDatabaseOptions(onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON')));
    await createStudySchema(db);
    await createSettingSchema(db);
    await createCalendarSchema(db);
    await createCalendarV5(db);
    await createCalendarV7(db);
    await createStudyPlanV8(db);
    await createTutorV9(db);
    await createTermV10(db);
    await createClassInfoV11(db);
    await createSubjectLinkV12(db);
    await createStickerV16(db);
    await createRound7V17(db);
    await createRound7V17(db); // รันซ้ำได้
    await round7Rules(SqliteCalendarRepository(db));
    await db.close();
  });

  test('หมวด "แทนไม่ได้" → จองติวทับไม่ได้', () {
    expect(const Busy(0, 60, 'วิ่ง', importance: 1).replaceable, isTrue);
    expect(const Busy(0, 60, 'วิ่ง', importance: 1, fixed: true).replaceable, isFalse);
  });

  testWidgets('ตั้งค่า › หมวดงาน: สร้างหมวดใหม่ (ชื่อ · สี · ไอคอน) แล้วขึ้นในรายการ', (tester) async {
    tester.view.physicalSize = const Size(1280, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final cal = MemoryCalendarRepository();
    await tester.pumpWidget(NoirManagerApp(studyRepository: MemoryStudyRepository.seeded(), calendarRepository: cal));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ตั้งค่า').first);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('cat-create')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('cat-create')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('cat-name')), 'อ่านหนังสือ');
    await tester.tap(find.byKey(const Key('cat-color-pink')));
    await tester.tap(find.byKey(const Key('cat-icon-📖')));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'สร้าง'));
    await tester.pumpAndSettle();
    final made = (await cal.categories()).firstWhere((c) => c.name == 'อ่านหนังสือ');
    expect(made.icon, '📖');
    expect(made.colorKey, 'pink');
    expect(find.textContaining('อ่านหนังสือ'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
