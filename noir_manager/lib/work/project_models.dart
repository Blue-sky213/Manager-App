/// โปรเจกต์ (รอบ 8E): บอร์ดตามสถานะ · งวดงาน → การเงิน · ทีม + หน้าที่ · ขั้นงาน → ปฏิทิน · ไฟล์
library;

enum ProjectStatus { quote, confirmed, doing, delivered, paid }

String projectStatusText(ProjectStatus s) => switch (s) {
      ProjectStatus.quote => 'เสนอราคา',
      ProjectStatus.confirmed => 'ยืนยันแล้ว',
      ProjectStatus.doing => 'กำลังทำ',
      ProjectStatus.delivered => 'ส่งมอบ',
      ProjectStatus.paid => 'เก็บเงินแล้ว',
    };

/// แบบโปรเจกต์ (ตั้งชื่อหมวดเงิน / ไอคอน)
const projectTypes = [
  ('steam', '♨️', 'งานสตีม / ท่อ'),
  ('machine', '⚙️', 'ติดตั้งเครื่องจักร'),
  ('design', '📐', 'ออกแบบ'),
  ('web', '💻', 'เว็บ / ดิจิทัล'),
  ('channel', '🎬', 'ช่อง YouTube'),
  ('other', '📌', 'อื่น ๆ'),
];

(String, String, String) projectType(String id) => projectTypes.firstWhere((t) => t.$1 == id, orElse: () => projectTypes.last);

class Project {
  const Project({
    this.id = 0,
    required this.name,
    this.client,
    this.type = 'other',
    this.status = ProjectStatus.quote,
    this.price,
    this.start,
    this.due,
    this.travelMinutes,
    this.note,
  });

  final int id;
  final String name;
  final String? client;
  final String type;
  final ProjectStatus status;

  /// ราคางาน (บาท)
  final double? price;
  final DateTime? start;
  final DateTime? due;

  /// กันเวลาเดินทางต่อวัน (นาที)
  final int? travelMinutes;
  final String? note;

  Project copyWith({ProjectStatus? status}) => Project(
        id: id,
        name: name,
        client: client,
        type: type,
        status: status ?? this.status,
        price: price,
        start: start,
        due: due,
        travelMinutes: travelMinutes,
        note: note,
      );
}

/// คนในทีม + หน้าที่ (ลูกค้า / ผู้ตรวจรับ ก็ใส่ได้)
class ProjectMember {
  const ProjectMember({this.id = 0, required this.projectId, required this.name, this.role, this.duty});
  final int id;
  final int projectId;
  final String name;
  final String? role;
  final String? duty;
}

/// ขั้นงาน · [activityId] = ลงปฏิทินแล้ว
class ProjectTask {
  const ProjectTask({this.id = 0, required this.projectId, required this.title, this.owner, this.due, this.done = false, this.activityId});
  final int id;
  final int projectId;
  final String title;
  final String? owner;
  final DateTime? due;
  final bool done;
  final int? activityId;

  ProjectTask copyWith({bool? done, int? activityId}) => ProjectTask(
      id: id, projectId: projectId, title: title, owner: owner, due: due, done: done ?? this.done, activityId: activityId ?? this.activityId);
}

/// งวดงาน · รับเงินแล้ว = มีรายการรับเงิน [entryId] ในการเงิน
class ProjectPayment {
  const ProjectPayment({this.id = 0, required this.projectId, required this.label, required this.amount, this.condition, this.due, this.entryId});
  final int id;
  final int projectId;
  final String label;
  final double amount;
  final String? condition;
  final DateTime? due;
  final int? entryId;

  bool get received => entryId != null;

  ProjectPayment withEntry(int? entry) =>
      ProjectPayment(id: id, projectId: projectId, label: label, amount: amount, condition: condition, due: due, entryId: entry);
}

enum ProjectFileKind { image, file, link }

class ProjectFile {
  const ProjectFile({this.id = 0, required this.projectId, required this.kind, required this.path, required this.title, required this.addedAt});
  final int id;
  final int projectId;
  final ProjectFileKind kind;
  final String path;
  final String title;
  final DateTime addedAt;
}
