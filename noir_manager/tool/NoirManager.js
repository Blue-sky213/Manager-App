// Noir Manager · iPhone (รอบ 14) — แอป PC เขียนไฟล์นี้ให้อัตโนมัติ (แก้แล้วจะถูกเขียนทับ)
// วิดเจ็ต: เพิ่ม Scriptable widget → Script = NoirManager · แตะวิดเจ็ต = เปิดหน้าวันนี้
// ข้อมูล: อ่าน NoirManager/snapshot.json (PC เขียน) · แก้ไข = เขียนคำสั่งลง NoirManager/inbox/ ให้ PC ทำ
const VERSION = 1;
const fm = FileManager.iCloud();
const ROOT = fm.joinPath(fm.documentsDirectory(), "NoirManager");
const SNAP = fm.joinPath(ROOT, "snapshot.json");
const INBOX = fm.joinPath(ROOT, "inbox");
const lfm = FileManager.local();
const PENDING = lfm.joinPath(lfm.documentsDirectory(), "noir_pending.json");

const C = {
  bg: new Color("#111316"), card: new Color("#1A1D22"), text: new Color("#ECEEF1"), muted: new Color("#A3A9B3"),
  accent: new Color("#5B9DFF"), good: new Color("#4CC38A"), warn: new Color("#F2B33D"), bad: new Color("#F06A6A"),
  work: new Color("#F2C66D"),
};

// ---------- ตัวช่วย ----------
const pad = (n) => String(n).padStart(2, "0");
const dayKey = (d) => `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
const hm = (d) => `${pad(d.getHours())}:${pad(d.getMinutes())}`;
const toMin = (s) => (s ? Number(s.slice(0, 2)) * 60 + Number(s.slice(3, 5)) : null);
const thDays = ["อา.", "จ.", "อ.", "พ.", "พฤ.", "ศ.", "ส."];
const thDate = (key) => {
  const d = new Date(key + "T00:00:00");
  return `${thDays[d.getDay()]} ${d.getDate()}/${d.getMonth() + 1}`;
};
const scoreColor = (s) => (s == null ? C.muted : s >= 80 ? C.good : s >= 60 ? C.warn : C.bad);

async function loadSnap() {
  if (!fm.fileExists(SNAP)) return null;
  try {
    await fm.downloadFileFromiCloud(SNAP);
    return JSON.parse(fm.readString(SNAP));
  } catch (e) {
    return null;
  }
}

function loadPending() {
  try {
    return lfm.fileExists(PENDING) ? JSON.parse(lfm.readString(PENDING)) : [];
  } catch (e) {
    return [];
  }
}

// คำสั่งที่ PC ยังไม่ทำ (snapshot เก่ากว่าคำสั่ง) → แสดงผลล่วงหน้าบนมือถือ
// PC บอก id คำสั่งที่ทำแล้ว (applied) → ออกจากคิวทันที · เผื่อ PC รุ่นเก่า: snapshot ใหม่กว่าคำสั่ง = ทำแล้ว
function stillPending(snap) {
  const gen = snap && snap.generatedAt ? new Date(snap.generatedAt).getTime() : 0;
  const applied = new Set((snap && snap.applied) || []);
  const day = 24 * 3600 * 1000;
  const list = loadPending().filter(
    (c) => !applied.has(c.id) && !(gen && new Date(c.at).getTime() <= gen) && Date.now() - new Date(c.at).getTime() < day,
  );
  lfm.writeString(PENDING, JSON.stringify(list));
  return list;
}

function send(cmd) {
  cmd.id = `${Date.now()}-${Math.random().toString(36).slice(2, 8)}`;
  cmd.at = new Date().toISOString();
  cmd.v = VERSION;
  if (!fm.fileExists(INBOX)) fm.createDirectory(INBOX, true);
  fm.writeString(fm.joinPath(INBOX, `${Date.now()}-${cmd.type}.json`), JSON.stringify(cmd));
  const list = loadPending();
  list.push(cmd);
  lfm.writeString(PENDING, JSON.stringify(list));
}

// รายการของวัน + ผลของคำสั่งที่รอ PC
function itemsOf(snap, key, pending) {
  const day = (snap.days || []).find((d) => d.date === key);
  const items = day ? day.items.map((i) => Object.assign({}, i)) : [];
  for (const c of pending) {
    if (c.type === "done" && c.date === key) {
      const it = items.find((i) => i.occ === c.occ);
      if (it) {
        it.done = c.done !== false;
        it.wait = true;
      }
    } else if (c.type === "add" && c.date === key) {
      items.push({ title: c.name, start: c.start, end: null, done: false, wait: true, imp: c.imp });
    } else if (c.type === "move" && c.date === key) {
      const i = items.findIndex((x) => x.occ === c.occ);
      if (i >= 0) items.splice(i, 1);
    }
  }
  return items.sort((a, b) => (toMin(a.start) ?? 9999) - (toMin(b.start) ?? 9999));
}

function nextItem(items) {
  const now = new Date().getHours() * 60 + new Date().getMinutes();
  const open = items.filter((i) => !i.done);
  return open.find((i) => i.start && (toMin(i.end) ?? toMin(i.start)) >= now) || open[0] || null;
}

function syncText(snap, pending) {
  if (!snap) return "ยังไม่มีข้อมูลจาก PC";
  const mins = Math.round((Date.now() - new Date(snap.generatedAt).getTime()) / 60000);
  const age = mins < 1 ? "เมื่อกี้" : mins < 60 ? `${mins} นาทีก่อน` : `${Math.round(mins / 60)} ชม.ก่อน`;
  // นับเป็นงาน ไม่ใช่จำนวนคำสั่ง (ติ๊กแล้วเลิกติ๊กงานเดียว = 1)
  const n = new Set(pending.map((c) => c.occ ?? c.topic ?? c.skill ?? c.id)).size;
  return pending.length ? `รอ PC ${n} รายการ · ข้อมูล ${age}` : `ตรงกับ PC · ${age}`;
}

// ---------- วิดเจ็ต ----------
function addText(stack, text, size, color, bold) {
  const t = stack.addText(text);
  t.font = bold ? Font.semiboldSystemFont(size) : Font.systemFont(size);
  t.textColor = color;
  t.lineLimit = 1;
  return t;
}

async function buildWidget(snap) {
  const w = new ListWidget();
  w.backgroundColor = C.bg;
  w.url = URLScheme.forRunningScript();
  w.refreshAfterDate = new Date(Date.now() + 15 * 60 * 1000);
  const fam = config.widgetFamily || "medium";
  if (!snap) {
    addText(w, "Noir Manager", 13, C.text, true);
    addText(w, "เปิดแอปบน PC + เปิดเชื่อมมือถือ", 11, C.muted);
    return w;
  }
  const pending = stillPending(snap);
  const items = itemsOf(snap, dayKey(new Date()), pending);
  const done = items.filter((i) => i.done).length;
  const next = nextItem(items);

  if (fam === "accessoryCircular") {
    addText(w, `${done}/${items.length}`, 14, Color.white(), true).centerAlignText();
    return w;
  }
  if (fam === "accessoryRectangular" || fam === "accessoryInline") {
    addText(w, next ? `${next.start || "วันนี้"} ${next.title}` : "ครบแล้ว ✓", 13, Color.white(), true);
    if (fam === "accessoryRectangular") addText(w, `ทำแล้ว ${done}/${items.length}`, 11, Color.white());
    return w;
  }
  if (fam === "small") {
    addText(w, next && next.start ? `ถัดไป · ${next.start}` : "ถัดไป", 10, C.muted);
    w.addSpacer(2);
    const t = addText(w, next ? next.title : "ครบทุกงาน ✓", 15, C.text, true);
    t.lineLimit = 3;
    w.addSpacer();
    addText(w, `ทำแล้ว ${done}/${items.length}`, 12, done === items.length ? C.good : C.accent, true);
    return w;
  }
  // medium / large
  addText(w, `วันนี้ · ${thDate(snap.today)} · ทำแล้ว ${done}/${items.length}`, 11, C.muted);
  w.addSpacer(4);
  const max = fam === "large" ? 10 : 4;
  const open = items.filter((i) => !i.done);
  for (const it of open.slice(0, max)) {
    const row = w.addStack();
    row.spacing = 6;
    addText(row, it.start || "—", 12, C.muted).font = Font.regularMonospacedSystemFont(12);
    addText(row, it.title + (it.wait ? " ⏳" : ""), 13, it.imp >= 3 ? C.warn : C.text, it === next);
    w.addSpacer(3);
  }
  if (!open.length) addText(w, "ครบทุกงานแล้ว ✓", 14, C.good, true);
  if (fam === "large" && snap.skills && snap.skills.length) {
    w.addSpacer();
    for (const s of snap.skills.slice(0, 3)) {
      const pct = s.total ? Math.round((s.green * 100) / s.total) : 0;
      addText(w, `${s.icon} ${s.name} · ${pct}%${s.current ? " · " + s.current.name : ""}`, 11, C.muted);
    }
  }
  w.addSpacer();
  return w;
}

// ---------- หน้าแอป ----------
async function choose(title, options, message) {
  const a = new Alert();
  a.title = title;
  if (message) a.message = message;
  options.forEach((o) => a.addAction(o));
  a.addCancelAction("ยกเลิก");
  const i = await a.presentSheet();
  return i < 0 ? null : i;
}

async function ask(title, fields, message) {
  const a = new Alert();
  a.title = title;
  if (message) a.message = message;
  fields.forEach(([ph, val]) => a.addTextField(ph, val == null ? "" : String(val)));
  a.addAction("ตกลง");
  a.addCancelAction("ยกเลิก");
  const i = await a.present();
  return i < 0 ? null : fields.map((_, k) => a.textFieldValue(k).trim());
}

async function pickScore() {
  const i = await choose("เข้าใจแค่ไหน", ["🟢 เข้าใจ 90", "🟡 พอได้ 70", "🔴 ยัง 40", "พิมพ์คะแนน 0–100"]);
  if (i == null) return null;
  if (i < 3) return [90, 70, 40][i];
  const v = await ask("คะแนน 0–100", [["80", ""]]);
  const n = v ? parseInt(v[0], 10) : NaN;
  return isNaN(n) ? null : Math.max(0, Math.min(100, n));
}

async function itemMenu(snap, key, it) {
  if (it.wait && it.occ == null) return; // งานที่เพิ่งเพิ่ม ยังรอ PC
  const opts = [it.done ? "↺ เลิกติ๊ก" : "✓ ทำแล้ว", "เลื่อนไปวัน / เวลาอื่น"];
  if (it.skill) opts.push("บันทึกรอบ + ให้คะแนน");
  const i = await choose(it.title, opts, `${it.start ? it.start + "–" + (it.end || "") : "ไม่ระบุเวลา"}${it.session ? " · ครั้งที่ " + it.session : ""}`);
  if (i === 0) send({ type: "done", occ: it.occ, act: it.act, date: key, done: !it.done });
  if (i === 1) {
    const dp = new DatePicker();
    dp.initialDate = new Date(key + "T" + (it.start || "09:00") + ":00");
    const d = await dp.pickDateAndTime();
    send({ type: "move", occ: it.occ, act: it.act, date: key, toDate: dayKey(d), toStart: it.start ? hm(d) : null });
  }
  if (i === 2) await skillLog(snap, it.skill, it, key);
}

async function skillLog(snap, skillId, it, key) {
  const s = (snap.skills || []).find((x) => x.id === skillId);
  if (!s) return;
  const mins = it && it.start && it.end ? toMin(it.end) - toMin(it.start) : 60;
  const v = await ask(`${s.icon} ${s.name}`, [["ฝึกไปกี่นาที", mins], ["ดีขึ้นตรงไหน (ไม่ใส่ก็ได้)", ""]]);
  if (!v) return;
  let topic = null, score = null;
  const topics = s.current ? s.current.topics : [];
  if (topics.length) {
    const t = await choose("เรียนหัวข้อไหน", topics.map((x) => `${x.name}${x.score != null ? " · " + x.score : ""}`), s.current.name);
    if (t != null) {
      topic = topics[t].id;
      score = await pickScore();
    }
  }
  if (it && !it.done) send({ type: "done", occ: it.occ, act: it.act, date: key, done: true });
  send({ type: "skillLog", skill: s.id, date: key || dayKey(new Date()), minutes: parseInt(v[0], 10) || null, note: v[1] || null, topic, score });
}

async function quickAdd(snap) {
  const v = await ask("+ งานด่วน", [["ชื่องาน", ""]]);
  if (!v || !v[0]) return;
  const dp = new DatePicker();
  dp.initialDate = new Date(Date.now() + 60 * 60 * 1000);
  const d = await dp.pickDateAndTime();
  const timed = (await choose("มีเวลาเริ่มไหม", [`มี · ${hm(d)}`, "ไม่ระบุเวลา (ลิสต์)"])) === 0;
  const cats = snap.categories || [];
  const ci = cats.length ? await choose("หมวด", cats.map((c) => `${c.icon || "●"} ${c.name}`)) : null;
  const cat = ci == null ? null : cats[ci];
  let minutes = cat && cat.minutes ? cat.minutes : 30;
  if (timed) {
    const m = await ask("นานกี่นาที", [["30", minutes]]);
    if (m) minutes = parseInt(m[0], 10) || minutes;
  }
  const imp = await choose("ความสำคัญ", ["● ต่ำ", "● กลาง", "● สำคัญ"]);
  send({ type: "add", name: v[0], date: dayKey(d), start: timed ? hm(d) : null, minutes, cat: cat ? cat.id : null, imp: imp == null ? 2 : imp + 1 });
}

async function checkin(snap) {
  const st = snap.stickers || [];
  const si = st.length ? await choose("วันนี้รู้สึกยังไง", st.map((s) => `${s.emoji} ${s.name}`)) : null;
  const e = await choose("พลังงาน", ["1 · หมดแรง", "2", "3 · ปกติ", "4", "5 · เต็มที่"]);
  const old = snap.checkin || {};
  const v = await ask("นอน / ตื่น (ไม่ใส่ก็ได้)", [["นอน เช่น 23:30", old.sleptAt], ["ตื่น เช่น 07:20", old.wokeAt], ["โน้ต", ""]]);
  const ok = (s) => (s && /^\d{1,2}:\d{2}$/.test(s) ? s.padStart(5, "0") : null);
  send({
    type: "checkin", date: dayKey(new Date()), energy: e == null ? null : e + 1, sticker: si == null ? null : st[si].id,
    sleptAt: v ? ok(v[0]) : null, wokeAt: v ? ok(v[1]) : null, note: v && v[2] ? v[2] : null,
  });
}

async function skillsView(snap) {
  const list = snap.skills || [];
  const i = await choose("สกิล", list.map((s) => `${s.icon} ${s.name} · 🟢 ${s.green}/${s.total}`));
  if (i == null) return;
  const s = list[i];
  const t = new UITable();
  t.showSeparators = true;
  const head = new UITableRow();
  head.isHeader = true;
  head.addText(`${s.icon} ${s.name}`, s.current ? s.current.name : "ผ่านครบทุกบท 🏆");
  t.addRow(head);
  const rows = [...(s.current ? s.current.topics : []), ...s.review.filter((r) => !(s.current && s.current.topics.some((x) => x.id === r.id)))];
  for (const x of rows) {
    const r = new UITableRow();
    r.height = 52;
    const name = r.addText(x.name, x.url ? "แตะ = ▶ คลิป / ให้คะแนน" : "แตะ = ให้คะแนน");
    name.widthWeight = 80;
    const sc = r.addText(x.score == null ? "–" : String(x.score));
    sc.rightAligned();
    sc.titleColor = scoreColor(x.score);
    sc.widthWeight = 20;
    r.onSelect = async () => {
      const opts = x.url ? ["▶ เปิดคลิป", "ให้คะแนน"] : ["ให้คะแนน"];
      const k = await choose(x.name, opts);
      if (k == null) return;
      if (x.url && k === 0) return Safari.open(x.url);
      const score = await pickScore();
      if (score != null) send({ type: "topicScore", topic: x.id, score, date: dayKey(new Date()) });
    };
    t.addRow(r);
  }
  const log = new UITableRow();
  log.addButton("บันทึกรอบ").onTap = async () => skillLog(snap, s.id, null, dayKey(new Date()));
  t.addRow(log);
  await t.present(false);
}

async function app() {
  let key = dayKey(new Date());
  const t = new UITable();
  t.showSeparators = true;
  async function render() {
    const snap = await loadSnap();
    t.removeAllRows();
    if (!snap) {
      const r = new UITableRow();
      r.addText("ยังไม่มีข้อมูลจาก PC", "เปิด Noir Manager บน PC › ตั้งค่า › เชื่อมมือถือ › เปิด");
      t.addRow(r);
      t.reload();
      return;
    }
    const pending = stillPending(snap);
    const head = new UITableRow();
    head.isHeader = true;
    head.height = 60;
    head.addText(key === snap.today ? "วันนี้ · " + thDate(key) : thDate(key), syncText(snap, pending));
    t.addRow(head);
    const nav = new UITableRow();
    const days = (snap.days || []).map((d) => d.date);
    const prev = nav.addButton("◀");
    prev.onTap = () => { const i = days.indexOf(key); if (i > 0) key = days[i - 1]; render(); };
    nav.addButton("+ งาน").onTap = async () => { await quickAdd(snap); render(); };
    nav.addButton("เช็กอิน").onTap = async () => { await checkin(snap); render(); };
    nav.addButton("สกิล").onTap = async () => { await skillsView(snap); render(); };
    nav.addButton("⟳").onTap = () => render();
    nav.addButton("▶").onTap = () => { const i = days.indexOf(key); if (i < days.length - 1) key = days[i + 1]; render(); };
    t.addRow(nav);
    const items = itemsOf(snap, key, pending);
    if (!items.length) {
      const r = new UITableRow();
      r.addText("ไม่มีงานวันนี้");
      t.addRow(r);
    }
    for (const it of items) {
      const r = new UITableRow();
      r.height = 56;
      const mark = r.addText(it.done ? "✓" : "○");
      mark.widthWeight = 10;
      mark.titleColor = it.done ? C.good : C.muted;
      const name = r.addText(it.title + (it.wait ? " ⏳" : ""), `${it.start ? it.start + "–" + (it.end || "") : "ไม่ระบุเวลา"}${it.session ? " · " + it.session : ""}`);
      name.widthWeight = 90;
      if (it.done) name.titleColor = C.muted;
      else if (it.imp >= 3) name.titleColor = C.warn;
      r.onSelect = async () => { await itemMenu(snap, key, it); render(); };
      r.dismissOnSelect = false;
      t.addRow(r);
    }
    t.reload();
  }
  await render();
  // เปิดค้างไว้ = โหลดข้อมูลใหม่ทุก 15 วินาที (⏳ หายเองเมื่อ PC ทำเสร็จ)
  const tick = Timer.schedule(15000, true, () => render());
  await t.present(true);
  tick.invalidate();
}

if (config.runsInWidget) {
  const w = await buildWidget(await loadSnap());
  Script.setWidget(w);
} else {
  await app();
}
Script.complete();
