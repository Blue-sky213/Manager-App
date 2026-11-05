// Render Mermaid diagrams in a real browser (with the real font) and check the geometry.
// usage: node render-check.cjs <outDir> a.mmd b.mmd ...
// output per file: <name>.light.svg / .dark.svg / .light.png + report printed as text
const fs = require('fs');
const path = require('path');
const { chromium } = require('playwright');

const here = __dirname;
const font = (sub, w) =>
  path.join(here, `node_modules/@fontsource/ibm-plex-sans-thai/files/ibm-plex-sans-thai-${sub}-${w}-normal.woff2`);
const FAMILY = '"IBM Plex Sans Thai", sans-serif';

const THEMES = {
  light: {
    background: '#ffffff', primaryColor: '#eef2fb', primaryBorderColor: '#3a5fc8',
    primaryTextColor: '#1b2230', secondaryColor: '#fff4dc', tertiaryColor: '#f6f8fb',
    lineColor: '#3d4656', textColor: '#1b2230', edgeLabelBackground: '#ffffff',
    clusterBkg: '#f6f8fb', clusterBorder: '#9aa6bb', titleColor: '#1b2230',
    attributeBackgroundColorOdd: '#ffffff', attributeBackgroundColorEven: '#f3f6fb',
  },
  dark: {
    background: '#171c26', primaryColor: '#1f2a45', primaryBorderColor: '#8aa8ff',
    primaryTextColor: '#e4e8f0', secondaryColor: '#352a12', tertiaryColor: '#141922',
    lineColor: '#aab4c6', textColor: '#e4e8f0', edgeLabelBackground: '#171c26',
    clusterBkg: '#141922', clusterBorder: '#4a5670', titleColor: '#e4e8f0',
    attributeBackgroundColorOdd: '#171c26', attributeBackgroundColorEven: '#1c2230',
  },
};

// ---------- runs inside the page ----------
function measure() {
  const svg = document.querySelector('#out svg');
  const R = (el) => { const b = el.getBoundingClientRect(); return { x: b.left, y: b.top, w: b.width, h: b.height }; };
  const inter = (a, b) => Math.max(0, Math.min(a.x + a.w, b.x + b.w) - Math.max(a.x, b.x)) *
                          Math.max(0, Math.min(a.y + a.h, b.y + b.h) - Math.max(a.y, b.y));
  const inside = (p, r, pad = 0) => p.x > r.x - pad && p.x < r.x + r.w + pad && p.y > r.y - pad && p.y < r.y + r.h + pad;
  const name = (el) => (el.textContent || '').trim().replace(/\s+/g, ' ').slice(0, 40) || el.id;
  const out = { errors: [], warnings: [], info: [] };

  // nodes = flowchart/state nodes + ER entities (shape box, not the whole group)
  const nodeEls = [...svg.querySelectorAll('g.node, g[id^="entity-"], g.mindmap-node')]
    .filter((g, i, all) => !all.some((o) => o !== g && o.contains(g)));
  const nodes = nodeEls.map((g) => {
    const shape = g.querySelector('.node-bkg, :scope > rect, :scope > polygon, :scope > circle, :scope > ellipse, :scope > path, :scope > g > rect, :scope > g > path') || g;
    return { g, name: name(g), box: R(shape), whole: R(g) };
  }).filter((n) => n.box.w > 2 && n.box.h > 2);

  // A. nodes overlapping each other
  for (let i = 0; i < nodes.length; i++)
    for (let j = i + 1; j < nodes.length; j++)
      if (inter(nodes[i].whole, nodes[j].whole) > 4)
        out.errors.push(`node overlap: "${nodes[i].name}" ↔ "${nodes[j].name}"`);

  const small = new Set();
  // B. text spilling out of its own box (+ clipped HTML labels)
  for (const n of nodes) {
    for (const t of n.g.querySelectorAll('foreignObject div, text')) {
      const b = R(t);
      if (b.w === 0) continue;
      if (b.x < n.box.x - 1 || b.y < n.box.y - 1 || b.x + b.w > n.box.x + n.box.w + 1 || b.y + b.h > n.box.y + n.box.h + 1)
        out.errors.push(`text outside its box: "${name(t)}" in "${n.name}"`);
      if (t.tagName === 'DIV' && (t.scrollWidth > t.clientWidth + 1 || t.scrollHeight > t.clientHeight + 1))
        out.errors.push(`text clipped: "${name(t)}"`);
      const fs = parseFloat(getComputedStyle(t).fontSize);
      if (fs < 12) small.add(fs);
    }
  }

  // edges: sample every 4px in screen coordinates
  const pathEls = [...svg.querySelectorAll('path.edge, .edgePaths path, path.relation, path.relationshipLine, path.transition, path.flowchart-link')]
    .filter((p, i, all) => all.indexOf(p) === i && p.getTotalLength && p.getTotalLength() > 0);
  const edges = pathEls.map((p) => {
    const m = p.getScreenCTM(); const L = p.getTotalLength(); const pts = [];
    for (let s = 0; s <= L; s += 4) { const q = p.getPointAtLength(s); pts.push({ x: m.a * q.x + m.c * q.y + m.e, y: m.b * q.x + m.d * q.y + m.f }); }
    const ends = nodes.filter((n) => inside(pts[0], n.whole, 10) || inside(pts[pts.length - 1], n.whole, 10));
    return { p, pts, ends, id: p.id || '(edge)' };
  });

  // D. an edge passing through a box that is not one of its two ends
  for (const e of edges) {
    for (const n of nodes) {
      if (e.ends.includes(n)) continue;
      const shrunk = { x: n.box.x + 3, y: n.box.y + 3, w: n.box.w - 6, h: n.box.h - 6 };
      if (e.pts.slice(3, -3).some((q) => inside(q, shrunk)))
        out.errors.push(`line goes through a box: ${e.id} crosses "${n.name}"`);
    }
  }

  // E. lines crossing other lines (warning: count)
  const segs = (pts) => pts.slice(1).map((q, i) => [pts[i], q]);
  const cross = (a, b) => {
    const d = (p, q, r) => (q.x - p.x) * (r.y - p.y) - (q.y - p.y) * (r.x - p.x);
    return d(a[0], a[1], b[0]) * d(a[0], a[1], b[1]) < 0 && d(b[0], b[1], a[0]) * d(b[0], b[1], a[1]) < 0;
  };
  let crossings = 0;
  for (let i = 0; i < edges.length; i++)
    for (let j = i + 1; j < edges.length; j++) {
      const shared = edges[i].ends.some((n) => edges[j].ends.includes(n));
      const si = segs(edges[i].pts.slice(4, -4)), sj = segs(edges[j].pts.slice(4, -4));
      let hit = false;
      for (const a of si) { for (const b of sj) if (cross(a, b)) { hit = true; break; } if (hit) break; }
      if (hit && !shared) crossings++;
    }
  if (crossings) out.warnings.push(`${crossings} pair(s) of lines cross each other`);

  // C. edge labels overlapping boxes / other labels / other lines
  const labels = [
    ...[...svg.querySelectorAll('g.edgeLabel')].map((g) => ({ g, name: name(g), box: R(g.querySelector('.label, foreignObject, text, rect') || g) })),
    ...[...svg.querySelectorAll('rect.relationshipLabelBox')].map((r) => {
      const t = [...svg.querySelectorAll('text.relationshipLabel')].find((x) => { const b = R(x), q = R(r); return inside({ x: b.x + b.w / 2, y: b.y + b.h / 2 }, q, 1); });
      return { g: r, name: t ? name(t) : '(label)', box: R(r) };
    }),
  ].filter((l) => l.name && l.box.w > 1);
  for (const l of labels) {
    for (const n of nodes) if (inter(l.box, n.whole) > 4) out.errors.push(`line label on a box: "${l.name}" ↔ "${n.name}"`);
    for (const o of labels) if (o !== l && o.name < l.name && inter(l.box, o.box) > 4) out.errors.push(`line labels overlap: "${l.name}" ↔ "${o.name}"`);
    const own = edges.filter((e) => e.pts.some((q) => inside(q, l.box, 2)));
    if (own.length > 1) out.errors.push(`line label "${l.name}" touches ${own.length} lines — it should sit on 1 only`);
  }

  // I. group (subgraph) titles covering boxes
  for (const c of svg.querySelectorAll('g.cluster')) {
    const lab = c.querySelector('.cluster-label');
    if (!lab) continue;
    const b = R(lab);
    for (const n of nodes) if (inter(b, n.whole) > 4) out.errors.push(`group title on a box: "${name(lab)}" ↔ "${n.name}"`);
  }

  // F. arrowheads
  const noArrow = [...svg.querySelectorAll('path.flowchart-link')].filter((p) => !p.getAttribute('marker-end') && !p.getAttribute('marker-start'));
  if (noArrow.length) out.info.push(`${noArrow.length} line(s) without an arrowhead (ok only if they are plain links)`);

  if (small.size) out.warnings.push(`text smaller than 12px (${[...small].join(', ')}px) — raise fontSize`);

  // L. long lines and lines running against the flow (they drag boxes out of order)
  const dir = (svg.getAttribute('aria-roledescription') || '').includes('flowchart')
    ? (window.__dir || 'TD') : null;
  const lens = edges.map((e) => e.pts.length * 4).sort((a, b) => a - b);
  const median = lens[Math.floor(lens.length / 2)] || 0;
  for (const e of edges) {
    const len = e.pts.length * 4;
    const a = e.pts[0], b = e.pts[e.pts.length - 1];
    const label = e.ends.map((n) => `"${n.name}"`).join(' → ') || e.id;
    if (median && len > Math.max(3 * median, 400)) out.warnings.push(`very long line (${Math.round(len)}px, median ${Math.round(median)}): ${label}`);
    if (dir === 'TD' && b.y < a.y - 30) out.warnings.push(`line runs upward (against TD flow): ${label} — lay it out forward (B --> A) and add "%% flip: B-A" — or accept it if it is a deliberate feedback loop`);
    if (dir === 'LR' && b.x < a.x - 30) out.warnings.push(`line runs leftward (against LR flow): ${label} — lay it out forward (B --> A) and add "%% flip: B-A" — or accept it if it is a deliberate feedback loop`);
  }

  const raw = (svg.textContent || '').match(/&(amp|lt|gt|quot|#\d+);|\\n|<br\s*\/?>/g);
  if (raw) out.errors.push(`visible escape code in text: ${[...new Set(raw)].join(' ')} — write "และ" instead of &, or use the diagram's own line-break syntax`);
  if (!nodes.length) out.errors.push('checker found 0 boxes — this diagram type is not supported by the selectors; check by eye and extend measure()');
  const W = R(svg).w;
  if (W > 1100) out.warnings.push(`diagram is ${Math.round(W)}px wide — will need side-scrolling; consider TD or splitting`);
  if (nodes.length > 15) out.warnings.push(`${nodes.length} boxes — consider splitting into 2 diagrams (≤ 12–15 each)`);
  out.info.push(`${nodes.length} boxes · ${edges.length} lines · ${labels.length} line labels · size ${Math.round(R(svg).w)}×${Math.round(R(svg).h)}`);
  return out;
}

(async () => {
  const [outDir, ...files] = process.argv.slice(2);
  fs.mkdirSync(outDir, { recursive: true });
  const browser = await chromium.launch();
  const page = await browser.newPage({ viewport: { width: 2600, height: 1600 } });
  const faces = ['thai', 'latin'].flatMap((sub) => [400, 600].map((w) =>
    `@font-face{font-family:"IBM Plex Sans Thai";font-weight:${w};src:url(file://${font(sub, w)}) format("woff2")}`)).join('\n');
  await page.goto('file://' + path.join(here, 'blank.html'));
  await page.setContent(`<style>${faces} body{margin:0;font-family:${FAMILY}} #out svg{max-width:none!important}</style><div id="out"></div>`);
  await page.addScriptTag({ path: path.join(here, 'node_modules/mermaid/dist/mermaid.min.js') });
  await page.evaluate(() => document.fonts.load('16px "IBM Plex Sans Thai"', 'ก').then(() => document.fonts.load('600 16px "IBM Plex Sans Thai"', 'ก')));

  let failed = 0;
  for (const file of files) {
    const base = path.basename(file, '.mmd');
    const code = fs.readFileSync(file, 'utf8');
    const lint = [];
    code.split('\n').forEach((line, i) => {
      if (/^\s*%%/.test(line)) return;
      if (/\w\s*<-[-.=]+(?!>)/.test(line) && !/<-[-.=]+>/.test(line))
        lint.push(`line ${i + 1}: "P <-- Q" is drawn as P → Q by Mermaid 11 — write "P --> Q" and add "%% flip: P-Q" to put the arrowhead on P`);
      const seg = new Intl.Segmenter('th', { granularity: 'grapheme' });
      const longest = Math.max(0, ...[...line.matchAll(/"([^"]*)"/g)].flatMap((m) => m[1].split(/<br\/?>/))
        .map((t) => [...seg.segment(t)].length));
      if (longest > 28)
        lint.push(`line ${i + 1}: label line longer than 28 characters — break it with <br/>`);
      if (/-->\s*\|?[^"|]*[\u0E00-\u0E7F(][^|]*\|/.test(line) && !/\|"/.test(line))
        lint.push(`line ${i + 1}: Thai/bracketed edge label without quotes — use |"..."|`);
    });
    for (const [mode, vars] of Object.entries(THEMES)) {
      let res;
      try { res = await page.evaluate(async ({ code, vars, FAMILY, mode, measureSrc }) => {
        mermaid.initialize({
          startOnLoad: false, theme: 'base', securityLevel: 'strict',
          themeVariables: { ...vars, fontFamily: FAMILY, fontSize: '16px' },
          flowchart: { curve: 'basis', nodeSpacing: 50, rankSpacing: 60, padding: 14, htmlLabels: true, wrappingWidth: 220 },
          er: { layoutDirection: 'TB', minEntityWidth: 120, fontSize: 16, entityPadding: 14 },
          state: { padding: 10 },
        });
        const { svg } = await mermaid.render('d_' + mode + Math.random().toString(36).slice(2), code);
        const out = document.getElementById('out');
        out.style.background = vars.background; out.style.display = 'inline-block'; out.style.padding = '16px';
        out.innerHTML = svg;
        const el = out.querySelector('svg');
        // %% flip: A-B → the line is laid out A→B (keeps the layout) but the arrowhead is drawn at A
        for (const m of code.matchAll(/^\s*%%\s*flip:\s*(\S+?)-(\S+)\s*$/gm)) {
          for (const p of el.querySelectorAll(`path[id^="L_${m[1]}_${m[2]}_"]`)) {
            const end = p.getAttribute('marker-end');
            if (!end) continue;
            p.setAttribute('marker-start', end.replace(/pointEnd/, 'pointStart'));
            p.removeAttribute('marker-end');
            p.dataset.flipped = '1';
          }
        }
        const vb = el.viewBox.baseVal; el.setAttribute('width', vb.width); el.setAttribute('height', vb.height); el.style.maxWidth = 'none';
        await new Promise((r) => requestAnimationFrame(() => requestAnimationFrame(r)));
        window.__dir = (/^\s*(?:flowchart|graph)\s+(TD|TB|LR|RL|BT)/m.exec(code) || [])[1]?.replace('TB', 'TD') || null;
        const report = mode === 'light' ? (0, eval)('(' + measureSrc + ')')() : null;
        return { svg: el.outerHTML, report };
      }, { code, vars, FAMILY, mode, measureSrc: measure.toString() }); }
      catch (err) {
        console.log(`\n== ${base} ==\n  ✗ Mermaid could not render (${mode}): ${String(err.message).split('\n')[0]}`);
        failed++; break;
      }
      fs.writeFileSync(path.join(outDir, `${base}.${mode}.svg`), res.svg);
      await page.locator('#out').screenshot({ path: path.join(outDir, `${base}.${mode}.png`) });
      if (res.report) {
        const r = res.report;
        console.log(`\n== ${base} ==`);
        for (const l of lint) { console.log('  ✗ ' + l); failed++; }
        for (const e of r.errors) console.log('  ✗ ' + e);
        for (const w of r.warnings) console.log('  ! ' + w);
        for (const i of r.info) console.log('  · ' + i);
        if (!r.errors.length) console.log('  ✓ no geometry errors');
        failed += r.errors.length;
      }
    }
  }
  await browser.close();
  console.log(`\n${failed ? failed + ' error(s)' : 'ALL CLEAN'}`);
  process.exit(failed ? 1 : 0);
})();
