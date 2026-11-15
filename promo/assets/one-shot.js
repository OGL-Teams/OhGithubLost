// OhGithubLost · Three.js 一镜到底
// -----------------------------------------------------------------------------
// 契约（HyperFrames runtimes.md / types/3d.md）：
// - 每一帧都从 hf-seek 的 e.detail.time 纯函数求值；frame 可以乱序渲染
// - 只有一个 canvas、一个 WebGLRenderer、一台 camera；没有 scene host 切换、没有 wipe
// - 不使用 requestAnimationFrame / Date.now / Math.random / setInterval / renderer.setAnimationLoop
// - setup 注册 window.__hf.buildReady.oneShot，首个 seek 等它完成
// - 所有素材在 setup 里加载完，之后只改 transform / opacity / material 参数
//
// 空间设计：亮色「GitHub 工作流长廊」。11 个站点沿 Z 轴排布，相机从 z=+34
// 连续飞到 z=-170；每个站点 = 一张烘焙好的中文信息面板 + 一张实机截图平面，
// 两者略微错开角度，但不倾斜到无法阅读。地面网格、浮空线框与柔光条提供纵深。
// -----------------------------------------------------------------------------
import * as THREE from "three";

const W = 1920;
const H = 1080;
const DUR = 175.01;

const canvas = document.getElementById("gl");
const chapterEl = document.getElementById("chapter");
const progressEl = document.getElementById("progress-fill");

const renderer = new THREE.WebGLRenderer({
  canvas,
  antialias: true,
  alpha: false,
  preserveDrawingBuffer: true,
  powerPreference: "high-performance",
});
renderer.setPixelRatio(1);
renderer.setSize(W, H, false);
renderer.setClearColor(0xf7f9fc, 1);
renderer.outputColorSpace = THREE.SRGBColorSpace;
renderer.toneMapping = THREE.ACESFilmicToneMapping;
renderer.toneMappingExposure = 1.08;
renderer.shadowMap.enabled = true;
renderer.shadowMap.type = THREE.PCFSoftShadowMap;

const scene = new THREE.Scene();
scene.background = new THREE.Color(0xf7f9fc);
scene.fog = new THREE.Fog(0xf7f9fc, 46, 180);

const camera = new THREE.PerspectiveCamera(42, W / H, 0.1, 400);
camera.position.set(0, 3.2, 34);

// ---- 灯光：亮色、柔、冷白，少量品牌蓝边缘光 ----
scene.add(new THREE.HemisphereLight(0xffffff, 0xdfe7f2, 1.45));
const key = new THREE.DirectionalLight(0xffffff, 1.6);
key.position.set(12, 22, 20);
key.castShadow = true;
key.shadow.mapSize.set(1024, 1024);
key.shadow.camera.near = 1;
key.shadow.camera.far = 200;
key.shadow.camera.left = -30;
key.shadow.camera.right = 30;
key.shadow.camera.top = 30;
key.shadow.camera.bottom = -30;
scene.add(key);
const rim = new THREE.DirectionalLight(0x8ab4ff, 0.9);
rim.position.set(-18, 10, -40);
scene.add(rim);

// ---- 材质与几何 ----
const matPanel = new THREE.MeshStandardMaterial({
  color: 0xffffff, roughness: 0.62, metalness: 0.02,
  side: THREE.DoubleSide,
});
const matShot = new THREE.MeshStandardMaterial({
  color: 0xffffff, roughness: 0.55, metalness: 0.0,
  side: THREE.DoubleSide,
});
const matFrame = new THREE.MeshStandardMaterial({
  color: 0xd7e3ff, roughness: 0.5, metalness: 0.1,
});
const matLine = new THREE.LineBasicMaterial({ color: 0x0b57d0, transparent: true, opacity: 0.22 });
const matDot = new THREE.MeshBasicMaterial({ color: 0x0b57d0 });
const matGold = new THREE.MeshBasicMaterial({ color: 0xb26a00 });

// 亮色地面：一层大平面 + 规则网格线，提供连续飞行的速度感
const floor = new THREE.Mesh(
  new THREE.PlaneGeometry(120, 320),
  new THREE.MeshStandardMaterial({ color: 0xeef3fb, roughness: 0.92, metalness: 0.0 })
);
floor.rotation.x = -Math.PI / 2;
floor.position.set(0, -6, -70);
floor.receiveShadow = true;
scene.add(floor);

const grid = new THREE.GridHelper(320, 64, 0x9ab4d8, 0xd9e2f0);
grid.position.set(0, -5.98, -70);
grid.material.transparent = true;
grid.material.opacity = 0.34;
scene.add(grid);

// 纵向「导轨」：一条品牌蓝细线贯穿 175s 的飞行路径
const railGeo = new THREE.BufferGeometry().setFromPoints([
  new THREE.Vector3(0, -5.8, 32),
  new THREE.Vector3(0, -5.8, -178),
]);
scene.add(new THREE.Line(railGeo, new THREE.LineBasicMaterial({ color: 0x0b57d0, transparent: true, opacity: 0.34 })));

// ---- 站点 ----
const STATIONS = [
  { t: 0,    z: 20,    panel: "panel-00.png", shot: null,                 chapter: "00 · 开场" },
  { t: 14,   z: 1,     panel: "panel-01.png", shot: "06-repo-files.png",   chapter: "01 · 仓库" },
  { t: 30,   z: -18,   panel: "panel-02.png", shot: "07-code-view.png",    chapter: "02 · 代码" },
  { t: 46,   z: -37,   panel: "panel-03.png", shot: "08-editor-save.png",  chapter: "03 · 编辑" },
  { t: 62,   z: -56,   panel: "panel-04.png", shot: "09-issue-comment.png",chapter: "04 · Issue" },
  { t: 80,   z: -74,   panel: "panel-05.png", shot: "11-log.png",          chapter: "05 · 日志" },
  { t: 96,   z: -93,   panel: "panel-06.png", shot: "10-network-dns.png",  chapter: "06 · 网络" },
  { t: 116,  z: -112,  panel: "panel-07.png", shot: "12-legal.png",        chapter: "07 · 法律" },
  { t: 134,  z: -130,  panel: "panel-08.png", shot: "03-profile.png",      chapter: "08 · 账号" },
  { t: 150,  z: -148,  panel: "panel-09.png", shot: "05-about.png",        chapter: "09 · 产物" },
  { t: 168,  z: -166,  panel: "panel-10.png", shot: null,                 chapter: "10 · 片尾" },
];

const PANEL_W = 9.6;
const PANEL_H = 6.0;
const SHOT_W = 3.6;
const SHOT_H = 6.4;

function loadTexture(url) {
  return new Promise((resolve, reject) => {
    const loader = new THREE.TextureLoader();
    loader.load(url, (tex) => {
      tex.colorSpace = THREE.SRGBColorSpace;
      tex.anisotropy = Math.min(8, renderer.capabilities.getMaxAnisotropy());
      tex.needsUpdate = true;
      resolve(tex);
    }, undefined, reject);
  });
}

function makeFrame(group, w, h, x) {
  const back = new THREE.Mesh(
    new THREE.PlaneGeometry(w + 0.26, h + 0.26),
    matFrame.clone()
  );
  back.position.set(x, 0, -0.04);
  back.castShadow = true;
  back.receiveShadow = true;
  group.add(back);
  return back;
}

const stations = [];

async function buildStations() {
  const tasks = [];
  for (const s of STATIONS) {
    const group = new THREE.Group();
    group.position.set(0, 0, s.z);

    const pGeo = new THREE.PlaneGeometry(PANEL_W, PANEL_H);
    const pMat = matPanel.clone();
    const panel = new THREE.Mesh(pGeo, pMat);
    panel.position.set(-2.8, 0.6, 0);
    panel.rotation.y = 0.045;           // 极轻微角度，文字仍可读
    panel.castShadow = true;
    group.add(panel);
    const pFrame = makeFrame(group, PANEL_W, PANEL_H, -2.8);
    pFrame.rotation.y = panel.rotation.y;
    pFrame.position.z = -0.05;

    let shot = null;
    let sFrame = null;
    if (s.shot) {
      const sGeo = new THREE.PlaneGeometry(SHOT_W, SHOT_H);
      const sMat = matShot.clone();
      shot = new THREE.Mesh(sGeo, sMat);
      shot.position.set(5.6, 0.35, 0.2);
      shot.rotation.y = -0.05;
      shot.castShadow = true;
      group.add(shot);
      sFrame = makeFrame(group, SHOT_W, SHOT_H, 5.6);
      sFrame.position.set(5.6, 0.35, 0.14);
      sFrame.rotation.y = shot.rotation.y;
    } else {
      // 片头/片尾：右侧放一组轻质线框块，避免空场
      const box = new THREE.Mesh(
        new THREE.BoxGeometry(3.6, 3.6, 3.6),
        new THREE.MeshStandardMaterial({ color: 0xdce8ff, roughness: 0.5, metalness: 0.12 })
      );
      box.position.set(5.4, 0.4, 0.2);
      box.rotation.set(0.18, 0.35, 0.08);
      box.castShadow = true;
      group.add(box);
      const edges = new THREE.LineSegments(
        new THREE.EdgesGeometry(box.geometry),
        new THREE.LineBasicMaterial({ color: 0x0b57d0, transparent: true, opacity: 0.42 })
      );
      edges.position.copy(box.position);
      edges.rotation.copy(box.rotation);
      group.add(edges);
    }

    // 站点标牌：4 个小圆点 + 一条短横线，作为空间锚点
    for (let i = 0; i < 4; i++) {
      const dot = new THREE.Mesh(new THREE.SphereGeometry(0.075, 12, 12), i === 0 ? matGold : matDot);
      dot.position.set(-8 + i * 0.34, -3.4, 0.4);
      group.add(dot);
    }
    const tick = new THREE.Mesh(new THREE.BoxGeometry(2.6, 0.03, 0.03), matDot);
    tick.position.set(-6.7, -3.4, 0.4);
    group.add(tick);

    // 浮空信息线：在面板与截图之间连一条细线
    const linkGeo = new THREE.BufferGeometry().setFromPoints([
      new THREE.Vector3(2.1, 0.6, 0.15),
      new THREE.Vector3(3.7, 0.6, 0.15),
    ]);
    const link = new THREE.Line(linkGeo, matLine);
    group.add(link);

    scene.add(group);
    const item = { def: s, group, panel, shot, link, pMat, sMat: shot && shot.material };
    stations.push(item);

    tasks.push(
      loadTexture(`assets/panels/${s.panel}`).then((tex) => { pMat.map = tex; pMat.needsUpdate = true; })
    );
    if (s.shot) {
      tasks.push(
        loadTexture(`assets/screens/${s.shot}`).then((tex) => { item.sMat.map = tex; item.sMat.needsUpdate = true; })
      );
    }
  }
  await Promise.all(tasks);
}

// ---- 连续飞行：相机 z 由 t 线性推进，站点自身也做轻微的呼吸/摆动 ----
function smoothstep(a, b, x) {
  const u = Math.max(0, Math.min(1, (x - a) / (b - a)));
  return u * u * (3 - 2 * u);
}

function poseAt(t) {
  const u = Math.max(0, Math.min(1, t / DUR));
  // 一镜到底：z 从 +34 推进到约 -158（终点站点再留 8 单位余量），
  // 避免相机贴到片尾截图平面上造成局部放大破图；x/y 用低频正弦制造手持感
  camera.position.set(
    Math.sin(t * 0.055) * 1.15 + Math.sin(t * 0.013) * 0.55,
    3.0 + Math.sin(t * 0.041) * 0.35,
    34 - u * 192
  );
  // 始终看向下一站点附近：不是硬切，而是连续 look-ahead
  const lookZ = camera.position.z - 21;
  const lookY = 0.4 + Math.sin(t * 0.031) * 0.35;
  camera.lookAt(Math.sin(t * 0.021) * 0.9, lookY, lookZ);
  camera.rotation.z = Math.sin(t * 0.018) * 0.006;

  // 站点靠近时从 0.86 放大到 1.0 再缩回，形成「经过」而非「切到」
  stations.forEach((s, i) => {
    const dz = camera.position.z - s.def.z;
    const near = Math.exp(-Math.pow(dz / 10, 2));
    const scale = 0.94 + 0.06 * near;
    s.group.scale.setScalar(scale);
    s.group.position.y = Math.sin(t * 0.5 + i * 0.7) * 0.12 * (1 - near);
    s.group.rotation.y = Math.sin(t * 0.18 + i) * 0.012;
    s.pMat.opacity = 0.72 + 0.28 * near;
    s.pMat.transparent = true;
    if (s.sMat) {
      s.sMat.opacity = 0.7 + 0.3 * near;
      s.sMat.transparent = true;
    }
    s.link.material.opacity = 0.08 + 0.32 * near;
  });

  // 雾与曝光随 BGM 段落轻微变化（亮色，不变暗）
  const bloom = smoothstep(90, 120, t) * (1 - smoothstep(160, 175, t));
  renderer.toneMappingExposure = 1.06 + 0.08 * bloom;
  scene.fog.near = 42 + 8 * bloom;
  scene.fog.far = 170 + 18 * bloom;

  // HUD 进度与章节名（纯时间函数）
  progressEl.style.width = `${(u * 100).toFixed(2)}%`;
  let chap = STATIONS[0].chapter;
  for (const s of STATIONS) if (t >= s.t) chap = s.chapter;
  chapterEl.textContent = chap;
}

// ---- setup：编译 shader + 首帧 GPU 读回，避免第一帧与后续不一致 ----
function waitForGpu() {
  const gl = renderer.getContext();
  renderer.setRenderTarget(null);
  const px = new Uint8Array(4);
  gl.readPixels(0, 0, 1, 1, gl.RGBA, gl.UNSIGNED_BYTE, px);
}

async function setup() {
  await buildStations();
  poseAt(0);
  await renderer.compileAsync(scene, camera);
  renderer.render(scene, camera);
  waitForGpu();
}

const ready = setup();
window.__hf = window.__hf || {};
window.__hf.buildReady = window.__hf.buildReady || {};
window.__hf.buildReady["oneShot"] = ready;

let queue = ready;
let shownTime = null;
window.addEventListener("hf-seek", (e) => {
  const t = Number(e.detail.time);
  queue = queue
    .catch(() => {})
    .then(() => ready)
    .then(() => {
      if (t === shownTime) return;
      poseAt(t);
      renderer.render(scene, camera);
      waitForGpu();
      shownTime = t;
    });
  e.detail.waitUntil(queue);
});

// 根 timeline：canvas 自己 seek，注册一个空的 paused timeline 满足 runtime
window.__timelines = window.__timelines || {};
window.__timelines["main"] = gsap.timeline({ paused: true });
