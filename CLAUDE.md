# CLAUDE.md — Noir Manager

แอปจัดการตัวเองของนัวร์ (Noir): ปฏิทิน + แผนการเรียน + คะแนนความเข้าใจ (Mastery) ไว้ที่เดียว
ผู้ใช้: นัวร์ + คนใกล้ตัวที่ช่วยเทส (ยังไม่ขาย) · หลักการแอป: **อิสระ ไม่บล็อก** — เตือนและให้ตัวเลือกแทนการห้าม · มีโหมด EZ / Advanced

ก่อนเริ่มงานทุกครั้ง อ่าน:
1. `docs/PRINCIPLES.md` — กฎการทำงานของ AI ทุกตัว (บังคับ)
2. `docs/FEATURE_MAP.md` — ฟีเจอร์ที่มี, เข้าถึงยังไง, หลักฐานว่าทำงาน

## Stack

| เรื่อง | ค่า |
|---|---|
| Framework | Flutter (Dart SDK `^3.13.7`) · Material 3 |
| ฐานข้อมูล | SQLite — `sqflite` (Android/iOS), `sqflite_common_ffi` (Windows) · schema **v14** |
| Migration | `onUpgrade` + `addColumnIfMissing` — ห้ามแก้ migration เก่า เพิ่มเวอร์ชันใหม่เท่านั้น |
| แพลตฟอร์ม | Windows (หลัก) · Android · iPhone/iPad (ติดตั้งเทสเอง ไม่ขึ้น App Store) |
| ฟอนต์ | IBM Plex Sans Thai (`assets/fonts/`) |

## โครงสร้าง (โปรเจกต์อยู่ใน `noir_manager/`)

| โฟลเดอร์ `lib/` | มีอะไร |
|---|---|
| `shell/` | โครงแอป + เมนู 5 หน้า |
| `pages/` | วันนี้ · ปฏิทิน · วิชา · ไฟล์ · สถิติ |
| `calendar/` | model, repository, มุมมองสัปดาห์, เวลาชน, หาช่องว่าง, เทอม & วันหยุด |
| `data/` | DB + migration, model วิชา, ข้อมูลตัวอย่างแผน 4 ปี |
| `study/` | แผนผังหลักสูตร, mastery, กฎ Advanced, รอบติว, สีวิชา |
| `theme/` `utils/` `widgets/` | ธีม Dark/Light, วันที่ไทย, dialog กลาง |

สถาปัตยกรรม: Repository pattern (SQLite + Memory สำหรับเทส) · ส่งลงหน้าด้วย InheritedWidget (`StudyScope`, `CalendarScope`) · ปฏิทินแจ้งเปลี่ยนด้วย `ChangeNotifier`

แผนภาพระบบ (ER, flowchart): `docs/diagrams/`

## คำสั่ง (รันใน `noir_manager/`)

```bash
flutter pub get
flutter analyze          # ต้องไม่มี error (ค้างอยู่ 13 ข้อ ณ 5 พ.ย. — ห้ามเพิ่ม)
flutter test             # ต้องผ่านทั้งหมด
flutter run -d windows   # นัวร์รันบนเครื่องจริง
```

CI: `.github/workflows/flutter-ci.yml` รัน analyze + test ทุกครั้งที่ push / เปิด PR — **ใช้เป็นหลักฐาน verify**

## วิธีทำงาน

1. เล่าปัญหา/งานด้วยคำของตัวเองก่อนแตะโค้ด
2. ทำตาม playbook (Bug fix / Feature / Investigation / Deploy) — ห้ามข้ามขั้นเงียบ
3. เขียนเทสคู่กับโค้ด · commit เล็ก ข้อความ commit ภาษาอังกฤษสั้น ๆ
4. **Done means** = CI เขียว + อัปเดต `docs/FEATURE_MAP.md` ถ้าฟีเจอร์เปลี่ยน + บอกนัวร์ว่าต้องเช็กอะไรด้วยมือบน Windows
5. งานที่ต้องเห็นหน้าจอจริง → ขอ screenshot จากนัวร์ (เครื่อง cloud รัน Windows build ไม่ได้)

## สไตล์โค้ด

- ตาม `analysis_options.yaml` (flutter_lints)
- ข้อความในแอปเป็นภาษาไทย · ชื่อตัวแปร/ฟังก์ชันภาษาอังกฤษ
- คอมเมนต์ภาษาไทย สั้น อธิบาย "ทำไม" ไม่ใช่ "ทำอะไร"
- แจ้งเตือนใช้แถบสั้นด้านล่าง (SnackBar) ไม่ใช้ popup ยาว
