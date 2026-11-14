import 'package:flutter/widgets.dart';

import '../skills/skill_repository.dart';
import '../work/work_repository.dart';
import 'calendar_models.dart';
import 'stickers.dart';
export 'stickers.dart';

/// "สัญญา" ของที่เก็บข้อมูลปฏิทิน (แบบเดียวกับ StudyRepository)
///
/// เป็น [ChangeNotifier]: ทุกครั้งที่เขียนข้อมูล จะแจ้งทุกหน้าที่ฟังอยู่ให้โหลดใหม่
/// → หน้า "วันนี้" กับ "ปฏิทิน" ตรงกันเสมอ แม้แก้จากอีกหน้า
abstract class CalendarRepository extends ChangeNotifier {
  /// ให้ทุกหน้าที่ฟังปฏิทินวาดใหม่ (เช่น หลังตั้งคำมั่น / เปิดปิดล็อก ซึ่งเก็บใน setting)
  void refresh() => notifyListeners();

  /// สกิล (v19 · รอบ 8C) · ฟังการเปลี่ยนแปลงแยกจากปฏิทิน
  SkillRepository get skillRepo;

  /// เมนู "งาน": การเงิน (v20 · รอบ 8D) · โปรเจกต์ (รอบ 8E)
  WorkRepository get workRepo;

  Future<List<ActivityCategory>> categories();

  /// หมวดสร้างเอง (v17) · ลบ = ย้ายงานไปหมวด [moveTo] ก่อน (null = ไม่มีหมวด) · หมวดระบบลบไม่ได้
  Future<int> addCategory(ActivityCategory c);
  Future<void> updateCategory(ActivityCategory c);
  Future<void> deleteCategory(int id, {int? moveTo});

  /// หมวด → จำนวนงาน (กิจกรรม) ที่ใช้อยู่
  Future<Map<int, int>> categoryUsage();

  /// งานยืดหยุ่น: ตั้งช่วงที่ว่างจากงานของครั้งนี้ (null = ล้าง)
  Future<void> setFree(int occurrenceId, DateTime? start, DateTime? end);

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
  /// แก้ชื่อ (และค่าถ้าส่ง [values]) ของ Preset เดิม · id เดิม งานที่ใช้อยู่ไม่หลุดกลุ่ม
  Future<void> updatePreset(int presetId, String name, NewActivity? values);
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

  /// งานทุกวันในช่วง [from]–[to] (รวมทั้งสองวัน) · ทุกวันมี key แม้ไม่มีงาน
  /// SQLite ทำในรอบเดียว (เรียกทีละวัน = เขียน DB ทีละวัน → 372 วันในหน้าสถิติหน่วงมาก)
  Future<Map<DateTime, List<Occurrence>>> occurrencesBetween(DateTime from, DateTime to) async {
    final out = <DateTime, List<Occurrence>>{};
    for (var d = dayOnly(from); !d.isAfter(dayOnly(to)); d = DateTime(d.year, d.month, d.day + 1)) {
      out[d] = await occurrencesOn(d);
    }
    return out;
  }

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
  // ---------- สติกเกอร์อารมณ์ ----------
  /// ทุกชุด (รวมที่ซ่อน) พร้อมสติกเกอร์ในชุด เรียงตามลำดับ
  Future<List<StickerPack>> stickerPacks();
  Future<int> addStickerPack(String name);
  Future<void> setStickerPackEnabled(int packId, bool enabled);

  /// ลบได้เฉพาะชุดที่ผู้ใช้สร้าง · สติกเกอร์และที่แปะไว้หายตาม
  Future<void> deleteStickerPack(int packId);
  Future<int> addSticker(int packId, String name, {String? emoji, String? imagePath});
  Future<void> deleteSticker(int stickerId);

  /// ซูม / เลื่อนให้พอดี (v18) · ไม่แตะไฟล์รูป
  Future<void> updateStickerFit(int stickerId, {required double scale, required double dx, required double dy});

  /// สติกเกอร์ที่แปะในช่วงวัน (รวมทั้งสองวัน) · เรียงวัน → ลำดับที่แปะ
  Future<List<DaySticker>> daySticker(DateTime from, DateTime to);
  Future<int> stickDay(DateTime day, int stickerId,
      {String? note, double? x, double? y, bool highlight = false, String? auto});

  /// แก้โน้ต / ย้ายตำแหน่ง โดยไม่เปลี่ยนลำดับ (เดิมแก้โน้ต = ลอกแล้วแปะใหม่ → ลำดับสลับ)
  Future<void> updateDaySticker(int dayStickerId, {String? note, bool clearNote = false, double? x, double? y});

  /// ตั้ง ⭐ ไฮไลต์ (วันละชิ้นเดียว)
  Future<void> setHighlight(int dayStickerId);

  /// เปลี่ยนตัวสติกเกอร์ (เช่น พลาด → เสร็จย้อนหลัง) ตำแหน่ง/ลำดับเดิม
  Future<void> swapDaySticker(int dayStickerId, int stickerId, {String? auto});
  Future<void> unstickDay(int dayStickerId);

  /// เช็กอินตอนเช้า (v17)
  Future<Checkin?> checkin(DateTime day);
  Future<List<Checkin>> checkins(DateTime from, DateTime to);
  Future<void> saveCheckin(Checkin c);

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
