import 'package:flutter/material.dart';

import '../widgets/page_scaffold.dart';

/// หน้า "ปฏิทิน": Calendar Core — ใส่งาน ยกเลิก เลื่อน (Phase 1)
class CalendarPage extends StatelessWidget {
  const CalendarPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const PageScaffold(
      overline: 'Calendar Core',
      title: 'ปฏิทิน',
      children: [
        ComingSoonCard(
          icon: Icons.calendar_month_outlined,
          message: 'ตารางงาน · ยกเลิกพร้อมเหตุผล · เลื่อนพร้อมวันแทน — มาใน Phase 1',
        ),
      ],
    );
  }
}
