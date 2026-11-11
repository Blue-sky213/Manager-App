import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:noir_manager/app.dart';
import 'package:noir_manager/calendar/calendar_repository.dart';
import 'package:noir_manager/calendar/memory_calendar_repository.dart';
import 'package:noir_manager/calendar/sticker_images.dart';
import 'package:noir_manager/calendar/sqlite_calendar_repository.dart';
import 'package:noir_manager/data/app_database.dart';
import 'package:noir_manager/data/memory_study_repository.dart';

/// กฎเดียวกันทั้ง RAM และ SQLite
Future<void> stickerRules(CalendarRepository repo) async {
  var packs = await repo.stickerPacks();
  expect(packs.map((p) => p.name), ['อารมณ์', 'การทำงาน']);
  expect(packs.first.builtin, isTrue);
  final happy = packs.first.stickers.firstWhere((s) => s.name == 'แฮปปี้');
  expect(happy.glyph, '😊');

  // แปะ 2 ชิ้นในวันเดียว · ดูช่วงวัน
  final d1 = DateTime(2026, 11, 11);
  await repo.stickDay(d1, happy.id, note: 'ส่งงานทัน');
  final tired = packs.first.stickers.firstWhere((s) => s.name == 'เหนื่อยมาก');
  final t = await repo.stickDay(d1, tired.id);
  await repo.stickDay(DateTime(2026, 11, 20), happy.id);
  var stuck = await repo.daySticker(d1, d1);
  expect(stuck.map((d) => d.sticker.name), ['แฮปปี้', 'เหนื่อยมาก']);
  expect(stuck.first.note, 'ส่งงานทัน');
  expect(await repo.daySticker(DateTime(2026, 11, 1), DateTime(2026, 11, 30)), hasLength(3));
  await repo.unstickDay(t);
  expect(await repo.daySticker(d1, d1), hasLength(1));

  // ชุดของฉัน + ทีละชิ้น · ชุดในแอปลบไม่ได้แต่ซ่อนได้
  final mine = await repo.addStickerPack('แมว');
  final cat = await repo.addSticker(mine, 'อยากนอน', emoji: '🐱');
  await repo.stickDay(d1, cat);
  await repo.deleteStickerPack(packs.first.id); // ชุดในแอป → ไม่ถูกลบ
  await repo.setStickerPackEnabled(packs.last.id, false);
  packs = await repo.stickerPacks();
  expect(packs.map((p) => p.name), ['อารมณ์', 'การทำงาน', 'แมว']);
  expect(packs[1].enabled, isFalse);
  expect(packs.last.stickers.single.glyph, '🐱');

  // ลบชุดของฉัน → สติกเกอร์ + ที่แปะไว้หายตาม
  await repo.deleteStickerPack(mine);
  stuck = await repo.daySticker(d1, d1);
  expect(stuck.map((d) => d.sticker.name), ['แฮปปี้']);
  expect((await repo.stickerPacks()), hasLength(2));
}

void main() {
  test('RAM: สติกเกอร์ชุด / ชิ้น / แปะ', () => stickerRules(MemoryCalendarRepository()));

  test('SQLite: migration v16 ใส่ชุดในแอปครั้งเดียว · รันซ้ำได้ · กฎเหมือน RAM', () async {
    sqfliteFfiInit();
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath,
        options: OpenDatabaseOptions(onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON')));
    await createStickerV16(db);
    await createStickerV16(db); // ไม่ใส่ชุดซ้ำ
    await stickerRules(SqliteCalendarRepository(db));
    await db.close();
  });

  testWidgets('หน้าวันนี้: แปะสติกเกอร์ → เห็นในการ์ด · คลิกขวา → ลอกออก', (tester) async {
    tester.view.physicalSize = const Size(1280, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(NoirManagerApp(
      studyRepository: MemoryStudyRepository.seeded(),
      calendarRepository: MemoryCalendarRepository(),
    ));
    await tester.pumpAndSettle();
    expect(find.text('วันนี้รู้สึกยังไง?'), findsOneWidget);
    await tester.tap(find.text('แปะ'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ภูมิใจ'));
    await tester.pumpAndSettle();
    expect(find.text('🥳'), findsOneWidget);
    await tester.longPress(find.text('🥳'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ลอกออก'));
    await tester.pumpAndSettle();
    expect(find.text('🥳'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  test('ชื่อสติกเกอร์จากชื่อไฟล์', () {
    expect(stickerNameFromFile(r'C:\รูป\แมว_อยาก-นอน.png'.replaceAll('\\', '/')), 'แมว อยาก นอน');
    expect(stickerNameFromFile('/a/very_long_file_name_for_a_sticker_image.png').length, 20);
  });

  testWidgets('รูปสติกเกอร์: ย่อด้านยาวเหลือ 256px · เก็บเป็น PNG ในโฟลเดอร์ของแอป', (tester) async {
    await tester.runAsync(() async {
      final dir = await Directory.systemTemp.createTemp('noir_st_');
      // สร้างรูป 600×300 จริง ๆ แล้วเซฟเป็นไฟล์ต้นฉบับ
      final rec = ui.PictureRecorder();
      Canvas(rec).drawRect(const Rect.fromLTWH(0, 0, 600, 300), Paint()..color = const Color(0xFFE91E63));
      final img = await rec.endRecording().toImage(600, 300);
      final src = File('${dir.path}/รูปใหญ่.png')
        ..writeAsBytesSync((await img.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List());
      final saved = await saveStickerImage(src.path, dir);
      final codec = await ui.instantiateImageCodec(await File(saved).readAsBytes());
      final f = await codec.getNextFrame();
      expect(f.image.width, 256);
      expect(f.image.height, 128);
      expect(saved.endsWith('.png'), isTrue);
      await dir.delete(recursive: true);
    });
  });
}
