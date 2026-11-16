/// เมนู "งาน" (รอบ 9A): โปรเจกต์ · เงินแยกไปเมนูของตัวเอง
library;

import 'package:flutter/material.dart';

import '../widgets/menu_header.dart';
import '../work/projects_page.dart';

class WorkPage extends StatelessWidget {
  const WorkPage({super.key});

  @override
  Widget build(BuildContext context) => const Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        MenuHeader(group: 'งาน & เงิน', title: 'งาน'),
        Expanded(child: ProjectsPage()),
      ]);
}
