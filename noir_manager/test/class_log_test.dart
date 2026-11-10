import 'package:flutter_test/flutter_test.dart';

import 'package:noir_manager/calendar/calendar_models.dart';
import 'package:noir_manager/calendar/memory_calendar_repository.dart';
import 'package:noir_manager/data/memory_study_repository.dart';
import 'package:noir_manager/data/study_models.dart';
import 'package:noir_manager/study/attendance.dart';
import 'package:noir_manager/study/class_log.dart';
import 'package:noir_manager/study/tutor_plan.dart';

void main() {
  test('บันทึกคาบ: เลือกบท + หัวข้อเดิม/ใหม่ → บทกลายเป็น "กำลังติว" · รอบติวหยิบบทนี้', () async {
    final repo = MemoryStudyRepository();
    final sid = await repo.addSubject('การเขียนโปรแกรม');
    final ch1 = await repo.addChapter(sid, 'บท 1 พื้นฐาน');
    await repo.addSubtopic(ch1, 'ตัวแปร');
    await repo.addChapter(sid, 'บท 2 ลูป');
    expect(guessChapter(await repo.chapters(sid)), ch1);

    // คาบ 1: เลือกหัวข้อที่มีอยู่ + เพิ่มหัวข้อใหม่ · ถึงกลางบท
    await saveClassLog(repo, sid, DateTime(2026, 11, 9),
        const ClassLogInput(chapterId: null, topics: ['ตัวแปร'], newTopics: ['ชนิดข้อมูล']),
        occurrenceId: 11);
    // chapterId null + ไม่มีบทใหม่ → บันทึกได้แต่ไม่ระบุบท
    expect((await repo.classLogs(sid)).single.chapterId, isNull);

    await saveClassLog(repo, sid, DateTime(2026, 11, 9),
        ClassLogInput(chapterId: ch1, topics: const ['ตัวแปร'], newTopics: const ['ชนิดข้อมูล']),
        occurrenceId: 11);
    var chapters = await repo.chapters(sid);
    expect(chapters.first.chapter.status, ChapterStatus.learning);
    expect(chapters.first.subtopics.map((t) => t.name), ['ตัวแปร', 'ชนิดข้อมูล']);
    expect(nextChapter(chapters)?.id, ch1);
    var logs = await repo.classLogs(sid);
    expect(logs, hasLength(1)); // คาบเดิม = แก้ของเดิม
    expect(logs.single.topics, ['ตัวแปร', 'ชนิดข้อมูล']);

    // คาบ 2: บทใหม่ที่ยังไม่มีในแอป
    await saveClassLog(repo, sid, DateTime(2026, 11, 10), const ClassLogInput(newChapter: 'บท 3 ฟังก์ชัน', finished: true),
        occurrenceId: 12);
    chapters = await repo.chapters(sid);
    expect(chapters.map((c) => c.chapter.name), contains('บท 3 ฟังก์ชัน'));
    logs = await repo.classLogs(sid);
    expect(logs.first.day, DateTime(2026, 11, 10)); // ใหม่ → เก่า
    expect(logs.first.finished, isTrue);

    // ลบบท → บันทึกยังอยู่ แต่ไม่ระบุบท
    await repo.deleteChapter(ch1);
    logs = await repo.classLogs(sid);
    expect(logs.last.chapterId, isNull);
    expect(logs.last.topics, ['ตัวแปร', 'ชนิดข้อมูล']);
  });

  test('อาจารย์สั่งงาน ⭐: ลงปฏิทินวันส่ง · นับเป็นชิ้นคะแนน · แก้บันทึกไม่สร้างงานซ้ำ', () async {
    final study = MemoryStudyRepository();
    final cal = MemoryCalendarRepository();
    final sid = await study.addSubject('การเขียนโปรแกรม');
    final part = await study.addGradePart(sid, 'งาน', 20, items: 2, itemFull: 5);
    final day = DateTime(2026, 11, 9);
    final due = nextWeek(day);
    expect(due, DateTime(2026, 11, 16, 23, 59));

    final id = await saveClassLog(study, sid, day,
        ClassLogInput(homework: 'การบ้านบท 1 ข้อ 1–10', dueAt: due, gradePartId: part),
        calendar: cal, occurrenceId: 21);
    final log = (await study.classLogs(sid)).single;
    expect(log.id, id);
    expect(log.homework, 'การบ้านบท 1 ข้อ 1–10');
    expect(log.dueAt, due);
    expect(log.taskActivityId, isNotNull);

    final onDue = await cal.occurrencesOn(DateTime(2026, 11, 16));
    expect(onDue.map((o) => o.title), contains('ส่ง: การบ้านบท 1 ข้อ 1–10 · การเขียนโปรแกรม'));
    final task = onDue.firstWhere((o) => o.title.startsWith('ส่ง:'));
    expect(task.endAt, DateTime(2026, 11, 16, 23, 59));
    expect(task.subjectId, sid);

    final items = (await study.gradeParts(sid)).single.items;
    expect(items.map((i) => i.name), contains('การบ้านบท 1 ข้อ 1–10'));
    expect(items.last.full, 5);

    // แก้บันทึกเดิม → ไม่มีงานส่งซ้ำ ไม่มีชิ้นคะแนนซ้ำ
    await saveClassLog(study, sid, day,
        ClassLogInput(homework: 'การบ้านบท 1 ข้อ 1–10', dueAt: due, gradePartId: part, note: 'ทำในสมุด'),
        calendar: cal, occurrenceId: 21, existing: log);
    expect((await cal.occurrencesOn(DateTime(2026, 11, 16))).where((o) => o.title.startsWith('ส่ง:')), hasLength(1));
    expect((await study.gradeParts(sid)).single.items, hasLength(3));
    expect((await study.classLogs(sid)).single.note, 'ทำในสมุด');

    expect(dueText(due, now: day), contains('อีก 7 วัน'));
    expect(dueText(DateTime(2026, 11, 10, 9), now: day), contains('พรุ่งนี้'));
  });

  test('คาบหน้า: หาคาบถัดไปของวิชาจากตารางเรียน (วัน + เวลาเริ่ม)', () async {
    final cal = MemoryCalendarRepository();
    for (final (wd, start) in [(1, 9 * 60), (3, 13 * 60)]) {
      await cal.addActivity(NewActivity(
        name: 'เรียน',
        categoryId: null,
        importance: 3,
        timed: true,
        day: DateTime(2026, 11, 2),
        startMinute: start,
        durationMin: 120,
        repeat: RepeatKind.weekly,
        weekdays: {wd},
        endDate: DateTime(2027, 2, 1),
        subjectId: 7,
        kind: ActivityKind.classSession,
      ));
    }
    // จันทร์ 9 → คาบหน้า = พุธ 11 13:00 · พุธ 11 → จันทร์ 16 09:00
    expect(await nextClassAfter(cal, 7, DateTime(2026, 11, 9)), DateTime(2026, 11, 11, 13));
    expect(await nextClassAfter(cal, 7, DateTime(2026, 11, 11)), DateTime(2026, 11, 16, 9));
    expect(await nextClassAfter(cal, 8, DateTime(2026, 11, 11)), isNull);
  });
}
