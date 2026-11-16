// ชั่วคราว: หาว่าแถวไหนล้นจอ (ลบหลังแก้)
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:noir_manager/app.dart';
import 'package:noir_manager/calendar/memory_calendar_repository.dart';
import 'package:noir_manager/data/memory_study_repository.dart';
import 'package:noir_manager/widgets/device_preview.dart';

void main() {
  tearDown(() => devicePreview.value = (id: null, landscape: false));
  for (final d in previewDevices.where((d) => d.name.contains('iPhone 15') || d.name.contains('iPad mini'))) {
    testWidgets('DIAG ${d.name}', (tester) async {
      tester.view.physicalSize = const Size(1366, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      devicePreview.value = (id: d.id, landscape: false);
      await tester.pumpWidget(NoirManagerApp(studyRepository: MemoryStudyRepository.seeded(), calendarRepository: MemoryCalendarRepository()));
      await tester.pumpAndSettle();
      final old = FlutterError.onError;
      FlutterError.onError = (e) => debugPrint('DIAG ${d.name}: ${e.toString().split('\n').take(30).join('\nDIAG ')}');
      for (final p in ['การเรียน', 'เงิน']) {
        if (find.text(p).evaluate().isEmpty) {
          await tester.tap(find.byKey(const Key('nav-more')));
          await tester.pumpAndSettle();
        }
        await tester.tap(find.text(p).last);
        await tester.pumpAndSettle();
      }
      FlutterError.onError = old;
    });
  }
}
