/// เมนู "เงิน" (รอบ 9A · 9C): แยกจากงาน · แท็บ เดือนนี้ (ต้องจัดการขึ้นก่อน) · รายการ · ค่าบริการ · ลงทุน
/// งวดงานจากโปรเจกต์ยังไหลเข้ามาเอง
library;

import 'package:flutter/material.dart';

import '../widgets/menu_header.dart';
import '../work/finance_page.dart';

class MoneyPage extends StatefulWidget {
  const MoneyPage({super.key});

  @override
  State<MoneyPage> createState() => _MoneyPageState();
}

class _MoneyPageState extends State<MoneyPage> {
  MoneyView _view = MoneyView.overview;

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        MenuHeader(
          group: 'งาน & เงิน',
          title: 'เงิน',
          tabs: MenuTabs<MoneyView>(
            key: const Key('money-tabs'),
            value: _view,
            items: const [
              (MoneyView.overview, 'เดือนนี้'),
              (MoneyView.entries, 'รายการ'),
              (MoneyView.subs, 'ค่าบริการ'),
              (MoneyView.invest, 'ลงทุน'),
            ],
            onChanged: (v) => setState(() => _view = v),
          ),
        ),
        // หน้าเดียวเปลี่ยนมุมมอง → เดือนที่เลือก + ข้อมูลที่โหลดแล้วไม่หายตอนสลับแท็บ
        Expanded(child: FinancePage(view: _view)),
      ]);
}
