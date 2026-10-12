/// L2 · AI 工具注册表（只读 + 受控）。
///
/// 把 `domain/gh` 的能力包装成模型可调用的 [AiTool]。**v1 只放只读工具**：
/// 任何会改动仓库 / 触发工作流的操作都该走「提案 → 用户审阅」流程，
/// 不在此直接开放给模型。
library;

import '../gh/gh_api.dart';
import '../gh/gh_models.dart';
import 'ai_tool.dart';

/// 装配 AI 工具注册表。
List<AiTool> buildAiTools(GhApi api) => <AiTool>[
      AiTool(
        name: 'list_files',
        description: '列出仓库某个目录下的文件与子目录。返回 path 与 type(file|dir)。',
        parameters: <String, Object?>{
          'type': 'object',
          'properties': <String, Object?>{
            'repo': <String, Object?>{
              'type': 'string',
              'description': '仓库全名（owner/name）。',
            },
            'path': <String, Object?>{
              'type': 'string',
              'description': '目录路径；空串表示根目录。',
            },
          },
          'required': <String>['repo'],
        },
        run: (Map<String, Object?> args) async {
          final String repo = '${args['repo'] ?? ''}';
          if (repo.isEmpty) {
            return <String, Object?>{'error': '缺少 repo'};
          }
          final String dir = '${args['path'] ?? ''}'.replaceAll(RegExp(r'^/+'), '');
          try {
            final GhTree tree = await api.tree(repo, recursive: true);
            final List<Map<String, String>> out = <Map<String, String>>[];
            for (final GhTreeEntry e in tree.entries) {
              final bool under = dir.isEmpty || e.path == dir || e.path.startsWith('$dir/');
              if (!under) {
                continue;
              }
              final String rest = dir.isEmpty ? e.path : e.path.substring(dir.length).replaceAll(RegExp(r'^/+'), '');
              if (rest.isEmpty || rest.contains('/')) {
                continue; // 只列直接子项
              }
              out.add(<String, String>{
                'path': e.path,
                'name': rest,
                'type': e.type.name,
              });
            }
            return out;
          } on Object catch (e) {
            return <String, Object?>{'error': '$e'};
          }
        },
      ),
      AiTool(
        name: 'read_file',
        description: '读取仓库某个文件的文本内容。返回文件正文。',
        parameters: <String, Object?>{
          'type': 'object',
          'properties': <String, Object?>{
            'repo': <String, Object?>{
              'type': 'string',
              'description': '仓库全名（owner/name）。',
            },
            'path': <String, Object?>{
              'type': 'string',
              'description': '文件路径。',
            },
          },
          'required': <String>['repo', 'path'],
        },
        run: (Map<String, Object?> args) async {
          final String repo = '${args['repo'] ?? ''}';
          final String path = '${args['path'] ?? ''}';
          if (repo.isEmpty || path.isEmpty) {
            return <String, Object?>{'error': '缺少 repo 或 path'};
          }
          try {
            final String? text = await api.rawFileText(repo, path);
            if (text == null) {
              return <String, Object?>{'error': '文件不存在或不可读'};
            }
            return <String, Object?>{'path': path, 'content': text};
          } on Object catch (e) {
            return <String, Object?>{'error': '$e'};
          }
        },
      ),
    ];
