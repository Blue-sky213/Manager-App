import 'package:flutter/widgets.dart';

import 'calendar_repository.dart';

/// mixin = "ชิ้นส่วนเสริม" ใส่ให้ State ไหนก็ได้
///
/// ทำ 3 อย่างให้อัตโนมัติ: หยิบ repository จาก CalendarScope · ฟังการเปลี่ยนแปลง
/// · เลิกฟังตอนหน้าถูกทิ้ง (ไม่งั้นหน่วยความจำรั่ว)
/// หน้าที่ใช้แค่เขียน [reload] ว่าจะโหลดอะไร
mixin CalendarListener<T extends StatefulWidget> on State<T> {
  CalendarRepository? calendar;

  Future<void> reload();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final repo = CalendarScope.of(context);
    if (repo != calendar) {
      calendar?.removeListener(_onChanged);
      calendar = repo..addListener(_onChanged);
      reload();
    }
  }

  void _onChanged() {
    if (mounted) reload();
  }

  @override
  void dispose() {
    calendar?.removeListener(_onChanged);
    super.dispose();
  }
}
