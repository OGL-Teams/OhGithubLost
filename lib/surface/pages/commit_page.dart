/// L3 展示级 · 提交详情（元信息 + 分色补丁）。
///
/// - 与父提交比较（`parents.first → sha`），列出变更文件；
/// - 补丁按行分色：`+` 绿 / `-` 红 / `@@` 强调色（其余正常）；
/// - 初始提交（无父提交）给出明确说明，而不是空白。
library;

import 'package:flutter/material.dart';

import '../app/animations.dart';
import '../app/async.dart';
import '../i18n/og_l_i18n.dart';
import '../surface_bridge.dart';
import '../theme.dart';
import '../types.dart';
import '../util/gh_format.dart';
import '../util/og_l_radius.dart';
import '../util/og_l_space.dart';

/// 取 `commit_page` 分片文案。
String _t(String key, [Map<String, Object?>? args]) => OgLI18n.instance.t(
    'commit_page', key,
    args:
        args?.map((String k, Object? v) => MapEntry<String, String>(k, '$v')));

/// 提交详情页。
class CommitPage extends StatefulWidget {
  /// 创建页面。
  const CommitPage({
    required this.surface,
    required this.fullName,
    required this.commit,
    super.key,
  });

  /// 表面桥。
  final SurfaceBridge surface;

  /// 仓库全名（`owner/repo`）。
  final String fullName;

  /// 提交对象。
  final GhCommit commit;

  @override
  State<CommitPage> createState() => _CommitPageState();
}

class _CommitPageState extends State<CommitPage> {
  AsyncController<List<Map<String, dynamic>>>? _diff;

  @override
  void initState() {
    super.initState();
    _diffC().loadIfNeeded();
  }

  @override
  void dispose() {
    _diff?.dispose();
    super.dispose();
  }

  AsyncController<List<Map<String, dynamic>>> _diffC() {
    final existing = _diff;
    if (existing != null) {
      return existing;
    }
    final controller = AsyncController<List<Map<String, dynamic>>>(
      label: _t('changes'),
      isEmpty: (List<Map<String, dynamic>> value) => value.isEmpty,
      loader: () {
        final List<String> parents = widget.commit.parentShas;
        if (parents.isEmpty) {
          return Future<List<Map<String, dynamic>>>.value(
            const <Map<String, dynamic>>[],
          );
        }
        return widget.surface.domain.api
            .compare(widget.fullName, parents.first, widget.commit.sha);
      },
    );
    _diff = controller;
    return controller;
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final GhCommit commit = widget.commit;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          ghShortSha(commit.sha),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: OgLReveal(
          delay: Duration.zero,
          child: CustomScrollView(
            slivers: <Widget>[
              // 头部：常量级 widget 数量，一次性构建即可；
              // 数据行交给下面的 sliver 懒加载（长列表不再一次性构建）。
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(
                    OgLSpace.lg, OgLSpace.lg, OgLSpace.lg, 0),
                sliver: SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(OgLSpace.md),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              SelectableText(
                                commit.sha,
                                style: const TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: 12,
                                ),
                              ),
                              const SizedBox(height: OgLSpace.sm),
                              Text(
                                '${ghCommitAuthor(commit)} · '
                                '${commit.date?.toIso8601String().split('T').first ?? ''}',
                                style: theme.textTheme.bodySmall,
                              ),
                              const SizedBox(height: OgLSpace.md),
                              SelectableText(commit.message),
                            ],
                          ),
                        ),
                      ),
                      const Divider(height: 32),
                      Text(_t('changedFiles'),
                          style: theme.textTheme.titleMedium),
                      const SizedBox(height: OgLSpace.sm)
                    ],
                  ),
                ),
              ),
              OgLAsyncSliver<List<Map<String, dynamic>>>(
                controller: _diffC(),
                padding: const EdgeInsets.symmetric(horizontal: OgLSpace.lg),
                itemCountOf: (List<Map<String, dynamic>> files) => files.length,
                itemBuilder: (
                  BuildContext context,
                  List<Map<String, dynamic>> files,
                  int index,
                ) =>
                    _fileTile(files[index]),
                emptyIcon: Icons.history,
                emptyText: (widget.commit.parentShas.isEmpty
                    ? _t('initialCommit')
                    : _t('noChanges')),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: OgLSpace.xl)),
            ],
          )),
    );
  }

  Widget _fileTile(Map<String, dynamic> file) {
    final String name = ghStr(file, 'filename');
    final int additions = ghInt(file, 'additions');
    final int deletions = ghInt(file, 'deletions');
    final String? patch = ghStrOrNull(file, 'patch');
    final String subtitle =
        '${ghFileStatusText(ghStr(file, 'status'))} · +$additions / -$deletions';
    if (patch == null || patch.trim().isEmpty) {
      return ListTile(
        leading: const Icon(Icons.description_outlined),
        title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(subtitle),
      );
    }
    return ExpansionTile(
      leading: const Icon(Icons.description_outlined),
      title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(subtitle),
      childrenPadding:
          const EdgeInsets.fromLTRB(OgLSpace.lg, 0, OgLSpace.lg, OgLSpace.lg),
      children: <Widget>[
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(OgLSpace.md),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(OgLRadius.sm),
          ),
          child: _PatchView(patch: patch),
        ),
      ],
    );
  }
}

/// 分色补丁：`+` 绿 / `-` 红 / `@@` 强调色 / 其余跟随主题。
class _PatchView extends StatelessWidget {
  const _PatchView({required this.patch});

  final String patch;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final OgLSemanticColors sem =
        Theme.of(context).extension<OgLSemanticColors>()!;
    const TextStyle base = TextStyle(fontFamily: 'monospace', fontSize: 12);
    final List<TextSpan> spans = <TextSpan>[];
    for (final String line in patch.split('\n')) {
      Color color = scheme.onSurface;
      if (line.startsWith('+')) {
        color = sem.success;
      } else if (line.startsWith('-')) {
        color = scheme.error;
      } else if (line.startsWith('@@')) {
        color = scheme.primary;
      }
      spans.add(
        TextSpan(
          text: '$line\n',
          style: base.copyWith(color: color),
        ),
      );
    }
    return SelectableText.rich(TextSpan(children: spans));
  }
}
