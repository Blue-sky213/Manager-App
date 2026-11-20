import 'package:flutter_test/flutter_test.dart';

import 'package:noir_manager/sync/conflict_text.dart';
import 'package:noir_manager/sync/merge.dart';

void main() {
  test('รายงานค่าต่างกัน: ภาษาคน (ชื่อไทย · เวลาเป็นนาฬิกา · วันในสัปดาห์ · ชื่องาน)', () {
    const bed = SyncConflict(table: 'life_base', id: '1', field: 'bed_minute', local: 720, remote: 60, localAt: 2, remoteAt: 1);
    expect(conflictTitle(bed, {'weekday': 1, 'bed_minute': 720}), 'เวลาประจำวัน · วันจันทร์ · เวลานอน');
    expect(conflictValue('bed_minute', 720), '12:00');
    expect(conflictValue('wake_minute', 450), '07:30');
    const live = SyncConflict(table: 'activity', id: 'x', field: 'duration_min', local: 150, remote: 120, localAt: 1, remoteAt: 2);
    expect(conflictTitle(live, {'name': 'ไลฟ์ · Noir Lev'}), 'งาน · ไลฟ์ · Noir Lev · ความยาว');
    expect(conflictValue('duration_min', 150), '2 ชม. 30 นาที');
    expect(conflictValue('status', 'done'), 'ทำแล้ว');
    expect(conflictValue(null, null), 'ลบแล้ว');
    expect(conflictValue('note', ''), '(ว่าง)');
  });
}
