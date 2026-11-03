import 'package:flutter/material.dart';

import '../widgets/page_scaffold.dart';

/// หน้า "ไฟล์": File Manager (Phase 3)
class FilesPage extends StatelessWidget {
  const FilesPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const PageScaffold(
      overline: 'File Manager',
      title: 'ไฟล์',
      children: [
        ComingSoonCard(
          icon: Icons.folder_outlined,
          message: 'โฟลเดอร์ต่อวิชา · ตั้งชื่ออัตโนมัติ · sync Google Drive — มาใน Phase 3',
        ),
      ],
    );
  }
}
