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

/// สติกเกอร์ตำแหน่ง / ไฮไลต์ / แก้โน้ตไม่สลับลำดับ
Future<void> stickerPlaceRules(CalendarRepository repo) async {
  final packs = await repo.stickerPacks();
  final st = packs.first.stickers;
  final d = DateTime(2026, 11, 13);
  final a = await repo.stickDay(d, st[0].id);
  final b = await repo.stickDay(d, st[1].id, x: 0.2, y: 0.8);
  final c = await repo.stickDay(d, st[2].id);
  await repo.updateDaySticker(a, note: 'ไอเดียแล่น');
  var list = await repo.daySticker(d, d);
  expect(list.map((x) => x.id), [a, b, c]); // ลำดับเดิม (เดิมแก้โน้ตแล้วไปท้าย)
  expect(list.first.note, 'ไอเดียแล่น');
  expect(list[1].x, closeTo(0.2, 1e-9));
  expect(list[1].y, closeTo(0.8, 1e-9));
  await repo.setHighlight(c);
  await repo.setHighlight(b);
  list = await repo.daySticker(d, d);
  expect(list.where((x) => x.highlight).map((x) => x.id), [b]); // วันละชิ้นเดียว
  await repo.swapDaySticker(a, st[3].id, auto: 'late');
  list = await repo.daySticker(d, d);
  expect(list.first.sticker.id, st[3].id);
  expect(list.first.auto, 'late');
  expect(list.first.note, 'ไอเดียแล่น');
}

void main() {
  test('RAM: สติกเกอร์ตำแหน่ง / ไฮไลต์', () => stickerPlaceRules(MemoryCalendarRepository()));

  test('SQLite: สติกเกอร์ตำแหน่ง / ไฮไลต์', () async {
    sqfliteFfiInit();
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath,
        options: OpenDatabaseOptions(onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON')));
    await createStickerV16(db);
    await createRound7V17(db);
    await stickerPlaceRules(SqliteCalendarRepository(db));
    await db.close();
  });

  testWidgets('สมุดสติกเกอร์: ลากไปวางในช่องวัน → แปะตรงจุดที่วาง', (tester) async {
    tester.view.physicalSize = const Size(1600, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final cal = MemoryCalendarRepository();
    await tester.pumpWidget(NoirManagerApp(studyRepository: MemoryStudyRepository.seeded(), calendarRepository: cal));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ปฏิทิน').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('สัปดาห์').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('เดือน').last);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('sticker-book')), findsOneWidget);

    final now = DateTime.now();
    final sticker = (await cal.stickerPacks()).first.stickers.first;
    final from = tester.getCenter(find.byKey(ValueKey('book-${sticker.id}')));
    final cell = tester.getRect(find.byKey(ValueKey('nb-${now.month}-${now.day}')));
    final to = Offset(cell.left + cell.width * 0.25, cell.top + cell.height * 0.7);
    final g = await tester.startGesture(from);
    await tester.pump(const Duration(milliseconds: 50));
    for (var i = 1; i <= 10; i++) {
      await g.moveTo(Offset.lerp(from, to, i / 10)!);
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(find.byKey(ValueKey('drop-hover-${now.month}-${now.day}')), findsOneWidget); // ช่องใต้เมาส์ขึ้นกรอบ
    await g.up();
    await tester.pumpAndSettle();
    final stuck = await cal.daySticker(now, now);
    expect(stuck, hasLength(1));
    expect(stuck.single.x, closeTo(0.25, 0.05));
    expect(stuck.single.y, closeTo(0.7, 0.05));
    expect(tester.takeException(), isNull);
  });

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
    await tester.scrollUntilVisible(find.byKey(const Key('cat-create')), 300, scrollable: find.byType(Scrollable).first);
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
