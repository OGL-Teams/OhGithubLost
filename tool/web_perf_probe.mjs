// OGL Web 冷启动探针
//
// 目的：把冷启动拆成「链路」与「初始化」两段分别计量，作为验收口径：
//   · 链路：导航 → 最后一个资源下载完成；
//   · 初始化：最后一个资源完成 → 应用首帧（Flutter 插入视图）。
// 目标：**初始化 5 秒内**（网络完成后的时间，与用户口径一致）。
//
// 两档条件各测一次：
//   · 直连：CI 机房网络，反映初始化本身的成本；
//   · 4G：1.6 Mbps / 150 ms RTT，模拟移动网络下的真实冷启动。
//
// 用法：node tool/web_perf_probe.mjs <url> [预算毫秒]
// 输出：Markdown（可直接进 $GITHUB_STEP_SUMMARY）；超预算退出码 1。

import { chromium } from 'playwright';

const url = process.argv[2] || 'https://oghapp.344977.xyz/';
const budgetMs = Number(process.argv[3] || 5000);

const PROFILES = [
  { name: '直连（机房网络）', latency: 0, down: -1, up: -1 },
  { name: '4G（1.6 Mbps / 150 ms）', latency: 150, down: 1.6 * 1024 * 1024 / 8, up: 750 * 1024 / 8 },
];

const fmt = (ms) => (ms == null ? '—' : `${(ms / 1000).toFixed(2)} s`);

async function measure(browser, profile) {
  const context = await browser.newContext(); // 每个档位都用全新上下文：无缓存
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

  let appFrame = null;
  for (let i = 0; i < 900; i++) {
    appFrame = page.frames().find((f) => /\/(js|wasm)\//.test(f.url()));
    if (appFrame) break;
    await page.waitForTimeout(100);
  }
  if (!appFrame) throw new Error('未找到应用框架');

  const variant = appFrame.url().includes('/wasm/') ? 'wasm(dart2wasm)' : 'js(dart2js)';
  await appFrame.waitForSelector('flt-glass-pane, flt-scene-host, flutter-view', { timeout: 300000 });
  const firstFrame = Date.now() - t0;

  const m = await appFrame.evaluate(() => {
    const res = performance.getEntriesByType('resource');
    const nav = performance.getEntriesByType('navigation')[0] || {};
    let lastEnd = nav.responseEnd || 0;
    let bytes = 0;
    const big = [];
    for (const r of res) {
      if (r.responseEnd > lastEnd) lastEnd = r.responseEnd;
      bytes += r.transferSize || 0;
      big.push({ name: r.name.split('/').pop(), kb: Math.round((r.transferSize || 0) / 1024) });
    }
    return { ttfb: nav.responseStart || 0, dcl: nav.domContentLoadedEventEnd || 0, lastEnd, bytes, count: res.length, big };
  });

  const init = Math.max(0, firstFrame - m.lastEnd);
  await context.close();
  return { ...m, firstFrame, init, variant, profile: profile.name };
}

const browser = await chromium.launch({ args: ['--no-sandbox'] });
const rows = [];
let worstInit = 0;
for (const p of PROFILES) {
  try {
    const r = await measure(browser, p);
    rows.push(r);
    worstInit = Math.max(worstInit, r.init);
  } catch (e) {
    rows.push({ profile: p.name, error: String(e).slice(0, 120) });
  }
}
await browser.close();

const lines = ['### OGL Web 冷启动实测', '', `- 地址：${url}`, `- 预算（网络完成后 → 首帧）：**${fmt(budgetMs)}**`, ''];
lines.push('| 条件 | 渲染变体 | 网络加载完成 | 应用首帧 | **初始化** | 传输量 | 请求数 |');
lines.push('| --- | --- | ---: | ---: | ---: | ---: | ---: |');
for (const r of rows) {
  if (r.error) {
    lines.push(`| ${r.profile} | — | — | — | 失败：${r.error} | — | — |`);
    continue;
  }
  lines.push(`| ${r.profile} | ${r.variant} | ${fmt(r.lastEnd)} | ${fmt(r.firstFrame)} | **${fmt(r.init)}** | ${(r.bytes / 1048576).toFixed(2)} MB | ${r.count} |`);
}
lines.push('');

const ok = rows.filter((r) => !r.error);
if (ok.length) {
  const big = ok[0].big.sort((a, b) => b.kb - a.kb).slice(0, 6);
  lines.push('直连条件下的主要传输：');
  lines.push('');
  lines.push('| 资源 | 传输 |');
  lines.push('| --- | ---: |');
  for (const b of big) lines.push(`| ${b.name} | ${b.kb} KB |`);
  lines.push('');
}
lines.push(`**结论：${worstInit <= budgetMs ? '通过' : '未通过'}**（最差初始化 ${fmt(worstInit)} / 预算 ${fmt(budgetMs)}）`);

console.log(lines.join('\n'));
process.exit(worstInit <= budgetMs && ok.length === PROFILES.length ? 0 : 1);
