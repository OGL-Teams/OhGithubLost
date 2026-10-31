/// L3 展示级 · 客户端主壳（登录门 + 四页导航）。
///
/// ## 形态（Material 3 原生）
/// - 手机（< 600）：`NavigationBar` 底栏；
/// - 平板 / 桌面（≥ 600）：`NavigationRail` 导航轨（≥ 1200 展开标签）。
///
/// ## 两个产品级细节
/// 1. **懒挂载**：只构建访问过的标签页，避免冷启动时多个页面同时发请求；
/// 2. **登录门**：未登录时展示登录页；游客模式可跳过（只读浏览公开内容）。
///
/// "关于"不再是独立标签，而是设置页内的全屏子页面（见 [SettingsPage]）。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../kernel/kernel.dart';
import '../app/notifier.dart';
import '../i18n/og_l_i18n.dart';
import '../pages/dashboard_page.dart';
import '../pages/login_page.dart';
import '../pages/onboarding_page.dart';
import '../pages/profile_page.dart';
import '../pages/search_page.dart';
import '../pages/settings_page.dart';
import '../surface_bridge.dart';
import '../types.dart';
import '../widgets/anim/anim_preload.dart';
import 'animations.dart';
import 'back_guard.dart';
import 'error_surface.dart';

/// 壳内的四个页面（导航值）。
enum OgLShellTab {
  /// 仓库（我的仓库 / 星标）。
  home,

  /// 搜索（仓库 / 代码）。
  search,

  /// 我的（账户管理 / 多账号切换 / Gist / 草稿 / 危险区）。
  profile,

  /// 设置（外观 / 代码 / 网络 / 关于 / 日志）。
  ///
  /// U1：从「我的」页底二次点击提到一级入口 —— 设置是高频页，
  /// 不该埋在账户管理里再点一次。
  settings,
}

/// 客户端主壳（含登录门）。
class OgLClientShell extends StatefulWidget {
  /// 创建主壳。
  const OgLClientShell({
    required this.surface,
    required this.report,
    super.key,
  });

  /// 表面桥。
  final SurfaceBridge surface;

  /// 启动报告（关于页需要）。
  final KernelReport report;

  @override
  State<OgLClientShell> createState() => _OgLClientShellState();
}

class _OgLClientShellState extends State<OgLClientShell> {
  OgLShellTab _tab = OgLShellTab.home;
  bool _checked = false;
  bool _guest = false;
  String? _accountId;

  /// 是否已完成首次引导（设置在 `runApp` 之前已加载，直接读取即可）。
  bool _onboardingDone = false;

  /// 已经访问过的页面（**懒挂载**）。
  final Set<OgLShellTab> _visited = <OgLShellTab>{OgLShellTab.home};

  @override
  void initState() {
    super.initState();
    _onboardingDone = widget.surface.settings.settings.onboardingDone;
    // ★ 认证是全局可观察状态：登录 / 失效 / 切号 / 登出都自动联动。
    widget.surface.domain.auth.addListener(_onAuthChanged);
    _check();
  }

  @override
  void dispose() {
    widget.surface.domain.auth.removeListener(_onAuthChanged);
    super.dispose();
  }

  void _onAuthChanged() {
    if (mounted) {
      _check();
    }
  }

  Future<void> _check() async {
    String? accountId;
    try {
      final account = await widget.surface.domain.auth.activeAccount();
      accountId = account?.id;
    } catch (error) {
      // 读取失败不能把应用卡在"启动中"（没有恢复路径）：
      // 按未登录处理并留痕，用户至少能到达登录门 / 游客模式。
      OgLAppLog.instance.add(
        '账户',
        '启动时账户读取失败（按未登录处理）：$error',
        severity: OgLNoticeSeverity.warning,
      );
      accountId = null;
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _accountId = accountId;
      _checked = true;
      if (accountId != null) {
        _guest = false;
      }
    });
  }

  /// 返回键状态机（「双击退出」的时序逻辑在 [OgLBackGuard] 里，可单测）。
  final OgLBackGuard _backGuard = OgLBackGuard();

  /// 返回链**重入闸门**：`_handleBack` 处理期间（含 `await` 挂起点）拒绝再次进入。
  ///
  /// 系统返回键 / 手势返回**没有节流**，`PopScope` 回调可在极短时间内连发；
  /// 没有此闸门时，第二次调用会落在第一层尚未处理完的链路上，表现为
  /// "快速连按穿两层"——第一击刚关掉弹窗 / 二级页，第二击就直接落进壳状态机
  ///（切 tab / 触发「再按一次退出」）。
  bool _backHandling = false;

  /// 抽屉状态需要它（返回键优先关抽屉，而不是切 tab / 退出）。
  ///
  /// 注：本应用当前**无抽屉**（[OgLBackAction.closeDrawer] 分支不可达），
  /// 该 key 保留，以备将来加入侧边面板。
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  /// 统一返回键处理：二级页/弹窗 → 抽屉 → 回首页 → 双击退出。
  ///
  /// **一次误按绝不退出应用**：这是用户明确抱怨的点（返回键行为不佳）。
  ///
  /// 入口带重入保护（[_backHandling]）与 [mounted] 检查：前者防"连按穿层"；
  /// 后者防壳已卸载（element 失效）后仍被调用——`Navigator.maybeOf(context)`
  /// 在 defunct element 上会抛。
  Future<void> _handleBack() async {
    if (!mounted) {
      return;
    }
    if (_backHandling) {
      return;
    }
    _backHandling = true;
    try {
      final NavigatorState? navigator = Navigator.maybeOf(context);
      if (navigator != null && navigator.canPop()) {
        navigator.pop();
        return;
      }
      // `atHome` 只在**真正的壳**（四页导航已可见）里才算成立：引导页 /
      // 启动检查 / 登录门阶段 `_tab` 仍是 home，但壳还没构建（[_buildShell]
      // 提前 return，没有 tab bar）——此时不能按"已在首页"处理，
      // 否则登录门上的返回键会直接进入「再按一次退出」链路。
      final bool atHome = _tab == OgLShellTab.home &&
          _onboardingDone &&
          _checked &&
          (_accountId != null || _guest);
      final OgLBackAction action = _backGuard.decide(
        atHome: atHome,
        drawerOpen: _scaffoldKey.currentState?.isDrawerOpen ?? false,
        now: DateTime.now(),
      );
      switch (action) {
        case OgLBackAction.closeDrawer:
          // 本应用当前无抽屉，此分支不可达；保留以备将来加入侧边面板。
          _scaffoldKey.currentState?.closeDrawer();
        case OgLBackAction.goHome:
          _select(OgLShellTab.home);
        case OgLBackAction.armExit:
          if (!mounted) {
            return;
          }
          OgLNotifier.of(context)
              .info(OgLI18n.instance.t('shell', kOgLBackExitHintKey));
        case OgLBackAction.exit:
          await SystemNavigator.pop();
      }
    } finally {
      _backHandling = false;
    }
  }

  void _select(OgLShellTab tab) {
    // 切 tab 即清除「待退出」：避免刚提示过又误触退出。
    _backGuard.reset();
    if (tab == _tab) {
      return;
    }
    setState(() {
      _tab = tab;
      _visited.add(tab);
    });
  }

  /// 某一页的实例（懒挂载：只有访问过的 tab 才会被构建）。
  Widget _pageFor(OgLShellTab tab) {
    switch (tab) {
      case OgLShellTab.home:
        return DashboardPage(
          key: ValueKey<String>('dash-${_accountId ?? 'guest'}'),
          surface: widget.surface,
        );
      case OgLShellTab.search:
        return SearchPage(
          key: ValueKey<String>('search-${_accountId ?? 'guest'}'),
          surface: widget.surface,
        );
      case OgLShellTab.profile:
        return ProfilePage(surface: widget.surface, onAccountsChanged: _check);
      case OgLShellTab.settings:
        return SettingsPage(surface: widget.surface, report: widget.report);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
        // 统一接管返回键：二级页 / 弹窗 / 抽屉 / tab / 退出（见 [_handleBack]）。
        canPop: false,
        onPopInvokedWithResult: (bool didPop, Object? result) {
          if (didPop) {
            return;
          }
          unawaited(_handleBack());
        },
        child: _buildShell(context),
      );

  /// 原 shell 构建（被 [build] 包在 `PopScope` 里）。
  Widget _buildShell(BuildContext context) {
    // 首次引导优先于登录门：先让用户知道"这个应用会碰什么、不碰什么"。
    if (!_onboardingDone) {
      return OnboardingPage(
        surface: widget.surface,
        onFinished: () => setState(() => _onboardingDone = true),
      );
    }
    if (!_checked) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if ((_accountId == null ||
            widget.surface.domain.auth.state == GhAuthState.expired) &&
        !_guest) {
      return LoginPage(
        surface: widget.surface,
        onLoggedIn: _check,
        onSkip: () async {
          setState(() => _guest = true);
        },
      );
    }

    // 隐藏页**停表**：`TickerMode(enabled: false)` 让不可见页面的动画不再推进
    //（下载进度条、入场动画等），避免"看不见的页面在偷偷烧帧"。
    //
    // 每页外面再套一层**分级预加载作用域**（透明、不改布局 / 不改动效语义）：
    // - 可见时按当前档位把核心（档位质量表 / 过渡主题）预热，并交给页面一个
    //   登记入口（页面自己 register 的项按 `group` 归组）；
    // - 切走 / 卸载时**取消本组未完成的预加载并归还额度**（不留下可达对象）。
    final List<Widget> pages = <Widget>[
      for (final OgLShellTab tab in OgLShellTab.values)
        _visited.contains(tab)
            ? TickerMode(
                enabled: tab == _tab,
                child: OgLAnimPreloadBoundary(
                  group: 'ogl-tab-${tab.name}',
                  enabled: tab == _tab,
                  child: _pageFor(tab),
                ),
              )
            : const SizedBox.shrink(),
    ];
    final int index = OgLShellTab.values.indexOf(_tab);
    // R7：页面切换加**左右滑动**入场动画（保留 IndexedStack 的状态与懒挂载）。
    // 关闭动画（档位 0 / 系统减少动效）时瞬时切换。
    final Widget body = _OgLShellSlide(
      index: index,
      child: IndexedStack(index: index, children: pages),
    );

    final double width = MediaQuery.sizeOf(context).width;

    // ── 手机：底栏 ──
    if (width < 600) {
      return Scaffold(
        key: _scaffoldKey,
        body: body,
        bottomNavigationBar: NavigationBar(
          selectedIndex: index,
          onDestinationSelected: (int value) =>
              _select(OgLShellTab.values[value]),
          destinations: <NavigationDestination>[
            NavigationDestination(
              icon: const Icon(Icons.folder_outlined),
              selectedIcon: const Icon(Icons.folder),
              label: OgLI18n.instance.t('shell', 'home'),
            ),
            NavigationDestination(
              icon: const Icon(Icons.search),
              label: OgLI18n.instance.t('shell', 'search'),
            ),
            NavigationDestination(
              icon: const Icon(Icons.person_outline),
              selectedIcon: const Icon(Icons.person),
              label: OgLI18n.instance.t('shell', 'profile'),
            ),
            // U1：设置升为一级入口（icons.settings_outlined 是 5 tab 里最
            // 不抢眼的，符合"功能而非主操作"的产品意图）。
            NavigationDestination(
              icon: const Icon(Icons.settings_outlined),
              selectedIcon: const Icon(Icons.settings),
              label: OgLI18n.instance.t('shell', 'settings'),
            ),
          ],
        ),
      );
    }

    // ── 平板 / 桌面：导航轨 ──
    final bool extended = width >= 1200;
    return Scaffold(
      key: _scaffoldKey,
      body: Row(
        children: <Widget>[
          NavigationRail(
            selectedIndex: index,
            onDestinationSelected: (int value) =>
                _select(OgLShellTab.values[value]),
            extended: extended,
            labelType: extended
                ? NavigationRailLabelType.none
                : NavigationRailLabelType.all,
            destinations: <NavigationRailDestination>[
              NavigationRailDestination(
                icon: const Icon(Icons.folder_outlined),
                selectedIcon: const Icon(Icons.folder),
                label: Text(OgLI18n.instance.t('shell', 'home')),
              ),
              NavigationRailDestination(
                icon: const Icon(Icons.search),
                label: Text(OgLI18n.instance.t('shell', 'search')),
              ),
              NavigationRailDestination(
                icon: const Icon(Icons.person_outline),
                selectedIcon: const Icon(Icons.person),
                label: Text(OgLI18n.instance.t('shell', 'profile')),
              ),
              NavigationRailDestination(
                icon: const Icon(Icons.settings_outlined),
                selectedIcon: const Icon(Icons.settings),
                label: Text(OgLI18n.instance.t('shell', 'settings')),
              ),
            ],
          ),
          const VerticalDivider(width: 1),
          Expanded(child: body),
        ],
      ),
    );
  }
}

/// R7：底部/侧边导航切换时的**左右滑动**入场。
///
/// 保留 [IndexedStack] 作为 child（状态与懒挂载不变），只在切换那一刻
/// 对新页面做一次轻微水平位移 + 淡出过渡。关闭动画时（档位 0 / 系统减少动效）
/// 不做任何位移——直接瞬时切换。
class _OgLShellSlide extends StatefulWidget {
  const _OgLShellSlide({required this.index, required this.child});

  /// 当前索引（变化即触发一次入场）。
  final int index;

  /// 页面内容。
  final Widget child;

  @override
  State<_OgLShellSlide> createState() => _OgLShellSlideState();
}

class _OgLShellSlideState extends State<_OgLShellSlide>
    with SingleTickerProviderStateMixin {
  /// 弹簧驱动的进度控制器。
  ///
  /// 上下界特意放开到 `[-1, 2]`：欠阻尼弹簧会**轻微过冲**（回弹），
  /// 若仍锁在 `[0, 1]` 就会把回弹削掉，变成"没有回弹的弹簧"。
  ///
  /// ★ 7.4.1：改成在 `initState` 里**提前建好**（而不是 `late final` 首次
  /// 访问才建）——这就是切 tab 这条**全屏动画**的"预加载"：`Ticker` 的创建 /
  /// 注册（以及控制器上的一整套监听列表初始化）成本被挪到页面挂载时，
  /// 而不是挪到你按下 tab 的那一帧里去付。语义不变（初值仍是 1 = 已落位）。
  late AnimationController _controller;

  /// 起始水平位移（正=从右进入，负=从左进入）。
  double _from = 0;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: Duration.zero,
      value: 1,
      lowerBound: -1,
      upperBound: 2,
    );
  }

  @override
  void didUpdateWidget(covariant _OgLShellSlide oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.index == widget.index) {
      return;
    }
    final bool animate = OgLAnim.enabled(context);
    if (!animate) {
      _from = 0;
      _controller.value = 1;
      return;
    }
    // 上一次切换尚未落位：让它跑完，避免位置跳变（弹簧本身就是"可中断"的，
    // 这里只是不把同一段位移硬生生打断成两段相反方向）。
    if (_controller.isAnimating) {
      return;
    }
    // 位移距离按档位（低档更短、更快 —— "更贴"的手感）。
    final double distance = OgLAnim.shellOffset(context);
    _from = widget.index > oldWidget.index ? distance : -distance;
    // **物理弹簧**驱动（不是固定时长）：更"跟手 / 丝滑"，
    // 档位越高、回弹越明显（档位 1 临界阻尼，不振荡）。
    OgLSpring.run(_controller, context, from: 0);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 切 tab 也是"大体积动画"，且**基于物理**：进度由弹簧给出
    //（可能轻微过冲 → 落位前"回弹"一下）。位置 / 透明度直接读弹簧进度。
    return AnimatedBuilder(
      animation: _controller,
      // RepaintBoundary：切 tab 时只做图层位移、不重绘整页
      //（此前"整棵页面树每帧重绘"正是切换卡顿的主因）。
      //
      // 再叠一层**很轻的淡入**（0.7 → 1）：整页纯位移会显得"生硬"，
      // 一点点透明度变化就足以让切换"活"起来，成本几乎为零。
      builder: (BuildContext context, Widget? child) {
        final double t = _controller.value;
        return RepaintBoundary(
          child: Opacity(
            opacity: (0.7 + 0.3 * t).clamp(0.0, 1.0),
            child: FractionalTranslation(
              translation: Offset(_from * (1 - t), 0),
              child: child,
            ),
          ),
        );
      },
      child: widget.child,
    );
  }
}
