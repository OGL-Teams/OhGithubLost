/// 日志落盘的层内检查：**写盘必须真的发生**，失败必须能说清原因。
///
/// 为什么这些断言值得存在：用户此前拿不到任何日志（只在内存里、进程一死就没了），
/// 于是所有排查都变成猜。这套测试保证：
/// 1. 写过的行一定出现在文件里（不是"以为写了"）；
/// 2. 候选目录按顺序尝试，不可写的跳过并**记录原因**；
/// 3. 跨天/超限的文件命名与滚动规则稳定；
/// 4. `OgLAppLog`（应用日志）与落盘器是**联通**的。
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ohgithublost/kernel/log/og_l_log_file.dart';
import 'package:ohgithublost/surface/app/error_surface.dart';

String _todayStamp() {
  final DateTime now = DateTime.now();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${now.year}${two(now.month)}${two(now.day)}';
}

void main() {
  late Directory temp;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('ogl_log_test_');
  });

  tearDown(() async {
    await OgLLogFile.close();
    try {
      temp.deleteSync(recursive: true);
    } catch (_) {
      // 清理失败不影响结论。
    }
  });

  test('写入的行一定落盘（含级别与区域）', () async {
    final String dir = '${temp.path}/logging';
    await OgLLogFile.init(candidates: <String>[dir]);
    expect(OgLLogFile.isEnabled, isTrue, reason: '临时目录一定可写');
    expect(OgLLogFile.filePath, isNotNull);
    expect(OgLLogFile.filePath!.endsWith('ogl-${_todayStamp()}.log'), isTrue);

    OgLLogFile.line('测试', '第一行', level: 'INFO');
    OgLLogFile.line('测试', '出错行', level: 'ERR');
    await OgLLogFile.flush();

    final String text = File(OgLLogFile.filePath!).readAsStringSync();
    expect(text.contains('[INFO] [测试] 第一行'), isTrue);
    expect(text.contains('[ERR] [测试] 出错行'), isTrue);
  });

  test('候选顺序：不可写的跳过，可写的接管，原因可查', () async {
    // 用一个"文件"当父路径，createSync 必然失败 —— 模拟 /sdcard 无权限。
    final File blocker = File('${temp.path}/blocker');
    blocker.writeAsStringSync('x');
    final String bad = '${blocker.path}/logging';
    final String good = '${temp.path}/fallback';

    await OgLLogFile.init(candidates: <String>[bad, good]);
    expect(OgLLogFile.isEnabled, isTrue);
    expect(OgLLogFile.filePath!.startsWith(good), isTrue);
    expect(OgLLogFile.triedDirectories, <String>[bad, good]);
  });

  test('全部候选都不可写：不启用、不抛、原因留在现场', () async {
    final File blocker = File('${temp.path}/blocker2');
    blocker.writeAsStringSync('x');
    await OgLLogFile.init(candidates: <String>['${blocker.path}/a']);
    expect(OgLLogFile.isEnabled, isFalse);
    expect(OgLLogFile.filePath, isNull);
    expect(OgLLogFile.lastError, isNotNull);
    // 不启用时写入也不能抛（宁可丢日志，不能反过来炸功能）。
    OgLLogFile.line('测试', '无盘可写');
  });

  test('超限滚动：同一天的旧文件被挪到 .1.log', () async {
    final String dir = '${temp.path}/rotate';
    Directory(dir).createSync(recursive: true);
    final File today = File('$dir/ogl-${_todayStamp()}.log');
    // 造一个"比上限还大"的旧文件（不真的写 2MB 内容之外的东西）。
    today.writeAsStringSync('x' * (OgLLogFile.maxBytes + 10));

    await OgLLogFile.init(candidates: <String>[dir]);
    expect(File('$dir/ogl-${_todayStamp()}.log.1.log').existsSync(), isTrue,
        reason: '旧文件应被滚到 .1.log');
    expect(today.existsSync(), isTrue, reason: '新文件继续写同一天的文件名');
  });

  test('OgLAppLog 与落盘器联通：应用日志会出现在文件里', () async {
    final String dir = '${temp.path}/bridge';
    await OgLLogFile.init(candidates: <String>[dir]);
    OgLAppLog.instance.add('联调', '内存与磁盘都要有这一行');
    OgLAppLog.instance.result('联调', '动作完成', '3 条');
    await OgLLogFile.flush();

    final String text = File(OgLLogFile.filePath!).readAsStringSync();
    expect(text.contains('内存与磁盘都要有这一行'), isTrue);
    // 5.0：正文里**不再出现 ✔ / ▶ 这类符号字形**（Android 上会被当 emoji
    // 呈现，即用户说的"emoji 撕裂"）；结果与步骤的区分交给 level 字段。
    expect(text.contains('动作完成：3 条'), isTrue, reason: '成功结果同样入库（用户明确要求）');
    expect(text.contains('✔'), isFalse, reason: '正文不得再出现符号字形');
    // 内存侧也保留（关于页要能翻）。
    final List<String> displayed = OgLAppLog.instance.entries
        .map((OgLAppLogEntry e) => e.toDisplay())
        .toList();
    expect(
      displayed.any((String line) => line.contains('内存与磁盘都要有这一行')),
      isTrue,
    );
  });
}
