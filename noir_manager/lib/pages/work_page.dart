/// เมนู "งาน" (รอบ 8D/8E): สลับ โปรเจกต์ | การเงิน · ซ่อนเมนูนี้ได้ในตั้งค่า (คนที่ใช้แค่เรียน)
library;

import 'package:flutter/material.dart';

import '../widgets/mini_segments.dart';
import '../widgets/page_scaffold.dart';
import '../work/finance_page.dart';

class WorkPage extends StatefulWidget {
  const WorkPage({super.key});

  @override
  State<WorkPage> createState() => _WorkPageState();
}

class _WorkPageState extends State<WorkPage> {
  bool _money = true;

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
        child: Align(
          alignment: Alignment.centerLeft,
          child: SizedBox(
            width: 240,
            child: MiniSegments<bool>(
              key: const Key('work-switch'),
              value: _money,
              items: const [(false, 'โปรเจกต์'), (true, 'การเงิน')],
              onChanged: (v) => setState(() => _money = v),
            ),
          ),
        ),
      ),
      Expanded(
        child: IndexedStack(index: _money ? 1 : 0, children: const [
          PageScaffold(
            overline: 'งาน',
            title: 'โปรเจกต์',
            children: [ComingSoonCard(icon: Icons.view_kanban_outlined, message: 'บอร์ดโปรเจกต์ · งวดงาน · ทีม — มาในชุด 8E')],
          ),
          FinancePage(),
        ]),
      ),
    ]);
  }
}
