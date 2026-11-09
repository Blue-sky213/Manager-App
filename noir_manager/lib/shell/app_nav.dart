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
