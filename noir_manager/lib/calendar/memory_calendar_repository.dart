import 'calendar_models.dart';
import 'calendar_repository.dart';

/// CalendarRepository แบบเก็บใน RAM — ใช้ในการเทส กฎต้องเหมือนตัว SQLite ทุกข้อ
class MemoryCalendarRepository extends CalendarRepository {
  MemoryCalendarRepository() {
    for (var i = 0; i < seedCategories.length; i++) {
      _categories.add(ActivityCategory(
          id: i + 1, name: seedCategories[i].$1, colorKey: seedCategories[i].$2));
    }
    // Preset ตั้งต้นเหมือนฐานข้อมูลจริง: Stream · สตรีม · สำคัญ · 20:00–00:00
    _presets.add(Preset(
      id: _nextId++,
      name: 'Stream',
      categoryId: _categories.firstWhere((c) => c.name == 'สตรีม').id,
      importance: 3,
      startMinute: 20 * 60,
      durationMin: 4 * 60,
    ));
  }

  int _nextId = 100;
  final List<ActivityCategory> _categories = [];
  final List<Preset> _presets = [];
  final Map<int, Activity> _activities = {};
  final List<_Occ> _occs = [];
  List<LifeBaseDay> _lifeBase = defaultLifeBase();

  Occurrence _toOccurrence(_Occ o) {
    final a = _activities[o.activityId]!;
    return Occurrence(
      id: o.id,
      activityId: a.id,
      title: a.name,
      categoryId: a.categoryId,
      importance: a.importance,
      repeats: a.repeat != RepeatKind.none,
      day: o.day,
      startAt: o.startAt,
      endAt: o.endAt,
      status: o.status,
      reason: o.reason,
      movedFromId: o.movedFrom,
      subjectId: a.subjectId,
      actualStart: o.actualStart,
      actualEnd: o.actualEnd,
      kind: a.kind,
    );
  }

  @override
  Future<List<ActivityCategory>> categories() async => List.of(_categories);

  @override
  Future<int> addActivity(NewActivity n) async {
    final id = _nextId++;
    _activities[id] = n.toActivity(id: id);
    notifyListeners();
    return id;
  }

  @override
  Future<Activity> activity(int activityId) async => _activities[activityId]!;

  @override
  Future<void> updateActivity(int activityId, NewActivity n,
      {DateTime? from}) async {
    _activities[activityId] = n.toActivity(id: activityId);
    final f = dayOnly(from ?? DateTime.now());
    _occs.removeWhere((o) =>
        o.activityId == activityId &&
        o.originDay != null &&
        !o.originDay!.isBefore(f) &&
        o.status == OccurrenceStatus.planned);
    notifyListeners();
  }

  @override
  Future<void> updateOccurrenceTime(
      int occurrenceId, DateTime start, DateTime end) async {
    _occ(occurrenceId)
      ..startAt = start
      ..endAt = end;
    notifyListeners();
  }

  @override
  Future<List<Preset>> presets() async =>
      List.of(_presets)..sort((a, b) => a.name.compareTo(b.name));

  @override
  Future<int> addPreset(String name, NewActivity v) async {
    final id = _nextId++;
    _presets.add(Preset(
      id: id,
      name: name,
      categoryId: v.categoryId,
      importance: v.importance,
      startMinute: v.timed ? v.startMinute : null,
      durationMin: v.timed ? v.durationMin : null,
    ));
    notifyListeners();
    return id;
  }

  @override
  Future<void> deletePreset(int presetId) async {
    _presets.removeWhere((p) => p.id == presetId);
    for (final e in _activities.entries.toList()) {
      if (e.value.presetId == presetId) {
        final d = e.value.toDraft();
        _activities[e.key] = NewActivity(
          name: d.name,
          categoryId: d.categoryId,
          importance: d.importance,
          timed: d.timed,
          day: d.day,
          startMinute: d.startMinute,
          durationMin: d.durationMin,
          repeat: d.repeat,
          weekdays: d.weekdays,
          endDate: d.endDate,
          dates: d.dates,
          subjectId: d.subjectId,
          kind: d.kind,
        ).toActivity(id: e.key);
      }
    }
    notifyListeners();
  }

  @override
  Future<void> deleteActivity(int activityId) async {
    _occs.removeWhere((o) => o.activityId == activityId);
    _activities.remove(activityId);
    notifyListeners();
  }

  @override
  Future<List<Occurrence>> occurrencesOn(DateTime day) async {
    final d = dayOnly(day);
    for (final a in _activities.values) {
      if (!occursOn(a, d)) continue;
      final exists = _occs.any((o) => o.activityId == a.id && o.originDay == d);
      if (exists) continue;
      final time = timeFor(a, d);
      final start = time == null ? null : atMinute(d, time.$1);
      _occs.add(_Occ(
        id: _nextId++,
        activityId: a.id,
        originDay: d,
        day: d,
        startAt: start,
        endAt: start?.add(Duration(minutes: time!.$2)),
      ));
    }
    final list = _occs.where((o) => o.day == d).toList()
      ..sort((x, y) {
        if ((x.startAt == null) != (y.startAt == null)) {
          return x.startAt == null ? 1 : -1; // ล็อกเวลาก่อน งานลิสต์ทีหลัง
        }
        if (x.startAt != null) {
          final c = x.startAt!.compareTo(y.startAt!);
          if (c != 0) return c;
        }
        return x.id.compareTo(y.id);
      });
    return list.map(_toOccurrence).toList();
  }

  @override
  Future<void> setActualTimes(int occurrenceId, {DateTime? start, DateTime? end}) async {
    _occ(occurrenceId)
      ..actualStart = start
      ..actualEnd = end;
    notifyListeners();
  }

  @override
  Future<List<Activity>> activitiesForSubject(int subjectId) async =>
      _activities.values.where((a) => a.subjectId == subjectId).toList();

  @override
  Future<List<Occurrence>> occurrencesForSubject(int subjectId) async => (_occs
          .where((o) => _activities[o.activityId]?.subjectId == subjectId)
          .toList()
        ..sort((a, b) => a.day.compareTo(b.day)))
      .map(_toOccurrence)
      .toList();

  @override
  Future<List<Occurrence>> inbox() async => (_occs
          .where((o) => o.status == OccurrenceStatus.inbox)
          .toList()
        ..sort((a, b) => a.day.compareTo(b.day)))
      .map(_toOccurrence)
      .toList();

  _Occ _occ(int id) => _occs.firstWhere((o) => o.id == id);

  @override
  Future<void> setDone(int occurrenceId, bool done) async {
    _occ(occurrenceId)
      ..status = done ? OccurrenceStatus.done : OccurrenceStatus.planned
      ..reason = null;
    notifyListeners();
  }

  @override
  Future<void> cancel(int occurrenceId, String reason) async {
    _occ(occurrenceId)
      ..status = OccurrenceStatus.cancelled
      ..reason = reason;
    notifyListeners();
  }

  @override
  Future<void> sendToInbox(int occurrenceId) async {
    _occ(occurrenceId)
      ..status = OccurrenceStatus.inbox
      ..reason = null;
    notifyListeners();
  }

  @override
  Future<int> moveOccurrence(int occurrenceId, DateTime day,
      {DateTime? start, DateTime? end}) async {
    final old = _occ(occurrenceId)..status = OccurrenceStatus.moved;
    final id = _nextId++;
    _occs.add(_Occ(
      id: id,
      activityId: old.activityId,
      originDay: null,
      day: dayOnly(day),
      startAt: start,
      endAt: end,
      movedFrom: occurrenceId,
    ));
    notifyListeners();
    return id;
  }

  @override
  Future<void> moveSeries(
      int activityId, DateTime fromDay, int startMinute, int durationMin) async {
    final d = _activities[activityId]!.toDraft();
    _activities[activityId] = NewActivity(
      name: d.name,
      categoryId: d.categoryId,
      importance: d.importance,
      timed: d.timed,
      day: d.day,
      startMinute: startMinute,
      durationMin: durationMin,
      repeat: d.repeat,
      weekdays: d.weekdays,
      endDate: d.endDate,
      presetId: d.presetId,
      dates: d.dates,
      subjectId: d.subjectId,
      kind: d.kind,
    ).toActivity(id: activityId);
    final from = dayOnly(fromDay);
    for (final o in _occs) {
      if (o.activityId != activityId ||
          o.originDay == null ||
          o.originDay!.isBefore(from) ||
          o.status != OccurrenceStatus.planned) {
        continue;
      }
      o.startAt = atMinute(o.day, startMinute);
      o.endAt = o.startAt!.add(Duration(minutes: durationMin));
    }
    notifyListeners();
  }

  @override
  Future<List<LifeBaseDay>> lifeBase() async => List.of(_lifeBase);

  @override
  Future<void> setLifeBase(List<LifeBaseDay> days) async {
    _lifeBase = List.of(days);
    notifyListeners();
  }
}

class _Occ {
  _Occ({
    required this.id,
    required this.activityId,
    required this.originDay,
    required this.day,
    required this.startAt,
    required this.endAt,
    this.movedFrom,
  });

  final int id;
  final int activityId;
  final DateTime? originDay;
  final DateTime day;
  DateTime? startAt;
  DateTime? endAt;
  OccurrenceStatus status = OccurrenceStatus.planned;
  String? reason;
  final int? movedFrom;
  DateTime? actualStart;
  DateTime? actualEnd;
}
