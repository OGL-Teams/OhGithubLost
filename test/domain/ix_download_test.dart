/// L2 中枢级 · 下载器安全边界测试（文件名净化 + 协议白名单）。
///
/// 这两条是**下载器必须自己守住**的边界，不能外包给第三方库：
/// 1. **文件名净化** —— `fileName` 的来源之一是 Release 附件名，仓库所有者
///    完全可控；不做净化等于把路径构造交给 `background_downloader` 的内部
///    实现，而那不在本仓库内、无法审计；
/// 2. **协议白名单** —— 加速通道地址由**用户填写**，允许 `file://` 等协议
///    等于让远端内容指定去读本机任意文件，且非 http 协议在浏览器端无法走 CORS。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:ohgithublost/domain/ix/ix_download.dart';
import 'package:ohgithublost/domain/ix/ix_presign.dart';

void main() {
  group('文件名净化', () {
    test('路径穿越被截断到末段', () {
      expect(ogLSafeDownloadFileName('../../etc/passwd'), 'passwd');
      expect(ogLSafeDownloadFileName(r'..\..\windows\system32\cmd.exe'),
          'cmd.exe');
      expect(ogLSafeDownloadFileName('/absolute/path/file.zip'), 'file.zip');
    });

    test('空与纯点号回落到默认名', () {
      expect(ogLSafeDownloadFileName(''), 'download');
      expect(ogLSafeDownloadFileName('   '), 'download');
      expect(ogLSafeDownloadFileName('..'), 'download');
      expect(ogLSafeDownloadFileName('.'), 'download');
      expect(ogLSafeDownloadFileName('...'), 'download');
      expect(ogLSafeDownloadFileName('..', fallback: 'x'), 'x');
    });

    test('控制字符与非法字符被剔除', () {
      expect(ogLSafeDownloadFileName('a\u0000b.txt'), 'ab.txt');
      expect(ogLSafeDownloadFileName('bad\nname.txt'), 'badname.txt');
      expect(ogLSafeDownloadFileName('file<>:"?*.txt'), 'file.txt');
    });

    test('空白收敛、前导点与尾随点被去掉', () {
      expect(ogLSafeDownloadFileName('  spaced name.zip  '), 'spaced name.zip');
      expect(ogLSafeDownloadFileName('.gitignore'), 'gitignore');
      expect(ogLSafeDownloadFileName('report.'), 'report');
    });

    test('Windows 保留设备名被改名', () {
      expect(ogLSafeDownloadFileName('con.txt'), '_con.txt');
      expect(ogLSafeDownloadFileName('NUL'), '_NUL');
      expect(ogLSafeDownloadFileName('com1.log'), '_com1.log');
    });

    test('扩展名被保住，过长扩展名整个丢弃', () {
      expect(ogLSafeDownloadFileName('archive.tar.gz'), 'archive.tar.gz');
      expect(
        ogLSafeDownloadFileName('OGL-v6.0.0-Android.arm64-v8a.zip'),
        'OGL-v6.0.0-Android.arm64-v8a.zip',
      );
      expect(ogLSafeDownloadFileName('name.${'e' * 30}'), 'name');
    });

    test('超长名限长 120 且保住扩展名', () {
      expect(ogLSafeDownloadFileName('${'x' * 200}.zip'), '${'x' * 120}.zip');
      expect(ogLSafeDownloadFileName('a' * 200), 'a' * 120);
      expect(ogLSafeDownloadFileName('.${'x' * 200}.zip'), '${'x' * 120}.zip');
    });

    test('非 ASCII 文件名原样保留', () {
      expect(ogLSafeDownloadFileName('中文文件名.txt'), '中文文件名.txt');
    });
  });

  group('协议白名单', () {
    test('http / https 通过', () {
      expect(ogLAssertDownloadUrl('https://github.com/a/b'), isNotEmpty);
      expect(ogLAssertDownloadUrl('http://github.com/a/b'), isNotEmpty);
      expect(
        ogLAssertDownloadUrl('https://proxy.344977.xyz/https://github.com/a'),
        isNotEmpty,
      );
    });

    test('非 http(s) 一律拒绝', () {
      expect(() => ogLAssertDownloadUrl('file:///etc/passwd'),
          throwsArgumentError);
      expect(() => ogLAssertDownloadUrl('data:text/plain,hi'),
          throwsArgumentError);
      expect(() => ogLAssertDownloadUrl('javascript:alert(1)'),
          throwsArgumentError);
      expect(() => ogLAssertDownloadUrl(''), throwsArgumentError);
      expect(() => ogLAssertDownloadUrl('not a url'), throwsArgumentError);
    });
  });

  group('跳转目标校验（拒绝把设备引向内网）', () {
    test('回环 / 私网 / 链路本地 / 未指定一律拒绝', () {
      for (final String host in <String>[
        'localhost',
        'app.localhost',
        '127.0.0.1',
        '127.9.9.9',
        '0.0.0.0',
        '10.0.0.5',
        '172.16.0.1',
        '172.31.255.255',
        '192.168.1.1',
        // 云环境元数据服务：最值得挡的一个。
        '169.254.169.254',
        '::1',
        'fd00::1',
        'fe80::1',
        '',
      ]) {
        expect(IxPresign.isForbiddenHost(host), isTrue, reason: '应拒绝：$host');
      }
    });

    test('公网域名与公网 IP 放行', () {
      for (final String host in <String>[
        'github.com',
        'release-assets.githubusercontent.com',
        'results-receiver.actions.githubusercontent.com',
        'productionresultssa9.blob.core.windows.net',
        'proxy.344977.xyz',
        '1.1.1.1',
        // 172.32/173.x 不在私网段内。
        '172.32.0.1',
        '172.15.0.1',
      ]) {
        expect(IxPresign.isForbiddenHost(host), isFalse, reason: '应放行：$host');
      }
    });

    test('相对 Location 按基准补全，绝对地址原样取用', () {
      final Uri base = Uri.parse('https://api.github.com/x/y');
      expect(
        IxPresign.safeRedirectTarget('/a/b', base),
        'https://api.github.com/a/b',
      );
      expect(
        IxPresign.safeRedirectTarget('https://cdn.example.com/z', base),
        'https://cdn.example.com/z',
      );
      // 危险协议与内网目标一律拒绝。
      expect(IxPresign.safeRedirectTarget('file:///etc/passwd', base), isNull);
      expect(IxPresign.safeRedirectTarget('http://127.0.0.1/x', base), isNull);
      expect(IxPresign.safeRedirectTarget('http://169.254.169.254/', base),
          isNull);
    });
  });

  group('摘要规整（不谎称验过）', () {
    // 注意：字符串的 `*` 重复是**运行期**运算，不能出现在 const 里。
    final String hex64 = List<String>.filled(64, 'a').join();
    final String hex64Upper = List<String>.filled(64, 'A').join();
    final String hex32 = List<String>.filled(32, 'a').join();
    final String notHex64 = List<String>.filled(64, 'z').join();

    test('接受规范的小写 sha256', () {
      expect(IxPresign.normalizeDigest('sha256:$hex64'), hex64);
      expect(IxPresign.normalizeDigest('SHA256:$hex64Upper'), hex64);
    });

    test('缺失 / 非 sha256 / 长度不对 → null（= 未校验）', () {
      expect(IxPresign.normalizeDigest(null), isNull);
      expect(IxPresign.normalizeDigest(''), isNull);
      expect(IxPresign.normalizeDigest('md5:$hex32'), isNull);
      expect(IxPresign.normalizeDigest('sha256:abc'), isNull);
      expect(IxPresign.normalizeDigest('sha256:$notHex64'), isNull);
      expect(IxPresign.normalizeDigest(hex64), isNull);
      expect(IxPresign.normalizeDigest(123), isNull);
    });
  });
}
