import 'package:flutter_test/flutter_test.dart';

import 'package:noir_manager/data/memory_study_repository.dart';
import 'package:noir_manager/data/study_models.dart';
import 'package:noir_manager/study/class_log.dart';
import 'package:noir_manager/study/tutor_plan.dart';

void main() {
  test('บันทึกคาบ: บทใหม่ + หัวข้อ → บทกลายเป็น "กำลังติว" · รอบติวหยิบบทนี้', () async {
    final repo = MemoryStudyRepository();
    final sid = await repo.addSubject('การเขียนโปรแกรม');
    final ch1 = await repo.addChapter(sid, 'บท 1 พื้นฐาน');
    await repo.addChapter(sid, 'บท 2 ลูป');
    expect(guessChapter(await repo.chapters(sid)), ch1);

    // คาบ 1: เรียนบท 1 ถึงกลางบท
    await saveClassLog(repo, sid, DateTime(2026, 11, 9), occurrenceId: 11, chapterId: ch1, topics: ['ตัวแปร', 'ชนิดข้อมูล']);
    var chapters = await repo.chapters(sid);
    expect(chapters.first.chapter.status, ChapterStatus.learning);
    expect(chapters.first.subtopics.map((t) => t.name), ['ตัวแปร', 'ชนิดข้อมูล']);
    expect(nextChapter(chapters)?.id, ch1);

    // คาบเดิมบันทึกซ้ำ = แก้ของเดิม · หัวข้อซ้ำไม่เพิ่ม
    await saveClassLog(repo, sid, DateTime(2026, 11, 9), occurrenceId: 11, chapterId: ch1, topics: ['ตัวแปร'], finished: true, note: 'งาน 1 ส่งศุกร์');
    var logs = await repo.classLogs(sid);
    expect(logs, hasLength(1));
    expect(logs.single.finished, isTrue);
    expect(logs.single.note, 'งาน 1 ส่งศุกร์');
    expect((await repo.chapters(sid)).first.subtopics, hasLength(2));

    // คาบ 2: บทใหม่ที่ยังไม่มีในแอป
    await saveClassLog(repo, sid, DateTime(2026, 11, 10), occurrenceId: 12, newChapter: 'บท 3 ฟังก์ชัน', topics: ['def']);
    chapters = await repo.chapters(sid);
    expect(chapters.map((c) => c.chapter.name), contains('บท 3 ฟังก์ชัน'));
    logs = await repo.classLogs(sid);
    expect(logs.first.day, DateTime(2026, 11, 10)); // ใหม่ → เก่า

    // ลบบท → บันทึกยังอยู่ แต่ไม่ระบุบท
    await repo.deleteChapter(ch1);
    logs = await repo.classLogs(sid);
    expect(logs.last.chapterId, isNull);
    await repo.deleteClassLog(logs.last.id);
    expect(await repo.classLogs(sid), hasLength(1));
  });
}
