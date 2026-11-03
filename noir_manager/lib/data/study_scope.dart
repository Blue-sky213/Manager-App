import 'package:flutter/widgets.dart';

import 'study_repository.dart';

/// "ท่อส่ง" repository ลงไปให้ทุกหน้าในแอป
///
/// วางไว้บนสุดครั้งเดียว แล้วหน้าไหนอยากใช้ก็เรียก `StudyScope.of(context)`
/// ไม่ต้องส่งผ่าน constructor ทีละชั้น
class StudyScope extends InheritedWidget {
  const StudyScope({
    super.key,
    required this.repository,
    required super.child,
  });

  final StudyRepository repository;

  static StudyRepository of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<StudyScope>();
    assert(scope != null, 'ไม่พบ StudyScope เหนือ widget นี้');
    return scope!.repository;
  }

  @override
  bool updateShouldNotify(StudyScope oldWidget) =>
      repository != oldWidget.repository;
}
