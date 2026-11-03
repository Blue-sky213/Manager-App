import 'package:flutter/material.dart';

import '../widgets/page_scaffold.dart';

/// หน้า "สถิติ": สรุป 3/6/9/12 เดือน (Phase 2)
class StatsPage extends StatelessWidget {
  const StatsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const PageScaffold(
      overline: 'Stats',
      title: 'สถิติ',
      children: [
        ComingSoonCard(
          icon: Icons.insights_outlined,
          message: 'สรุป 3 / 6 / 9 / 12 เดือน — มาใน Phase 2',
        ),
      ],
    );
  }
}
