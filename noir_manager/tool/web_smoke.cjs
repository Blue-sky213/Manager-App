// เทสเว็บแบบเร็ว (รอบ 17): เปิดหน้าเว็บที่ build แล้วใน Chromium → แอปต้องขึ้น ไม่มี error ใน console
// ใช้ใน CI: node tool/web_smoke.cjs http://localhost:8080/Manager-App/
const { chromium } = require('playwright');

(async () => {
  const url = process.argv[2];
  const browser = await chromium.launch();
  const page = await browser.newPage({ viewport: { width: 1280, height: 800 } });
  const errors = [];
  page.on('console', (m) => {
    console.log(`[console.${m.type()}] ${m.text()}`);
    if (m.type() === 'error') errors.push(m.text());
  });
  page.on('pageerror', (e) => {
    console.log(`[pageerror] ${e.message}`);
    errors.push(e.message);
  });
  await page.goto(url, { waitUntil: 'networkidle' });
  // รอ Flutter วาดหน้าแรก (เปิด DB ครั้งแรก + สร้างตาราง)
  await page.waitForSelector('flt-glass-pane, flutter-view', { timeout: 60000 });
  await page.waitForTimeout(8000);
  await page.screenshot({ path: 'build/web_smoke.png' });
  // โหลดใหม่ = เปิด DB เดิมจาก IndexedDB (ข้อมูลต้องอยู่)
  await page.reload({ waitUntil: 'networkidle' });
  await page.waitForTimeout(6000);
  await page.screenshot({ path: 'build/web_smoke_reload.png' });
  await browser.close();
  // Supabase ถูกเรียกจาก CI ไม่ได้บางครั้ง → ไม่นับ error เน็ต
  const real = errors.filter((e) => !/Failed to load resource|net::|supabase/i.test(e));
  console.log(real.length ? `WEB SMOKE FAIL: ${real.length} error(s)` : 'WEB SMOKE OK');
  process.exit(real.length ? 1 : 0);
})().catch((e) => {
  console.log(`WEB SMOKE FAIL: ${e.message}`);
  process.exit(1);
});
