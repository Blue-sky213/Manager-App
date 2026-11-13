import 'calendar_models.dart';
import 'calendar_repository.dart';

/// CalendarRepository แบบเก็บใน RAM — ใช้ในการเทส กฎต้องเหมือนตัว SQLite ทุกข้อ
class MemoryCalendarRepository extends CalendarRepository {
  MemoryCalendarRepository() {
    for (var i = 0; i < seedCategories.length; i++) {
      _categories.add(ActivityCategory(
          id: i + 1,
          name: seedCategories[i].$1,
          colorKey: seedCategories[i].$2,
          systemKey: seedCategories[i].$3,
          icon: seedCategoryIcons[i]));
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
      rootDay: _rootDay(o),
      freeStart: o.freeStart,
      freeEnd: o.freeEnd,
      flexible: a.flexible,
    );
  }

  /// เหมือน root_day ใน SQL: ไล่ movedFrom ย้อนกลับจนเจอครั้งที่มี originDay
  DateTime? _rootDay(_Occ o) {
    _Occ? cur = o;
    while (cur != null) {
      if (cur.originDay != null) return cur.originDay;
      final from = cur.movedFrom;
      cur = from == null ? null : _occs.where((x) => x.id == from).firstOrNull;
    }
    return null;
  }

  @override
  Future<List<ActivityCategory>> categories() async => List.of(_categories);

  @override
  Future<int> addCategory(ActivityCategory c) async {
    final id = _nextId++;
    _categories.add(c.copyWith(id: id));
    notifyListeners();
    return id;
  }

  @override
  Future<void> updateCategory(ActivityCategory c) async {
    final i = _categories.indexWhere((x) => x.id == c.id);
    if (i >= 0) _categories[i] = c.copyWith(systemKey: _categories[i].systemKey);
    notifyListeners();
  }

  @override
  Future<void> deleteCategory(int id, {int? moveTo}) async {
    if (_categories.any((c) => c.id == id && c.isSystem)) return;
    for (final e in _activities.entries.toList()) {
      if (e.value.categoryId == id) {
        final d = e.value.toDraft();
        _activities[e.key] = NewActivity(
          name: d.name,
          categoryId: moveTo,
          importance: d.importance,
          timed: d.timed,
          day: d.day,
          startMinute: d.startMinute,
          durationMin: d.durationMin,
          repeat: d.repeat,
          weekdays: d.weekdays,
          endDate: d.endDate,
          presetId: d.presetId,
          dates: d.dates,
          subjectId: d.subjectId,
          kind: d.kind,
          classInfo: d.classInfo,
          flexible: d.flexible,
        ).toActivity(id: e.key);
      }
    }
    _categories.removeWhere((c) => c.id == id);
    notifyListeners();
  }

  @override
  Future<Map<int, int>> categoryUsage() async {
    final m = <int, int>{};
    for (final a in _activities.values) {
      if (a.categoryId != null) m[a.categoryId!] = (m[a.categoryId!] ?? 0) + 1;
    }
    return m;
  }

  @override
  Future<void> setFree(int occurrenceId, DateTime? start, DateTime? end) async {
    final o = _occs.firstWhere((x) => x.id == occurrenceId);
    o
      ..freeStart = start
      ..freeEnd = end;
    notifyListeners();
  }

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
  Future<void> updatePreset(int presetId, String name, NewActivity? v) async {
    final i = _presets.indexWhere((p) => p.id == presetId);
    if (i < 0) return;
    final old = _presets[i];
    _presets[i] = Preset(
      id: presetId,
      name: name,
      categoryId: v == null ? old.categoryId : v.categoryId,
      importance: v == null ? old.importance : v.importance,
      startMinute: v == null ? old.startMinute : (v.timed ? v.startMinute : null),
      durationMin: v == null ? old.durationMin : (v.timed ? v.durationMin : null),
    );
    notifyListeners();
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
        classInfo: d.classInfo,
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
    return attachSessions(list.map(_toOccurrence).toList());
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
  Future<List<Occurrence>> occurrencesForSubject(int subjectId) async {
    final list = _occs
        .where((o) => _activities[o.activityId]?.subjectId == subjectId)
        .toList()
      ..sort((a, b) => a.day.compareTo(b.day));
    return attachSessions(list.map(_toOccurrence).toList());
  }

  @override
  Future<List<Occurrence>> inbox() async {
    final list = _occs.where((o) => o.status == OccurrenceStatus.inbox).toList()
      ..sort((a, b) => a.day.compareTo(b.day));
    return attachSessions(list.map(_toOccurrence).toList());
  }

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
  Future<DateTime?> shiftToNextRound(int occurrenceId, String reason) async {
    final o = _occ(occurrenceId);
    final a = _activities[o.activityId]!;
    if (!canShiftToNextRound(a)) {
      throw StateError('งานนี้ไม่มีกฎการทำซ้ำ เลื่อนไปรอบถัดไปไม่ได้');
    }
    o
      ..status = OccurrenceStatus.shifted
      ..reason = reason;
    DateTime? newEnd;
    if (a.endDate != null) {
      newEnd = nextSlotAfter(a, a.endDate!);
      final d = a.toDraft();
      _activities[a.id] = NewActivity(
        name: d.name,
        categoryId: d.categoryId,
        importance: d.importance,
        timed: d.timed,
        day: d.day,
        startMinute: d.startMinute,
        durationMin: d.durationMin,
        repeat: d.repeat,
        weekdays: d.weekdays,
        endDate: newEnd,
        presetId: d.presetId,
        dates: d.dates,
        subjectId: d.subjectId,
        kind: d.kind,
        classInfo: d.classInfo,
      ).toActivity(id: a.id);
    }
    notifyListeners();
    return newEnd;
  }

  @override
  Future<Set<DateTime>> shiftedDays(int activityId) async => {
        for (final o in _occs)
          if (o.activityId == activityId && o.status == OccurrenceStatus.shifted)
            ?_rootDay(o),
      };

  final Map<String, String> _settings = {};

  // ---------- สติกเกอร์ (ชุดในตัวแอปใส่ไว้ตั้งแต่สร้าง เหมือน migration v16) ----------
  late final List<({int id, String name, bool builtin, bool enabled})> _packs = _seedPacks();
  final List<Sticker> _stickers = [];
  final List<DaySticker> _daySticker = [];

  List<({int id, String name, bool builtin, bool enabled})> _seedPacks() {
    final out = <({int id, String name, bool builtin, bool enabled})>[];
    for (final (name, items) in builtinStickerPacks) {
      final id = _nextId++;
      out.add((id: id, name: name, builtin: true, enabled: true));
      for (final (n, e) in items) {
        _stickers.add(Sticker(id: _nextId++, packId: id, name: n, emoji: e));
      }
    }
    return out;
  }

  @override
  Future<List<StickerPack>> stickerPacks() async => [
        for (final p in _packs)
          StickerPack(
              id: p.id,
              name: p.name,
              builtin: p.builtin,
              enabled: p.enabled,
              stickers: _stickers.where((s) => s.packId == p.id).toList()),
      ];

  @override
  Future<int> addStickerPack(String name) async {
    final id = _nextId++;
    _packs.add((id: id, name: name, builtin: false, enabled: true));
    notifyListeners();
    return id;
  }

  @override
  Future<void> setStickerPackEnabled(int packId, bool enabled) async {
    final i = _packs.indexWhere((p) => p.id == packId);
    if (i < 0) return;
    final p = _packs[i];
    _packs[i] = (id: p.id, name: p.name, builtin: p.builtin, enabled: enabled);
    notifyListeners();
  }

  @override
  Future<void> deleteStickerPack(int packId) async {
    if (_packs.any((p) => p.id == packId && p.builtin)) return;
    _packs.removeWhere((p) => p.id == packId);
    final gone = _stickers.where((s) => s.packId == packId).map((s) => s.id).toSet();
    _stickers.removeWhere((s) => gone.contains(s.id));
    _daySticker.removeWhere((d) => gone.contains(d.sticker.id));
    notifyListeners();
  }

  @override
  Future<int> addSticker(int packId, String name, {String? emoji, String? imagePath}) async {
    final id = _nextId++;
    _stickers.add(Sticker(id: id, packId: packId, name: name, emoji: emoji, imagePath: imagePath));
    notifyListeners();
    return id;
  }

  @override
  Future<void> deleteSticker(int stickerId) async {
    _stickers.removeWhere((s) => s.id == stickerId);
    _daySticker.removeWhere((d) => d.sticker.id == stickerId);
    notifyListeners();
  }

  @override
  Future<List<DaySticker>> daySticker(DateTime from, DateTime to) async {
    final a = dayOnly(from), b = dayOnly(to);
    return _daySticker.where((d) => !d.day.isBefore(a) && !d.day.isAfter(b)).toList()
      ..sort((x, y) => x.day != y.day ? x.day.compareTo(y.day) : x.id - y.id);
  }

  @override
  Future<int> stickDay(DateTime day, int stickerId,
      {String? note, double? x, double? y, bool highlight = false, String? auto}) async {
    final s = _stickers.firstWhere((s) => s.id == stickerId);
    final id = _nextId++;
    final d = dayOnly(day);
    if (highlight) _clearHighlight(d);
    _daySticker.add(DaySticker(id: id, day: d, sticker: s, note: note, x: x, y: y, highlight: highlight, auto: auto));
    notifyListeners();
    return id;
  }

  void _clearHighlight(DateTime day) {
    for (var i = 0; i < _daySticker.length; i++) {
      if (_daySticker[i].day == day && _daySticker[i].highlight) _daySticker[i] = _daySticker[i].copyWith(highlight: false);
    }
  }

  @override
  Future<void> updateDaySticker(int dayStickerId, {String? note, bool clearNote = false, double? x, double? y}) async {
    final i = _daySticker.indexWhere((d) => d.id == dayStickerId);
    if (i < 0) return;
    _daySticker[i] = _daySticker[i].copyWith(note: note, clearNote: clearNote, x: x, y: y);
    notifyListeners();
  }

  @override
  Future<void> setHighlight(int dayStickerId) async {
    final i = _daySticker.indexWhere((d) => d.id == dayStickerId);
    if (i < 0) return;
    _clearHighlight(_daySticker[i].day);
    _daySticker[i] = _daySticker[i].copyWith(highlight: true);
    notifyListeners();
  }

  @override
  Future<void> swapDaySticker(int dayStickerId, int stickerId, {String? auto}) async {
    final i = _daySticker.indexWhere((d) => d.id == dayStickerId);
    if (i < 0) return;
    _daySticker[i] = _daySticker[i].copyWith(sticker: _stickers.firstWhere((s) => s.id == stickerId), auto: auto);
    notifyListeners();
  }

  @override
  Future<void> unstickDay(int dayStickerId) async {
    _daySticker.removeWhere((d) => d.id == dayStickerId);
    notifyListeners();
  }

  final Map<DateTime, Checkin> _checkins = {};

  @override
  Future<Checkin?> checkin(DateTime day) async => _checkins[dayOnly(day)];

  @override
  Future<List<Checkin>> checkins(DateTime from, DateTime to) async {
    final a = dayOnly(from), b = dayOnly(to);
    return (_checkins.values.where((c) => !c.day.isBefore(a) && !c.day.isAfter(b)).toList()
      ..sort((x, y) => x.day.compareTo(y.day)));
  }

  @override
  Future<void> saveCheckin(Checkin c) async {
    _checkins[dayOnly(c.day)] = c;
    notifyListeners();
  }

  @override
  Future<String?> getSetting(String key) async => _settings[key];

  @override
  Future<void> setSetting(String key, String value) async {
    _settings[key] = value;
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
        classInfo: d.classInfo,
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

  final List<Term> _terms = [];
  final Map<String, Holiday> _holidays = {};

  @override
  Future<List<Term>> terms() async =>
      [..._terms]..sort((a, b) => a.year != b.year ? a.year - b.year : a.termNo - b.termNo);

  @override
  Future<void> saveTerm(int year, int termNo, DateTime start, DateTime end) async {
    _terms.removeWhere((t) => t.year == year && t.termNo == termNo);
    _terms.add(Term(
        id: _nextId++, year: year, termNo: termNo, start: dayOnly(start), end: dayOnly(end)));
    notifyListeners();
  }

  @override
  Future<void> deleteTerm(int termId) async {
    _terms.removeWhere((t) => t.id == termId);
    notifyListeners();
  }

  @override
  Future<List<Holiday>> holidays() async =>
      _holidays.values.toList()..sort((a, b) => a.day.compareTo(b.day));

  @override
  Future<void> setHoliday(DateTime day, String name) async {
    _holidays[dayKey(day)] = Holiday(dayOnly(day), name);
    notifyListeners();
  }

  @override
  Future<void> removeHoliday(DateTime day) async {
    _holidays.remove(dayKey(day));
    notifyListeners();
  }

  @override
  Future<int> removeDuplicateActivities() async {
    final ids = duplicateActivityIds(_activities.values);
    for (final id in ids) {
      _occs.removeWhere((o) => o.activityId == id);
      _activities.remove(id);
    }
    if (ids.isNotEmpty) notifyListeners();
    return ids.length;
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
  DateTime? freeStart;
  DateTime? freeEnd;
  DateTime? actualEnd;
}
