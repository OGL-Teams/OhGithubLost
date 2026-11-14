/// 展示层 · **真机 UI 反馈**的回归锁（三处布局契约）。
///
/// 背景：一次真机反馈暴露三处 UI 问题，逐像素比对真机截图后定位到根因，
/// 这里把「为什么坏」的**结构性原因**钉成测试，避免下次重构再犯。
///
/// 1. **编辑器工具栏漏缝**：工具栏与代码区背景同色了，但工具栏**没铺满
///    宽度**——横向滚动视图里的 `Row(mainAxisSize: min)` 只有图标那么宽，
///    Material 于是按内容收缩，真机实测灰带只覆盖 x=43..978，两端各露
///    一条 surface 白缝，而下方代码区满宽 x=0..1038。
/// 2. **动态整页空白**：动态行用 `Row(crossAxisAlignment: stretch)` 撑满
///    行高，而纵向 ListView 的子项高度是**无界**的 → release 下断言被剥掉，
///    整行不绘制 → 整个 tab 一个像素都不剩（连空态都没有）。
/// 3. **Issues 筛选胶囊文字溢出**：胶囊行被写死 32dp 高，ListView 上下
///    padding 就吃掉 16dp，标签文字被挤到胶囊背景之外（真机实测底色
///    y=319..341、文字 y=352..374）。
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ohgithublost/surface/widgets/code_editor_toolbar.dart';
import 'package:ohgithublost/surface/widgets/discover_rows.dart';

/// 取装饰框的左侧边框（[BoxBorder] 基类没有 `left`，需先收窄成 [Border]）。
BorderSide _leftSide(DecoratedBox box) {
  final BoxBorder border = (box.decoration as BoxDecoration).border!;
  return (border as Border).left;
}

// ★ 批 9 · B14：上面三组测试都只 new 组件，页面若弃用它们测试照样绿。
//   这里用源码静态断言把「页面确实接线」也钉住 —— 不做 widget 渲染
//   （页面依赖 SurfaceBridge，测试环境构造成本高），只查真实引用。
String _readSource(String relative) =>
    File('lib/surface/pages/$relative').readAsStringSync();

void main() {
  group('页面接线（组件必须真的被页面使用）', () {
    test('发现页接入 OgLFeedRow 与 OgLIssuesFilterChips', () {
      final String source = _readSource('search_page.dart');
      expect(
        source,
        contains('OgLFeedRow('),
        reason: '发现页动态 tab 必须复用 OgLFeedRow',
      );
      expect(
        source,
        contains('OgLIssuesFilterChips('),
        reason: '发现页 Issues tab 必须复用 OgLIssuesFilterChips',
      );
      expect(
        source,
        contains('crossAxisAlignment: CrossAxisAlignment.stretch'),
        reason: 'Issues 筛选行满宽契约',
      );
    });

    test('发现页打磨契约（LTS 前打磨项，2026-11）', () {
      final String source = _readSource('search_page.dart');

      // ① 骨架与数据态行节奏一致：骨架列表也用 separated + Divider(height:1)，
      //    否则加载完成瞬间每行多出 1px、整列累计闪跳。
      final String skeleton = source.substring(
        source.indexOf('class _SkeletonList'),
        source.indexOf('class _SearchHit'),
      );
      expect(
        skeleton,
        contains('ListView.separated'),
        reason: '骨架列表必须与数据态同为 separated 节奏',
      );
      expect(
        skeleton,
        contains('const Divider(height: 1)'),
        reason: '骨架分隔符必须与数据态等高',
      );
      // ② 推荐 tab 错误重试文案必须来自本页分片（_t('retry') 会兜底成
      //    字面键名「retry」——search_page.json 里没有这个键）。
      expect(
        source,
        isNot(contains("_t('retry')")),
        reason: 'search_page 分片没有 retry 键，错误重试文案必须用本分片键',
      );
      expect(
        source,
        contains("_t('categoryRetry')"),
        reason: '推荐 tab 的重试按钮必须用 search_page 分片的 categoryRetry',
      );
      // ③ 推荐卡 README 切片：展开后必须能再点收起（InkWell 恒可用）。
      final String card = source.substring(
        source.indexOf('class _RepoCard'),
        source.indexOf('/// 发现页。'),
      );
      expect(
        card,
        contains('_readmeExpanded = !_readmeExpanded'),
        reason: 'README 切片必须可展开也可收起（tap 不得在展开后置 null）',
      );
      // ④ 分类筛选与 Issues 统一为 FilterChip 横滑行（SegmentedButton
      //    五档窄屏临界溢出，audit_spec_b B17）；语言档此前硬编码英文。
      //    （搜索结果页的两档 SegmentedButton 是合法用途，不在本断言内。）
      final String recommended = source.substring(
        source.indexOf('Widget _buildRecommendedTab()'),
        source.indexOf('// ── tab 3：Issues'),
      );
      expect(
        recommended,
        isNot(contains('SegmentedButton<int>')),
        reason: '推荐分类不得退回 SegmentedButton（窄屏溢出）',
      );
      expect(recommended, contains('OgLIssuesFilterChips('),
          reason: '推荐分类必须用与 Issues 一致的统一筛选行');
      expect(source, contains("_t('catType')"), reason: '分类文案走 i18n 键');
      expect(
        source,
        isNot(contains("label: const Text('TypeScript')")),
        reason: '分类语言档不得硬编码英文字面量',
      );
      // ⑤ 星标数紧凑记法：双列网格 meta 行不被裸数字挤满。
      expect(source, contains('_compactCount(repo.stars)'),
          reason: '星标数用紧凑记法（12.3k）');
      // ⑥ Issues 行首状态色点（open/closed 一眼区分）。
      expect(source, contains('final Color stateColor'),
          reason: 'Issues 行首状态色点必须存在');
      // ⑦ 设置页「存储与网络」折叠摘要含下载线程数（不展开即见并发档）。
      final String settings = _readSource('settings_page.dart');
      expect(
        settings,
        contains("_t('downloadConnections')"),
        reason: '存储与网络摘要必须含下载线程档位',
      );
    });

    test('代码编辑器页接入 OgLCodeEditorToolbar 且 body 满宽', () {
      final String source = _readSource('code_editor_page.dart');
      expect(
        source,
        contains('OgLCodeEditorToolbar('),
        reason: '编辑器页必须复用 OgLCodeEditorToolbar',
      );
      expect(
        source,
        contains('crossAxisAlignment: CrossAxisAlignment.stretch'),
        reason: '工具栏与代码区同宽契约',
      );
    });

    test('下拉刷新统一走 OgLRefreshIndicator（不留裸 RefreshIndicator）', () {
      final Directory pages = Directory('lib/surface/pages');
      final List<File> files = pages
          .listSync(recursive: true)
          .whereType<File>()
          .where((File f) => f.path.endsWith('.dart'))
          .toList();
      int wrapped = 0;
      for (final File f in files) {
        final String text = f.readAsStringSync();
        wrapped += 'OgLRefreshIndicator('.allMatches(text).length;
        // 允许包装器自身文件与注释里出现，但页面源码不许裸用。
        final String stripped = text.replaceAll('OgLRefreshIndicator(', '');
        expect(
          stripped,
          isNot(contains('RefreshIndicator(')),
          reason: '${f.path} 仍有裸 RefreshIndicator',
        );
      }
      expect(wrapped, greaterThan(0), reason: '包装器没有被任何页面使用');
    });
  });

  group('异步 Sliver 四态（批 9 · B1）', () {
    test('空/错误/加载三态统一走 OgLSurfaceSwitch，data 态保持懒加载', () {
      final String source =
          File('lib/surface/app/async.dart').readAsStringSync();
      final String sliver = source.substring(
        source.indexOf('class OgLAsyncSliver'),
      );
      expect(
        sliver,
        contains('OgLSurfaceSwitch('),
        reason: 'AsyncSliver 三态不能是硬切',
      );
      expect(
        sliver,
        contains('ValueKey<String>(state)'),
        reason: '状态切换必须带 Key，AnimatedSwitcher 才能识别',
      );
      expect(
        sliver,
        contains('SliverList.builder'),
        reason: '数据态必须保留按需构建，不能套动画容器一次建全表',
      );
    });
  });

  group('动态行（OgLFeedRow）', () {
    testWidgets('在无界高度里渲染不抛异常、且内容可见', (WidgetTester tester) async {
      // ★ 无界高度正是 ListView 子项的真实约束；此前 stretch 竖条在此崩掉。
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListView(
              children: <Widget>[
                OgLFeedRow(
                  unread: true,
                  title: '标题行',
                  meta: '仓库 · Issue · 3 小时前',
                  onTap: () {},
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('标题行'), findsOneWidget);
      expect(find.text('仓库 · Issue · 3 小时前'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('未读与已读都有状态竖条（宽度恒定，行不跳动）', (WidgetTester tester) async {
      Widget build(bool unread) => MaterialApp(
            home: Scaffold(
              body: OgLFeedRow(
                  unread: unread, title: 'T', meta: 'M', onTap: () {}),
            ),
          );

      await tester.pumpWidget(build(true));
      final DecoratedBox box = tester.widget<DecoratedBox>(
        find.byType(DecoratedBox).first,
      );
      final BorderSide side = _leftSide(box);
      expect(side.width, greaterThan(0), reason: '未读行必须有状态竖条');

      await tester.pumpWidget(build(false));
      final DecoratedBox box2 = tester.widget<DecoratedBox>(
        find.byType(DecoratedBox).first,
      );
      final BorderSide side2 = _leftSide(box2);
      expect(side2.width, greaterThan(0), reason: '已读行宽度恒定，行不跳动');
    });
  });

  group('Issues 筛选胶囊行（OgLIssuesFilterChips）', () {
    testWidgets('三个胶囊都在、文字落在胶囊内（不被压扁）', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: OgLIssuesFilterChips(
              selected: 0,
              labels: const <String>['全部', '我提出的', 'Star 仓库'],
              onSelect: (int index) {},
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('全部'), findsOneWidget);
      expect(find.text('我提出的'), findsOneWidget);
      expect(find.text('Star 仓库'), findsOneWidget);
      expect(tester.takeException(), isNull);

      // ★ 文字必须落在胶囊的垂直范围内（此前文字掉到胶囊外面）。
      for (final String label in <String>['全部', '我提出的', 'Star 仓库']) {
        final Rect chip = tester.getRect(
          find.ancestor(
            of: find.text(label),
            matching: find.byType(FilterChip),
          ),
        );
        final Rect text = tester.getRect(find.text(label));
        expect(
          text.top >= chip.top - 0.5 && text.bottom <= chip.bottom + 0.5,
          isTrue,
          reason: '「$label」的文字超出了胶囊的垂直范围',
        );
      }
    });

    testWidgets('点击胶囊回调对应下标', (WidgetTester tester) async {
      final List<int> picked = <int>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: OgLIssuesFilterChips(
              selected: 0,
              labels: const <String>['全部', '我提出的', 'Star 仓库'],
              onSelect: picked.add,
            ),
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.text('Star 仓库'));
      await tester.pump();
      expect(picked, <int>[2]);
    });
  });

  group('代码编辑器工具栏（OgLCodeEditorToolbar）', () {
    testWidgets('背景条铺满宽度（不露白缝）', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: <Widget>[
                OgLCodeEditorToolbar(
                  backgroundColor: const Color(0xFFE2E2E9),
                  canUndo: true,
                  canRedo: false,
                  wrap: false,
                  onUndo: () {},
                  onRedo: () {},
                  onToggleFind: () {},
                  onToggleWrap: () {},
                  onFontSmaller: () {},
                  onFontLarger: () {},
                  onPreview: () {},
                  undoTooltip: '撤销',
                  redoTooltip: '重做',
                  findTooltip: '查找',
                  wrapOnTooltip: '自动换行',
                  wrapOffTooltip: '取消换行',
                  fontSmallerTooltip: '缩小',
                  fontLargerTooltip: '放大',
                  previewTooltip: '预览',
                ),
                const Expanded(
                  child: ColoredBox(
                    color: Color(0xFFE2E2E9),
                    child: SizedBox.expand(),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pump();

      final double screen = tester.getSize(find.byType(Scaffold)).width;
      final double toolbar =
          tester.getSize(find.byType(OgLCodeEditorToolbar)).width;
      expect(toolbar, screen, reason: '工具栏没有铺满宽度，两端会露白缝');
      expect(tester.takeException(), isNull);
    });
  });

  group('设置页（单层进入式）', () {
    test('根页只有入口，内部分组在子页', () {
      final String source = _readSource('settings_page.dart');
      final String child = _readSource('settings_section_page.dart');
      // 根 build 内不得直接把 OgLSettingsGroup 平铺进 ListView
      final int buildStart =
          source.indexOf('Widget build(BuildContext context)');
      final int entryStart = source.indexOf('Widget _entry(', buildStart);
      final String rootBuild = source.substring(buildStart, entryStart);
      expect(rootBuild.contains('_entry('), isTrue,
          reason: '根页必须全部分类走 _entry 入口');
      expect(rootBuild.contains('OgLSettingsGroup('), isFalse,
          reason: '根页不得再出现可折叠分组（应移到子页）');
      expect(rootBuild.contains('SettingsSectionPage('), isFalse,
          reason: '子页构造集中在 _entry 内');
      expect(child.contains('class SettingsSectionPage'), isTrue);
      // ★ 批 12：设置页**单层平铺、零气泡**——不得再出现圆角卡片，
      //   也不得再有可折叠分组头（AppBar 标题即分类名）。
      final String group =
          File('lib/surface/widgets/settings/settings_group.dart')
              .readAsStringSync();
      final String groupBuild =
          group.substring(group.indexOf('class OgLSettingsGroup'));
      expect(groupBuild.contains('return Card('), isFalse,
          reason: '设置分组不得再使用卡片气泡');
      expect(groupBuild.contains('onToggle'), isFalse, reason: '设置页不再有可折叠分组');
      expect(source.contains('OgLSettingsGroup('), isTrue);
      expect(source.contains('_toggleGroup('), isFalse, reason: '折叠状态机制应已移除');
      // 法律正文：十七节齐备（含适用法律、不可抗力、第三方链接、知识产权等）
      final String legal =
          File('assets/i18n/zh/onboarding.json').readAsStringSync();
      for (final String section in <String>[
        '适用法律与争议解决',
        '不可抗力与责任限制',
        '第三方链接与内容',
        '知识产权',
        '未成年人',
        '终止使用',
      ]) {
        expect(legal.contains(section), isTrue, reason: '法律正文缺少：$section');
        // ★ UI 审查 P3 收敛：等宽字号令牌 / 宽屏限宽 / Enter 防重。
        for (final String f in <String>[
          'lib/surface/pages/commit_page.dart',
          'lib/surface/widgets/code_editor_field.dart',
        ]) {
          final String src = File(f).readAsStringSync();
          expect(src.contains('fontSize: 12') || src.contains('fontSize: 13'),
              isFalse,
              reason: '$f 仍有裸等宽字号');
        }
        final String shell =
            File('lib/surface/app/client_shell.dart').readAsStringSync();
        expect(shell.contains('maxWidth: 720'), isTrue, reason: '宽屏一级页内容限宽应在位');
        final String login =
            File('lib/surface/pages/login_page.dart').readAsStringSync();
        final int submit = login.indexOf('onSubmitted:');
        expect(login.substring(submit, submit + 160).contains('_busy'), isTrue,
            reason: 'Enter 提交必须与按钮共用防重闸');
      } // 关于页：占位文案已删，致谢/协议/贡献者改为真实内容。
      final String about =
          File('lib/surface/pages/about_page.dart').readAsStringSync();
      for (final String key in <String>[
        'futureExt',
        'futureExtDesc',
        'thanksDesc'
      ]) {
        expect(about.contains("_t('$key')"), isFalse,
            reason: '关于页不得再出现 $key 占位/旧文案');
      }
      expect(about.contains('kOgLDependencyLicenses'), isTrue,
          reason: '致谢必须复用依赖唯一事实源，不手写第二份名单');
      expect(about.contains('_licenseCareCard('), isTrue,
          reason: '协议重要性说明必须在位');
      expect(about.contains('_contributorsCard('), isTrue, reason: '贡献者名单必须在位');
      final String aboutI18n =
          File('assets/i18n/zh/about_page.json').readAsStringSync();
      expect(aboutI18n.contains('"futureExt"'), isFalse,
          reason: '占位 i18n 键应一并删除');
      expect(aboutI18n.contains('"licenseWhyApache"'), isTrue);
      // 文案精简：新摘要键六语言齐全
      for (final String loc in <String>[
        'zh',
        'zh_Hant',
        'en',
        'de',
        'fr',
        'ru'
      ]) {
        final String json =
            File('assets/i18n/$loc/settings.json').readAsStringSync();
        expect(json.contains('"accountSummary"'), isTrue, reason: loc);
        expect(json.contains('"aboutSummary"'), isTrue, reason: loc);
      }
    });
  });
}
