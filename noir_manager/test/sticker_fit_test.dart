import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:noir_manager/calendar/calendar_repository.dart';
import 'package:noir_manager/calendar/memory_calendar_repository.dart';
import 'package:noir_manager/calendar/sqlite_calendar_repository.dart';
import 'package:noir_manager/calendar/sticker_fit.dart';
import 'package:noir_manager/calendar/sticker_images.dart';
import 'package:noir_manager/data/app_database.dart';
import 'package:noir_manager/theme/app_theme.dart';

/// ภาพ 100×100 ใสทั้งภาพ ยกเว้นสี่เหลี่ยมทึบ [l, t] ขนาด [w]×[h]
Uint8List blockImage(int l, int t, int w, int h) {
  final px = Uint8List(100 * 100 * 4);
  for (var y = t; y < t + h; y++) {
    for (var x = l; x < l + w; x++) {
      px[(y * 100 + x) * 4 + 3] = 255;
    }
  }
  return px;
}

/// ปรับให้พอดีแล้วจำค่า · ที่แปะไว้แล้วเห็นค่าใหม่ด้วย
Future<void> fitRules(CalendarRepository repo) async {
  final st = (await repo.stickerPacks()).first.stickers.first;
  expect(st.fitted, isFalse); // ค่าเริ่มต้น = หน้าตาเดิม
  final day = DateTime(2026, 11, 14);
  await repo.stickDay(day, st.id);
  await repo.updateStickerFit(st.id, scale: 1.6, dx: -0.1, dy: 0.2);
  final again = (await repo.stickerPacks()).first.stickers.first;
  expect((again.scale, again.dx, again.dy), (1.6, -0.1, 0.2));
  final placed = (await repo.daySticker(day, day)).single.sticker;
  expect((placed.scale, placed.dx, placed.dy), (1.6, -0.1, 0.2));
}

void main() {
  test('พอดีอัตโนมัติ: ขยายส่วนที่ไม่ใสให้เต็ม 80% แล้วจัดกลาง', () {
    // ทึบ 40×40 ที่ (40, 20) → กว้าง 0.4 ของกรอบ → ซูม 2 · ศูนย์กลาง (60, 40) → เลื่อนซ้าย 0.2 ลง 0.2
    expect(fitFromAlpha(blockImage(40, 20, 40, 40), 100, 100), (2.0, -0.2, 0.2));
    // เต็มภาพแล้ว → ย่อเหลือ 80%
    expect(fitFromAlpha(blockImage(0, 0, 100, 100), 100, 100), (0.8, 0.0, 0.0));
    // ชิ้นเล็กมาก → ซูมสูงสุด 2.5 · เลื่อนไม่เกิน 0.5
    final tiny = fitFromAlpha(blockImage(0, 0, 4, 4), 100, 100)!;
    expect(tiny.$1, 2.5);
    expect(tiny.$2, 0.5);
    // ใสทั้งภาพ = ไม่ปรับ
    expect(fitFromAlpha(Uint8List(100 * 100 * 4), 100, 100), isNull);
  });

  test('RAM: จำค่าพอดี + ที่แปะไว้เห็นด้วย', () => fitRules(MemoryCalendarRepository()));

  test('SQLite v18: จำค่าพอดี · migration รันซ้ำได้', () async {
    sqfliteFfiInit();
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath,
        options: OpenDatabaseOptions(onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON')));
    await createStickerV16(db);
    await createRound7V17(db);
    await createStickerFitV18(db);
    await createStickerFitV18(db);
    await fitRules(SqliteCalendarRepository(db));
    await db.close();
  });

  testWidgets('ตัวปรับ: ลากเลื่อน · ซูม · คืนค่าเดิม · บันทึก', (tester) async {
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final repo = MemoryCalendarRepository();
    final st = (await repo.stickerPacks()).first.stickers.first;
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.dark(),
      home: Scaffold(body: Builder(builder: (ctx) => TextButton(
            onPressed: () => showStickerFitEditor(ctx, repo, st),
            child: const Text('เปิด'),
          ))),
    ));
    await tester.tap(find.text('เปิด'));
    await tester.pumpAndSettle();
    await tester.drag(find.byKey(const Key('fit-stage')), const Offset(66, -88));
    await tester.pump();
    await tester.drag(find.byKey(const Key('fit-zoom')), const Offset(60, 0));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'บันทึก'));
    await tester.pumpAndSettle();
    var s = (await repo.stickerPacks()).first.stickers.first;
    expect(s.dx, greaterThan(0.05));
    expect(s.dy, lessThan(-0.1));
    expect(s.scale, greaterThan(1));

    // คืนค่าเดิม
    await tester.tap(find.text('เปิด'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('fit-reset')));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'บันทึก'));
    await tester.pumpAndSettle();
    s = (await repo.stickerPacks()).first.stickers.first;
    expect(s.fitted, isFalse);
    expect(tester.takeException(), isNull);
  });
}
