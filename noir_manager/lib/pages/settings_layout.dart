/// หน้าตั้งค่าแบบแยกหมวด (รอบ 21 · preview https://claude.ai/artifact/FhPruzV6eMYQJh48fNRGzS)
/// คอม / แท็บเล็ต = รายการหมวดซ้าย + รายละเอียดขวา · มือถือ = รายการหมวด → กดเข้าทีละหน้า
/// ตัวหนังสือไม่เล็กกว่า 13 · แถวกดสูงอย่างน้อย 56 (กดง่ายบนมือถือ)
library;

import 'package:flutter/material.dart';

import '../sync/cloud_sync.dart';
import '../theme/noir_colors.dart';

class SettingsCategory {
  const SettingsCategory(this.id, this.title, this.icon, this.summary, this.sections);

  final String id;
  final String title;
  final IconData icon;

  /// บอกสั้น ๆ ว่ามีอะไรข้างใน (ใช้ค้นหาด้วย)
  final String summary;
  final List<Widget> sections;
}

/// กลุ่มหมวด (เว้นช่องระหว่างกลุ่มเหมือนตั้งค่าในโทรศัพท์)
const _groups = [
  ['display', 'mode'],
  ['calendar', 'study', 'sticker'],
  ['account', 'devices', 'data'],
  ['test', 'about'],
];

class SettingsCategoryList extends StatelessWidget {
  const SettingsCategoryList({
    super.key,
    required this.cats,
    required this.selected,
    required this.query,
    required this.onQuery,
    required this.onOpen,
  });

  final List<SettingsCategory> cats;

  /// หมวดที่เปิดอยู่ (จอกว้าง) · null = มือถือ
  final String? selected;
  final String query;
  final ValueChanged<String> onQuery;
  final ValueChanged<String> onOpen;

  @override
  Widget build(BuildContext context) {
    final c = context.noir;
    final q = query.trim().toLowerCase();
    bool hit(SettingsCategory x) => q.isEmpty || '${x.title} ${x.summary}'.toLowerCase().contains(q);
    final byId = {for (final x in cats) x.id: x};
    final groups = [
      for (final g in _groups) [for (final id in g) if (byId[id] case final x? when hit(x)) x],
    ].where((g) => g.isNotEmpty).toList();

    return ColoredBox(
      color: selected == null ? Colors.transparent : c.surface2,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          TextField(
            key: const Key('settings-search'),
            onChanged: onQuery,
            style: const TextStyle(fontSize: 15),
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: 'ค้นหาการตั้งค่า',
              isDense: true,
            ),
          ),
          const SizedBox(height: 12),
          _AccountCard(onTap: () => onOpen('account'), selected: selected == 'account'),
          for (final g in groups) ...[
            const SizedBox(height: 12),
            Material(
              color: c.surface,
              borderRadius: BorderRadius.circular(12),
              clipBehavior: Clip.antiAlias,
              child: Column(children: [
                for (final (i, x) in g.indexed) ...[
                  if (i > 0) Divider(height: 1, indent: 56, color: c.line),
                  _CatTile(cat: x, selected: x.id == selected, onTap: () => onOpen(x.id)),
                ],
              ]),
            ),
          ],
          if (groups.isEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text('ไม่พบการตั้งค่าที่ตรงกับ "$query"', style: TextStyle(fontSize: 14, color: c.muted)),
            ),
        ],
      ),
    );
  }
}

class _CatTile extends StatelessWidget {
  const _CatTile({required this.cat, required this.selected, required this.onTap});
  final SettingsCategory cat;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.noir;
    return InkWell(
      key: Key('set-cat-${cat.id}'),
      onTap: onTap,
      child: Container(
        color: selected ? c.accent.withValues(alpha: 0.14) : null,
        constraints: const BoxConstraints(minHeight: 60),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(color: c.accent.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(9)),
            child: Icon(cat.icon, size: 19, color: c.accent),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(cat.title, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: c.text)),
              Text(cat.summary, style: TextStyle(fontSize: 13, color: c.muted), maxLines: 2, overflow: TextOverflow.ellipsis),
            ]),
          ),
          Icon(Icons.chevron_right, color: c.muted),
        ]),
      ),
    );
  }
}

/// การ์ดบัญชีบนสุด (เหมือนโปรไฟล์ในตั้งค่าโทรศัพท์)
class _AccountCard extends StatelessWidget {
  const _AccountCard({required this.onTap, required this.selected});
  final VoidCallback onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final c = context.noir;
    final s = CloudSyncService.instance;
    Widget card(String title, String sub) => Material(
          color: selected ? c.accent.withValues(alpha: 0.14) : c.surface,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            key: const Key('set-account-card'),
            borderRadius: BorderRadius.circular(12),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor: c.accent,
                  child: Text(title.isEmpty ? '?' : title.characters.first.toUpperCase(),
                      style: TextStyle(color: c.onAccent, fontWeight: FontWeight.w600)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(title, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: c.text), overflow: TextOverflow.ellipsis),
                    Text(sub, style: TextStyle(fontSize: 13, color: c.muted)),
                  ]),
                ),
                Icon(Icons.chevron_right, color: c.muted),
              ]),
            ),
          ),
        );
    if (s == null) return card('ข้อมูลในเครื่อง', 'ไม่ได้เชื่อมบัญชี');
    return ValueListenableBuilder(
      valueListenable: s.status,
      builder: (context, st, _) => st.state == CloudState.signedOut
          ? card('ยังไม่ได้เข้าระบบ', 'แตะเพื่อเข้าระบบและซิงก์ข้ามเครื่อง')
          : card(st.email ?? '', switch (st.state) {
              CloudState.offline => 'ออฟไลน์ · ${st.pending} รายการรอส่ง',
              CloudState.error => 'ซิงก์ไม่สำเร็จ · แตะเพื่อดู',
              CloudState.syncing => 'กำลังบันทึก…',
              _ => 'ออนไลน์ · บันทึกแล้ว',
            }),
    );
  }
}

/// เนื้อหาของหมวด (ฝั่งขวาบนคอม)
class SettingsCategoryBody extends StatelessWidget {
  const SettingsCategoryBody({super.key, required this.cat, this.showTitle = true});
  final SettingsCategory cat;
  final bool showTitle;

  @override
  Widget build(BuildContext context) {
    final c = context.noir;
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        // จอกว้างมากไม่ยืดเต็ม → อ่านง่าย
        constraints: const BoxConstraints(maxWidth: 760),
        child: ListView(
          key: Key('set-body-${cat.id}'),
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          children: [
            if (showTitle) ...[
              Text('ตั้งค่า › ${cat.title}', style: TextStyle(fontSize: 13, color: c.muted)),
              const SizedBox(height: 4),
              Text(cat.title, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600, color: c.text)),
              const SizedBox(height: 12),
            ],
            for (final (i, w) in cat.sections.indexed) ...[if (i > 0) const SizedBox(height: 14), w],
          ],
        ),
      ),
    );
  }
}

/// หน้าหมวดบนมือถือ (กดเข้ามาจากรายการ)
class SettingsCategoryPage extends StatelessWidget {
  const SettingsCategoryPage({super.key, required this.cat});
  final SettingsCategory cat;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(cat.title)),
        body: SettingsCategoryBody(cat: cat, showTitle: false),
      );
}
