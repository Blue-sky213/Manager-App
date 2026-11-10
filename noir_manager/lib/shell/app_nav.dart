import 'package:flutter/foundation.dart';

/// คำขอ "เปิดปฏิทินที่วันนี้" จากหน้าอื่น (เช่น แตะวันสอบในหน้าวิชา)
///
/// ตัวเดียวทั้งแอป: shell สลับไปเมนูปฏิทิน · หน้าปฏิทินเลื่อนไปวันนั้น
/// ใช้ ChangeNotifier ไม่ใช่ ValueNotifier เพราะกดวันเดิมซ้ำก็ต้องพาไปอีกครั้ง
class CalendarJump extends ChangeNotifier {
  DateTime? day;

  void go(DateTime d) {
    day = DateTime(d.year, d.month, d.day);
    notifyListeners();
  }
}

final calendarJump = CalendarJump();

/// คำขอ "เปิดวิชานี้" จากหน้าอื่น (เช่น คลิกคาบเรียนในปฏิทิน) → shell สลับไปเมนูวิชา · หน้าวิชาเปิดวิชานั้น
class SubjectJump extends ChangeNotifier {
  int? subjectId;

  void go(int id) {
    subjectId = id;
    notifyListeners();
  }
}

final subjectJump = SubjectJump();

/// ย้อนกลับของทั้งแอป (เมาส์ปุ่ม 4 / ปุ่ม "กลับ") หลังปิดหน้าที่เปิดซ้อนไม่ได้แล้ว
/// ตัวที่ลงทะเบียนทีหลังได้ลองก่อน (หน้า → shell) · คืน true = จัดการแล้ว
class AppBack {
  final _handlers = <bool Function()>[];

  void add(bool Function() h) => _handlers.add(h);
  void remove(bool Function() h) => _handlers.remove(h);

  bool handle() {
    for (final h in _handlers.reversed.toList()) {
      if (h()) return true;
    }
    return false;
  }
}

final appBack = AppBack();

/// ชื่อเมนูที่เปิดอยู่ · หน้าที่ซ่อนอยู่ใน IndexedStack ใช้เช็กว่าตัวเองกำลังโชว์ไหม
final currentTab = ValueNotifier<String>('วันนี้');
