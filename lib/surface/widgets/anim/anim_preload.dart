/// L3 展示级 · 动画**分级预加载**（跟着动效档位走；有上限、可取消、空闲调度）。
///
/// ## 它解决什么
/// 低性能设备上"第一次出现"的动画最容易卡：首帧要建图层、要解码图片、
/// 要现算过渡参数。预加载就是把这些**一次性成本**提前做掉。但预加载本身
/// 也吃 CPU / 内存 —— 所以它必须**跟着档位走**，而不是"一律全预热"。
///
/// ## 分级策略（唯一事实来源 = [kOgLAnimPreloadPolicies]，不要在别处写 if）
///
/// | level | 名称 | 策略 |
/// |---|---|---|
/// | 0 | 最低级 | **不预加载**（`maxJobs = 0`：任何登记都被拒） |
/// | 1 | 第二级 | **仅预加载当前页面**（`currentPage`） |
/// | 2 | 倒数第二级 | **预加载最多**，以**全屏动画**为主（`currentPage` + `fullScreen`，额度最大） |
/// | 3 | 最高级 | **当前层级 + 下一子层级的主要动画**（`currentPage` + `fullScreen` + `childLevel`） |
///
/// 注：档位 2 的**总额度**（数量 / 内存）刻意大于档位 3 —— 用户口径是
/// "倒数第二级预加载最多"；档位 3 虽然多了一类（子层级），但每类更克制，
/// 因为它要同时覆盖**两层**。
///
/// ## "全屏动画"的判定口径（哪些按 [OgLAnimPreloadKind.fullScreen] 登记）
/// 满足任一条即算：
/// 1. **路由转场**：`PageRoute` 的过渡（即 `OgLMotion.pageTransitions` 产出的
///    `PageTransitionsBuilder`，经 `ThemeData.pageTransitionsTheme` 全局生效）
///    —— 整页参与；
/// 2. **同一路由内的整页 / 半页内容替换**：`OgLSurfaceSwitch`（loading → data）、
///    `OgLClientShell` 的 tab 切换滑动（`_OgLShellSlide`）、引导页整页翻页
///    （`PageView`，时长取自 `OgLAnim.pageViewDuration`）；
/// 3. **全屏弹层**：`showModalBottomSheet` / `showDialog`（半屏及以上，时长取自
///    `OgLAnim.sheetDuration`）。
///
/// **不算**全屏（按 [OgLAnimPreloadKind.currentPage] 登记）：列表单项入场
///（`OgLReveal`）、按钮 / 开关的状态反馈、单行 `AnimatedContainer` 之类。
///
/// ## 三条纪律
/// 1. **幂等**：同一个 `id` 重复登记只跑一次（在途去重 + **有界**的已完成记录）；
/// 2. **有上限**：数量上限 [OgLAnimPreloadPolicy.maxJobs] + 内存上限
///    [OgLAnimPreloadPolicy.maxBytes]（在**登记时**就预扣估算字节），
///    超限一律**拒收**而不是排队堆积 —— "不要过了"；
/// 3. **可取消且不泄漏**：本模块**不持有** `BuildContext` / `Element` / `State`
///    （图片直接走 `ImageProvider.resolve`，与页面无绑定）。取消 = 未开始项
///    直接丢弃（并把它占的额度还回去）+ 已开始的图片项按需摘除监听。
library;

import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../app/motion.dart';

/// 预加载对象的**类别**：决定它在哪一档被允许（见 [kOgLAnimPreloadPolicies]）。
enum OgLAnimPreloadKind {
  /// 当前页面自身的动画（本页一进来就要用到的元素 / 图片）。
  currentPage,

  /// **全屏动画**（判定口径见库文档：路由转场 / 整页内容替换 / 全屏弹层）。
  fullScreen,

  /// **下一子层级的主要动画**（即将 push 的子页面、即将展开的子层级）。
  childLevel,
}

/// 一个档位的预加载策略（**纯数据**，可单测；不含任何运行时状态）。
@immutable
class OgLAnimPreloadPolicy {
  /// 创建。
  const OgLAnimPreloadPolicy({
    required this.level,
    required this.label,
    required this.kinds,
    required this.maxJobs,
    required this.maxBytes,
    required this.jobsPerIdleSlot,
  });

  /// 档位（0–3）。
  final int level;

  /// 档位名称（诊断用，非界面文案）。
  final String label;

  /// 本档允许登记的类别。
  final Set<OgLAnimPreloadKind> kinds;

  /// **数量上限**（同时驻留的预加载项；超出即拒收）。
  final int maxJobs;

  /// **内存上限**（估算字节；在途额度在登记时预扣）。
  final int maxBytes;

  /// 每个空闲窗口最多推进几项（保证不与渲染争资源）。
  final int jobsPerIdleSlot;

  /// 是否允许登记 [kind] 类别的预加载。
  bool admits(OgLAnimPreloadKind kind) => kinds.contains(kind);

  /// 档位 0 的"关闭"策略（越界档位一律按它处理：**少做**永远比多做安全）。
  static const OgLAnimPreloadPolicy off = OgLAnimPreloadPolicy(
    level: 0,
    label: 'off',
    kinds: <OgLAnimPreloadKind>{},
    maxJobs: 0,
    maxBytes: 0,
    jobsPerIdleSlot: 0,
  );
}

/// 千字节（让策略表里的内存额度可读）。
const int _kKiB = 1024;

/// 兆字节。
const int _kMiB = 1024 * _kKiB;

/// **分级预加载策略表**（唯一事实来源）。
///
/// 用户口径（原话）：
/// - 最低级（0）**不预加载**；
/// - 倒数第二级（2）**预加载最多**，主要为**全屏动画**；
/// - 第二级（1）**仅预加载当前页面**；
/// - 最高级（3）预加载**当前层级和下一个子层级的主要动画**。
///
/// 要调预加载力度，**只改这张表**（别在调用点写 `if (level >= 2)`）。
const List<OgLAnimPreloadPolicy> kOgLAnimPreloadPolicies =
    <OgLAnimPreloadPolicy>[
  // level 0 · 最低级：不预加载。
  OgLAnimPreloadPolicy.off,
  // level 1 · 第二级：仅当前页面（最少）。
  OgLAnimPreloadPolicy(
    level: 1,
    label: 'current-page-only',
    kinds: <OgLAnimPreloadKind>{OgLAnimPreloadKind.currentPage},
    maxJobs: 8,
    maxBytes: 4 * _kMiB,
    jobsPerIdleSlot: 1,
  ),
  // level 2 · 倒数第二级：预加载**最多**，以全屏动画为主。
  OgLAnimPreloadPolicy(
    level: 2,
    label: 'fullscreen-first',
    kinds: <OgLAnimPreloadKind>{
      OgLAnimPreloadKind.currentPage,
      OgLAnimPreloadKind.fullScreen,
    },
    maxJobs: 24,
    maxBytes: 16 * _kMiB,
    jobsPerIdleSlot: 2,
  ),
  // level 3 · 最高级：当前层级 + 下一子层级的主要动画（克制地为两层打算）。
  OgLAnimPreloadPolicy(
    level: 3,
    label: 'current-and-child',
    kinds: <OgLAnimPreloadKind>{
      OgLAnimPreloadKind.currentPage,
      OgLAnimPreloadKind.fullScreen,
      OgLAnimPreloadKind.childLevel,
    },
    maxJobs: 18,
    maxBytes: 10 * _kMiB,
    jobsPerIdleSlot: 1,
  ),
];

/// 取某一档的策略（越界 → [OgLAnimPreloadPolicy.off]）。
OgLAnimPreloadPolicy ogLAnimPreloadPolicyFor(int level) {
  if (level <= 0 || level >= kOgLAnimPreloadPolicies.length) {
    return OgLAnimPreloadPolicy.off;
  }
  return kOgLAnimPreloadPolicies[level];
}

/// 一项预加载任务（**幂等键 = [id]**）。
class OgLAnimPreloadJob {
  /// 图片预加载：走 `ImageProvider.resolve`（**不需要 `BuildContext`**，因此不会
  /// 把页面 / Element 拖住），解码结果进 Flutter 自己的 `ImageCache`，由缓存
  /// 自行淘汰 —— 预加载不参与淘汰策略，所以额度必须自己控住。
  ///
  /// [configuration] 决定缓存键：默认 [ImageConfiguration.empty]（与设备无关，
  /// 任何上下文都能用）。若调用方知道自己那份 `Image` 的像素比 / 尺寸，
  /// 传进来才能命中**同一个**缓存条目，否则会各解一份。
  OgLAnimPreloadJob.image({
    required this.id,
    required this.group,
    required ImageProvider image,
    this.kind = OgLAnimPreloadKind.currentPage,
    this.weightBytes = 2 * _kMiB,
    this.priority = 0,
    ImageConfiguration configuration = ImageConfiguration.empty,
  })  : _image = image,
        _configuration = configuration,
        _run = null;

  /// 自定义任务（例如预热一份数据、预建一次过渡参数）。
  ///
  /// ★ 回调里**不要持有 `BuildContext` / `Element`**（那会把页面拖住不回收）；
  /// 它只适合做"与页面无关"的准备动作。
  OgLAnimPreloadJob.task({
    required this.id,
    required this.group,
    required FutureOr<void> Function() run,
    this.kind = OgLAnimPreloadKind.currentPage,
    this.weightBytes = 256 * _kKiB,
    this.priority = 0,
  })  : _run = run,
        _image = null,
        _configuration = ImageConfiguration.empty;

  /// 幂等键（同一个 id 只跑一次）。
  final String id;

  /// 作用域标识（页面 / tab 级），[OgLAnimPreload.cancelGroup] 按它整组取消。
  final String group;

  /// 类别（决定在哪一档被允许）。
  final OgLAnimPreloadKind kind;

  /// **估算**内存占用（字节）：用于内存上限的预扣。
  final int weightBytes;

  /// 优先级（小的先跑；同优先级按登记顺序）。
  final int priority;

  final ImageProvider? _image;
  final ImageConfiguration _configuration;
  final FutureOr<void> Function()? _run;

  /// 是否已被取消（取消后即便解码完成也不再计入）。
  bool get cancelled => _cancelled;

  bool _cancelled = false;

  /// 额度是否已归还（幂等：完成 / 取消两条路径都可能走到）。
  bool _released = false;

  /// 图片监听是否已摘除（幂等：取消与帧末清理都可能摘）。
  bool _detached = false;

  /// 在途取消钩子（当前只有图片项会带上：摘除 `ImageStreamListener`）。
  void Function()? _abort;
}

/// 预加载的运行统计（**只读快照**，供诊断 / 单测使用）。
@immutable
class OgLAnimPreloadStats {
  /// 创建。
  const OgLAnimPreloadStats({
    required this.level,
    required this.policyLabel,
    required this.registered,
    required this.rejected,
    required this.ran,
    required this.failed,
    required this.cancelled,
    required this.pending,
    required this.running,
    required this.reservedBytes,
    required this.budgetBytes,
  });

  /// 当前档位。
  final int level;

  /// 当前档位策略名。
  final String policyLabel;

  /// 累计成功登记数。
  final int registered;

  /// 因**上限**或**该档不允许**而被拒收的登记数（"不要过了"）。
  final int rejected;

  /// 累计完成数。
  final int ran;

  /// 累计失败数。
  final int failed;

  /// 累计取消数。
  final int cancelled;

  /// 仍在排队（未开始）的数量。
  final int pending;

  /// 已经开始（在途）的数量。
  final int running;

  /// 在途**估算**内存（字节）。
  final int reservedBytes;

  /// 本档允许的在途内存上限（字节）。
  final int budgetBytes;
}

/// 分级预加载的**全局登记处 / 调度器**（一个进程一份）。
///
/// 用法（在页面里，**可选**接入）：
/// ```dart
/// OgLAnimPreload.register(
///   OgLAnimPreloadJob.image(
///     id: 'dashboard-avatar-$userId',
///     group: 'ogl-tab-home',
///     kind: OgLAnimPreloadKind.currentPage,
///     image: NetworkImage(url),
///   ),
/// );
/// OgLAnimPreload.schedule();
/// ```
/// 或者把整页包进 [OgLAnimPreloadBoundary]（它负责“可见就按档位预热、离开就
/// 取消未完成项”）。
abstract final class OgLAnimPreload {
  /// 未开始的任务队列（**有界**：登记时按 [OgLAnimPreloadPolicy.maxJobs] 卡住）。
  static final List<OgLAnimPreloadJob> _queue = <OgLAnimPreloadJob>[];

  /// 在途任务（id → job）；取消时要能摘掉监听，所以按 id 索引。
  static final Map<String, OgLAnimPreloadJob> _running =
      <String, OgLAnimPreloadJob>{};

  /// 排队中的 id（去重用；取消 / 完成即移除）。
  static final Set<String> _pending = <String>{};

  /// **已经跑过**的 id（有界 LRU：只记最近 [_kDoneIdLimit] 个，避免无限增长）。
  static final Set<String> _done = <String>{};

  /// 已完成 id 的记忆上限（**有界**：本模块任何内部结构都不会随时间无限增长）。
  static const int _kDoneIdLimit = 64;

  static OgLAnimPreloadPolicy _policy = OgLAnimPreloadPolicy.off;
  static int _level = 0;
  static int _warmedLevel = -1;
  static int _budgetBytes = 0;
  static int _reservedBytes = 0;
  static bool _scheduled = false;
  static bool _draining = false;

  static int _registeredCount = 0;
  static int _rejectedCount = 0;
  static int _ranCount = 0;
  static int _failedCount = 0;
  static int _cancelledCount = 0;

  /// 当前档位（未预热时为 0 = 不预加载）。
  static int get level => _level;

  /// 当前档位策略。
  static OgLAnimPreloadPolicy get policy => _policy;

  /// 仍在排队（未开始）的任务数。
  static int get pendingCount => _queue.length;

  /// 在途（已开始）的任务数。
  static int get runningCount => _running.length;

  /// 在途**估算**内存（字节）。
  static int get reservedBytes => _reservedBytes;

  /// 本档允许的在途内存上限（字节）。
  static int get budgetBytes => _budgetBytes;

  /// 统计快照。
  static OgLAnimPreloadStats get stats => OgLAnimPreloadStats(
        level: _level,
        policyLabel: _policy.label,
        registered: _registeredCount,
        rejected: _rejectedCount,
        ran: _ranCount,
        failed: _failedCount,
        cancelled: _cancelledCount,
        pending: _queue.length,
        running: _running.length,
        reservedBytes: _reservedBytes,
        budgetBytes: _budgetBytes,
      );

  /// **幂等**的档位切换：把策略表换成 [level] 那份，并做一次"零风险"核心预热。
  ///
  /// 核心预热 = 档位质量表 + 页面过渡主题：这两者都是后续每一次动画都要读的
  /// 东西，提前算掉可以让**第一次**动画（最贵的那次）不再顺带分配它们。
  /// 它不碰图片、不碰页面，所以任何档位下都安全。
  ///
  /// 档位**下调**时会把超出新额度的在途项取消 —— "不要过了"。
  static void warmCore(int level) {
    if (_warmedLevel == level) {
      return;
    }
    _warmedLevel = level;
    _level = level;
    _policy = ogLAnimPreloadPolicyFor(level);
    _budgetBytes = _computeBudget(_policy);
    // 核心预热（无副作用、可重复调用）。
    OgLOAnimQuality.of(level);
    OgLMotion.pageTransitions(level);
    _enforceCaps();
  }

  /// 登记一项预加载。**幂等**：同 [OgLAnimPreloadJob.id] 只跑一次。
  ///
  /// 返回 `false` = 被拒（该档不允许 / 已跑过 / 触到数量或内存上限）。
  /// **拒收而不是排队堆积**，正是"不要过了"的落点。
  static bool register(OgLAnimPreloadJob job) {
    final OgLAnimPreloadPolicy current = _policy;
    if (current.maxJobs <= 0 || !current.admits(job.kind)) {
      _rejectedCount++;
      return false;
    }
    if (_pending.contains(job.id) ||
        _running.containsKey(job.id) ||
        _done.contains(job.id)) {
      return false; // 幂等命中：不算拒收，也不算新登记
    }
    if (_queue.length + _running.length >= current.maxJobs) {
      _rejectedCount++;
      return false;
    }
    if (_reservedBytes + job.weightBytes > _budgetBytes) {
      _rejectedCount++;
      return false;
    }
    job._cancelled = false;
    job._released = false;
    job._detached = false;
    _insertByPriority(job);
    _pending.add(job.id);
    _reservedBytes += job.weightBytes;
    _registeredCount++;
    return true;
  }

  /// 在**空闲时**推进队列：每个空闲窗口只推进
  /// [OgLAnimPreloadPolicy.jobsPerIdleSlot] 项，绝不与首帧 / 当前帧争资源。
  ///
  /// ### 为什么用 `addPostFrameCallback` 而不是 `SchedulerBinding.scheduleTask`
  /// 本模块要求**可取消**，而本项目所用 Flutter 版本的
  /// `SchedulerBinding.scheduleTask` 返回的是一个 `Future`（拿不到可取消的句柄，
  /// 早期版本返回的 `TaskEntry` 已不再暴露）；帧末回调是跨版本稳定的"空闲"
  /// 时机，配合每窗口限额即可达成同样效果：**渲染优先，预加载垫后**。
  static void schedule() {
    if (_scheduled || _queue.isEmpty) {
      return;
    }
    final WidgetsBinding? binding = _binding();
    if (binding == null) {
      return;
    }
    _scheduled = true;
    binding.addPostFrameCallback((Duration _) {
      _scheduled = false;
      _drain();
    });
  }

  /// 取消一个作用域（页面 / tab）的**未完成**预加载，并把它占的额度还回去。
  ///
  /// 页面离开时调用它即可：本模块不持有页面对象，所以取消之后**不留任何
  /// 可达引用**（在途图片项会立刻摘掉 `ImageStreamListener`；已经进入解码的
  /// 那次工作由框架负责收尾，无法从中途回滚 —— `ImageProvider` 不提供取消）。
  static void cancelGroup(String group) {
    for (int i = _queue.length - 1; i >= 0; i--) {
      final OgLAnimPreloadJob job = _queue[i];
      if (job.group != group) {
        continue;
      }
      _queue.removeAt(i);
      _pending.remove(job.id);
      job._cancelled = true;
      _cancelledCount++;
      _release(job);
    }
    for (final String id in _running.keys.toList()) {
      final OgLAnimPreloadJob? job = _running[id];
      if (job == null || job.group != group) {
        continue;
      }
      job._cancelled = true;
      _cancelledCount++;
      final void Function()? abort = job._abort;
      job._abort = null;
      abort?.call();
    }
  }

  /// 取消**全部**未完成项（并清掉幂等记忆，使它们可以被重新登记）。
  static void cancelAll() {
    for (final OgLAnimPreloadJob job in _queue) {
      job._cancelled = true;
      _cancelledCount++;
      _release(job);
    }
    _queue.clear();
    _pending.clear();
    for (final OgLAnimPreloadJob job in _running.values) {
      job._cancelled = true;
      _cancelledCount++;
      final void Function()? abort = job._abort;
      job._abort = null;
      abort?.call();
    }
    _done.clear();
  }

  // ── 内部 ────────────────────────────────────────────────────────────────

  /// 内存上限口径：取"档位表额度"与"图片缓存份额"中的较小者。
  ///
  /// 后半段是个**固定常量**（12 MiB = Flutter `ImageCache` 默认上限 100 MiB 的
  /// 1/8），刻意**不**从 `PaintingBinding.instance` 现取：预加载只是把东西塞进
  /// 图片缓存，缓存自己会淘汰；把预加载压在缓存的一小块里，才不会把用户正常
  /// 浏览要用的缓存挤掉。固定值同时让额度**可预测 / 可单测**（不依赖 binding
  /// 是否已初始化）。
  static const int _kImageCacheShareBytes = 12 * _kMiB;

  static int _computeBudget(OgLAnimPreloadPolicy policy) {
    if (policy.maxBytes <= 0) {
      return 0;
    }
    return policy.maxBytes < _kImageCacheShareBytes
        ? policy.maxBytes
        : _kImageCacheShareBytes;
  }

  /// 按优先级稳定插入（额度很小，线性插入足够）。
  static void _insertByPriority(OgLAnimPreloadJob job) {
    int at = _queue.length;
    for (int i = 0; i < _queue.length; i++) {
      if (_queue[i].priority > job.priority) {
        at = i;
        break;
      }
    }
    _queue.insert(at, job);
  }

  /// 档位变化后收紧：超出的项一律取消（而不是"留着慢慢跑"）。
  static void _enforceCaps() {
    while (_queue.length + _running.length > _policy.maxJobs &&
        _queue.isNotEmpty) {
      final OgLAnimPreloadJob job = _queue.removeLast();
      _pending.remove(job.id);
      job._cancelled = true;
      _cancelledCount++;
      _release(job);
    }
    while (_reservedBytes > _budgetBytes && _queue.isNotEmpty) {
      final OgLAnimPreloadJob job = _queue.removeLast();
      _pending.remove(job.id);
      job._cancelled = true;
      _cancelledCount++;
      _release(job);
    }
    for (int i = _queue.length - 1; i >= 0; i--) {
      final OgLAnimPreloadJob job = _queue[i];
      if (_policy.admits(job.kind)) {
        continue;
      }
      _queue.removeAt(i);
      _pending.remove(job.id);
      job._cancelled = true;
      _cancelledCount++;
      _release(job);
    }
    // 在途但已不被本档允许的：同样立刻取消（图片项会摘监听，其余在完成时归还）。
    for (final String id in _running.keys.toList()) {
      final OgLAnimPreloadJob? job = _running[id];
      if (job == null || _policy.admits(job.kind)) {
        continue;
      }
      job._cancelled = true;
      _cancelledCount++;
      final void Function()? abort = job._abort;
      job._abort = null;
      abort?.call();
    }
  }

  static void _drain() {
    if (_draining) {
      return;
    }
    _draining = true;
    try {
      final int slots = _policy.jobsPerIdleSlot;
      for (int i = 0; i < slots && _queue.isNotEmpty; i++) {
        final OgLAnimPreloadJob job = _queue.removeAt(0);
        _pending.remove(job.id);
        if (job._cancelled || !_policy.admits(job.kind)) {
          _release(job);
          continue;
        }
        _start(job);
      }
    } finally {
      _draining = false;
    }
    if (_queue.isNotEmpty) {
      // 空闲时主动排一帧，保证"一帧推进一点"的链条不会停住。
      _binding()?.ensureVisualUpdate();
      schedule();
    }
  }

  static void _start(OgLAnimPreloadJob job) {
    _running[job.id] = job;
    if (job._image != null) {
      _startImage(job);
      return;
    }
    final FutureOr<void> Function()? run = job._run;
    if (run == null) {
      _finish(job);
      return;
    }
    unawaited(
      Future<void>.sync(run).then(
        (void _) => _finish(job),
        onError: (Object error, StackTrace stack) => _finish(job, failed: true),
      ),
    );
  }

  static void _startImage(OgLAnimPreloadJob job) {
    final ImageProvider provider = job._image!;
    final ImageStream stream = provider.resolve(job._configuration);
    late final ImageStreamListener listener;

    /// 摘监听 + 释放"属于本监听者的那一份 `ImageInfo`"。
    ///
    /// 与 Flutter `precacheImage` 同一套路（见 `widgets/image.dart`）：推到**帧末**
    /// 执行。原因有二：
    /// 1. `ImageStreamCompleter` 给每个监听者发的是 `image.clone()`（谁拿谁负责
    ///    释放）——不释放就会漏掉一个 `ui.Image` 句柄；
    /// 2. 太早摘监听 / 释放，可能出现"刚解码完就被回收"（`ImageCache._liveImages`
    ///    要活到本帧结束），预加载就白做了。
    void detachLater(ImageInfo? image) {
      void detachNow() {
        if (!job._detached) {
          job._detached = true;
          stream.removeListener(listener);
        }
        image?.dispose();
      }

      final WidgetsBinding? binding = _binding();
      if (binding == null) {
        detachNow();
        return;
      }
      binding.addPostFrameCallback((Duration _) => detachNow());
    }

    listener = ImageStreamListener(
      (ImageInfo image, bool synchronousCall) {
        detachLater(image);
        _finish(job);
      },
      onError: (Object error, StackTrace? stackTrace) {
        detachLater(null);
        _finish(job, failed: true);
      },
    );
    // **取消钩子**：立即摘监听（不留任何引用），并归还额度 / 移出在途表。
    // 这一份 `ImageInfo` 还没到手，所以不需要释放。
    job._abort = () {
      if (job._detached) {
        return;
      }
      job._detached = true;
      stream.removeListener(listener);
      _finish(job);
    };
    stream.addListener(listener);
  }

  static void _finish(OgLAnimPreloadJob job, {bool failed = false}) {
    final bool wasRunning = _running.remove(job.id) != null;
    job._abort = null;
    if (!wasRunning || job._cancelled) {
      _release(job);
      return;
    }
    if (failed) {
      _failedCount++;
      _release(job);
      return;
    }
    _ranCount++;
    _remember(job.id);
    _release(job);
  }

  /// 记住已完成的 id（**有界 LRU**：超出 [_kDoneIdLimit] 就丢最旧的）。
  static void _remember(String id) {
    _done.remove(id);
    _done.add(id);
    while (_done.length > _kDoneIdLimit) {
      _done.remove(_done.first);
    }
  }

  /// 归还额度（登记时预扣，完成 / 取消时归还；**幂等**）。
  static void _release(OgLAnimPreloadJob job) {
    if (job._released) {
      return;
    }
    job._released = true;
    _pending.remove(job.id);
    _reservedBytes -= job.weightBytes;
    if (_reservedBytes < 0) {
      _reservedBytes = 0;
    }
  }

  static WidgetsBinding? _binding() {
    try {
      return WidgetsBinding.instance;
    } catch (_) {
      // binding 尚未初始化（纯 Dart 单测 / 极早期启动）：不调度、不预热。
      return null;
    }
  }
}

/// 页面侧接入点（**可选、透明**）：把一段页面子树声明成一个预加载作用域。
///
/// 行为：
/// - 可见（[enabled]）且档位 > 0 时，按当前档位预热，并登记 [jobs]；
/// - 页面被隐藏（[enabled] 变 false，例如切走 tab）或卸载时，
///   【取消本作用域未完成的预加载】**并归还额度** —— 这就是"可取消、不泄漏"；
/// - 系统"减少动效"或档位 0 时按最低级处理（**不预加载**）。
///
/// 它 **原样返回 [child]**：不改布局、不改绘制、不影响任何动效强度语义，
/// 因此可以安全地"加一层"。
class OgLAnimPreloadBoundary extends StatefulWidget {
  /// 创建。
  const OgLAnimPreloadBoundary({
    required this.group,
    required this.child,
    this.jobs = const <OgLAnimPreloadJob>[],
    this.enabled = true,
    this.kinds = const <OgLAnimPreloadKind>[OgLAnimPreloadKind.currentPage],
    super.key,
  });

  /// 作用域标识（取消时按它成组取消）。
  final String group;

  /// 子控件（原样返回）。
  final Widget child;

  /// 本作用域要预加载的项（同 id 幂等；上一档不允许的类别会被自动拒收）。
  final List<OgLAnimPreloadJob> jobs;

  /// 当前是否"可见 / 活跃"（false = 取消未完成项）。
  final bool enabled;

  /// 本作用域**声明**要参与预加载的类别（真正的准入仍由档位策略表决定）。
  final List<OgLAnimPreloadKind> kinds;

  @override
  State<OgLAnimPreloadBoundary> createState() => _OgLAnimPreloadBoundaryState();
}

class _OgLAnimPreloadBoundaryState extends State<OgLAnimPreloadBoundary> {
  int _level = 0;
  int _syncedLevel = -1;
  bool _active = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 档位来自作用域；系统"减少动效"时按最低级（0 = 不预加载）处理。
    final int level = MediaQuery.disableAnimationsOf(context)
        ? 0
        : OgLMotionScope.levelOf(context);
    _level = level;
    OgLAnimPreload.warmCore(level);
    _sync();
  }

  @override
  void didUpdateWidget(covariant OgLAnimPreloadBoundary oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.group != widget.group) {
      // 作用域换了：旧组先取消，避免旧组的未完成项继续占额度。
      OgLAnimPreload.cancelGroup(oldWidget.group);
      _syncedLevel = -1;
    }
    _sync();
  }

  void _sync() {
    final bool want = widget.enabled && _level > 0;
    if (!want) {
      if (_active) {
        _active = false;
        OgLAnimPreload.cancelGroup(widget.group);
      }
      _syncedLevel = -1;
      return;
    }
    _active = true;
    if (_syncedLevel == _level) {
      return;
    }
    _syncedLevel = _level;
    for (final OgLAnimPreloadJob job in widget.jobs) {
      if (widget.kinds.contains(job.kind)) {
        OgLAnimPreload.register(job);
      }
    }
    OgLAnimPreload.schedule();
  }

  @override
  void dispose() {
    // ★ 页面离开：取消本作用域未完成项（本模块不持有页面引用，故不会泄漏）。
    OgLAnimPreload.cancelGroup(widget.group);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
