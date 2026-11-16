/// เมนู "เงิน" (รอบ 9A): แยกจากงาน · งวดงานจากโปรเจกต์ยังไหลเข้ามาเอง
library;

import 'package:flutter/material.dart';

import '../widgets/menu_header.dart';
import '../work/finance_page.dart';

class MoneyPage extends StatelessWidget {
  const MoneyPage({super.key});

  @override
  Widget build(BuildContext context) => const Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        MenuHeader(group: 'งาน & เงิน', title: 'เงิน'),
        Expanded(child: FinancePage()),
      ]);
}
