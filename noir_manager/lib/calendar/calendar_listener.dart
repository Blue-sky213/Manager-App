import 'package:flutter/widgets.dart';

import '../shell/app_nav.dart';
import '../study/subject_colors.dart';
import 'calendar_repository.dart';

/// mixin = "ชิ้นส่วนเสริม" ใส่ให้ State ไหนก็ได้
///
/// ทำ 3 อย่างให้อัตโนมัติ: หยิบ repository จาก CalendarScope · ฟังการเปลี่ยนแปลง
/// · เลิกฟังตอนหน้าถูกทิ้ง (ไม่งั้นหน่วยความจำรั่ว)
/// หน้าที่ใช้แค่เขียน [reload] ว่าจะโหลดอะไร
mixin CalendarListener<T extends StatefulWidget> on State<T> {
  CalendarRepository? calendar;

  Future<void> reload();

  /// หน้าหนักที่อยู่ในเมนูหลัก (IndexedStack เก็บไว้ทุกหน้า) ใส่ชื่อเมนู →
  /// ตอนซ่อนอยู่ ข้อมูลเปลี่ยนไม่โหลดทันที รอจนกลับมาเปิดหน้านี้ค่อยโหลดครั้งเดียว
  /// (เดิมกด "ทำแล้ว" ที่หน้าวันนี้ → หน้าสถิติที่ซ่อนอยู่โหลด 372 วันทุกครั้ง = หน่วง)
  String? get hiddenTab => null;
  bool _stale = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final repo = CalendarScope.of(context);
    if (repo != calendar) {
      calendar?.removeListener(_onChanged);
      calendar = repo..addListener(_onChanged);
      // เปลี่ยนสีวิชา → กล่องงานในปฏิทินเปลี่ยนสีตามทันที
      subjectColors.addListener(_onChanged);
      if (hiddenTab != null) currentTab.addListener(_onTab);
      reload();
    }
  }

  bool get _hidden =>
      hiddenTab != null && currentTab.value != hiddenTab && context.findAncestorWidgetOfExactType<IndexedStack>() != null;

  void _onChanged() {
    if (!mounted) return;
    if (_hidden) {
      _stale = true;
      return;
    }
    reload();
  }

  void _onTab() {
    if (_stale && mounted && !_hidden) {
      _stale = false;
      reload();
    }
  }

  @override
  void dispose() {
    calendar?.removeListener(_onChanged);
    subjectColors.removeListener(_onChanged);
    currentTab.removeListener(_onTab);
    super.dispose();
  }
}
