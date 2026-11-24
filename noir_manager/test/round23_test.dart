import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:noir_manager/calendar/stickers.dart';
import 'package:noir_manager/data/app_database.dart';
import 'package:noir_manager/sync/duplicate_plan.dart';
import 'package:noir_manager/theme/app_theme.dart';
import 'package:noir_manager/theme/noir_colors.dart';
import 'package:noir_manager/widgets/menu_header.dart';

void main() {
  test('สติกเกอร์ซ้ำ (ชุดในแอป 2 ชุด + ตัวซ้ำในชุด) → รวมเป็นตัวเดียว · สติกเกอร์ที่แปะในวันยังอยู่ · รันซ้ำได้', () async {
    sqfliteFfiInit();
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath,
        options: OpenDatabaseOptions(onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON')));
    await createAllTables(db);
    Future<int> n(String sql) async => ((await db.rawQuery(sql)).first.values.first as num).toInt();
    final total = builtinStickerPacks.fold(0, (a, p) => a + p.$2.length);
    expect(await n('SELECT COUNT(*) FROM sticker'), total);
    // จำลองข้อมูลที่รวมมาจาก 2 เครื่อง: ชุด "อารมณ์" ซ้ำทั้งชุด + "การทำงาน" มีทุกตัว 2 อัน
    final (name, items) = builtinStickerPacks.first;
    final p2 = await db.insert('sticker_pack', {'name': name, 'builtin': 1, 'sort': 0});
    for (final (i, (sn, e)) in items.indexed) {
      await db.insert('sticker', {'pack_id': p2, 'name': sn, 'emoji': e, 'sort': i});
    }
    final work = (await db.query('sticker_pack', where: 'name = ?', whereArgs: [builtinStickerPacks[1].$1])).single['id'];
    final dupIds = <int>[];
    for (final (i, (sn, e)) in builtinStickerPacks[1].$2.indexed) {
      dupIds.add(await db.insert('sticker', {'pack_id': work, 'name': sn, 'emoji': e, 'sort': i}));
    }
    await db.insert('day_sticker', {'day': '2026-11-20', 'sticker_id': dupIds.first});
    expect(await n('SELECT COUNT(*) FROM sticker'), total * 2);

    expect(await dedupeStickers(db), 1 + total);
    expect(await n('SELECT COUNT(*) FROM sticker'), total);
    expect(await n('SELECT COUNT(*) FROM sticker_pack WHERE builtin = 1'), builtinStickerPacks.length);
    final placed = (await db.query('day_sticker')).single;
    final s = (await db.query('sticker', where: 'id = ?', whereArgs: [placed['sticker_id']])).single;
    expect(s['emoji'], builtinStickerPacks[1].$2.first.$2);
    expect(await dedupeStickers(db), 0);
    await db.close();
  });

  testWidgets('แท็บย่อยล้นจอ: กดแท็บท้าย → เลื่อนมาให้เห็น · กดแท็บแรก → เลื่อนกลับ', (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    var value = 0;
    final labels = ['ภาพรวม', 'รายวิชา', 'แผน 4 ปี', 'ตารางเรียน', 'เทอม & วันหยุด', 'ติว', 'คะแนน'];
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.of(themeChoices.first),
      home: Scaffold(
        body: StatefulBuilder(
          builder: (context, set) => MenuTabs<int>(
            value: value,
            items: [for (final (i, l) in labels.indexed) (i, l)],
            onChanged: (v) => set(() => value = v),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    ScrollPosition pos() => tester.state<ScrollableState>(find.byType(Scrollable).first).position;
    expect(pos().pixels, 0);
    // แท็บที่อยู่ชิดขอบขวา (เห็นแค่บางส่วน) → กดส่วนที่เห็น แล้วเลื่อนมากลาง
    final edge = [for (final (i, l) in labels.indexed) (i, l, tester.getRect(find.byKey(ValueKey('tab-$l'))))]
        .firstWhere((e) => e.$3.left < 350 && e.$3.right > 360);
    await tester.tapAt(Offset((edge.$3.left + 355) / 2, edge.$3.center.dy));
    await tester.pumpAndSettle();
    expect(value, edge.$1);
    expect(pos().pixels, greaterThan(0));
    final r = tester.getRect(find.byKey(ValueKey('tab-${edge.$2}')));
    final maxed = pos().pixels >= pos().maxScrollExtent - 0.5;
    if (!maxed) expect((r.center.dx - 180).abs(), lessThan(40)); // อยู่กลางจอ (ถ้ายังเลื่อนต่อได้)
    expect(r.left, greaterThanOrEqualTo(0));
    expect(r.right, lessThanOrEqualTo(360));
    await tester.drag(find.byType(SingleChildScrollView), const Offset(800, 0));
    await tester.pumpAndSettle();
    expect(pos().pixels, 0); // สุดขอบซ้าย เลื่อนต่อไม่ได้แล้ว
    await tester.tap(find.byKey(const ValueKey('tab-ภาพรวม')));
    await tester.pumpAndSettle();
    expect(value, 0);
    expect(pos().pixels, 0);
  });
}
