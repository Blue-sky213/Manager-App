/// เมนู "งาน" (รอบ 9A · 9C · 22): แท็บ ภาพรวม (เปิดมาเจอ) · เข้างาน (เช็คอิน + ค่าจ้าง) · บอร์ด · ขั้นงานทั้งหมด · เงินแยกไปเมนูของตัวเอง
library;

import 'package:flutter/material.dart';

import '../widgets/menu_header.dart';
import '../work/checkin_page.dart';
import '../work/projects_page.dart';
import '../work/work_overview.dart';

enum WorkTab { overview, checkin, board, tasks }

class WorkPage extends StatefulWidget {
  const WorkPage({super.key});

  @override
  State<WorkPage> createState() => _WorkPageState();
}

class _WorkPageState extends State<WorkPage> {
  WorkTab _tab = WorkTab.overview;

  void _openProject(int id) {
    setState(() => _tab = WorkTab.board);
    projectOpenRequest.value = id;
  }

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        MenuHeader(
          group: 'งาน & เงิน',
          title: 'งาน',
          tabs: MenuTabs<WorkTab>(
            key: const Key('work-tabs'),
            value: _tab,
            items: const [(WorkTab.overview, 'ภาพรวม'), (WorkTab.checkin, 'เข้างาน'), (WorkTab.board, 'บอร์ด'), (WorkTab.tasks, 'ขั้นงานทั้งหมด')],
            onChanged: (t) => setState(() => _tab = t),
          ),
        ),
        Expanded(
          child: IndexedStack(index: _tab.index, children: [
            WorkOverview(onOpenProject: _openProject, onAllTasks: () => setState(() => _tab = WorkTab.tasks)),
            const CheckinView(),
            const ProjectsPage(),
            AllTasksView(onOpenProject: _openProject),
          ]),
        ),
      ]);
}
