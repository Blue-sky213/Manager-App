import 'calendar_models.dart';
import 'calendar_repository.dart';

/// CalendarRepository แบบเก็บใน RAM — ใช้ในการเทส กฎต้องเหมือนตัว SQLite ทุกข้อ
class MemoryCalendarRepository extends CalendarRepository {
  MemoryCalendarRepository() {
    for (var i = 0; i < seedCategories.length; i++) {
      _categories.add(ActivityCategory(
          id: i + 1, name: seedCategories[i].$1, colorKey: seedCategories[i].$2));
    }
  }

  int _nextId = 1;
  final List<ActivityCategory> _categories = [];
  final List<Activity> _activities = [];
  final List<_Occ> _occs = [];
  List<LifeBaseDay> _lifeBase = defaultLifeBase();

  Activity _activity(int id) => _activities.firstWhere((a) => a.id == id);

  Occurrence _toOccurrence(_Occ o) {
    final a = _activity(o.activityId);
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
    );
  }

  @override
  Future<List<ActivityCategory>> categories() async => List.of(_categories);

  @override
  Future<int> addActivity(NewActivity n) async {
    final id = _nextId++;
    _activities.add(Activity(
      id: id,
      name: n.name,
      categoryId: n.categoryId,
      importance: n.importance,
      timed: n.timed,
      startMinute: n.timed ? n.startMinute : null,
      durationMin: n.timed ? n.durationMin : null,
      repeat: n.repeat,
      weekdays: n.weekdays,
      startDate: dayOnly(n.day),
    ));
    notifyListeners();
    return id;
  }

  @override
  Future<void> deleteActivity(int activityId) async {
    _occs.removeWhere((o) => o.activityId == activityId);
    _activities.removeWhere((a) => a.id == activityId);
    notifyListeners();
  }

  @override
  Future<List<Occurrence>> occurrencesOn(DateTime day) async {
    final d = dayOnly(day);
    for (final a in _activities) {
      if (!occursOn(a, d)) continue;
      final exists = _occs.any((o) => o.activityId == a.id && o.originDay == d);
      if (exists) continue;
      final start = a.timed ? atMinute(d, a.startMinute!) : null;
      _occs.add(_Occ(
        id: _nextId++,
        activityId: a.id,
        originDay: d,
        day: d,
        startAt: start,
        endAt: start?.add(Duration(minutes: a.durationMin!)),
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
  Future<List<Occurrence>> inbox() async => (_occs
          .where((o) => o.status == OccurrenceStatus.inbox)
          .toList()
        ..sort((a, b) => a.day.compareTo(b.day)))
      .map(_toOccurrence)
      .toList();

  _Occ _occ(int id) => _occs.firstWhere((o) => o.id == id);

  @override
  Future<void> setDone(int occurrenceId, bool done) async {
    _occ(occurrenceId).status =
        done ? OccurrenceStatus.done : OccurrenceStatus.planned;
    _occ(occurrenceId).reason = null;
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
    final i = _activities.indexWhere((a) => a.id == activityId);
    final a = _activities[i];
    _activities[i] = Activity(
      id: a.id,
      name: a.name,
      categoryId: a.categoryId,
      importance: a.importance,
      timed: a.timed,
      startMinute: startMinute,
      durationMin: durationMin,
      repeat: a.repeat,
      weekdays: a.weekdays,
      startDate: a.startDate,
    );
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
}
