import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:noir_manager/app.dart';
import 'package:noir_manager/calendar/memory_calendar_repository.dart';
import 'package:noir_manager/data/memory_study_repository.dart';
import 'package:noir_manager/widgets/device_preview.dart';

/// จำลองจอมือถือ / แท็บเล็ตบนคอม: ทุกอุปกรณ์ × แนวตั้ง / แนวนอน ต้องไม่ล้นจอ
void main() {
  tearDown(() => devicePreview.value = (id: null, landscape: false));

  for (final d in previewDevices) {
    for (final land in [false, true]) {
      testWidgets('จำลอง ${d.name} ${land ? 'แนวนอน' : 'แนวตั้ง'}: ทุกหน้าไม่ล้น', (tester) async {
        tester.view.physicalSize = const Size(1366, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);
        devicePreview.value = (id: d.id, landscape: land);
        await tester.pumpWidget(NoirManagerApp(
          studyRepository: MemoryStudyRepository.seeded(),
          calendarRepository: MemoryCalendarRepository(),
        ));
        await tester.pumpAndSettle();
        // แอปข้างในเห็นขนาดจอของอุปกรณ์ ไม่ใช่ของคอม
        final size = land ? d.size.flipped : d.size;
        expect(MediaQuery.sizeOf(tester.element(find.byType(Scaffold).first)), size);
        expect(Theme.of(tester.element(find.byType(Scaffold).first)).platform,
            d.ios ? TargetPlatform.iOS : TargetPlatform.android);
        for (final p in ['วันนี้', 'ปฏิทิน', 'การเรียน', 'ไฟล์', 'สถิติ']) {
          await tester.tap(find.text(p).last);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: 'หน้า $p บน ${d.name}');
        }
      });
    }
  }

  testWidgets('ตั้งค่า (บนคอม): เลือก iPhone 15 → แนวนอน → จำไว้ → ปิด', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    tester.view.physicalSize = const Size(1280, 4000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final study = MemoryStudyRepository.seeded();
    await tester.pumpWidget(NoirManagerApp(studyRepository: study, calendarRepository: MemoryCalendarRepository()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ตั้งค่า').first);
    await tester.pumpAndSettle();
    expect(find.text('ทดลองหน้าจออุปกรณ์'), findsOneWidget);

    await tester.tap(find.text('iPhone 15'));
    await tester.pumpAndSettle();
    expect(await study.getSetting(devicePreviewKey), 'iphone15');
    expect(find.textContaining('iPhone 15 · 393×852'), findsOneWidget);

    await tester.tap(find.text('แนวนอน'));
    await tester.pumpAndSettle();
    expect(await study.getSetting(devicePreviewKey), 'iphone15:land');

    // เปิดแอปใหม่ → ยังจำลองอยู่
    devicePreview.value = (id: null, landscape: false);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(NoirManagerApp(studyRepository: study, calendarRepository: MemoryCalendarRepository()));
    await tester.pumpAndSettle();
    expect(devicePreview.value.id, 'iphone15');
    expect(devicePreview.value.landscape, isTrue);

    devicePreview.value = (id: null, landscape: false);
    await tester.pumpAndSettle();
    expect(find.textContaining('จำลองขนาดจอ'), findsNothing);
    expect(tester.takeException(), isNull);
    debugDefaultTargetPlatformOverride = null;
  });
}
