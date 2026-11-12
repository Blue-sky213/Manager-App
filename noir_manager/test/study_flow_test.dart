import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:noir_manager/app.dart';
import 'package:noir_manager/calendar/calendar_models.dart';
import 'package:noir_manager/calendar/memory_calendar_repository.dart';
import 'package:noir_manager/data/memory_study_repository.dart';
import 'package:noir_manager/study/class_log.dart';
import 'package:noir_manager/study/tutor_plan.dart';

Occurrence cls(int id, ActivityKind kind) => Occurrence(
      id: id,
      activityId: id,
      title: 'x',
      categoryId: 1,
      importance: 2,
      repeats: true,
      day: DateTime(2026, 11, 9),
      startAt: null,
      endAt: null,
      status: OccurrenceStatus.done,
      reason: null,
      movedFromId: null,
      kind: kind,
    );

void main() {
  group('กฎติว', () {
    final week3 = [cls(1, ActivityKind.classSession), cls(2, ActivityKind.classSession), cls(3, ActivityKind.classSession)];

    test('EZ: เรียนครบเป้า = ไม่บังคับติว · Advanced: อย่างน้อย 1 รอบ', () {
      expect(weekQuota(3, week3).tutorNeeded, 0);
      expect(weekQuota(3, week3, advanced: true).tutorNeeded, 1);
      expect(weekQuota(3, [cls(1, ActivityKind.classSession)], advanced: true).tutorNeeded, 2);
      expect(weekQuota(3, const [], advanced: true).tutorNeeded, 3); // ไม่มีคาบ = ตามเป้าเดิม
    });

    test('ผ่านเกณฑ์ → ไม่บังคับ (พักได้)', () {
      final q = weekQuota(3, week3, advanced: true, passed: true);
      expect(q.ruleNeeded, 1);
      expect(q.tutorNeeded, 0);
      expect(q.remaining, 0);
    });

    test('ขอบเขต = บทที่เรียนถึง · ผ่าน 80% ต้องประเมินครบทุกหัวข้อ · อ่อนสุดก่อน', () async {
      final repo = MemoryStudyRepository();
      final sid = await repo.addSubject('โปรแกรม');
      final ch1 = await repo.addChapter(sid, 'บท 1');
      final ch2 = await repo.addChapter(sid, 'บท 2');
      await repo.addChapter(sid, 'บท 3');
      final a = await repo.addSubtopic(ch1, 'ตัวแปร');
      final b = await repo.addSubtopic(ch2, 'ลูป');
      await saveClassLog(repo, sid, DateTime(2026, 11, 9), ClassLogInput(chapterId: ch2), occurrenceId: 1);

      var chapters = await repo.chapters(sid);
      final logs = await repo.classLogs(sid);
      expect(reachedIndex(chapters, logs), 1);
      expect(tutorScope(chapters, logs).length, 2);
      expect(scopePassed(tutorScope(chapters, logs), 80), isFalse); // ยังไม่ประเมิน

      await repo.addAssessment(a, 90);
      await repo.addAssessment(b, 70);
      chapters = await repo.chapters(sid);
      final scope = tutorScope(chapters, logs);
      expect(scopeAverage(scope), 80);
      expect(scopePassed(scope, 80), isTrue);
      expect(scopePassed(scope, 90), isFalse);
      expect(weakestFirst(scope).first.name, 'ลูป');
    });
  });

  testWidgets('มือถือ: กดทำแล้วที่คาบเรียน → แผ่นเดียว (แค่ทำแล้ว / บันทึก) · ปฏิทินสัปดาห์มีแถบ 7 วัน', (tester) async {
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final study = MemoryStudyRepository.seeded();
    final cal = MemoryCalendarRepository();
    final sid = (await study.subjects()).first.id;
    final now = DateTime.now();
    await cal.addActivity(NewActivity(
      name: 'เรียน · ทดสอบ',
      categoryId: null,
      importance: 2,
      timed: true,
      day: DateTime(now.year, now.month, now.day),
      startMinute: 23 * 60,
      durationMin: 30,
      subjectId: sid,
      kind: ActivityKind.classSession,
    ));
    await cal.setSetting('lock_started', 'off');
    await tester.pumpWidget(NoirManagerApp(studyRepository: study, calendarRepository: cal));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('เรียน · ทดสอบ'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('เรียน · ทดสอบ'));
    await tester.pumpAndSettle();
    expect(find.text('บันทึกเรียนถึงไหน'), findsNothing); // เมนูซ้ำถูกเอาออก
    await tester.tap(find.text('ทำแล้ว'));
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsOneWidget);
    expect(find.textContaining('✓ เรียนเสร็จ'), findsOneWidget);
    await tester.tap(find.text('แค่ทำแล้ว ไม่บันทึก'));
    await tester.pumpAndSettle();
    expect(await study.classLogs(sid), isEmpty);
    expect(find.textContaining('ครบทุกงาน'), findsOneWidget); // ความสำเร็จ: งานเดียวของวันเสร็จ

    // ปฏิทิน → สัปดาห์ → แถบ 7 วัน + จุดเขียววันนี้
    await tester.tap(find.text('ปฏิทิน').last);
    await tester.pumpAndSettle();
    // ค่าเริ่มต้น = สัปดาห์
    expect(find.byKey(ValueKey('strip-${now.day}')), findsOneWidget);
    expect(find.byKey(ValueKey('complete-${now.day}')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
