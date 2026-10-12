/// 月度贡献统计：明确区分提交总数与实际取到差异的样本行数。
library;

import 'package:flutter/material.dart';

import '../surface_bridge.dart';
import '../types.dart';
import 'ai_settings_page.dart';

class ContributionsPage extends StatefulWidget {
  const ContributionsPage({required this.surface, super.key});
  final SurfaceBridge surface;
  @override
  State<ContributionsPage> createState() => _ContributionsPageState();
}

class _ContributionsPageState extends State<ContributionsPage> {
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  Map<String, dynamic>? _stats;
  bool _busy = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _busy = true;
      _error = null;
      _stats = null;
    });
    try {
      final account = await widget.surface.domain.auth.activeAccount();
      if (account == null) {
        throw const AiException('loginRequired');
      }
      final stats = await widget.surface.monthlyContributions(
        account.login,
        _month,
      );
      if (mounted) {
        setState(() => _stats = stats);
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

  void _change(int offset) {
    setState(() => _month = DateTime(_month.year, _month.month + offset));
    _load();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(aiText('contributions'))),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              tooltip: aiText('previousMonth'),
              onPressed: _busy ? null : () => _change(-1),
              icon: const Icon(Icons.chevron_left),
            ),
            Text('${_month.year}-${_month.month.toString().padLeft(2, '0')}'),
            IconButton(
              tooltip: aiText('nextMonth'),
              onPressed:
                  _busy ||
                      _month.isAfter(
                        DateTime(
                          DateTime.now().year,
                          DateTime.now().month,
                        ).subtract(const Duration(microseconds: 1)),
                      )
                  ? null
                  : () => _change(1),
              icon: const Icon(Icons.chevron_right),
            ),
          ],
        ),
        const SizedBox(height: 20),
        if (_busy) const LinearProgressIndicator(),
        if (_error != null)
          ListTile(
            title: Text(_error!),
            trailing: TextButton(
              onPressed: _load,
              child: Text(aiText('retry')),
            ),
          ),
        if (_stats != null) ...[
          for (final key in ['commits', 'added', 'deleted', 'measured'])
            Card(
              child: ListTile(
                title: Text(aiText(key == 'deleted' ? 'deletedLines' : key)),
                trailing: Text(
                  '${_stats![key]}',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
            ),
          const SizedBox(height: 16),
          Text(aiText('statsScope')),
          if (_stats!['sampled'] == true ||
              _stats!['incomplete'] == true ||
              _stats!['failed'] != 0)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(aiText('statsPartial')),
            ),
        ],
      ],
    ),
  );
}
