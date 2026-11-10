import 'package:flutter/widgets.dart';

import 'calendar_models.dart';

/// "สัญญา" ของที่เก็บข้อมูลปฏิทิน (แบบเดียวกับ StudyRepository)
///
/// เป็น [ChangeNotifier]: ทุกครั้งที่เขียนข้อมูล จะแจ้งทุกหน้าที่ฟังอยู่ให้โหลดใหม่
/// → หน้า "วันนี้" กับ "ปฏิทิน" ตรงกันเสมอ แม้แก้จากอีกหน้า
abstract class CalendarRepository extends ChangeNotifier {
  Future<List<ActivityCategory>> categories();

  Future<int> addActivity(NewActivity a);

  /// กิจกรรมต้นแบบ 1 ตัว (ใช้เปิดฟอร์มแก้ไข)
  Future<Activity> activity(int activityId);

  /// แก้กิจกรรมต้นแบบ: ชื่อ/หมวด/ความสำคัญ เปลี่ยนทุกครั้ง
  /// ส่วนวัน/เวลา: ครั้งที่ยังเป็นแผนตั้งแต่ [from] (ค่าเริ่มต้น = วันนี้) จะสร้างใหม่ตามค่าใหม่
  /// ครั้งที่ทำแล้ว / ยกเลิก / เลื่อน ไม่ถูกแตะ
  Future<void> updateActivity(int activityId, NewActivity a, {DateTime? from});

  /// แก้เวลาเฉพาะครั้งนี้ (วันเดิม ไม่นับว่าเลื่อน)
  Future<void> updateOccurrenceTime(int occurrenceId, DateTime start, DateTime end);

  /// Preset: ชุดค่าที่บันทึกไว้ เช่น Stream (สตรีม · สำคัญ · 20:00–00:00)
  Future<List<Preset>> presets();
  Future<int> addPreset(String name, NewActivity values);
  Future<void> deletePreset(int presetId);

  /// บันทึกเวลาเริ่ม/เลิกจริง (null = ล้างค่า)
  Future<void> setActualTimes(int occurrenceId, {DateTime? start, DateTime? end});

  /// งานต้นแบบที่ผูกกับวิชา (ตารางเรียนของวิชานั้น)
  Future<List<Activity>> activitiesForSubject(int subjectId);

  /// ทุกครั้งของงานที่ผูกกับวิชา (ใช้คิดสถิติเวลาเลิก)
  Future<List<Occurrence>> occurrencesForSubject(int subjectId);

  /// ลบกิจกรรมต้นแบบ + ทุกครั้งของมัน
  Future<void> deleteActivity(int activityId);

  /// งานทุกครั้งของวัน [day] (สร้างครั้งของงานซ้ำให้อัตโนมัติถ้ายังไม่มี)
  Future<List<Occurrence>> occurrencesOn(DateTime day);

  /// Updates: งานที่เลื่อนแล้วแต่ยังไม่มีวันแทน
  Future<List<Occurrence>> inbox();

  Future<void> setDone(int occurrenceId, bool done);

  /// ยกเลิก (ต้องมีเหตุผลเสมอ)
  Future<void> cancel(int occurrenceId, String reason);

  /// เลื่อนแต่ยังไม่มีวันแทน → ไป Updates
  Future<void> sendToInbox(int occurrenceId);

  /// เลื่อนเฉพาะครั้งนี้: ครั้งเดิม = moved · สร้างครั้งใหม่ในวัน [day]
  /// [start]/[end] = null สำหรับงานแบบลิสต์
  Future<int> moveOccurrence(
    int occurrenceId,
    DateTime day, {
    DateTime? start,
    DateTime? end,
  });

  /// เลื่อนทั้งแถว: เปลี่ยนเวลาของงานซ้ำ ตั้งแต่วัน [fromDay] เป็นต้นไป
  Future<void> moveSeries(
      int activityId, DateTime fromDay, int startMinute, int durationMin);

  /// Life Base: เวลานอน/ตื่น 7 วัน (จันทร์ → อาทิตย์)
  Future<List<LifeBaseDay>> lifeBase();
  Future<void> setLifeBase(List<LifeBaseDay> days);

  /// ภาคเรียน: เรียงตามปี → เทอม · บันทึกซ้ำปี+เทอมเดิม = เขียนทับ
  Future<List<Term>> terms();
  Future<void> saveTerm(int year, int termNo, DateTime start, DateTime end);
  Future<void> deleteTerm(int termId);

  /// วันหยุด: เรียงตามวัน · วันเดิม = เปลี่ยนชื่อ
  Future<List<Holiday>> holidays();
  Future<void> setHoliday(DateTime day, String name);
  Future<void> removeHoliday(DateTime day);

  /// ลบคาบเรียน/วันสอบที่ซ้ำกัน (ดู [duplicateActivityIds]) → คืนจำนวนที่ลบ
  Future<int> removeDuplicateActivities();

  /// "เลื่อนไปรอบถัดไป" (กล่องเลื่อนข้อ 1): ครั้งนี้ไม่เกิด เนื้อหาไหลไปครั้งหน้า
  /// งานที่มี "ถึงวันที่" → ขยายวันสุดท้ายไปอีก 1 รอบตามกฎการทำซ้ำ
  /// คืนวันสุดท้ายใหม่ · null = งานไม่มีวันสิ้นสุด (ไม่ต้องขยาย)
  /// ใช้ได้เฉพาะงานที่ [canShiftToNextRound] (ไม่งั้นโยน [StateError])
  Future<DateTime?> shiftToNextRound(int occurrenceId, String reason);

  /// วันที่ (ตามกฎการทำซ้ำ) ของครั้งที่ถูกเลื่อนไปรอบถัดไป → ไม่นับเลข n/N
  Future<Set<DateTime>> shiftedDays(int activityId);

  /// ค่าตั้งเล็ก ๆ (ตาราง setting เดียวกับฝั่งวิชา) เช่น ตัวเลือกวันหยุดที่ "จำไว้"
  Future<String?> getSetting(String key);
  Future<void> setSetting(String key, String value);

  /// เติม "ครั้งที่ n/N" ให้งานซ้ำ · ใช้ร่วมกันทั้งตัว SQLite และตัว RAM ให้กฎตรงกัน
  /// อ่านกิจกรรมเต็มทีละตัว (cache ต่อรอบ) เพราะโหมดเลือกวันเองต้องรู้ทุกวันถึงจะนับได้
  @protected
  Future<List<Occurrence>> attachSessions(List<Occurrence> items) async {
    final cache = <int, Activity?>{};
    final skipped = <int, Set<DateTime>>{};
    final out = <Occurrence>[];
    for (final o in items) {
      if (!o.repeats || o.rootDay == null) {
        out.add(o);
        continue;
      }
      if (!cache.containsKey(o.activityId)) {
        try {
          cache[o.activityId] = await activity(o.activityId);
        } catch (_) {
          // งานถูกลบระหว่างหน้ากำลังโหลด (เช่น ลบหลายคาบติดกัน) → ข้าม รอบโหลดถัดไปก็ไม่มีแล้ว
          cache[o.activityId] = null;
        }
      }
      final a = cache[o.activityId];
      if (a == null) continue;
      final skip = skipped[o.activityId] ??= await shiftedDays(o.activityId);
      out.add(o.withSession(sessionCount(a, o.rootDay!, skipped: skip)));
    }
    return out;
  }
}

/// ท่อส่ง CalendarRepository ลงไปทุกหน้า (เหมือน StudyScope)
class CalendarScope extends InheritedWidget {
  const CalendarScope({
    super.key,
    required this.repository,
    required super.child,
  });

  final CalendarRepository repository;

  static CalendarRepository of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<CalendarScope>();
    assert(scope != null, 'ไม่พบ CalendarScope เหนือ widget นี้');
    return scope!.repository;
  }

  @override
  bool updateShouldNotify(CalendarScope oldWidget) =>
      repository != oldWidget.repository;
}
