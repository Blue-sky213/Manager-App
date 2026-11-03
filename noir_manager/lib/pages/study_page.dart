import 'package:flutter/material.dart';

import '../widgets/page_scaffold.dart';

/// หน้า "วิชา": Study Tree + Mastery Score (Phase 1 ทดสอบกับวิชา DaVinci)
class StudyPage extends StatelessWidget {
  const StudyPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const PageScaffold(
      overline: 'Study Tree',
      title: 'วิชา',
      children: [
        ComingSoonCard(
          icon: Icons.account_tree_outlined,
          message: 'วิชา → บท → หัวข้อย่อย + คะแนนความเข้าใจ — มาใน Phase 1',
        ),
      ],
    );
  }
}
