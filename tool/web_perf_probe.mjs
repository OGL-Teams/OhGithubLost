// OGL Web 冷启动探针
//
// 口径：
//   · 网络加载完成 = 应用框架内最后一个资源 responseEnd；
//   · 应用首帧     = Flutter 插入首个视图元素（flt-glass-pane / flutter-view）；
//   · 初始化       = 首帧 − 网络完成（**验收指标，预算 5 秒**）。
//
// 同时测三条路径：入口（按浏览器能力自动选路）、wasm 桶、js 桶。
// 每条路径跑两档网络：直连、4G（1.6 Mbps / 150 ms）。
//
// 用法：node tool/web_perf_probe.mjs <站点地址> [预算毫秒]

import { chromium } from 'playwright';

const base = (process.argv[2] || 'https://oghapp.344977.xyz/').replace(/\/?$/, '/');
const budgetMs = Number(process.argv[3] || 5000);

const PROFILES = [
  { name: '直连', latency: 0, down: -1, up: -1 },
  { name: '4G', latency: 150, down: (1.6 * 1024 * 1024) / 8, up: (750 * 1024) / 8 },
];

const fmt = (ms) => (ms == null ? '—' : `${(ms / 1000).toFixed(2)} s`);

async function latestDir() {
  try {
    const r = await fetch(base + 'versions.json');
    const list = await r.json();
    return list?.[0]?.dir || null;
  } catch {
    return null;
  }
}

async function measure(browser, url, profile) {
  const context = await browser.newContext();
  const page = await context.newPage();
  const cdp = await context.newCDPSession(page);
  await cdp.send('Network.enable');
  if (profile.latency) {
    await cdp.send('Network.emulateNetworkConditions', {
      offline: false,
      latency: profile.latency,
      downloadThroughput: profile.down,
      uploadThroughput: profile.up,
    });
  }

  const t0 = Date.now();
  await page.goto(url, { waitUntil: 'domcontentloaded', timeout: 180000 });

  // 应用可能在 iframe 里（入口页），也可能就是主框架（桶直连）
  let frame = null;
  for (let i = 0; i < 900; i++) {
    frame = page
      .frames()
      .find((f) => /\/(js|wasm)\//.test(f.url()) && f !== page.mainFrame()) || null;
    if (!frame && /\/(js|wasm)\//.test(page.url())) frame = page.mainFrame();
    if (frame) break;
    await page.waitForTimeout(100);
  }
  if (!frame) throw new Error('未找到应用框架');

  const variant = frame.url().includes('/wasm/') ? 'wasm' : 'js';
  await frame.waitForSelector('flt-glass-pane, flt-scene-host, flutter-view', { timeout: 300000 });
  const firstFrame = Date.now() - t0;

  const m = await frame.evaluate(() => {
    const res = performance.getEntriesByType('resource');
    const nav = performance.getEntriesByType('navigation')[0] || {};
    let lastEnd = nav.responseEnd || 0;
    let bytes = 0;
    for (const r of res) {
      if (r.responseEnd > lastEnd) lastEnd = r.responseEnd;
      bytes += r.transferSize || 0;
    }
    const names = res.map((r) => r.name);
    return {
      lastEnd,
      bytes,
      count: res.length,
      usedWasm: names.some((n) => n.includes('main.dart.wasm')),
      usedJs: names.some((n) => n.includes('main.dart.js')),
    };
  });

  await context.close();
  const engine = m.usedWasm ? 'dart2wasm' : m.usedJs ? 'dart2js' : '?';
  return { variant, engine, firstFrame, init: Math.max(0, firstFrame - m.lastEnd), ...m };
}

const dir = await latestDir();
const targets = [{ label: '入口（自动选路）', url: base }];
if (dir) {
  targets.push({ label: `wasm 桶（${dir}）`, url: `${base}wasm/${dir}/` });
  targets.push({ label: `js 桶（${dir}）`, url: `${base}js/${dir}/` });
}

const browser = await chromium.launch({ args: ['--no-sandbox'] });
const rows = [];
for (const target of targets) {
  for (const p of PROFILES) {
    try {
      const r = await measure(browser, target.url, p);
      rows.push({ label: target.label, profile: p.name, ...r });
    } catch (e) {
      rows.push({ label: target.label, profile: p.name, error: String(e).slice(0, 90) });
    }
  }
}
await browser.close();

const ok = rows.filter((r) => !r.error);
// 验收只看 wasm 路径（dart2wasm 渲染），js 路径仅作参考。
const wasmRows = ok.filter((r) => r.engine === 'dart2wasm');
const worst = wasmRows.length ? Math.max(...wasmRows.map((r) => r.init)) : Infinity;

const out = ['### OGL Web 冷启动实测', '', `- 站点：${base}`, `- 预算：网络完成 → 首帧 **${fmt(budgetMs)}**`, ''];
out.push('| 路径 | 网络 | 变体 | 网络完成 | 首帧 | **初始化** | 传输 | 请求 |');
out.push('| --- | --- | --- | ---: | ---: | ---: | ---: | ---: |');
for (const r of rows) {
  if (r.error) {
    out.push(`| ${r.label} | ${r.profile} | — | — | — | 失败：${r.error} | — | — |`);
    continue;
  }
  out.push(
    `| ${r.label} | ${r.profile} | ${r.engine} | ${fmt(r.lastEnd)} | ${fmt(r.firstFrame)} | **${fmt(r.init)}** | ${(r.bytes / 1048576).toFixed(2)} MB | ${r.count} |`,
  );
}
out.push('');
const passed = wasmRows.length > 0 && worst <= budgetMs;
out.push(`**结论：${passed ? '通过' : '未通过'}**（wasm 路径最差初始化 ${fmt(worst)} / 预算 ${fmt(budgetMs)}；js 路径仅供参考，不计入验收）`);
console.log(out.join('\n'));
process.exit(passed ? 0 : 1);
