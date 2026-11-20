/// รายงาน "แก้ต่างกันบน 2 เครื่อง" แบบคนทั่วไปอ่านเข้าใจ (รอบ 20 · นัวร์ขอ)
/// ชื่อตาราง/ช่อง → คำไทย · นาที → 01:00 · สถานะ → คำไทย · บอกว่าเป็นรายการไหน (ชื่องาน / วันในสัปดาห์)
library;

import 'merge.dart';

const _tables = {
  'life_base': 'เวลาประจำวัน',
  'activity': 'งาน',
  'occurrence': 'งานในวัน',
  'checkin': 'เช็กอิน',
  'setting': 'ตั้งค่า',
  'category': 'หมวดงาน',
  'subject': 'วิชา',
  'sticker': 'สติกเกอร์',
  'sticker_pack': 'ชุดสติกเกอร์',
  'day_sticker': 'สติกเกอร์ในวัน',
  'project': 'โปรเจกต์',
  'project_task': 'งานในโปรเจกต์',
  'money_entry': 'รายการเงิน',
  'skill': 'สกิล',
  'skill_log': 'บันทึกสกิล',
  'class_log': 'บันทึกเรียน',
  'preset': 'แบบงาน',
  'holiday': 'วันหยุด',
};

const _fields = {
  'name': 'ชื่อ',
  'title': 'ชื่อ',
  'bed_minute': 'เวลานอน',
  'wake_minute': 'เวลาตื่น',
  'start_minute': 'เวลาเริ่ม',
  'duration_min': 'ความยาว',
  'status': 'สถานะ',
  'note': 'โน้ต',
  'reason': 'เหตุผล',
  'day': 'วัน',
  'start_date': 'วันเริ่ม',
  'end_date': 'วันสุดท้าย',
  'start_at': 'เวลาเริ่ม',
  'end_at': 'เวลาจบ',
  'importance': 'ความสำคัญ',
  'energy': 'พลัง',
  'value': 'ค่า',
  'amount': 'จำนวนเงิน',
  'color': 'สี',
  'emoji': 'อีโมจิ',
  'category_id': 'หมวด',
};

const _status = {
  'planned': 'ตามแผน',
  'done': 'ทำแล้ว',
  'cancelled': 'ยกเลิก',
  'moved': 'เลื่อนแล้ว',
  'shifted': 'เลื่อนไปรอบถัดไป',
  'inbox': 'รอวันใหม่',
};

const _weekdays = ['จันทร์', 'อังคาร', 'พุธ', 'พฤหัสบดี', 'ศุกร์', 'เสาร์', 'อาทิตย์'];

String _hm(int m) => '${(m ~/ 60 % 24).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}';

/// ค่าแบบอ่านง่าย
String conflictValue(String? field, Object? v) {
  if (field == null) return v == null ? 'ลบแล้ว' : 'ยังอยู่ (แก้ไว้)';
  if (v == null || v == '') return '(ว่าง)';
  if (field.endsWith('_minute') && v is num) return _hm(v.toInt());
  if (field == 'duration_min' && v is num) {
    final h = v ~/ 60, m = v.toInt() % 60;
    return [if (h > 0) '$h ชม.', if (m > 0) '$m นาที'].join(' ').ifEmpty('0 นาที');
  }
  if (field == 'status') return _status['$v'] ?? '$v';
  if ((field.endsWith('_at')) && v is String && v.length >= 16) return '${v.substring(8, 10)}/${v.substring(5, 7)} ${v.substring(11, 16)}';
  final s = '$v';
  return s.length > 40 ? '${s.substring(0, 40)}…' : s;
}

extension on String {
  String ifEmpty(String other) => isEmpty ? other : this;
}

/// หัวข้อ: "เวลาประจำวัน · วันจันทร์ · เวลานอน" / "งาน · ไลฟ์ RE4 · เวลาเริ่ม"
/// [row] = ค่าของรายการนั้นตอนนี้ (หาชื่อ) · null ได้
String conflictTitle(SyncConflict c, Map<String, Object?>? row) {
  final parts = <String>[_tables[c.table] ?? c.table];
  final r = row ?? const {};
  final who = r['name'] ?? r['title'];
  if (who != null && '$who'.isNotEmpty) {
    parts.add('$who');
  } else if (c.table == 'life_base' && r['weekday'] is num) {
    final w = (r['weekday'] as num).toInt();
    parts.add('วัน${_weekdays[(w - 1).clamp(0, 6)]}');
  } else if (r['day'] != null) {
    parts.add('${r['day']}');
  } else if (c.table == 'setting') {
    parts.add(c.id);
  }
  parts.add(c.field == null ? 'ลบ / แก้' : (_fields[c.field] ?? c.field!));
  return parts.join(' · ');
}
