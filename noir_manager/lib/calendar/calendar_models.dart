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
  const ActivityCategory(
      {required this.id, required this.name, required this.colorKey, this.systemKey});

  final int id;
  final String name;

  /// หมวดที่ระบบใช้เอง เช่น 'study' = หมวดเรียน (เปลี่ยนชื่อหมวดได้ ระบบไม่พัง)
  final String? systemKey;

  /// ชื่อสี: blue · green · purple · amber · gray (แปลงเป็นสีจริงตามธีม)
  final String colorKey;

  factory ActivityCategory.fromRow(Map<String, Object?> r) => ActivityCategory(
        id: r['id'] as int,
        name: r['name'] as String,
        colorKey: r['color'] as String,
        systemKey: r['system_key'] as String?,
      );
}

/// รหัสหมวดเรียน (ไม่ผูกกับชื่อหมวด)
const studySystemKey = 'study';

/// id ของหมวดเรียน · null = ไม่มี (ผู้ใช้ลบหมวดไปแล้ว)
int? studyCategoryId(List<ActivityCategory> cats) =>
    cats.where((c) => c.systemKey == studySystemKey).firstOrNull?.id;

// ---------- Preset (ชุดค่าที่บันทึกไว้ + กลุ่ม) ----------

/// Preset เช่น "Stream": หมวด + ความสำคัญ + เวลาเริ่ม–จบที่ใช้บ่อย
/// งานหลายหัวข้อ (RE4, Minecraft, Valorant) ใช้ Preset เดียวกัน = อยู่กลุ่มเดียวกัน
class Preset {
  const Preset({
    required this.id,
    required this.name,
    required this.categoryId,
    required this.importance,
    required this.startMinute,
    required this.durationMin,
  });

  final int id;
  final String name;
  final int? categoryId;
  final int importance;

  /// null = งานแบบลิสต์ (ไม่ล็อกเวลา)
  final int? startMinute;
  final int? durationMin;

  factory Preset.fromRow(Map<String, Object?> r) => Preset(
        id: r['id'] as int,
        name: r['name'] as String,
        categoryId: r['category_id'] as int?,
        importance: r['importance'] as int,
        startMinute: r['start_minute'] as int?,
        durationMin: r['duration_min'] as int?,
      );
}

// ---------- กิจกรรม (ต้นแบบ) ----------

/// ประเภทงาน: ทั่วไป · คาบเรียน · สอบ · รอบติว
enum ActivityKind { todo, classSession, exam, tutor }

ActivityKind activityKindOf(Object? raw) => switch (raw) {
      'class' => ActivityKind.classSession,
      'exam' => ActivityKind.exam,
      'tutor' => ActivityKind.tutor,
      _ => ActivityKind.todo,
    };

String activityKindDb(ActivityKind k) => switch (k) {
      ActivityKind.classSession => 'class',
      ActivityKind.exam => 'exam',
      ActivityKind.tutor => 'tutor',
      ActivityKind.todo => 'todo',
    };

/// none = ครั้งเดียว · daily = ทุกวัน · weekly = ทุกสัปดาห์ (เลือกวัน) · dates = เลือกวันเอง
enum RepeatKind { none, daily, weekly, dates }

/// 1 วันในโหมด "เลือกวันเอง" · เวลา null = ใช้เวลาหลักของงาน
class ScheduledDate {
  const ScheduledDate(this.day, {this.startMinute, this.durationMin});

  final DateTime day;
  final int? startMinute;
  final int? durationMin;

  bool get customTime => startMinute != null;
}

/// ประเภทคาบเรียน (ตามตารางทะเบียน: S = ทฤษฎี · L = ปฏิบัติ)
enum ClassType { theory, lab }

ClassType? classTypeOf(Object? v) => switch (v) {
      'theory' => ClassType.theory,
      'lab' => ClassType.lab,
      _ => null,
    };

String classTypeLabel(ClassType? t) => switch (t) {
      ClassType.theory => 'ทฤษฎี',
      ClassType.lab => 'ปฏิบัติ',
      null => 'ไม่ระบุประเภท',
    };

/// ข้อมูลเฉพาะคาบเรียน (v11) · คาบเก่าก่อน v11 = ว่างทั้งหมด
class ClassInfo {
  const ClassInfo({this.type, this.room, this.section});

  static const none = ClassInfo();

  final ClassType? type;

  /// ห้องเรียน เช่น 1-B4-08
  final String? room;

  /// กลุ่มเรียน เช่น S.1 / L.1
  final String? section;

  factory ClassInfo.fromRow(Map<String, Object?> r) => ClassInfo(
        type: classTypeOf(r['class_type']),
        room: _blankToNull(r['room'] as String?),
        section: _blankToNull(r['section'] as String?),
      );

  /// ช่องว่าง → null (ไม่เก็บสตริงว่างลง DB)
  /// พิมพ์ "กลุ่ม L.1" / "ห้อง 1-B4-08" มา → เก็บแค่ค่า เพราะหน้าจอเติมคำนำหน้าให้เอง
  ClassInfo get normalized => ClassInfo(
        type: type,
        room: _blankToNull(_stripLabel(room, 'ห้อง')),
        section: _blankToNull(_stripLabel(section, 'กลุ่ม')),
      );

  @override
  bool operator ==(Object other) =>
      other is ClassInfo && other.type == type && other.room == room && other.section == section;

  @override
  int get hashCode => Object.hash(type, room, section);
}

String? _stripLabel(String? s, String label) {
  final t = s?.trim();
  if (t == null || !t.startsWith(label)) return t;
  return t.substring(label.length).replaceFirst(RegExp(r'^[\s:：]+'), '');
}

String? _blankToNull(String? s) => (s == null || s.trim().isEmpty) ? null : s.trim();

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
    this.endDate,
    this.presetId,
    this.dates = const {},
    this.subjectId,
    this.kind = ActivityKind.todo,
    this.classInfo = ClassInfo.none,
  });

  /// ผูกกับวิชาในหน้าวิชา (คาบเรียน) · null = งานทั่วไป
  final int? subjectId;
  final ActivityKind kind;

  /// ประเภท/ห้อง/กลุ่ม ของคาบเรียน (ใช้กับ kind = class)
  final ClassInfo classInfo;

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

  /// วันสุดท้าย (null = ไม่มีกำหนด) ใช้กับทุกวัน / ทุกสัปดาห์
  final DateTime? endDate;

  /// อยู่ในกลุ่ม Preset ไหน (null = ไม่มี)
  final int? presetId;

  /// โหมดเลือกวันเอง: dayKey → วันนั้น (พร้อมเวลาเฉพาะวัน ถ้ามี)
  final Map<String, ScheduledDate> dates;

  factory Activity.fromRow(Map<String, Object?> r,
          {Map<String, ScheduledDate> dates = const {}}) =>
      Activity(
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
        endDate: r['end_date'] == null
            ? null
            : DateTime.parse(r['end_date'] as String),
        presetId: r['preset_id'] as int?,
        dates: dates,
        subjectId: r['subject_id'] as int?,
        kind: activityKindOf(r['kind']),
        classInfo: ClassInfo.fromRow(r),
      );

  /// แปลงกลับเป็นฟอร์ม (ใช้ตอนกด "แก้ไขงาน")
  NewActivity toDraft() => NewActivity(
        name: name,
        categoryId: categoryId,
        importance: importance,
        timed: timed,
        day: startDate,
        startMinute: startMinute,
        durationMin: durationMin,
        repeat: repeat,
        weekdays: weekdays,
        endDate: endDate,
        presetId: presetId,
        dates: (dates.values.toList()..sort((a, b) => a.day.compareTo(b.day))),
        subjectId: subjectId,
        kind: kind,
        classInfo: classInfo,
      );
}

/// '1,3,5' → {1, 3, 5}
Set<int> parseWeekdays(String s) =>
    s.split(',').where((x) => x.isNotEmpty).map(int.parse).toSet();

String weekdaysToText(Set<int> days) => (days.toList()..sort()).join(',');

/// กิจกรรมนี้มีงานในวัน [day] ไหม
bool occursOn(Activity a, DateTime day) {
  final d = dayOnly(day);
  if (a.repeat == RepeatKind.dates) return a.dates.containsKey(dayKey(d));
  if (d.isBefore(dayOnly(a.startDate))) return false;
  if (a.endDate != null && d.isAfter(dayOnly(a.endDate!))) return false;
  return switch (a.repeat) {
    RepeatKind.none => d == dayOnly(a.startDate),
    RepeatKind.daily => true,
    RepeatKind.weekly => a.weekdays.contains(d.weekday),
    RepeatKind.dates => false, // จัดการด้านบนแล้ว
  };
}

/// เวลาเริ่ม/ระยะเวลาของงานในวัน [day] (วันที่ตั้งเวลาเฉพาะไว้ ใช้เวลานั้น)
(int, int)? timeFor(Activity a, DateTime day) {
  if (!a.timed) return null;
  final custom = a.dates[dayKey(day)];
  if (custom != null && custom.customTime) {
    return (custom.startMinute!, custom.durationMin ?? a.durationMin!);
  }
  return (a.startMinute!, a.durationMin!);
}

/// ข้อมูลในฟอร์ม "เพิ่มงาน / แก้ไขงาน" (ยังไม่มี id)
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
    this.endDate,
    this.presetId,
    this.dates = const [],
    this.subjectId,
    this.kind = ActivityKind.todo,
    this.classInfo = ClassInfo.none,
  });

  final int? subjectId;
  final ActivityKind kind;
  final ClassInfo classInfo;

  final String name;
  final int? categoryId;
  final int importance;
  final bool timed;

  /// วันที่ (ครั้งเดียว) หรือวันเริ่ม (งานซ้ำ)
  final DateTime day;
  final int? startMinute;
  final int? durationMin;
  final RepeatKind repeat;
  final Set<int> weekdays;
  final DateTime? endDate;
  final int? presetId;

  /// ใช้เมื่อ repeat = dates
  final List<ScheduledDate> dates;

  /// วันแรกจริงของงาน (โหมดเลือกวันเอง = วันที่เร็วที่สุดในรายการ)
  DateTime get firstDay => repeat == RepeatKind.dates && dates.isNotEmpty
      ? dates.map((d) => dayOnly(d.day)).reduce((a, b) => a.isBefore(b) ? a : b)
      : dayOnly(day);

  /// สร้าง Activity ชั่วคราว (id = 0) เพื่อใช้กฎ occursOn / timeFor ก่อนบันทึกจริง
  Activity toActivity({int id = 0}) => Activity(
        id: id,
        name: name,
        categoryId: categoryId,
        importance: importance,
        timed: timed,
        startMinute: timed ? startMinute : null,
        durationMin: timed ? durationMin : null,
        repeat: repeat,
        weekdays: repeat == RepeatKind.weekly ? weekdays : const {},
        startDate: firstDay,
        endDate: repeat == RepeatKind.daily || repeat == RepeatKind.weekly
            ? endDate
            : null,
        presetId: presetId,
        dates: repeat == RepeatKind.dates
            ? {for (final d in dates) dayKey(d.day): d}
            : const {},
        subjectId: subjectId,
        kind: kind,
        classInfo: classInfo,
      );

  /// ฉบับเดิมแต่เปลี่ยนข้อมูลคาบเรียน (ตั้งประเภท/ห้อง/กลุ่มให้คาบที่มีอยู่แล้ว)
  NewActivity withClassInfo(ClassInfo info) => NewActivity(
        name: name,
        categoryId: categoryId,
        importance: importance,
        timed: timed,
        day: day,
        startMinute: startMinute,
        durationMin: durationMin,
        repeat: repeat,
        weekdays: weekdays,
        endDate: endDate,
        presetId: presetId,
        dates: dates,
        subjectId: subjectId,
        kind: kind,
        classInfo: info,
      );
}

/// ข้อความเวลา เช่น "20:00–00:00 (4 ชม.)"
String rangeText(int startMinute, int durationMin) =>
    '${fmtMinute(startMinute)}–${fmtMinute(startMinute + durationMin)}';

// ---------- งาน 1 ครั้ง ----------

/// shifted = "เลื่อนไปรอบถัดไป": ครั้งนี้ไม่เกิด เนื้อหาไหลไปครั้งหน้า · ไม่กินเลข n/N
enum OccurrenceStatus { planned, done, cancelled, moved, inbox, shifted }

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
    this.subjectId,
    this.actualStart,
    this.actualEnd,
    this.kind = ActivityKind.todo,
    this.rootDay,
    this.session,
  });

  final ActivityKind kind;

  /// วันที่ครั้งนี้ "ควรเกิด" ตามกฎการทำซ้ำ · ครั้งที่ถูกเลื่อนมาใช้วันของครั้งต้นทาง
  /// (ไล่ moved_from กลับไปจนเจอ) เพื่อให้เลข "ครั้งที่ n" ติดตัวเนื้อหาไปด้วย
  final DateTime? rootDay;

  /// "ครั้งที่ n/N" · null = งานครั้งเดียว หรือยังไม่ได้คำนวณ
  final SessionCount? session;

  /// สำเนาที่เปลี่ยนสถานะ (ใช้ตอนเพิ่งกดทำแล้ว ก่อนโหลดใหม่)
  Occurrence copyWithStatus(OccurrenceStatus st) => Occurrence(
        id: id,
        activityId: activityId,
        title: title,
        categoryId: categoryId,
        importance: importance,
        repeats: repeats,
        day: day,
        startAt: startAt,
        endAt: endAt,
        status: st,
        reason: reason,
        movedFromId: movedFromId,
        subjectId: subjectId,
        actualStart: actualStart,
        actualEnd: actualEnd,
        kind: kind,
        rootDay: rootDay,
        session: session,
      );

  /// สำเนาที่ใส่เลขครั้งแล้ว (repository เติมให้หลังอ่านจาก DB)
  Occurrence withSession(SessionCount? s) => Occurrence(
        id: id,
        activityId: activityId,
        title: title,
        categoryId: categoryId,
        importance: importance,
        repeats: repeats,
        day: day,
        startAt: startAt,
        endAt: endAt,
        status: status,
        reason: reason,
        movedFromId: movedFromId,
        subjectId: subjectId,
        actualStart: actualStart,
        actualEnd: actualEnd,
        kind: kind,
        rootDay: rootDay,
        session: s,
      );

  /// วิชาที่ผูกไว้ (คาบเรียน)
  final int? subjectId;

  /// เวลาเริ่ม/เลิกจริง (บันทึกหลังเรียน ใช้ทำสถิติเลิกเร็ว/ช้า)
  final DateTime? actualStart;
  final DateTime? actualEnd;

  /// เลิกช้ากว่าแผนกี่นาที (ติดลบ = เลิกก่อน) · null = ยังไม่บันทึก
  int? get endDiffMinutes =>
      actualEnd == null || endAt == null ? null : actualEnd!.difference(endAt!).inMinutes;

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
        subjectId: r['subject_id'] as int?,
        actualStart: r['actual_start'] == null
            ? null
            : DateTime.parse(r['actual_start'] as String),
        actualEnd: r['actual_end'] == null
            ? null
            : DateTime.parse(r['actual_end'] as String),
        kind: activityKindOf(r['a_kind']),
        rootDay: r['root_day'] == null
            ? null
            : DateTime.parse(r['root_day'] as String),
      );
}

/// "ครั้งที่ n/N" ของงานซ้ำ · total null = งานไม่มี "ถึงวันที่"
class SessionCount {
  const SessionCount(this.n, this.total);

  final int n;
  final int? total;

  String get label => total == null ? 'ครั้งที่ $n' : 'ครั้งที่ $n/$total';

  @override
  bool operator ==(Object other) =>
      other is SessionCount && other.n == n && other.total == total;

  @override
  int get hashCode => Object.hash(n, total);

  @override
  String toString() => label;
}

/// ครั้งนี้ (วันที่ควรเกิด = [rootDay]) เป็นครั้งที่เท่าไหร่ของงาน [a]
///
/// นับทุกวันที่ควรเกิดตามกฎการทำซ้ำ → ครั้งที่ยกเลิกยังกินเลข (เนื้อหาครั้งนั้นหายไปจริง)
/// ส่วนครั้งที่ถูกเลื่อนใช้ [rootDay] ของวันเดิม จึงยังเป็นเลขเดิม
/// [a] ต้องเป็นข้อมูลเต็ม (โหมดเลือกวันเองต้องมีทุกวันใน dates)
///
/// [skipped] = วันที่ถูก "เลื่อนไปรอบถัดไป" → ไม่นับเลข (เนื้อหาไหลไปครั้งหน้า)
/// วันสุดท้ายถูกขยายให้แล้วตอนเลื่อน N จึงเท่าเดิม
SessionCount? sessionCount(Activity a, DateTime rootDay,
    {Set<DateTime> skipped = const {}}) {
  if (a.repeat == RepeatKind.none) return null;
  final root = dayOnly(rootDay);
  if (!occursOn(a, root) || skipped.contains(root)) return null;

  if (a.repeat == RepeatKind.dates) {
    final days = a.dates.values
        .map((d) => dayOnly(d.day))
        .where((d) => !skipped.contains(d))
        .toList()
      ..sort();
    return SessionCount(days.indexOf(root) + 1, days.length);
  }

  // ไม่มีวันสิ้นสุด → นับถึงวันนี้พอ (บอกได้แค่ n)
  final last = a.endDate == null ? root : dayOnly(a.endDate!);
  var count = 0;
  var n = 0;
  // สร้างวันด้วย DateTime(y, m, d + 1) แทน add(Duration) กันวันเพี้ยนช่วงเปลี่ยนเวลา (DST)
  for (var d = dayOnly(a.startDate);
      !d.isAfter(last);
      d = DateTime(d.year, d.month, d.day + 1)) {
    if (!occursOn(a, d) || skipped.contains(d)) continue;
    count++;
    if (d == root) n = count;
  }
  return SessionCount(n, a.endDate == null ? null : count);
}

/// "เลื่อนไปรอบถัดไป" ใช้ได้เฉพาะงานที่มีกฎการทำซ้ำ (ทุกวัน / ทุกสัปดาห์)
/// งานครั้งเดียว / เลือกวันเอง ไม่มีรอบถัดไปให้คำนวณ → ต้องเลือกวันเอง
bool canShiftToNextRound(Activity a) =>
    a.repeat == RepeatKind.daily ||
    (a.repeat == RepeatKind.weekly && a.weekdays.isNotEmpty);

/// วันแรกที่งานควรเกิด "หลัง" [day] ตามกฎการทำซ้ำ (ไม่สนวันสุดท้าย) · ใช้ขยายวันสุดท้าย
DateTime? nextSlotAfter(Activity a, DateTime day) {
  if (!canShiftToNextRound(a)) return null;
  final d = dayOnly(day);
  for (var i = 1; i <= 7; i++) {
    final c = DateTime(d.year, d.month, d.day + i);
    if (a.repeat == RepeatKind.daily || a.weekdays.contains(c.weekday)) return c;
  }
  return null;
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

/// id ของงานในวันเดียวกันที่เวลาทับกับงานอื่น (ไว้ทำกรอบแดงเตือน)
Set<int> clashingIds(List<Occurrence> dayItems) => {
      for (final o in dayItems)
        if (o.status == OccurrenceStatus.planned &&
            o.timed &&
            findOverlaps(dayItems, o.startAt!, o.endAt!, excludeId: o.id).isNotEmpty)
          o.id,
    };

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
/// (ชื่อ, สี, รหัสระบบ)
const List<(String, String, String?)> seedCategories = [
  ('เรียน', 'blue', studySystemKey),
  ('ออกกำลังกาย', 'green', null),
  ('สตรีม', 'purple', null),
  ('งาน', 'amber', null),
  ('อื่น ๆ', 'gray', null),
];

// ---------- ภาคเรียน + วันหยุด (v10) ----------

/// ภาคเรียน เช่น ปี 1 เทอม 1 · 2026-06-15 → 2026-10-16
/// term 3 = ภาคฤดูร้อน (ตรงกับ subject.plan_term)
class Term {
  const Term({
    required this.id,
    required this.year,
    required this.termNo,
    required this.start,
    required this.end,
  });

  final int id;
  final int year;
  final int termNo;
  final DateTime start;
  final DateTime end;

  String get label => termNo == 3 ? 'ปี $year · ภาคฤดูร้อน' : 'ปี $year · เทอม $termNo';

  /// วันนี้อยู่ในเทอมนี้ไหม (รวมวันแรกและวันสุดท้าย)
  bool contains(DateTime day) {
    final d = dayOnly(day);
    return !d.isBefore(start) && !d.isAfter(end);
  }

  factory Term.fromRow(Map<String, Object?> r) => Term(
        id: r['id'] as int,
        year: r['year'] as int,
        termNo: r['term_no'] as int,
        start: DateTime.parse(r['start_date'] as String),
        end: DateTime.parse(r['end_date'] as String),
      );
}

/// วันหยุด 1 วัน (วันหยุดราชการ / มหาลัยประกาศ)
class Holiday {
  const Holiday(this.day, this.name);
  final DateTime day;
  final String name;
}

/// งานเรียน/สอบที่ซ้ำกัน (ชื่อ · วิชา · ประเภท · เวลา · วันซ้ำ · ช่วงวัน ตรงกันหมด)
/// คืน id ที่ควรลบ · เก็บตัวที่ id น้อยสุด (ตัวแรกที่สร้าง) ไว้
/// ไม่แตะงานทั่วไป (todo/ติว) และงานแบบเลือกวันเอง เพราะอาจตั้งใจให้ชื่อซ้ำ
List<int> duplicateActivityIds(Iterable<Activity> activities) {
  final keep = <String, int>{};
  final remove = <int>[];
  final sorted = [...activities]..sort((a, b) => a.id.compareTo(b.id));
  for (final a in sorted) {
    if (a.kind != ActivityKind.classSession && a.kind != ActivityKind.exam) continue;
    if (a.repeat == RepeatKind.dates) continue;
    final key = [
      a.name, a.subjectId, a.kind.name, a.startMinute, a.durationMin, a.repeat.name,
      (a.weekdays.toList()..sort()).join(','), dayKey(a.startDate),
      a.endDate == null ? '' : dayKey(a.endDate!),
    ].join('|');
    if (keep.containsKey(key)) {
      remove.add(a.id);
    } else {
      keep[key] = a.id;
    }
  }
  return remove;
}
