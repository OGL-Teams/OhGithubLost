/// L0 内核级 · **日志落盘后端**（真实文件 + `IOSink`）。
///
/// 由 `og_l_log_file.dart` 导入；可以放心用 `dart:io`。
/// 公开面（`OgLLogBackend`）只暴露给主门面，不是跨平台契约的一部分。
library;

import 'dart:io';

/// 日志文件后端（真实文件系统）。
///
/// 落盘策略与改造前**逐字一致**：
/// - 每条写入后排队 `flush`；
/// - 文件按天切分（`<prefix>-<yyyymmdd>.log`）、超 [maxBytes] 滚动到 `.1.log`；
/// - `_open` 先写一个空追加作探针，权限不足在**打开时**就抛出。
class OgLLogBackend {
  /// 创建后端。
  OgLLogBackend({this.maxBytes = 2 * 1024 * 1024});

  /// 单文件大小上限（超出即滚动到 `.1.log`）。
  final int maxBytes;

  /// 出错回调（跨天切换 / 写入失败时由主门面记录到 `lastError`）。
  void Function(String error)? onError;

  IOSink? _sink;
  String? _filePath;
  String? _dirPath;
  String _dayStamp = '';
  Future<void> _flushTail = Future<void>.value();

  /// 是否已成功落盘。
  bool get isEnabled => _sink != null;

  /// 当前日志文件的绝对路径（未落盘时为 `null`）。
  String? get filePath => _filePath;

  /// 当前日志目录（未落盘时为 `null`）。
  String? get dirPath => _dirPath;

  /// 尝试把日志打开在 [dir]；成功返回 `null`，失败返回错误描述。
  Future<String?> openDir(
    String dir, {
    required String prefix,
    required String stamp,
  }) async {
    try {
      Directory(dir).createSync(recursive: true);
      final String path = '$dir/$prefix-$stamp.log';
      await _open(path, rotateIfNeeded: true);
      _dirPath = dir;
      _filePath = path;
      return null;
    } catch (error) {
      return '$error';
    }
  }

  /// 写一行（**已带时间戳的完整行**）；内部处理跨天切换。
  void write(String text) {
    if (_sink == null) {
      return;
    }
    // 先处理跨天切换：切换成功后 `_sink` 已指向新文件，
    // 因此下面**必须重新取一次**句柄，不能沿用进入时的旧引用
    // （否则跨天后的第一行会写向已关闭的旧句柄，静默丢失）。
    ensureCurrentDay();
    final IOSink? sink = _sink;
    if (sink == null) {
      return;
    }
    try {
      sink.writeln(text);
      // 排队 flush：不阻塞调用方，但保证"写过的行"尽快落盘。
      _flushTail = _flushTail.then((_) async {
        try {
          await _sink?.flush();
        } catch (_) {
          // flush 失败不能反过来炸应用；错误在下次 init 时重新暴露。
        }
      });
    } catch (error) {
      onError?.call('$error');
    }
  }

  /// 未落盘时的兜底输出：保持"不额外输出"（与改造前一致）。
  void fallback(String text) {
    // 有意留空：真实落盘失败时由主门面把原因记入 lastError，不刷屏。
  }

  /// 等所有已排队的写入落盘（退出前 / 崩溃上报时用）。
  Future<void> flush() async {
    try {
      await _sink?.flush();
    } catch (_) {
      // 同上：不抛出。
    }
    await _flushTail;
  }

  /// 关闭句柄（退出前调用）。
  Future<void> close() async {
    await flush();
    try {
      await _sink?.close();
    } catch (_) {
      // 关闭失败不影响退出。
    }
    _sink = null;
    _filePath = null;
  }

  /// 测试用：绑定一个任意 sink（不做目录探测）。
  void bindForTest(String path) {
    _dayStamp = _stamp(DateTime.now());
    _sink = File(path).openWrite(mode: FileMode.write);
    _filePath = path;
    _dirPath = File(path).parent.path;
  }

  Future<void> _open(String path, {bool rotateIfNeeded = false}) async {
    final File file = File(path);
    if (rotateIfNeeded && file.existsSync() && file.lengthSync() > maxBytes) {
      final File rotated = File('$path.1.log');
      try {
        if (rotated.existsSync()) {
          rotated.deleteSync();
        }
        file.renameSync(rotated.path);
      } catch (_) {
        // 滚动失败就继续往原文件写：宁可文件大，不可丢日志。
      }
    }
    // 探针：先同步写一个空追加，权限不足会**在这里**就抛出，
    // 而不是等到第一次 flush 才悄悄失败。
    file.writeAsStringSync('', mode: FileMode.append, flush: true);
    _sink = file.openWrite(mode: FileMode.append);
    _dayStamp = _stamp(DateTime.now());
  }

  /// 跨天时自动切到新文件（每次写入前检查，代价可忽略）。
  ///
  /// 顺序要点：**先把新句柄装好，再关闭旧句柄**——
  /// 反过来的话，切换瞬间正要写的那一行会落到已关闭的旧句柄上（静默丢失）。
  /// `_open` 失败时（如磁盘满）：旧句柄保持可用（未关），日志继续写旧文件，
  /// 错误记入回调，下一条日志会再次尝试切换。
  void ensureCurrentDay() {
    final IOSink? sink = _sink;
    final String? dir = _dirPath;
    if (sink == null || dir == null || _filePath == null) {
      return;
    }
    final String today = _stamp(DateTime.now());
    if (today == _dayStamp) {
      return;
    }
    final String prefix =
        File(_filePath!).uri.pathSegments.last.split('-').first;
    final String next = '$dir/$prefix-$today.log';
    try {
      sink.flush();
    } catch (_) {
      // 旧句柄 flush 失败不阻断切换。
    }
    // `_open` 的函数体同步执行：返回时 `_sink` / `_dayStamp` 已切到新文件；
    // 任何异步失败（探针写失败等）落在 future 上，由下面收尾。
    _open(next).then((_) {
      _filePath = next;
      try {
        sink.close();
      } catch (_) {
        // 旧句柄关闭失败不影响新句柄继续写。
      }
    }).catchError((Object error) {
      // 切换失败：保持旧句柄继续用（不能丢日志）；下一条写入会再次尝试。
      onError?.call('$error');
    });
  }

  static String _stamp(DateTime at) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${at.year}${two(at.month)}${two(at.day)}';
  }
}
