/// L3 展示级 · 全屏代码编辑器（**库实现**：`re_editor`）。
///
/// ## 相对旧自研版
/// - **编辑与高亮同层**：不再用"高亮图层 + 透明输入层"叠加，光标 / 换行 / 滚动
///   不会错位；
/// - **语法高亮 / 行号 / 查找替换 / 撤销重做 / 折叠 / 快捷键**全部由库提供；
/// - 本项目只保留业务语义：草稿防抖落盘、未保存拦截、加锁保存（D1–D7，基线过期
///   弹冲突对话框），以及来自设置的字号 / 换行 / 配色。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:re_editor/re_editor.dart';

import '../app/animations.dart';
import '../app/error_surface.dart';
import '../app/notifier.dart';
import '../app/overlays.dart';
import '../i18n/og_l_i18n.dart';
import '../surface_bridge.dart';
import '../types.dart';
import '../util/gh_format.dart';
import '../util/og_l_radius.dart';
import '../util/og_l_space.dart';
import '../widgets/code_editor_field.dart';

/// 取 `code_editor_page` 分片文案。
String _t(String key, [Map<String, Object?>? args]) => OgLI18n.instance.t(
    'code_editor_page', key,
    args:
        args?.map((String k, Object? v) => MapEntry<String, String>(k, '$v')));

/// 全屏代码编辑器页。
class CodeEditorPage extends StatefulWidget {
  /// 创建页面。
  const CodeEditorPage({
    required this.surface,
    required this.fullName,
    required this.path,
    required this.initialText,
    required this.baseSha,
    this.branch,
    super.key,
  });

  /// 表面桥。
  final SurfaceBridge surface;

  /// 仓库全名。
  final String fullName;

  /// 文件路径。
  final String path;

  /// 初始内容。
  final String initialText;

  /// 编辑基线（乐观锁）。
  final String baseSha;

  /// 分支。
  final String? branch;

  @override
  State<CodeEditorPage> createState() => _CodeEditorPageState();
}

class _CodeEditorPageState extends State<CodeEditorPage> {
  /// 编辑器内核（库）。
  late final CodeLineEditingController _controller =
      CodeLineEditingController.fromText(widget.initialText);

  /// 查找 / 替换（库）。
  late final CodeFindController _find = CodeFindController(_controller);

  /// 草稿自动保存（防抖）。
  Timer? _draftTimer;

  bool _saving = false;
  bool _saved = false;

  /// 已成功提交到远端的那份文本（F1：_saved 不能是一次性闩锁——
  /// 保存后再编辑时，dirty 判据必须是"与已保存版本不同"，
  /// 否则增量编辑既不进草稿也无一确认，退出即静默丢失）。
  String? _savedText;

  /// 「放弃修改」已确认：真正丢弃（dispose 时不再回写草稿，并删除草稿）。
  bool _abandon = false;
  bool _wrap = false;
  double _fontSize = 13;

  bool get _dirty => _controller.text != widget.initialText;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onEdit);
    unawaited(_restoreDraft());
  }

  @override
  void dispose() {
    _draftTimer?.cancel();
    // 只在「未保存且未放弃」时回写草稿：
    // - 保存成功后再回写会把**已提交内容**残留成草稿；
    // - 「放弃修改」后再回写等于把被放弃的改动又救回来，与操作语义相反。
    final bool savedClean =
        _savedText != null && _controller.text == _savedText;
    if (!savedClean && !_abandon) {
      unawaited(_persistDraft());
    }
    _controller.removeListener(_onEdit);
    _find.dispose();
    _controller.dispose();
    super.dispose();
  }

  /// 内容变化：草稿落盘防抖 + 重建（撤销 / 重做可用态与"未保存"标记）。
  void _onEdit() {
    _draftTimer?.cancel();
    _draftTimer = Timer(const Duration(milliseconds: 900), _persistDraft);
    if (_saved && _controller.text != _savedText) {
      // 保存之后又有新改动：保存态作废（dirty 判据回归"与已存版本比对"）。
      _saved = false;
    }
    if (mounted) {
      setState(() {});
    }
  }

  /// 进入编辑器时尝试恢复上次未提交的草稿。
  Future<void> _restoreDraft() async {
    try {
      final String? draft = await widget.surface.domain.api.loadDraft(
        widget.fullName,
        widget.path,
        branch: widget.branch,
      );
      if (!mounted || draft == null) {
        return;
      }
      if (draft == widget.initialText) {
        await widget.surface.domain.api.discardDraft(
          widget.fullName,
          widget.path,
          branch: widget.branch,
        );
        return;
      }
      // 草稿读取是异步的：期间用户若已开始输入，就**不再用旧草稿覆盖**
      // 他的内容（旧草稿留待下一次编辑落盘时自然被覆盖）。
      if (_controller.text != widget.initialText) {
        return;
      }
      _controller.text = draft;
      _notifier.info(_t('draftRestored'));
    } catch (_) {
      // 草稿读取失败不影响编辑。
    }
  }

  /// 把当前文本写入草稿（与远端一致则清掉草稿）。
  Future<void> _persistDraft() async {
    // 已放弃的改动绝不落草稿（编辑器审计 F4）：「放弃修改」与在途的
    // 防抖写入并发时，写入晚于 discard 会让被放弃的内容"复活"。
    if (_abandon) {
      return;
    }
    try {
      if (_controller.text == widget.initialText) {
        await widget.surface.domain.api.discardDraft(
          widget.fullName,
          widget.path,
          branch: widget.branch,
        );
        return;
      }
      await widget.surface.domain.api.saveDraft(
        widget.fullName,
        widget.path,
        _controller.text,
        branch: widget.branch,
        baseSha: widget.baseSha,
      );
    } catch (_) {
      // 草稿落盘失败不阻断编辑。
    }
  }

  void _changeFont(double delta) {
    setState(
        () => _fontSize = (_fontSize + delta).clamp(10.0, 24.0).toDouble());
  }

  Future<void> _save() async {
    if (_saving) {
      return;
    }
    setState(() => _saving = true);
    try {
      final String text = _controller.text;
      GhWriteResult result = await widget.surface.domain.api.putContentLocked(
        widget.fullName,
        widget.path,
        content: text,
        message: 'docs: update ${widget.path}',
        baseSha: widget.baseSha,
        branch: widget.branch,
      );
      if (!result.ok && result.canForceOverwrite) {
        final bool? overwrite = await _showConflictDialog(result);
        if (overwrite != true) {
          _notifier.warning(_t('cancelledRemoteUpdated'));
          return;
        }
        // ★ 复核远端：对话框展示的是**第一次失败时**的快照，用户确认
        //   期间远端可能又被第三方推进。force 顶掉的必须是用户看过的
        //   版本——变了就中止本次覆盖（草稿仍在，可重新保存走新冲突）。
        final GhContent? fresh = await widget.surface.domain.api.content(
          widget.fullName,
          widget.path,
          branch: widget.branch,
          refresh: true,
        );
        if (fresh != null && result.sha != null && fresh.sha != result.sha) {
          OgLAppLog.instance.add(
            _t('editTitle'),
            '强制覆盖前发现远端又已更新'
            '（确认时 ${result.sha?.substring(0, 8)}，'
            '现在 ${fresh.sha.substring(0, 8)}）',
            severity: OgLNoticeSeverity.warning,
          );
          _notifier.warning(_t('remoteChangedAgain'));
          return;
        }
        result = await widget.surface.domain.api.putContentLocked(
          widget.fullName,
          widget.path,
          content: text,
          message: 'docs: update ${widget.path}',
          baseSha: widget.baseSha,
          branch: widget.branch,
          force: true,
          confirmed: true,
        );
      }
      if (!result.ok) {
        // 冲突一律翻译成用户可读文案（不再把 `staleSha` 这类枚举名端给用户）。
        final String conflict = ghWriteConflictText(result.conflict);
        OgLAppLog.instance.add(
          _t('editTitle'),
          _t('commitFailedConflict', {
            'conflict': conflict,
            'detail': result.detail ?? '',
          }),
          severity: OgLNoticeSeverity.critical,
        );
        if (mounted) {
          _notifier.warning(
            _t('commitFailedDetail', {'detail': result.detail ?? conflict}),
          );
        }
        return;
      }
      OgLAppLog.instance.result(_t('editTitle'), _t('committed'), widget.path);
      // ★ 提交已成功（result.ok）：保存态**先**落定，再做草稿清理——
      //   清理失败（磁盘 IO 等）只是卫生问题，绝不能伪装成"提交失败"，
      //   否则用户重存会撞上自己刚提交的版本（D2 误报冲突）。
      _saved = true;
      _savedText = text;
      try {
        await widget.surface.domain.api.discardDraft(
          widget.fullName,
          widget.path,
          branch: widget.branch,
        );
      } catch (draftError) {
        OgLAppLog.instance.add(
          _t('editTitle'),
          '草稿清理失败（提交已成功）：$draftError',
          severity: OgLNoticeSeverity.warning,
        );
      }
      if (mounted) {
        _notifier.success(_t('committedPath', {'path': widget.path}));
        Navigator.of(context).pop(true);
      }
    } catch (error) {
      OgLAppLog.instance.add(
        _t('editTitle'),
        _t('commitFailedDetail', {'detail': error}),
        severity: OgLNoticeSeverity.critical,
      );
      if (mounted) {
        _notifier.warning(_t('commitFailedDetail', {'detail': error}));
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Future<bool?> _showConflictDialog(GhWriteResult result) => showDialog<bool>(
        context: context,
        builder: (BuildContext dialogContext) => AlertDialog(
          title: Text(_t('remoteUpdated')),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(_t('baseline', {'sha': _short(result.baseSha)})),
                Text(_t('remoteLatest', {'sha': _short(result.sha)})),
                const SizedBox(height: OgLSpace.sm),
                // ★ remoteContent 为**空串**（非 null）= 远端文件已被删除
                //   （D2′）。此时"强制覆盖"实际是重新创建文件，语义不同，
                //   必须给专门文案，不能渲染成空的"远端最新内容"块误导。
                if (result.remoteContent != null &&
                    result.remoteContent!.isEmpty) ...<Widget>[
                  const SizedBox(height: OgLSpace.md),
                  Text(_t('remoteDeletedNote')),
                ] else ...<Widget>[
                  Text(_t('overwriteWarning')),
                ],
                if (result.remoteContent != null &&
                    result.remoteContent!.isNotEmpty) ...<Widget>[
                  const SizedBox(height: OgLSpace.md),
                  Text(_t('remoteLatestContent')),
                  Container(
                    width: double.infinity,
                    constraints: const BoxConstraints(maxHeight: 200),
                    padding: const EdgeInsets.all(OgLSpace.sm),
                    decoration: BoxDecoration(
                      color: Theme.of(dialogContext)
                          .colorScheme
                          .surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(OgLRadius.sm),
                    ),
                    child: SingleChildScrollView(
                      child: SelectableText(
                        _preview(result.remoteContent!),
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(_t('keepRemote')),
            ),
            TextButton(
              style: TextButton.styleFrom(
                foregroundColor: Theme.of(dialogContext).colorScheme.error,
              ),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(_t('forceOverwrite')),
            ),
          ],
        ),
      );

  Future<bool?> _confirmDiscard() => showDialog<bool>(
        context: context,
        builder: (BuildContext dialogContext) => AlertDialog(
          title: Text(_t('discardTitle')),
          content: Text(_t('discardDesc')),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(_t('continueEditing')),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(_t('discardChanges')),
            ),
          ],
        ),
      );

  /// 统一提示入口（Phase 5 后半收敛）：**提示长什么样、什么语气只有一处定义**
  /// （见 [OgLNotifier]，即 `surface/app/notifier.dart`）—— 本页不再自造 SnackBar。
  ///
  /// 语气分工：[OgLNotifier.success] 操作已生效 / [OgLNotifier.info] 普通说明 /
  /// [OgLNotifier.warning] 失败与"被拦下"（权限不足、目标不存在、写回失败…）。
  OgLNotifier get _notifier => OgLNotifier(ScaffoldMessenger.of(context));

  static String _short(String? sha) => sha == null || sha.isEmpty
      ? '—'
      : (sha.length <= 8 ? sha : sha.substring(0, 8));

  static String _preview(String text) => text.length <= 4000
      ? text
      : _t('previewTruncated', {'text': text.substring(0, 4000)});

  /// 只读预览（弹层）：与编辑器同一套库渲染，便于核对排版与高亮。
  void _previewSheet() {
    final _EditorPrefs settings = _EditorPrefs(widget.surface);
    ogLShowSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      // 底部让位：弹层延伸到屏幕底边（useSafeArea 只管顶部 / 左右），
      // 编辑器最后一屏不会被手势条 / 浏览器下沿盖住。
      builder: (BuildContext sheetContext) => SafeArea(
        top: false,
        child: SizedBox(
          height: MediaQuery.of(sheetContext).size.height * 0.8,
          child: OgLCodeViewer(
            code: _controller.text,
            path: widget.path,
            fontSize: settings.fontSize,
            wrap: _wrap,
            highlight: settings.highlight,
            codeTheme: settings.theme(sheetContext),
          ),
        ),
      ),
    );
  }

  Widget _statusBar(ThemeData theme) => Material(
        color: theme.colorScheme.surfaceContainerHighest,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
              OgLSpace.md, OgLSpace.sm, OgLSpace.md, OgLSpace.sm),
          child: Text(
            '${_t('stats', {
                  'lines': _controller.lineCount,
                  'chars': _controller.text.length
                })}'
            '${_dirty ? _t('unsaved') : ''}',
            style: theme.textTheme.bodySmall,
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final _EditorPrefs prefs = _EditorPrefs(widget.surface);
    // 与已提交版本一致（或从未编辑）才算"干净"：保存后的增量编辑仍是 dirty。
    final bool savedClean =
        _savedText != null && _controller.text == _savedText;
    return PopScope(
      canPop: !_dirty || savedClean,
      onPopInvokedWithResult: (bool didPop, Object? result) async {
        if (didPop) {
          return;
        }
        final bool? leave = await _confirmDiscard();
        if (leave == true && context.mounted) {
          // 「放弃修改」= 真正丢弃：置位后 dispose 不再回写，并主动删除草稿
          //（否则被放弃的内容会当成草稿留在本机，下次进来"复活"）。
          _abandon = true;
          unawaited(widget.surface.domain.api.discardDraft(
            widget.fullName,
            widget.path,
            branch: widget.branch,
          ));
          Navigator.of(context).pop(_saved);
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            widget.path,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleMedium,
          ),
          actions: <Widget>[
            IconButton(
              icon: const Icon(Icons.undo),
              tooltip: _t('undo'),
              onPressed: _controller.canUndo ? _controller.undo : null,
            ),
            IconButton(
              icon: const Icon(Icons.redo),
              tooltip: _t('redo'),
              onPressed: _controller.canRedo ? _controller.redo : null,
            ),
            ValueListenableBuilder<CodeFindValue?>(
              valueListenable: _find,
              builder:
                  (BuildContext context, CodeFindValue? value, Widget? _) =>
                      IconButton(
                icon: Icon(value == null ? Icons.search : Icons.search_off),
                tooltip: _t('findReplace'),
                onPressed: () =>
                    value == null ? _find.findMode() : _find.close(),
              ),
            ),
            IconButton(
              icon: Icon(_wrap ? Icons.wrap_text : Icons.notes),
              tooltip: _wrap ? _t('wrapOff') : _t('wrapOn'),
              onPressed: () => setState(() => _wrap = !_wrap),
            ),
            IconButton(
              icon: const Icon(Icons.remove),
              tooltip: _t('fontSmaller'),
              onPressed: () => _changeFont(-1),
            ),
            IconButton(
              icon: const Icon(Icons.add),
              tooltip: _t('fontLarger'),
              onPressed: () => _changeFont(1),
            ),
            IconButton(
              icon: const Icon(Icons.visibility_outlined),
              tooltip: _t('preview'),
              onPressed: _previewSheet,
            ),
            IconButton(
              icon: const Icon(Icons.save_outlined),
              tooltip: _t('save'),
              onPressed: _saving ? null : _save,
            ),
          ],
        ),
        body: OgLReveal(
            delay: Duration.zero,
            child: Column(
              children: <Widget>[
                Expanded(
                  child: OgLCodeField(
                    controller: _controller,
                    path: widget.path,
                    fontSize: _fontSize,
                    wrap: _wrap,
                    highlight: prefs.highlight,
                    findController: _find,
                    codeTheme: prefs.theme(context),
                  ),
                ),
                _statusBar(theme),
              ],
            )),
      ),
    );
  }
}

/// 读取当前设置的小助手（避免在多处重复取 settings）。
class _EditorPrefs {
  /// 创建。
  const _EditorPrefs(this.surface);

  /// 表面桥。
  final SurfaceBridge surface;

  /// 代码字号。
  double get fontSize => surface.settings.settings.codeFontSize;

  /// 是否启用高亮。
  bool get highlight => surface.settings.settings.codeHighlight;

  /// 解析代码配色。
  OgLCodeTheme theme(BuildContext context) => ogLCodeThemeFor(
        preset: surface.settings.settings.codeThemePreset,
        scheme: Theme.of(context).colorScheme,
        customBackground: surface.settings.settings.codeColorBackground,
        customForeground: surface.settings.settings.codeColorForeground,
        customKeyword: surface.settings.settings.codeColorKeyword,
        customTypeName: surface.settings.settings.codeColorTypeName,
        customString: surface.settings.settings.codeColorString,
        customComment: surface.settings.settings.codeColorComment,
        customNumber: surface.settings.settings.codeColorNumber,
      );
}
