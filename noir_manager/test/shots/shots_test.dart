// ภาพตัวอย่างหน้าจอ iPhone 15 (ฟอนต์จริง) — ใช้ใน branch ชั่วคราวเท่านั้น ไม่ merge
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:noir_manager/app.dart';
import 'package:noir_manager/calendar/memory_calendar_repository.dart';
import 'package:noir_manager/data/memory_study_repository.dart';

Future<void> loadFonts() async {
  final thai = FontLoader('IBMPlexSansThai');
  for (final w in ['Regular', 'Medium', 'SemiBold']) {
    thai.addFont(Future.value(ByteData.sublistView(File('assets/fonts/IBMPlexSansThai-$w.ttf').readAsBytesSync())));
  }
  await thai.load();
  final root = Platform.environment['FLUTTER_ROOT']!;
  final icons = FontLoader('MaterialIcons')
    ..addFont(Future.value(ByteData.sublistView(
        File('$root/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf').readAsBytesSync())));
  await icons.load();
}

void main() {
  final tag = Platform.environment['SHOT_TAG'] ?? 'after';
  testWidgets('iPhone 15 shots', (tester) async {
    await tester.runAsync(loadFonts);
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    tester.view.physicalSize = const Size(393 * 2, 852 * 2);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(NoirManagerApp(
      studyRepository: MemoryStudyRepository.seeded(),
      calendarRepository: MemoryCalendarRepository(),
    ));
    await tester.pumpAndSettle();
    Future<void> shot(String name) async {
      await tester.pumpAndSettle();
      await expectLater(find.byType(NoirManagerApp), matchesGoldenFile('out/$tag-$name.png'));
    }

    await shot('1-today');
    await tester.tap(find.text('การเรียน').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('รายวิชา'));
    await tester.pumpAndSettle();
    await tester.drag(find.text('ภาพรวม').last, const Offset(0, -150));
    await shot('2-subject-top');
    await tester.drag(find.text('ภาพรวม').last, const Offset(0, -300));
    await shot('3-subject-tiles');
    debugDefaultTargetPlatformOverride = null;
  });
}
