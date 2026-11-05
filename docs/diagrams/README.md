# แผนภาพระบบ Noir Manager

ไฟล์ `.mmd` = ต้นฉบับ Mermaid ของหน้า Blueprint (แก้ข้อความ/กล่อง/เส้นได้ตรงนี้)

| ไฟล์ | ภาพ |
|---|---|
| `er.mmd` | ER Diagram DB v10 |
| `er-standalone.mmd` | ตารางที่ไม่มี FK |
| `shell.mmd` | หน้าจอ → Repository → DB |
| `occurrence.mmd` | วงจรชีวิตของ "ครั้ง" |
| `done.mmd` | หลังกด "ทำแล้ว" |
| `study.mmd` | วิชา → คาบ → หาเวลาติว |
| `clash.mmd` | เวลาชน |

ดูภาพเร็ว ๆ: วางโค้ดใน https://mermaid.live
ตรวจเส้นอัตโนมัติ (ต้องมี Node + Playwright): `npm i mermaid@11.4.1 @fontsource/ibm-plex-sans-thai@5.1.0` แล้ว `node render-check.cjs out *.mmd`

กติกาพิเศษ: `%% flip: A-B` = วางเส้นจาก A ไป B (ไม่ทำให้ layout เพี้ยน) แต่วาดหัวลูกศรที่ A — ใช้กับเส้นวนกลับ
