/// เมนู "สกิล" (รอบ 9B): แท็บ แผนผัง (ภาพรวมแบบเกม) | รายการ (หน้าสกิลเดิม รอบ 8C)
library;

import 'package:flutter/material.dart';

import '../calendar/calendar_repository.dart';
import '../skills/skill_forms.dart';
import '../skills/skill_tree_view.dart';
import '../skills/skills_page.dart';
import '../widgets/menu_header.dart';

enum SkillTab { tree, list }

class SkillMenuPage extends StatefulWidget {
  const SkillMenuPage({super.key});

  @override
  State<SkillMenuPage> createState() => _SkillMenuPageState();
}

class _SkillMenuPageState extends State<SkillMenuPage> {
  SkillTab _tab = SkillTab.tree;

  void _openSkill(int id) {
    setState(() => _tab = SkillTab.list);
    skillOpenRequest.value = id;
  }

  Future<void> _add() async {
    final id = await editSkillForm(context, CalendarScope.of(context).skillRepo);
    if (id != null && _tab == SkillTab.list) skillOpenRequest.value = id;
  }

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        MenuHeader(
          group: 'พัฒนาตัวเอง',
          title: 'สกิล',
          tabs: MenuTabs<SkillTab>(
            key: const Key('skill-tabs'),
            value: _tab,
            items: const [(SkillTab.tree, 'แผนผัง'), (SkillTab.list, 'รายการ')],
            onChanged: (t) => setState(() => _tab = t),
          ),
          action: TextButton.icon(key: const Key('skill-add-top'), onPressed: _add, icon: const Icon(Icons.add, size: 18), label: const Text('สกิล')),
        ),
        Expanded(
          child: IndexedStack(index: _tab.index, children: [
            SkillTreeView(onOpenSkill: _openSkill),
            const SkillsPage(),
          ]),
        ),
      ]);
}
