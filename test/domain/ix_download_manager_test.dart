/// L2 · 下载管理器 enqueue 幂等入队测试（内存态）。
///
/// 注入一个内存假 [IxDownloadBackend]（`pathFor` 返回固定路径、`enqueue`
/// 只记录），**不碰真实网络 / 磁盘 IO**，专测编排逻辑：
/// - 同 id 重复入队（queued）→ 返回同一条实例，后端只入队一次；
/// - 终态（canceled / failed / completed）→ 再次入队重建新实例；
/// - enqueue 的协议白名单与文件名净化边界。
library;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:ohgithublost/domain/ix/ix_download.dart';

/// 排空事件循环里挂起的微任务链：管理器内部 fire-and-forget 的收尾
/// （`_finishTask` → 完整性校验 → 置 completed）全是微任务，无定时器、无 IO，
/// 反复让出事件循环即可确定性地跑完。
Future<void> settle([int rounds = 32]) async {
  for (int i = 0; i < rounds; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

/// 内存假后端：不发事件（测试按需手动 `emitState`），只记录入队次数与 spec。
class FakeDownloadBackend implements IxDownloadBackend {
  final StreamController<IxDownloadEvent> _controller =
      StreamController<IxDownloadEvent>.broadcast(sync: true);

  /// 被入队的 spec（按顺序）。
  final List<IxDownloadSpec> specs = <IxDownloadSpec>[];

  int enqueueCalls = 0;
  int cancelCalls = 0;

  @override
  Stream<IxDownloadEvent> get events => _controller.stream;

  @override
  bool get canReadLocalFile => false;

  @override
  bool get supportsRanged => false;

  @override
  bool get supportsPauseResume => false;

  @override
  Future<String> pathFor(IxDownloadSpec spec) async =>
      '/tmp/ogl/${spec.folder}/${spec.fileName}';

  @override
  Future<void> enqueue(IxDownloadSpec spec) async {
    enqueueCalls++;
    specs.add(spec);
  }

  @override
  Future<void> pause(String id) async {}

  @override
  Future<void> resume(String id) async {}

  @override
  Future<void> cancel(String id) async {
    cancelCalls++;
  }

  @override
  Future<int?> completedSize(String id, {String? path}) async => null;

  @override
  Future<String?> fileSha256(String id, {String? path}) async => null;

  @override
  Future<void> deleteFile(String id, {String? path}) async {}

  @override
  void dispose() {
    _controller.close();
  }

  @override
  set downloadDirProvider(Future<String?> Function()? provider) {}

  /// 手动派发一个状态事件（`sync: true`，同步送达监听者）。
  void emitState(String id, IxDownloadStatus status, {String? error}) {
    _controller.add(IxDownloadEvent.state(id, status, error: error));
  }
}

void main() {
  const String url = 'https://github.com/o/r/releases/download/v1.0.0/a.zip';

  late FakeDownloadBackend backend;
  late IxDownloadManager manager;

  setUp(() {
    backend = FakeDownloadBackend();
    manager = IxDownloadManager(backend: backend);
  });

  tearDown(() {
    manager.dispose();
  });

  group('enqueue 幂等入队', () {
    test('首次入队：登记 queued 快照、后端入队一次、savePath 已回填', () async {
      final IxDownloadTask task =
          await manager.enqueue(url: url, fileName: 'a.zip');
      expect(task.status, IxDownloadStatus.queued);
      expect(task.savePath, isNotEmpty);
      expect(backend.enqueueCalls, 1);
      expect(backend.specs.single.fileName, 'a.zip');
    });

    test('同 id 重复入队（queued）→ 返回同一条实例且不二次入队', () async {
      final IxDownloadTask a =
          await manager.enqueue(url: url, fileName: 'a.zip');
      final IxDownloadTask b =
          await manager.enqueue(url: url, fileName: 'a.zip');
      expect(identical(a, b), isTrue);
      expect(backend.enqueueCalls, 1);
    });

    test('同 url 不同文件名 → 派生不同 id，两条独立记录', () async {
      final IxDownloadTask a =
          await manager.enqueue(url: url, fileName: 'a.zip');
      final IxDownloadTask b =
          await manager.enqueue(url: url, fileName: 'b.zip');
      expect(identical(a, b), isFalse);
      expect(a.id, isNot(b.id));
      expect(manager.tasks.length, 2);
    });

    test('已取消（终态）再次入队 → 重建新实例', () async {
      final IxDownloadTask first =
          await manager.enqueue(url: url, fileName: 'a.zip');
      await manager.cancel(first.id);
      expect(manager.tasks.single.status, IxDownloadStatus.canceled);

      final IxDownloadTask second =
          await manager.enqueue(url: url, fileName: 'a.zip');
      expect(identical(first, second), isFalse);
      expect(second.status, IxDownloadStatus.queued);
      expect(backend.enqueueCalls, 2);
    });

    test('已失败（终态）再次入队 → 重建且清空旧错误', () async {
      final IxDownloadTask first =
          await manager.enqueue(url: url, fileName: 'a.zip');
      backend.emitState(first.id, IxDownloadStatus.failed, error: 'timeout');
      expect(manager.tasks.single.status, IxDownloadStatus.failed);
      expect(manager.tasks.single.errorText, 'timeout');

      final IxDownloadTask second =
          await manager.enqueue(url: url, fileName: 'a.zip');
      expect(identical(first, second), isFalse);
      expect(second.status, IxDownloadStatus.queued);
      expect(second.error, isNull);
      expect(backend.enqueueCalls, 2);
    });

    test('已完成（终态）再次入队 → 重建新实例', () async {
      final IxDownloadTask first =
          await manager.enqueue(url: url, fileName: 'a.zip');
      backend.emitState(first.id, IxDownloadStatus.completed);
      await settle();
      expect(manager.tasks.single.status, IxDownloadStatus.completed);

      final IxDownloadTask second =
          await manager.enqueue(url: url, fileName: 'a.zip');
      expect(identical(first, second), isFalse);
      expect(second.status, IxDownloadStatus.queued);
      expect(backend.enqueueCalls, 2);
    });
  });

  group('enqueue 安全边界', () {
    test('文件名在入队时被净化（路径穿越截到末段）', () async {
      final IxDownloadTask task =
          await manager.enqueue(url: url, fileName: '../../evil.sh');
      expect(task.fileName, 'evil.sh');
      expect(backend.specs.single.fileName, 'evil.sh');
    });

    test('非 http(s) 地址被拒绝', () async {
      await expectLater(
        manager.enqueue(url: 'file:///etc/passwd', fileName: 'a'),
        throwsArgumentError,
      );
    });
  });
}
