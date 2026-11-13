import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:noir_manager/app.dart';
import 'package:noir_manager/calendar/calendar_models.dart';
import 'package:noir_manager/calendar/memory_calendar_repository.dart';
import 'package:noir_manager/calendar/stickers.dart';
import 'package:noir_manager/data/memory_study_repository.dart';

/// เปิดปฏิทินเดือน (จอกว้าง = มีสมุดสติกเกอร์)
Future<MemoryCalendarRepository> openMonth(WidgetTester tester) async {
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
  return cal;
}

Future<TestGesture> dragTo(WidgetTester tester, Offset from, Offset to) async {
  final g = await tester.startGesture(from);
  await tester.pump(const Duration(milliseconds: 50));
  for (var i = 1; i <= 10; i++) {
    await g.moveTo(Offset.lerp(from, to, i / 10)!);
    await tester.pump(const Duration(milliseconds: 16));
  }
  return g;
}

void main() {
  testWidgets('ลากสติกเกอร์: เห็นเงาตำแหน่งที่จะติด ทั้งช่องปกติและช่องซูม', (tester) async {
    final cal = await openMonth(tester);
    final now = DateTime.now();
    final st = (await cal.stickerPacks()).first.stickers;
    await cal.stickDay(now, st[0].id); // มี ⭐ แล้ว → ชิ้นต่อไปติดตามจุดที่ปล่อย
    await tester.pumpAndSettle();

    final ghost = find.byKey(ValueKey('ghost-${now.month}-${now.day}'));
    final cell = tester.getRect(find.byKey(ValueKey('nb-${now.month}-${now.day}')));
    final g = await dragTo(tester, tester.getCenter(find.byKey(ValueKey('book-${st[1].id}'))),
        Offset(cell.left + cell.width * 0.3, cell.top + cell.height * 0.7));
    expect(ghost, findsOneWidget); // ช่องปกติ

    // ค้างไว้ → ช่องซูม · ขยับในช่องซูม = เงาตามเมาส์
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.byKey(ValueKey('zoom-${now.month}-${now.day}')), findsOneWidget);
    await g.moveBy(const Offset(6, -4));
    await tester.pump();
    final z = tester.getRect(find.byKey(ValueKey('zoom-${now.month}-${now.day}')));
    final gh = tester.getCenter(ghost.last);
    expect(z.contains(gh), isTrue);
    expect(find.textContaining('ปล่อยตรงไหน ติดตรงนั้น'), findsOneWidget);
    await g.up();
    await tester.pumpAndSettle();
    expect(ghost, findsNothing);
    expect(await cal.daySticker(now, now), hasLength(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('ครบ 4 ชิ้น → ปล่อยแล้วถามแทนชิ้นไหน · จำนวนยังเท่าเดิม', (tester) async {
    final cal = await openMonth(tester);
    final now = DateTime.now();
    final st = (await cal.stickerPacks()).first.stickers;
    for (var i = 0; i < maxDayStickers; i++) {
      await cal.stickDay(now, st[i].id);
    }
    await tester.pumpAndSettle();
    final have = await cal.daySticker(now, now);

    final cell = tester.getRect(find.byKey(ValueKey('nb-${now.month}-${now.day}')));
    final g = await dragTo(tester, tester.getCenter(find.byKey(ValueKey('book-${st[5].id}'))),
        Offset(cell.left + cell.width * 0.2, cell.top + cell.height * 0.8));
    await g.up();
    await tester.pumpAndSettle();
    expect(find.textContaining('แปะครบ $maxDayStickers ชิ้นแล้ว'), findsOneWidget);
    await tester.tap(find.byKey(Key('choice-${have[2].id}')));
    await tester.pumpAndSettle();

    final after = await cal.daySticker(now, now);
    expect(after, hasLength(maxDayStickers));
    final swapped = after.firstWhere((d) => d.id == have[2].id);
    expect(swapped.sticker.id, st[5].id);
    expect(swapped.x, closeTo(0.2, 0.05)); // ย้ายไปจุดที่ปล่อย
    expect(tester.takeException(), isNull);
  });

  test('เพดานสติกเกอร์ = 4 (⭐ 1 + เล็ก 3 เห็นครบในช่อง)', () {
    expect(maxDayStickers, 4);
    expect(dayOnly(DateTime(2026, 11, 13, 9)), DateTime(2026, 11, 13));
  });
}
