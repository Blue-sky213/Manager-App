/// ข้อมูลตัวอย่างส่วน สกิล · งาน · เงิน · ชีวิต (รอบ 9D) · ต่อจากข้อมูลตัวอย่าง 1 ปี (demo_year)
///
/// กฎ (นัวร์อนุมัติรอบ 9 · 16 พ.ย. 2569):
/// - สกิล: 4 สาย · 7 สกิล · ทักษะย่อย 2–4 · DaVinci 8 สัปดาห์ (เวลาตัดคลิป 2:40 → ~1:42 มีขึ้นลง) · English คำศัพท์ 30 วัน
///   · Drawing พักไว้ · Premiere จบแล้ว · Thumbnail ต้องผ่าน Photoshop ก่อน · Portfolio 6 ชิ้น
/// - งาน: 5 โปรเจกต์ครบทุกสถานะ · งวดรวม = ราคางาน · ทีม 2–3 คน · ขั้นงาน 4–6 (เลยกำหนด 1)
/// - เงิน: 12 เดือน · รายจ่าย ~8 รายการ/สัปดาห์ · ค่าบริการ 4 (รายปี 1 · ยอดไม่แน่นอน 1) · ลงทุน 1 (คืน ~22%) · งบค่าบริการ ฿1,000
/// - ชีวิต: เช็กอินเช้า 60 วัน (นอน 5–8 ชม. · พลัง 1–5) · งานฝึกสกิลช่วงค่ำ อ/พฤ 21:00 ไม่ชนคาบ
/// - อยู่ในหน่วยความจำของโหมดตัวอย่างเท่านั้น (ปิดโหมด = หายทั้งชุด) · seed ตายตัว
library;

import 'dart:math';

import '../calendar/calendar_models.dart';
import '../calendar/calendar_repository.dart';
import '../skills/skill_models.dart';
import '../skills/skill_tree.dart';
import '../work/money_calc.dart';
import '../work/money_models.dart';
import '../work/project_models.dart';

DateTime _d(DateTime d) => DateTime(d.year, d.month, d.day);

Future<void> fillDemoLife(CalendarRepository cal, DateTime today, {int seed = 2569}) async {
  final now = _d(today);
  final rnd = Random(seed);
  DateTime ago(int days) => now.subtract(Duration(days: days));
  await _skills(cal, now, rnd, ago);
  await _work(cal, now, ago);
  await _money(cal, now, rnd, ago);
  await _life(cal, now, rnd, ago);
}

// ---------------- สกิล ----------------

Future<void> _skills(CalendarRepository cal, DateTime now, Random rnd, DateTime Function(int) ago) async {
  final r = cal.skillRepo;
  final edit = await r.saveBranch(const SkillBranch(name: 'ตัดต่อ', icon: '🎬', colorKey: 'purple', sort: 0));
  final lang = await r.saveBranch(const SkillBranch(name: 'ภาษา', icon: '🗣️', colorKey: 'sky', sort: 1));
  final art = await r.saveBranch(const SkillBranch(name: 'ศิลปะ', icon: '🎨', colorKey: 'pink', sort: 2));
  final stream = await r.saveBranch(const SkillBranch(name: 'สตรีม', icon: '🎮', colorKey: 'mint', sort: 3));

  Future<int> skill(String name, String icon, int branch, int startAgo,
          {SkillStatus status = SkillStatus.active, int? doneAgo, String? why}) =>
      r.saveSkill(Skill(
          name: name,
          icon: icon,
          branchId: branch,
          why: why,
          status: status,
          startedAt: ago(startAgo),
          doneAt: doneAgo == null ? null : ago(doneAgo)));
  Future<void> nodes(int skillId, List<String> names, int done) async {
    for (final (i, n) in names.indexed) {
      await r.saveNode(SkillNode(skillId: skillId, name: n, sort: i, done: i < done));
    }
  }

  // DaVinci: เป้าเร็วขึ้น · ฝึก อ/พฤ 8 สัปดาห์ · 2:40 → ~1:42
  final dv = await skill('DaVinci Resolve', '🎬', edit, 60, why: 'ตัดคลิปสตรีมเอง');
  final dvGoal = await r.saveGoal(SkillGoal(skillId: dv, kind: GoalKind.faster, title: 'ตัดคลิป 1 ชม.', unit: 'นาที', target: 90));
  await nodes(dv, ['Cut', 'Color', 'Fairlight', 'Fusion'], 1);
  final dvDays = [
    for (var w = 7; w >= 0; w--)
      for (final wd in [DateTime.tuesday, DateTime.thursday])
        if (ago(w * 7 + now.weekday - wd) case final d when d.isBefore(now)) d
  ];
  for (final (i, day) in dvDays.indexed) {
    final trend = 160 - (58 * i / (dvDays.length - 1));
    final v = (trend + (rnd.nextDouble() * 12 - 6)).roundToDouble();
    await r.saveLog(SkillLog(skillId: dv, goalId: dvGoal, day: day, minutes: v.round() + 10, value: v, rating: 3 + rnd.nextInt(2)));
  }
  final dvLog = (await r.logs(dv)).first.id;
  for (final (i, t) in ['คลิป Live CS2 #12', 'คลิป Live CS2 #15', 'Highlight ประจำเดือน'].indexed) {
    await r.saveFile(SkillFile(
        skillId: dv,
        logId: i == 0 ? dvLog : null,
        kind: SkillFileKind.link,
        path: 'https://youtu.be/demo-dv-$i',
        title: t,
        featured: i == 2,
        addedAt: ago(5 + i * 9)));
  }

  // Premiere: จบแล้ว (ก่อนย้ายไป DaVinci)
  final pr = await skill('Premiere Pro', '✂️', edit, 120, status: SkillStatus.done, doneAgo: 40);
  for (var i = 0; i < 12; i++) {
    await r.saveLog(SkillLog(skillId: pr, day: ago(115 - i * 6), minutes: 120, rating: 3));
  }
  await r.saveFile(SkillFile(skillId: pr, kind: SkillFileKind.link, path: 'https://youtu.be/demo-pr', title: 'คลิปแรกที่ตัดเอง', addedAt: ago(60)));

  // English: คำศัพท์ 10 คำ/วัน · 30 วัน
  final en = await skill('English', '🇬🇧', lang, 30, why: 'อ่าน doc / ดูคลิปไม่ต้องซับ');
  final enGoal = await r.saveGoal(SkillGoal(skillId: en, kind: GoalKind.count, title: 'คำศัพท์ใหม่', unit: 'คำ', target: 10, streak: 14));
  await nodes(en, ['Vocab', 'Listening', 'Speaking'], 0);
  for (var i = 30; i >= 1; i--) {
    if (rnd.nextDouble() < 0.15) continue; // บางวันไม่ได้ฝึก
    await r.saveLog(SkillLog(skillId: en, goalId: enGoal, day: ago(i), minutes: 20, value: (6 + rnd.nextInt(9)).toDouble()));
  }

  // Drawing: พักไว้
  final dr = await skill('Drawing', '🎨', art, 100, status: SkillStatus.paused);
  await nodes(dr, ['Line', 'Shading'], 1);
  for (var i = 0; i < 6; i++) {
    await r.saveLog(SkillLog(skillId: dr, day: ago(90 - i * 5), minutes: 30));
  }

  // Photoshop: เป้าด่าน (ผ่าน 2 / 4)
  final ps = await skill('Photoshop', '🎨', art, 45);
  await r.saveGoal(SkillGoal(
      skillId: ps,
      kind: GoalKind.milestone,
      title: 'ทำปกคลิปเอง',
      steps: const [GoalStep('Layer', done: true), GoalStep('Mask', done: true), GoalStep('Retouch'), GoalStep('ปกคลิป ≤ 30 นาที')]));
  for (var i = 0; i < 8; i++) {
    await r.saveLog(SkillLog(skillId: ps, day: ago(42 - i * 5), minutes: 45));
  }
  for (final (i, t) in ['ปก Live #14', 'ปก Highlight'].indexed) {
    await r.saveFile(SkillFile(skillId: ps, kind: SkillFileKind.link, path: 'https://example.com/demo-ps-$i', title: t, addedAt: ago(8 + i * 10)));
  }

  // Thumbnail: ต้องผ่าน Photoshop ก่อน (ล็อก · ยังไม่มีบันทึก)
  final th = await skill('Thumbnail', '🖌️', stream, 10);
  await r.addNeed(th, ps);

  // OBS: เป้าด่าน ตั้ง Scene (ผ่าน 3 / 5)
  final obs = await skill('OBS', '📡', stream, 50);
  await r.saveGoal(SkillGoal(skillId: obs, kind: GoalKind.milestone, title: 'ตั้ง Scene ครบ 5', steps: const [
    GoalStep('เริ่มไลฟ์', done: true),
    GoalStep('เกม', done: true),
    GoalStep('พัก', done: true),
    GoalStep('จบไลฟ์'),
    GoalStep('Replay'),
  ]));
  for (var i = 0; i < 5; i++) {
    await r.saveLog(SkillLog(skillId: obs, day: ago(48 - i * 9), minutes: 50));
  }

  // งานฝึกในปฏิทิน: DaVinci อ/พฤ 21:00 (หลังวิ่ง 17:30 · ก่อนนอน) ผูกกับสกิล
  final cats = await cal.categories();
  final cat = cats.where((c) => c.name.contains('สกิล') || c.name.contains('พัฒนา')).firstOrNull?.id ?? cats.first.id;
  final act = await cal.addActivity(NewActivity(
    name: 'ฝึก · DaVinci Resolve',
    categoryId: cat,
    importance: 2,
    timed: true,
    day: ago(56),
    startMinute: 21 * 60,
    durationMin: 60,
    repeat: RepeatKind.weekly,
    weekdays: {2, 4},
    endDate: now.add(const Duration(days: 60)),
    flexible: true,
  ));
  await r.linkActivity(dv, act);
  // วันที่มีบันทึก DaVinci = งานฝึกวันนั้น "ทำแล้ว" (ข้อมูลสองที่ตรงกัน)
  for (final day in dvDays) {
    for (final o in await cal.occurrencesOn(day)) {
      if (o.activityId == act) await cal.setDone(o.id, true);
    }
  }
}

// ---------------- งาน ----------------

Future<void> _work(CalendarRepository cal, DateTime now, DateTime Function(int) ago) async {
  final w = cal.workRepo;
  DateTime ahead(int days) => now.add(Duration(days: days));

  Future<void> team(int pj, List<(String, String, String)> people) async {
    for (final (n, role, duty) in people) {
      await w.saveMember(ProjectMember(projectId: pj, name: n, role: role, duty: duty));
    }
  }

  Future<void> tasks(int pj, List<(String, String?, DateTime, bool)> list) async {
    for (final (t, owner, due, done) in list) {
      await w.saveTask(ProjectTask(projectId: pj, title: t, owner: owner, due: due, done: done));
    }
  }

  /// งวด: (ชื่อ, ยอด, ครบกำหนด, วันที่รับ null = ยังไม่รับ)
  Future<void> pays(Project p, int pj, List<(String, double, DateTime, DateTime?)> list) async {
    for (final (label, amount, due, got) in list) {
      int? entry;
      if (got != null) {
        entry = await w.saveEntry(
            MoneyEntry(day: got, kind: MoneyKind.income, amount: amount, category: 'งวดงาน', note: '${p.name} · $label', projectId: pj));
      }
      await w.savePayment(ProjectPayment(projectId: pj, label: label, amount: amount, due: due, entryId: entry));
    }
  }

  Future<void> cost(int pj, DateTime day, double amount, String note) =>
      w.saveEntry(MoneyEntry(day: day, kind: MoneyKind.expense, amount: amount, category: 'วัสดุ / ค่าแรง', note: note, projectId: pj));

  // 1 · กำลังทำ
  var p = Project(name: 'ท่อไอน้ำ โรงงาน A', client: 'โรงงาน A', type: 'steam', status: ProjectStatus.doing, price: 180000,
      start: ago(40), due: ahead(34), travelMinutes: 45);
  var id = await w.saveProject(p);
  await team(id, [('ช่าง ก', 'หัวหน้าช่าง', 'เดินท่อ · เชื่อม'), ('ช่าง ข', 'ช่างเชื่อม', 'เชื่อม'), ('คุณสมชาย', 'ลูกค้า', 'ตรวจรับ')]);
  await tasks(id, [
    ('สำรวจหน้างาน', 'ช่าง ก', ago(38), true),
    ('สั่งท่อ + วาล์ว', null, ago(30), true),
    ('เดินท่อ ชั้น 1', 'ช่าง ก', ago(10), true),
    ('เดินท่อ ชั้น 2', 'ช่าง ก', ago(2), false), // เลยกำหนด
    ('ทดสอบแรงดัน', 'ช่าง ข', ahead(12), false),
    ('ส่งมอบ + ตรวจรับ', null, ahead(34), false),
  ]);
  await pays(p, id, [('งวด 1 มัดจำ', 54000, ago(38), ago(35)), ('งวด 2', 72000, ahead(14), null), ('งวด 3', 54000, ahead(34), null)]);
  await cost(id, ago(30), 38500, 'ท่อ + วาล์ว');
  await cost(id, ago(12), 12000, 'ค่าแรงช่าง');

  // 2 · เสนอราคา
  p = Project(name: 'ท่อไอน้ำ B', client: 'บริษัท B', type: 'steam', status: ProjectStatus.quote, price: 180000, due: ahead(90));
  id = await w.saveProject(p);
  await team(id, [('ช่าง ก', 'หัวหน้าช่าง', 'ประเมินงาน'), ('คุณวิภา', 'ลูกค้า', 'จัดซื้อ')]);
  await tasks(id, [
    ('สำรวจหน้างาน', 'ช่าง ก', ahead(4), false),
    ('ทำใบเสนอราคา', null, ahead(7), false),
    ('นัดคุยราคา', null, ahead(12), false),
    ('รอยืนยัน', null, ahead(20), false),
  ]);
  await pays(p, id, [('มัดจำ 50%', 90000, ahead(30), null), ('ส่งมอบ 50%', 90000, ahead(90), null)]);

  // 3 · ยืนยันแล้ว
  p = Project(name: 'ออกแบบ Heatpipe C', client: 'ร้าน C', type: 'design', status: ProjectStatus.confirmed, price: 45000,
      start: ahead(2), due: ahead(30));
  id = await w.saveProject(p);
  await team(id, [('นัวร์', 'ผู้ออกแบบ', 'แบบ 3D + แบบก่อสร้าง'), ('คุณต้น', 'ลูกค้า', 'อนุมัติแบบ')]);
  await tasks(id, [
    ('เก็บความต้องการ', null, ahead(3), false),
    ('แบบร่าง', null, ahead(10), false),
    ('แก้ตามคอมเมนต์', null, ahead(20), false),
    ('ส่งแบบ Heatpipe', null, ahead(30), false),
  ]);
  await pays(p, id, [('มัดจำ 50%', 22500, ahead(5), null), ('ส่งแบบ 50%', 22500, ahead(30), null)]);

  // 4 · ส่งมอบแล้ว (งวดสุดท้ายเลยกำหนด → ขึ้น "ต้องจัดการ" ในเงิน)
  p = Project(name: 'เว็บ mecsteam.com', client: 'MEC Steam', type: 'web', status: ProjectStatus.delivered, price: 25000,
      start: ago(70), due: ago(8));
  id = await w.saveProject(p);
  await team(id, [('นัวร์', 'Dev', 'หน้าเว็บ + Deploy'), ('คุณเมย์', 'ลูกค้า', 'ตรวจเนื้อหา')]);
  await tasks(id, [
    ('โครงหน้าเว็บ', null, ago(60), true),
    ('หน้า Products', null, ago(40), true),
    ('หน้า Contact', null, ago(20), true),
    ('Deploy + โดเมน', null, ago(10), true),
    ('สอนลูกค้าแก้เนื้อหา', null, ago(8), true),
  ]);
  await pays(p, id, [('งวด 1', 7500, ago(68), ago(66)), ('งวด 2', 10000, ago(38), ago(36)), ('งวด 3', 7500, ago(3), null)]);

  // 5 · เก็บเงินแล้ว (กำไร ฿12,400)
  p = Project(name: 'ติดตั้งปั๊ม D', client: 'โรงงาน D', type: 'machine', status: ProjectStatus.paid, price: 38000,
      start: ago(95), due: ago(50));
  id = await w.saveProject(p);
  await team(id, [('ช่าง ก', 'หัวหน้าช่าง', 'ติดตั้ง'), ('ช่าง ค', 'ผู้ช่วย', 'ยก + เดินสาย'), ('คุณเอก', 'ลูกค้า', 'ตรวจรับ')]);
  await tasks(id, [
    ('สำรวจ + วัดขนาด', 'ช่าง ก', ago(92), true),
    ('สั่งปั๊ม', null, ago(85), true),
    ('ติดตั้ง', 'ช่าง ก', ago(60), true),
    ('ทดสอบ + ส่งมอบ', 'ช่าง ค', ago(50), true),
  ]);
  await pays(p, id, [('มัดจำ', 19000, ago(90), ago(89)), ('ส่งมอบ', 19000, ago(50), ago(46))]);
  await cost(id, ago(84), 21600, 'ปั๊ม + อุปกรณ์');
  await cost(id, ago(60), 4000, 'ค่าแรงผู้ช่วย');
}

// ---------------- เงิน ----------------

const _subs = [
  Subscription(name: 'Adobe Creative Cloud', amount: 969, billDay: 5),
  Subscription(name: 'บริการ AI', amount: 700, billDay: 18),
  Subscription(name: 'โดเมน mecsteam.com', amount: 600, cycle: BillCycle.yearly, billDay: 20, billMonth: 3),
  Subscription(name: 'ค่าไฟห้อง (ยอดไม่แน่นอน)', billDay: 25),
];

Future<void> _money(CalendarRepository cal, DateTime now, Random rnd, DateTime Function(int) ago) async {
  final w = cal.workRepo;
  await cal.setSetting(subBudgetKey, '1000');
  final start = DateTime(now.year - 1, now.month + 1, 1); // 12 เดือนรวมเดือนนี้

  // ค่าบริการ: ติ๊กตรงวันตัดทุกเดือนที่ถึงแล้ว (รายปีเฉพาะเดือนนั้น · ยอดไม่แน่นอน = สุ่ม)
  for (final s in _subs) {
    final id = await w.saveSubscription(s);
    for (var m = start; !m.isAfter(now); m = DateTime(m.year, m.month + 1)) {
      final due = billDateIn(s, m);
      if (due == null || due.isAfter(now) || due.isBefore(start)) continue;
      // เดือนนี้ "บริการ AI" ยังไม่ติ๊ก → ใกล้ตัด/เลยวันตัด ให้เห็นในต้องจัดการ
      if (s.name == 'บริการ AI' && m.year == now.year && m.month == now.month) continue;
      await w.saveEntry(MoneyEntry(
          day: due,
          kind: MoneyKind.expense,
          amount: s.amount ?? (380 + rnd.nextInt(180)).toDouble(),
          category: 'ค่าบริการ',
          note: s.name,
          subscriptionId: id));
    }
  }

  // เงินลงทุน: คอมสตรีม ฿45,000 · สปอนเซอร์ช่วยคืนทุน 3 ครั้ง (22%)
  final inv = await w.saveInvestment(Investment(name: 'คอมสตรีม', amount: 45000, startDay: ago(300), note: 'ข้อมูลตัวอย่าง'));
  for (final (i, days) in [200, 120, 40].indexed) {
    await w.saveEntry(MoneyEntry(
        day: ago(days), kind: MoneyKind.income, amount: 3300, category: 'สปอนเซอร์', note: 'สปอนเซอร์ไลฟ์ #${i + 1}', investmentId: inv));
  }

  // รายวัน: อาหาร ~5 ครั้ง/สัปดาห์ · เดินทาง ~2 · บ้าน/อุปกรณ์ นาน ๆ ที · งานรับจ้าง 2 งาน/เดือน
  for (var d = start; !d.isAfter(now); d = DateTime(d.year, d.month, d.day + 1)) {
    if (rnd.nextDouble() < 0.72) {
      await w.saveEntry(MoneyEntry(day: d, kind: MoneyKind.expense, amount: (60 + rnd.nextInt(13) * 10).toDouble(), category: 'อาหาร'));
    }
    if (rnd.nextDouble() < 0.28) {
      await w.saveEntry(MoneyEntry(day: d, kind: MoneyKind.expense, amount: (40 + rnd.nextInt(9) * 10).toDouble(), category: 'เดินทาง'));
    }
    if (rnd.nextDouble() < 0.03) {
      await w.saveEntry(MoneyEntry(
          day: d, kind: MoneyKind.expense, amount: (300 + rnd.nextInt(12) * 100).toDouble(), category: 'อุปกรณ์', note: 'สายไฟ / อะไหล่'));
    }
    if (d.day == 1) {
      await w.saveEntry(MoneyEntry(day: d, kind: MoneyKind.expense, amount: 3500, category: 'บ้าน', note: 'ค่าหอ'));
    }
    if (d.day == 10 || d.day == 24) {
      await w.saveEntry(MoneyEntry(
          day: d, kind: MoneyKind.income, amount: (3000 + rnd.nextInt(10) * 500).toDouble(), category: 'งานรับจ้าง', note: 'ตัดคลิปให้ลูกค้า'));
    }
  }
}

// ---------------- ชีวิต ----------------

Future<void> _life(CalendarRepository cal, DateTime now, Random rnd, DateTime Function(int) ago) async {
  for (var i = 60; i >= 1; i--) {
    final day = ago(i);
    final sleepMin = 5 * 60 + rnd.nextInt(3 * 60 + 1); // 5–8 ชม.
    final woke = day.add(Duration(minutes: 6 * 60 + rnd.nextInt(120)));
    final slept = woke.subtract(Duration(minutes: sleepMin));
    final energy = (sleepMin / 60 - 4 + rnd.nextInt(2)).round().clamp(1, 5);
    await cal.saveCheckin(Checkin(day: day, sleptAt: slept, wokeAt: woke, energy: energy, missReason: energy <= 2 ? 'นอนดึก' : null));
  }
}

// ---------------- ตัวตรวจกฎ ----------------

/// ตัวตรวจกฎ สกิล · งาน · เงิน · ชีวิต · ว่าง = ผ่าน (ใช้ได้ทั้งข้อมูลตัวอย่าง และข้อมูลที่ใส่เอง)
Future<List<String>> checkDemoLife(CalendarRepository cal, DateTime today) async {
  final now = _d(today);
  final errors = <String>[];

  // สกิล
  final r = cal.skillRepo;
  final skills = await r.skills();
  final nodes = await r.nodes();
  final needs = await r.needs();
  final topics = await r.topics();
  final hours = <int, double>{}, ratios = <int, double>{};
  final logsBy = <int, List<SkillLog>>{};
  for (final s in skills) {
    final logs = await r.logs(s.id);
    logsBy[s.id] = logs;
    hours[s.id] = practiceHours(logs);
    ratios[s.id] = skillRatio(s, nodes: nodes.where((n) => n.skillId == s.id).toList(), topics: topics, goals: await r.goals(s.id), logs: logs, today: now);
  }
  final stats = skillStats(skills, needs, hours, ratios);
  for (final s in skills) {
    final logs = logsBy[s.id]!;
    final days = <DateTime>{};
    for (final l in logs) {
      if (l.day.isAfter(now)) errors.add('บันทึกสกิลในอนาคต: ${s.name} ${dayKey(l.day)}');
      if (!days.add(_d(l.day))) errors.add('บันทึกซ้ำวันเดียวกัน: ${s.name} ${dayKey(l.day)}');
    }
    if (stats[s.id]!.state == TreeState.lock && logs.isNotEmpty) errors.add('สกิลที่ยังล็อกมีบันทึก: ${s.name}');
    final mine = nodes.where((n) => n.skillId == s.id).toList();
    for (var i = 1; i < mine.length; i++) {
      if (mine[i].done && !mine[i - 1].done) errors.add('ทักษะย่อยข้ามด่าน: ${s.name} › ${mine[i].name}');
    }
    // เป้าเร็วขึ้น: ดีขึ้นจริงแต่มีขึ้นลง (ไม่ใช่เส้นตรงเป๊ะ)
    for (final g in await r.goals(s.id)) {
      if (g.kind != GoalKind.faster) continue;
      final vs = [for (final l in logs.reversed) if (l.goalId == g.id && l.value != null) l.value!];
      if (vs.length < 3) continue;
      if (vs.last >= vs.first) errors.add('เป้าเร็วขึ้นไม่ดีขึ้น: ${s.name}');
      var ups = 0;
      for (var i = 1; i < vs.length; i++) {
        if (vs[i] > vs[i - 1]) ups++;
      }
      if (ups == 0) errors.add('เป้าเร็วขึ้นลดลงตรงเป๊ะ (ไม่สมจริง): ${s.name}');
    }
  }
  for (final n in needs) {
    if (needs.any((m) => m.skillId == n.needId && m.needId == n.skillId)) errors.add('ต้องผ่านก่อนวนกัน: ${n.skillId} ↔ ${n.needId}');
  }

  // งาน
  final w = cal.workRepo;
  for (final p in await w.projects()) {
    final pays = await w.payments(p.id);
    final sum = pays.fold<double>(0, (a, x) => a + x.amount);
    if (p.price != null && pays.isNotEmpty && (sum - p.price!).abs() > 0.5) {
      errors.add('งวดรวมไม่เท่าราคา: ${p.name} (${baht(sum)} / ${baht(p.price!)})');
    }
    if (p.status == ProjectStatus.paid && pays.any((x) => !x.received)) errors.add('เก็บเงินแล้วแต่ยังมีงวดค้าง: ${p.name}');
    for (final t in await w.tasks(p.id)) {
      if (t.done && t.due != null && t.due!.isAfter(now)) errors.add('ขั้นงานเสร็จในอนาคต: ${p.name} › ${t.title}');
    }
  }

  // เงิน
  final entries = await w.entries(DateTime(2000), DateTime(2100));
  for (final e in entries) {
    if (e.day.isAfter(now)) errors.add('รายการเงินในอนาคต: ${e.category} ${dayKey(e.day)}');
  }
  final subs = {for (final s in await w.subscriptions()) s.id: s};
  for (final e in entries.where((e) => e.subscriptionId != null)) {
    final s = subs[e.subscriptionId];
    if (s == null) continue;
    final due = billDateIn(s, DateTime(e.day.year, e.day.month));
    if (due == null || _d(e.day) != due) errors.add('ค่าบริการไม่ตรงวันตัด: ${s.name} ${dayKey(e.day)}');
  }
  // เงินส่วนตัวเท่านั้น (ค่าวัสดุ/ค่าแรงของโปรเจกต์ไม่นับ)
  final months = lastMonths([for (final e in entries) if (e.projectId == null || e.kind == MoneyKind.income) e], DateTime(now.year, now.month), n: 12);
  final avgIncome = months.fold<double>(0, (a, m) => a + m.$2) / months.length;
  for (final (m, _, exp) in months) {
    if (exp > 0 && exp >= avgIncome) errors.add('รายจ่าย ${m.year}-${m.month} (${baht(exp)}) ≥ รายรับเฉลี่ย (${baht(avgIncome)})');
  }

  // ชีวิต
  for (final c in await cal.checkins(now.subtract(const Duration(days: 400)), now.add(const Duration(days: 400)))) {
    if (c.day.isAfter(now)) errors.add('เช็กอินในอนาคต: ${dayKey(c.day)}');
    final h = c.sleepHours;
    if (h != null && (h < 5 || h > 8)) errors.add('นอน ${h.toStringAsFixed(1)} ชม. (ต้อง 5–8): ${dayKey(c.day)}');
    if (c.energy != null && (c.energy! < 1 || c.energy! > 5)) errors.add('พลังเช้า ${c.energy} (ต้อง 1–5): ${dayKey(c.day)}');
  }
  return errors;
}

/// งานฝึกสกิลในปฏิทิน: ช่วงค่ำ (≥ 17:00) · จบไม่เกิน 23:00 · ไม่ชนคาบเรียน
Future<List<String>> checkPracticeSlots(CalendarRepository cal, DateTime from, DateTime to) async {
  final errors = <String>[];
  final skillActs = <int>{};
  for (final s in await cal.skillRepo.skills()) {
    skillActs.addAll(await cal.skillRepo.activitiesOf(s.id));
  }
  final days = await cal.occurrencesBetween(from, to);
  for (final e in days.entries) {
    final classes = [for (final o in e.value) if (o.kind == ActivityKind.classSession && o.timed) o];
    for (final o in e.value) {
      if (!skillActs.contains(o.activityId) || !o.timed) continue;
      if (o.startAt!.hour < 17) errors.add('ฝึกสกิลก่อน 17:00: ${dayKey(e.key)}');
      if (o.endAt!.isAfter(DateTime(e.key.year, e.key.month, e.key.day, 23))) errors.add('ฝึกสกิลเลย 23:00: ${dayKey(e.key)}');
      for (final k in classes) {
        if (o.startAt!.isBefore(k.endAt!) && k.startAt!.isBefore(o.endAt!)) errors.add('ฝึกสกิลชนคาบ ${k.title}: ${dayKey(e.key)}');
      }
    }
  }
  return errors;
}
