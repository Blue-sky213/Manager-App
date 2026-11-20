import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:noir_manager/app.dart';
import 'package:noir_manager/calendar/calendar_models.dart';
import 'package:noir_manager/calendar/memory_calendar_repository.dart';
import 'package:noir_manager/calendar/tray.dart';
import 'package:noir_manager/data/memory_study_repository.dart';
import 'package:noir_manager/work/project_models.dart';

Occurrence _occ(int id, String title, DateTime start, int min, {OccurrenceStatus status = OccurrenceStatus.planned}) =>
    Occurrence(
      id: id,
      activityId: id,
      title: title,
      categoryId: 4,
      importance: 2,
      repeats: false,
      day: DateTime(start.year, start.month, start.day),
      startAt: start,
      endAt: start.add(Duration(minutes: min)),
      status: status,
      reason: null,
      movedFromId: null,
    );

void main() {
  final now = DateTime(2026, 11, 20, 12);

  test('ถาด: โปรเจกต์พร้อมเริ่ม/กำลังทำ + ปักหมุด · เวลาจากครั้งล่าสุดที่ผ่านมาแล้ว · ชื่อซ้ำโชว์ครั้งเดียว', () {
    final history = {
      DateTime(2026, 11, 13): [_occ(1, 'ไลฟ์ RE4', DateTime(2026, 11, 13, 20), 120)],
      DateTime(2026, 11, 17): [
        _occ(2, 'ไลฟ์ re4 ', DateTime(2026, 11, 17, 21), 90),
        _occ(3, 'ไลฟ์ RE4', DateTime(2026, 11, 17, 8), 30, status: OccurrenceStatus.cancelled),
      ],
      // ลงล่วงหน้าไว้ → ไม่ใช่ "เวลาเดิมจริง"
      DateTime(2026, 11, 25): [_occ(4, 'ไลฟ์ RE4', DateTime(2026, 11, 25, 9), 60)],
    };
    final tray = buildTray(
      projects: const [
        Project(id: 1, name: 'ไลฟ์ RE4', type: 'stream', status: ProjectStatus.doing),
        Project(id: 2, name: 'เว็บลูกค้า', type: 'web', status: ProjectStatus.confirmed),
        Project(id: 3, name: 'ไอเดียเกมใหม่', status: ProjectStatus.quote),
        Project(id: 4, name: 'งานเก่า', status: ProjectStatus.paid),
      ],
      inbox: const [],
      pins: const ['อ่านหนังสือ', 'ไลฟ์ RE4'],
      history: history,
      now: now,
    );
    expect(tray.map((t) => t.title), ['ไลฟ์ RE4', 'เว็บลูกค้า', 'อ่านหนังสือ']);
    final re4 = tray.first;
    expect(re4.emoji, '🎮');
    expect(re4.startMinute, 21 * 60);
    expect(re4.durationMin, 90);
    expect(re4.sessions, 3); // ไม่นับที่ยกเลิก
    expect(re4.categoryId, 4);
    expect(tray[1].startMinute, isNull);
    expect(tray[2].source, TraySource.pin);
    expect(decodePins('["a","b"]'), ['a', 'b']);
    expect(decodePins('พัง'), isEmpty);
  });

  test('ถาด: เวลาชน = เตือนเฉพาะวันที่ทับจริง', () {
    final d1 = DateTime(2026, 11, 23), d2 = DateTime(2026, 11, 24);
    final byDay = {
      d1: [_occ(1, 'เรียน', DateTime(2026, 11, 23, 19, 30), 60)],
      d2: [_occ(2, 'กินข้าว', DateTime(2026, 11, 24, 18), 60)],
    };
    final c = trayClashes(byDay, [d1, d2], 19 * 60, 120);
    expect(c.keys, [d1]);
    expect(c[d1], ['เรียน']);
  });

  test('ถาด: ลงหลายวัน = งานชุดเดียว (เลือกวันเอง) · เลิกทำ = ลบชุดนั้น · งานรอวันใหม่ย้ายลงวันแรก', () async {
    final cal = MemoryCalendarRepository();
    final a = DateTime(2026, 11, 23), b = DateTime(2026, 11, 25);
    const item = TrayItem(title: 'ไลฟ์ RE4', emoji: '🎮', source: TraySource.project);
    final undo = await placeTrayItem(cal, item, {b, a}, 20 * 60, 120);
    for (final d in [a, b]) {
      final list = await cal.occurrencesOn(d);
      expect(list.single.title, 'ไลฟ์ RE4');
      expect(list.single.startAt, d.add(const Duration(hours: 20)));
      expect(list.single.endAt, d.add(const Duration(hours: 22)));
    }
    await undo();
    expect(await cal.occurrencesOn(a), isEmpty);
    expect(await cal.occurrencesOn(b), isEmpty);

    // งานรอวันใหม่
    final c = DateTime(2026, 11, 20);
    await cal.addActivity(NewActivity(
      name: 'ตัดคลิป',
      categoryId: null,
      importance: 2,
      timed: true,
      day: c,
      startMinute: 10 * 60,
      durationMin: 60,
    ));
    await cal.sendToInbox((await cal.occurrencesOn(c)).single.id);
    final inbox = await cal.inbox();
    final tray = buildTray(projects: const [], inbox: inbox, pins: const [], history: const {}, now: now);
    expect(tray.single.source, TraySource.inbox);
    expect(tray.single.startMinute, 10 * 60);
    await placeTrayItem(cal, tray.single, {b}, 10 * 60, 60);
    expect((await cal.occurrencesOn(b)).single.title, 'ตัดคลิป');
    expect(await cal.inbox(), isEmpty);
  });

  testWidgets('ปฏิทิน › สัปดาห์ (จอกว้าง): ถาดด้านขวา · แตะการ์ด → ติ๊กเพิ่มอีกวัน → ยืนยัน → ลงทั้ง 2 วัน', (tester) async {
    tester.view.physicalSize = const Size(1400, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final cal = MemoryCalendarRepository();
    await cal.workRepo.saveProject(const Project(name: 'ไลฟ์ RE4', type: 'stream', status: ProjectStatus.doing));
    await tester.pumpWidget(NoirManagerApp(studyRepository: MemoryStudyRepository.seeded(), calendarRepository: cal));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ปฏิทิน').first);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('tray-panel')), findsOneWidget);
    expect(find.text('ไลฟ์ RE4'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('tray-project:ไลฟ์ RE4')));
    await tester.pumpAndSettle();
    expect(find.text('ยืนยัน 1 วัน'), findsOneWidget);
    final today = DateTime.now();
    final tomorrow = DateTime(today.year, today.month, today.day + 1);
    await tester.tap(find.byKey(ValueKey('tray-day-${tomorrow.month}-${tomorrow.day}')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ยืนยัน 2 วัน'));
    await tester.pumpAndSettle();
    expect(find.text('✓ ลง ไลฟ์ RE4 2 วัน'), findsOneWidget);
    for (final d in [DateTime(today.year, today.month, today.day), tomorrow]) {
      final list = await cal.occurrencesOn(d);
      expect(list.where((o) => o.title == 'ไลฟ์ RE4').single.startAt, d.add(const Duration(minutes: trayDefaultStart)));
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('ปฏิทิน › มือถือ: แถบถาด + ปักหมุดของใหม่', (tester) async {
    tester.view.physicalSize = const Size(393, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final cal = MemoryCalendarRepository();
    await tester.pumpWidget(NoirManagerApp(studyRepository: MemoryStudyRepository.seeded(), calendarRepository: cal));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ปฏิทิน').first);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('tray-strip')), findsOneWidget);
    await tester.tap(find.byKey(const Key('tray-add-pin')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('tray-pin-name')), 'อ่านหนังสือ');
    await tester.tap(find.text('ปักหมุด').last);
    await tester.pumpAndSettle();
    expect(find.text('📌 อ่านหนังสือ'), findsOneWidget);
    expect(decodePins(await cal.getSetting(trayPinsKey)), ['อ่านหนังสือ']);
    expect(tester.takeException(), isNull);
  });
}
