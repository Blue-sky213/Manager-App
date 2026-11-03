import 'package:flutter/material.dart';

import '../utils/thai_date.dart';
import '../widgets/page_scaffold.dart';

/// หน้า "วันนี้": แผนรายวัน + ชั่วโมงนอน + Reminder Inbox (Phase 1)
class TodayPage extends StatelessWidget {
  const TodayPage({super.key});

  @override
  Widget build(BuildContext context) {
    return PageScaffold(
      overline: 'วันนี้',
      title: thaiShortDate(DateTime.now()),
      children: const [
        ComingSoonCard(
          icon: Icons.schedule,
          message: 'แผนรายวัน · ชั่วโมงนอน · Reminder Inbox — มาใน Phase 1',
        ),
      ],
    );
  }
}
