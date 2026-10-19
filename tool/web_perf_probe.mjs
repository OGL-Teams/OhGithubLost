// OGL Web 冷启动探针
//
// 目的：把"网络加载完成 → 应用首帧"这段时间单独量出来，作为冷启动的
// 验收指标（目标：5 秒内）。同时在报告里给出链路与体积数据，便于区分
// "网络慢"与"初始化慢"两类问题。
//
// 用法：node tool/web_perf_probe.mjs <url> [预算毫秒]
// 输出：标准输出一份 Markdown 表格（可直接进 $GITHUB_STEP_SUMMARY），
//       并以退出码 1 表示超出预算。

import { chromium } from 'playwright';

const url = process.argv[2] || 'https://oghapp.344977.xyz/';
const budgetMs = Number(process.argv[3] || 5000);

function fmt(ms) {
  return ms == null ? '—' : `${(ms / 1000).toFixed(2)} s`;
}

const browser = await chromium.launch({ args: ['--no-sandbox'] });
const context = await browser.newContext({ bypassCSP: false });
const page = await context.newPage();

const t0 = Date.now();
await page.goto(url, { waitUntil: 'domcontentloaded', timeout: 120000 });

// 应用被 iframe 包住：找到承载 Flutter 的子框架
let appFrame = null;
for (let i = 0; i < 600; i++) {
  appFrame = page.frames().find((f) => /\/(js|wasm)\//.test(f.url()));
  if (appFrame) break;
  await page.waitForTimeout(100);
}
if (!appFrame) {
  console.error('未找到应用框架');
  process.exit(2);
}
const variant = appFrame.url().includes('/wasm/') ? 'wasm(dart2wasm)' : 'js(dart2js)';

// Flutter 首帧会插入 <flt-glass-pane>（或 flt-scene-host），等它出现即为可交互
const frameSelector = 'flt-glass-pane, flt-scene-host, flutter-view';
await appFrame.waitForSelector(frameSelector, { timeout: 180000 });
const firstFrameAt = Date.now();
const firstFrame = firstFrameAt - t0;

// 在应用框架内读取资源时序：网络完成时刻 = 最后一个资源的 responseEnd
const metrics = await appFrame.evaluate((navStart) => {
  const res = performance.getEntriesByType('resource');
  const nav = performance.getEntriesByType('navigation')[0] || {};
  let lastEnd = nav.responseEnd || 0;
  let bytes = 0;
  const big = [];
  for (const r of res) {
    if (r.responseEnd > lastEnd) lastEnd = r.responseEnd;
    bytes += r.transferSize || 0;
    big.push({ name: r.name.split('/').pop(), kb: Math.round((r.transferSize || 0) / 1024), ms: Math.round(r.duration) });
  }
  const ttfb = nav.responseStart || 0;
  const dcl = nav.domContentLoadedEventEnd || 0;
  return { ttfb, dcl, lastResourceEnd: lastEnd, bytes, count: res.length, big };
}, 0);

const firstFrameP = firstFrame; // 自导航起算
const initMs = Math.max(0, firstFrameP - metrics.lastResourceEnd);
const totalBytesMb = (metrics.bytes / 1048576).toFixed(2);

const top = metrics.big
  .sort((a, b) => b.kb - a.kb)
  .slice(0, 8)
  .map((r) => `| ${r.name} | ${r.kb} KB | ${r.ms} ms |`)
  .join('\n');

const lines = [];
lines.push(`### OGL Web 冷启动探针`);
lines.push('');
lines.push(`- 目标地址：${url}`);
lines.push(`- 渲染变体：**${variant}**`);
lines.push(`- 预算（网络完成后）：${fmt(budgetMs)}`);
lines.push('');
lines.push('| 指标 | 用时 |');
lines.push('| --- | ---: |');
lines.push(`| 首字节（TTFB） | ${fmt(metrics.ttfb)} |`);
lines.push(`| DOM 解析完成 | ${fmt(metrics.dcl)} |`);
lines.push(`| **网络加载完成**（最后一个资源） | ${fmt(metrics.lastResourceEnd)} |`);
lines.push(`| **应用首帧**（自导航起算） | ${fmt(firstFrameP)} |`);
lines.push(`| **初始化用时**（网络完成 → 首帧） | **${fmt(initMs)}** |`);
lines.push(`| 传输总量 | ${totalBytesMb} MB / ${metrics.count} 个请求 |`);
lines.push('');
lines.push('体积最大的资源：');
lines.push('');
lines.push('| 资源 | 传输 | 耗时 |');
lines.push('| --- | ---: | ---: |');
lines.push(top);
lines.push('');
const verdict = initMs <= budgetMs ? '通过' : '超出预算';
lines.push(`**结论：${verdict}**（初始化 ${fmt(initMs)} / 预算 ${fmt(budgetMs)}）`);

const report = lines.join('\n');
console.log(report);

await browser.close();
process.exit(initMs <= budgetMs ? 0 : 1);
