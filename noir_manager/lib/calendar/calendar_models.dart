/// ข้อมูลฝั่งปฏิทิน (ตาม Data Model ในแผนรวม: ActivityCategory · Activity · Occurrence · LifeBase)
///
/// Activity = "ต้นแบบ" ของงาน เช่น "ออกกำลังกาย ทุกวัน 17:00 45 นาที"
/// Occurrence = งาน "1 ครั้ง" ในวันใดวันหนึ่ง (ทำแล้ว / ยกเลิก / เลื่อน แยกกันได้ทีละครั้ง)
library;

// ---------- ตัวช่วยเรื่องวันและเวลา ----------

/// ตัดเวลาทิ้ง เหลือแค่วันที่ (00:00)
DateTime dayOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// วันที่ → ข้อความ 'yyyy-mm-dd' (ใช้เก็บในฐานข้อมูล เรียงตามตัวอักษร = เรียงตามวัน)
String dayKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

/// นาทีนับจากเที่ยงคืน → 'HH:mm' (เช่น 1050 → 17:30)
String fmtMinute(int minute) =>
    '${(minute ~/ 60 % 24).toString().padLeft(2, '0')}:'
    '${(minute % 60).toString().padLeft(2, '0')}';

String fmtTime(DateTime t) => fmtMinute(t.hour * 60 + t.minute);

int minuteOf(DateTime t) => t.hour * 60 + t.minute;

/// วัน + นาที → DateTime (เก็บเป็น DateTime เสมอ เพื่อคำนวณข้ามเที่ยงคืนได้)
DateTime atMinute(DateTime day, int minute) =>
    dayOnly(day).add(Duration(minutes: minute));

/// 2 ช่วงเวลาทับกันไหม (ชนขอบพอดี = ไม่ทับ เช่น 17:00–18:00 กับ 18:00–19:00)
bool rangesOverlap(DateTime aStart, DateTime aEnd, DateTime bStart, DateTime bEnd) =>
    aStart.isBefore(bEnd) && bStart.isBefore(aEnd);

// ---------- หมวด ----------

class ActivityCategory {
  const ActivityCategory({required this.id, required this.name, required this.colorKey});

  final int id;
  final String name;

  /// ชื่อสี: blue · green · purple · amber · gray (แปลงเป็นสีจริงตามธีม)
  final String colorKey;

  factory ActivityCategory.fromRow(Map<String, Object?> r) => ActivityCategory(
        id: r['id'] as int,
        name: r['name'] as String,
        colorKey: r['color'] as String,
      );
}

// ---------- กิจกรรม (ต้นแบบ) ----------

enum RepeatKind { none, daily, weekly }

class Activity {
  const Activity({
    required this.id,
    required this.name,
    required this.categoryId,
    required this.importance,
    required this.timed,
    required this.startMinute,
    required this.durationMin,
    required this.repeat,
    required this.weekdays,
    required this.startDate,
  });

  final int id;
  final String name;
  final int? categoryId;

  /// ความสำคัญ 3 = สำคัญ · 2 = กลาง · 1 = น้อย
  final int importance;

  /// true = ล็อกเวลา (มีเวลาเริ่ม-จบ) · false = แบบลิสต์ (แค่ต้องทำวันนั้น)
  final bool timed;
  final int? startMinute;
  final int? durationMin;

  final RepeatKind repeat;

  /// วันในสัปดาห์ที่ซ้ำ (1 = จันทร์ ... 7 = อาทิตย์) ใช้เมื่อ repeat = weekly
  final Set<int> weekdays;

  /// วันแรกที่เริ่มมีงานนี้
  final DateTime startDate;

  factory Activity.fromRow(Map<String, Object?> r) => Activity(
        id: r['id'] as int,
        name: r['name'] as String,
        categoryId: r['category_id'] as int?,
        importance: r['importance'] as int,
        timed: (r['timed'] as int) == 1,
        startMinute: r['start_minute'] as int?,
        durationMin: r['duration_min'] as int?,
        repeat: RepeatKind.values.byName(r['repeat'] as String),
        weekdays: parseWeekdays(r['weekdays'] as String),
        startDate: DateTime.parse(r['start_date'] as String),
      );
}

/// '1,3,5' → {1, 3, 5}
Set<int> parseWeekdays(String s) =>
    s.split(',').where((x) => x.isNotEmpty).map(int.parse).toSet();

String weekdaysToText(Set<int> days) => (days.toList()..sort()).join(',');

/// กิจกรรมนี้มีงานในวัน [day] ไหม
bool occursOn(Activity a, DateTime day) {
  final d = dayOnly(day);
  if (d.isBefore(dayOnly(a.startDate))) return false;
  return switch (a.repeat) {
    RepeatKind.none => d == dayOnly(a.startDate),
    RepeatKind.daily => true,
    RepeatKind.weekly => a.weekdays.contains(d.weekday),
  };
}

/// ข้อมูลตอน "เพิ่มงานใหม่" (ยังไม่มี id)
class NewActivity {
  const NewActivity({
    required this.name,
    required this.categoryId,
    required this.importance,
    required this.timed,
    required this.day,
    this.startMinute,
    this.durationMin,
    this.repeat = RepeatKind.none,
    this.weekdays = const {},
  });

  final String name;
  final int? categoryId;
  final int importance;
  final bool timed;
  final DateTime day;
  final int? startMinute;
  final int? durationMin;
  final RepeatKind repeat;
  final Set<int> weekdays;
}

// ---------- งาน 1 ครั้ง ----------

enum OccurrenceStatus { planned, done, cancelled, moved, inbox }

class Occurrence {
  const Occurrence({
    required this.id,
    required this.activityId,
    required this.title,
    required this.categoryId,
    required this.importance,
    required this.repeats,
    required this.day,
    required this.startAt,
    required this.endAt,
    required this.status,
    required this.reason,
    required this.movedFromId,
  });

  final int id;
  final int activityId;
  final String title;
  final int? categoryId;
  final int importance;

  /// กิจกรรมต้นแบบเป็นงานซ้ำไหม (ใช้ตัดสินว่าจะถาม "เลื่อนทั้งแถว" หรือไม่)
  final bool repeats;

  final DateTime day;

  /// null = งานแบบลิสต์ (ไม่ล็อกเวลา)
  final DateTime? startAt;
  final DateTime? endAt;
  final OccurrenceStatus status;

  /// เหตุผลตอนยกเลิก
  final String? reason;

  /// ถ้าครั้งนี้เกิดจากการเลื่อน = id ของครั้งเดิม
  final int? movedFromId;

  bool get timed => startAt != null;

  /// ยังนับว่า "ต้องทำ / ทำแล้ว" อยู่ในวันนั้น (ไม่ถูกยกเลิก/เลื่อนออก)
  bool get active =>
      status == OccurrenceStatus.planned || status == OccurrenceStatus.done;

  factory Occurrence.fromRow(Map<String, Object?> r) => Occurrence(
        id: r['id'] as int,
        activityId: r['activity_id'] as int,
        title: (r['title'] as String?) ?? (r['a_name'] as String),
        categoryId: r['category_id'] as int?,
        importance: r['importance'] as int,
        repeats: (r['repeat'] as String) != RepeatKind.none.name,
        day: DateTime.parse(r['day'] as String),
        startAt: r['start_at'] == null
            ? null
            : DateTime.parse(r['start_at'] as String),
        endAt: r['end_at'] == null ? null : DateTime.parse(r['end_at'] as String),
        status: OccurrenceStatus.values.byName(r['status'] as String),
        reason: r['reason'] as String?,
        movedFromId: r['moved_from'] as int?,
      );
}

/// หางานที่ล็อกเวลาและทับกับช่วง [start]–[end] ในรายการของวันนั้น
List<Occurrence> findOverlaps(
  List<Occurrence> dayItems,
  DateTime start,
  DateTime end, {
  int? excludeId,
}) =>
    dayItems
        .where((o) =>
            o.id != excludeId &&
            o.status == OccurrenceStatus.planned &&
            o.timed &&
            rangesOverlap(start, end, o.startAt!, o.endAt!))
        .toList();

// ---------- Life Base: เวลานอน / ตื่น ----------

class LifeBaseDay {
  const LifeBaseDay({
    required this.weekday,
    required this.bedMinute,
    required this.wakeMinute,
  });

  /// 1 = จันทร์ ... 7 = อาทิตย์
  final int weekday;

  /// เวลานอนของคืนวันนี้ (นาที) · ก่อนเที่ยง = หลังเที่ยงคืน เช่น 30 = 00:30
  final int bedMinute;

  /// เวลาตื่นของเช้าวันนี้ (นาที)
  final int wakeMinute;

  LifeBaseDay copyWith({int? bedMinute, int? wakeMinute}) => LifeBaseDay(
        weekday: weekday,
        bedMinute: bedMinute ?? this.bedMinute,
        wakeMinute: wakeMinute ?? this.wakeMinute,
      );
}

/// ชั่วโมงนอนของคืน [tonight] → ตื่นเช้า [tomorrow]
/// เช่น นอน 23:30 ตื่น 07:00 = 7.5 ชม. · นอน 00:30 ตื่น 07:00 = 6.5 ชม.
double sleepHours(LifeBaseDay tonight, LifeBaseDay tomorrow) {
  final bed = tonight.bedMinute < 12 * 60
      ? tonight.bedMinute + 24 * 60 // นอนหลังเที่ยงคืน
      : tonight.bedMinute;
  final wake = tomorrow.wakeMinute + 24 * 60;
  return (wake - bed) / 60;
}

/// ค่าเริ่มต้นตาม Mockup: นอน 23:30 ตื่น 07:00 ทุกวัน
List<LifeBaseDay> defaultLifeBase() => [
      for (var d = 1; d <= 7; d++)
        LifeBaseDay(weekday: d, bedMinute: 23 * 60 + 30, wakeMinute: 7 * 60),
    ];

/// หมวดเริ่มต้นตอนสร้างฐานข้อมูลครั้งแรก
const List<(String, String)> seedCategories = [
  ('เรียน', 'blue'),
  ('ออกกำลังกาย', 'green'),
  ('สตรีม', 'purple'),
  ('งาน', 'amber'),
  ('อื่น ๆ', 'gray'),
];
