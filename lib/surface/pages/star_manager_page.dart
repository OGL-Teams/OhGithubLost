/// 星标管理：完整分页后在本地按名称、分类与标签检索，保留 GitHub 星标本身。
library;

import 'package:flutter/material.dart';

import '../surface_bridge.dart';
import '../types.dart';
import 'ai_settings_page.dart';
import 'repo_page.dart';

class StarManagerPage extends StatefulWidget {
  const StarManagerPage({required this.surface, super.key});
  final SurfaceBridge surface;
  @override
  State<StarManagerPage> createState() => _StarManagerPageState();
}

class _StarManagerPageState extends State<StarManagerPage> {
  final _query = TextEditingController();
  List<GhRepo> _repos = [];
  Map<String, dynamic> _meta = {};
  String _category = '';
  bool _busy = true, _partial = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final id = await widget.surface.domain.auth.activeAccountId();
      final repos = <GhRepo>[];
      bool partial = false;
      for (var page = 1; page <= 20; page++) {
        final next = await widget.surface.domain.api.starredRepos(
          perPage: 100,
          page: page,
        );
        repos.addAll(next);
        if (next.length < 100) {
          break;
        }
        if (page == 20) {
          partial = true;
        }
      }
      final meta = await widget.surface.starMetadata();
      if (id != await widget.surface.domain.auth.activeAccountId()) {
        throw const AiException('accountChanged');
      }
      if (mounted) {
        setState(() {
          _repos = repos;
          _meta = meta;
          _partial = partial;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = aiError(e));
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _organize(GhRepo repo) async {
    final data = _meta[repo.fullName] as Map? ?? {};
    final category = TextEditingController(
      text: data['category'] as String? ?? '',
    );
    final tags = TextEditingController(
      text: (data['tags'] as List? ?? []).join(', '),
    );
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(repo.fullName),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: category,
              decoration: InputDecoration(labelText: aiText('category')),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: tags,
              decoration: InputDecoration(
                labelText: aiText('tags'),
                helperText: aiText('tagHint'),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(aiText('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(aiText('save')),
          ),
        ],
      ),
    );
    try {
      if (result == true) {
        await widget.surface.organizeStar(
          repo.fullName,
          category.text,
          tags.text.split(RegExp(r'[,，]')),
        );
        final meta = await widget.surface.starMetadata();
        if (mounted) {
          setState(() => _meta = meta);
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = aiError(e));
      }
    } finally {
      category.dispose();
      tags.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final categories =
        _meta.values
            .whereType<Map>()
            .map((e) => e['category'])
            .whereType<String>()
            .where((e) => e.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
    final query = _query.text.trim().toLowerCase();
    final filtered = _repos.where((repo) {
      final data = _meta[repo.fullName] as Map? ?? {};
      final text =
          '${repo.fullName} ${repo.description} ${data['category']} ${(data['tags'] as List? ?? []).join(' ')}'
              .toLowerCase();
      return (_category.isEmpty || data['category'] == _category) &&
          text.contains(query);
    }).toList();
    return Scaffold(
      appBar: AppBar(
        title: Text(aiText('stars')),
        actions: [
          IconButton(
            tooltip: aiText('refresh'),
            onPressed: _busy ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _query,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                labelText: aiText('starSearch'),
                border: const OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  ChoiceChip(
                    label: Text(aiText('allCategories')),
                    selected: _category.isEmpty,
                    onSelected: (_) => setState(() => _category = ''),
                  ),
                  for (final category in categories)
                    Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: ChoiceChip(
                        label: Text(category),
                        selected: _category == category,
                        onSelected: (_) => setState(() => _category = category),
                      ),
                    ),
                ],
              ),
            ),
          ),
          if (_busy) const LinearProgressIndicator(),
          if (_partial)
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text(aiText('starsPartial')),
            ),
          if (_error != null)
            ListTile(
              title: Text(_error!),
              trailing: TextButton(
                onPressed: _load,
                child: Text(aiText('retry')),
              ),
            ),
          Expanded(
            child: filtered.isEmpty && !_busy
                ? Center(child: Text(aiText('noResults')))
                : ListView.builder(
                    itemCount: filtered.length,
                    itemBuilder: (context, index) {
                      final repo = filtered[index];
                      final data = _meta[repo.fullName] as Map? ?? {};
                      return Card(
                        elevation: 1,
                        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                        child: InkWell(
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute<void>(
                              builder: (_) =>
                                  RepoPage(surface: widget.surface, repo: repo),
                            ),
                          ),
                          borderRadius: BorderRadius.circular(12),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.star_outline,
                                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                                  size: 20,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        repo.fullName,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(fontWeight: FontWeight.w500),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        '${data['category'] ?? ''} ${(data['tags'] as List? ?? []).join(' · ')}',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                                        ),
                                      ),
                                      if (repo.description != null)
                                        Text(
                                          repo.description!,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  tooltip: aiText('organize'),
                                  icon: const Icon(Icons.label_outline),
                                  onPressed: () => _organize(repo),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
