#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""`inject_platform_spec.py` 的自检（不碰真实平台目录）。

用**临时目录里的假脚手架**验证：解析、幂等、逐项注入、以及"缺 why 必须拒绝"。
退出码 0 = 全部通过（可直接挂 CI）。
"""
import os
import shutil
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TOOL = os.path.join(ROOT, 'tool', 'inject_platform_spec.py')

FAKE_ANDROID_GRADLE = """android {
    namespace = "com.yingo.ohgithublost"
    compileSdk = 35

    defaultConfig {
        applicationId = "com.yingo.ohgithublost"
        minSdk = 24
        targetSdk = 35
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        coreLibraryDesugaringEnabled = true
        coreLibraryDesugaring 'com.android.tools:desugar_jdk_libs:2.1.4'
    }
}
"""

# Flutter 模板的另一套写法（Groovy / 旧模板）：必须同样能被注入命中。
FAKE_ANDROID_GRADLE_GROOVY = """android {
    compileSdkVersion flutter.compileSdkVersion

    compileOptions {
        coreLibraryDesugaringEnabled true
        coreLibraryDesugaring 'com.android.tools:desugar_jdk_libs:2.1.4'
    }
}
"""

FAKE_MANIFEST = """<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <application
        android:label="ohgithublost"
        android:name="${applicationName}">
    </application>
</manifest>
"""

FAKE_CMAKE = """cmake_minimum_required(VERSION 3.10)
project(runner LANGUAGES CXX)

# 运行库与宏
add_definitions(-DUNICODE -D_UNICODE)
"""

FAILURES = []


def check(name, ok, detail=''):
    print('  %s %s' % ('✓' if ok else '✗', name))
    if not ok:
        FAILURES.append('%s %s' % (name, detail))


def run(workspace, *args):
    # ★ cwd 必须是临时目录：万一注入器内部再出现相对路径，
    #   泄漏的也只会是临时目录，而**不是仓库根**（曾真的在仓库里
    #   建出 android/ 与 linux/runner/）。
    return subprocess.run(
        [sys.executable, TOOL, '--root', workspace] + list(args),
        capture_output=True, text=True, cwd=workspace)


def repo_is_clean(workspace):
    """仓库根不应被注入器写入任何东西。"""
    leaked = [name for name in ('android', 'linux', 'windows', 'macos', 'ios')
              if os.path.exists(os.path.join(ROOT, name))]
    return not leaked, leaked


def main():
    tmp = tempfile.mkdtemp(prefix='ogl-spec-')
    try:
        os.makedirs(os.path.join(tmp, 'android', 'app'))
        os.makedirs(os.path.join(tmp, 'android', 'app', 'src', 'main'))
        os.makedirs(os.path.join(tmp, 'windows', 'runner'))
        os.makedirs(os.path.join(tmp, 'linux', 'runner', 'resources'))
        gradle = os.path.join(tmp, 'android', 'app', 'build.gradle')
        manifest = os.path.join(tmp, 'android', 'app', 'src', 'main',
                                'AndroidManifest.xml')
        cmake = os.path.join(tmp, 'windows', 'CMakeLists.txt')
        with open(gradle, 'w', encoding='utf-8') as fh:
            fh.write(FAKE_ANDROID_GRADLE)
        with open(manifest, 'w', encoding='utf-8') as fh:
            fh.write(FAKE_MANIFEST)
        with open(cmake, 'w', encoding='utf-8') as fh:
            fh.write(FAKE_CMAKE)
        # 图标注入需要真实的 SVG 源，复制一份进来（与 CI 里同源）。
        icon_src = os.path.join(ROOT, 'assets', 'icon', 'ogl_icon.svg')
        os.makedirs(os.path.join(tmp, 'assets', 'icon'), exist_ok=True)
        shutil.copy(icon_src, os.path.join(tmp, 'assets', 'icon', 'ogl_icon.svg'))

        print('① Android 注入')
        r1 = run(tmp, '--target', 'android')
        check('退出码 0', r1.returncode == 0, r1.stderr[:200])
        gradle_text = open(gradle, encoding='utf-8').read()
        manifest_text = open(manifest, encoding='utf-8').read()
        check('compileSdk 已标记', 'OGL_PLATFORM_SPEC compileSdk' in gradle_text)
        check('desugaring 已标记', 'OGL_PLATFORM_SPEC desugaring' in gradle_text)
        check('INTERNET 已声明', 'android.permission.INTERNET' in manifest_text)
        check('MANAGE_EXTERNAL_STORAGE 已声明',
              'MANAGE_EXTERNAL_STORAGE' in manifest_text)
        check('requestLegacyExternalStorage 已处理',
              'requestLegacyExternalStorage' in manifest_text)
        check('label 已改 OGL', 'android:label="OGL"' in manifest_text)
        check('图标前景已写入',
              os.path.isfile(os.path.join(
                  tmp, 'android', 'app', 'src', 'main', 'res', 'drawable',
                  'ic_launcher_foreground.xml')))

        print('② 幂等（重跑不应改内容、不报错）')
        before = (gradle_text, manifest_text)
        r2 = run(tmp, '--target', 'android')
        check('退出码 0', r2.returncode == 0, r2.stderr[:200])
        check('build.gradle 未变化',
              open(gradle, encoding='utf-8').read() == before[0])
        check('AndroidManifest 未变化',
              open(manifest, encoding='utf-8').read() == before[1])

        print('③ Windows 注入')
        r3 = run(tmp, '--target', 'windows')
        check('退出码 0', r3.returncode == 0, r3.stderr[:200])
        cmake_text = open(cmake, encoding='utf-8').read()
        check('编译宏已注入', 'add_compile_definitions' in cmake_text)
        check('幂等标记已写入', 'OGL_PLATFORM_SPEC' in cmake_text)
        check('ICO 已写入',
              os.path.isfile(os.path.join(tmp, 'windows', 'runner', 'resources',
                                          'app_icon.ico')))

        print('④ Linux 注入')
        r4 = run(tmp, '--target', 'linux')
        check('退出码 0', r4.returncode == 0, r4.stderr[:200])
        check('PNG 已写入',
              os.path.isfile(os.path.join(tmp, 'linux', 'runner', 'resources',
                                          'app_icon.png')))

        print('⑤ 单 job 过滤')
        r5 = run(tmp, '--target', 'android', '--job', 'android-icon')
        check('只跑指定 job 退出码 0', r5.returncode == 0, r5.stderr[:200])
        check('输出只含该 job', 'android-icon' in r5.stdout)

        print('⑥ 缺 why 必须拒绝（防止注入成为逃生舱）')
        bad = os.path.join(tmp, 'bad_spec.yaml')
        with open(bad, 'w', encoding='utf-8') as fh:
            fh.write('spec_version: 1\nspecs:\n  - target: android\n'
                     '    id: x\n    steps:\n      - file: nope.txt\n'
                     '        patch: set_app_label\n')
        r6 = subprocess.run(
            [sys.executable, TOOL, '--root', tmp, '--target', 'android',
             '--spec', bad], capture_output=True, text=True)
        check('退出码非 0', r6.returncode != 0)
        check('明确提示缺 why', 'why' in (r6.stderr + r6.stdout))

        print('⑦ 未知平台只是跳过')
        r7 = run(tmp, '--target', 'plan9')
        check('退出码 0', r7.returncode == 0, r7.stderr[:200])

        print('⑧ 仓库根未被污染（不许建出 android/ linux/ 等）')
        clean, leaked = repo_is_clean(tmp)
        check('仓库根干净', clean, '泄漏：%s' % '、'.join(leaked))

        print('⑨ compileSdk 两种模板写法都能命中')
        # ⑨-a Groovy 旧写法：`compileSdkVersion flutter.compileSdkVersion`
        groovy_dir = os.path.join(tmp, 'groovy')
        os.makedirs(os.path.join(groovy_dir, 'android', 'app'))
        groovy_gradle = os.path.join(groovy_dir, 'android', 'app', 'build.gradle')
        with open(groovy_gradle, 'w', encoding='utf-8') as fh:
            fh.write(FAKE_ANDROID_GRADLE_GROOVY)
        rg = run(groovy_dir, '--target', 'android')
        check('Groovy 写法退出码 0', rg.returncode == 0, rg.stderr[:200])
        groovy_text = open(groovy_gradle, encoding='utf-8').read()
        check('Groovy 写法已注入',
              'OGL_PLATFORM_SPEC compileSdk' in groovy_text)
        check('Groovy 写法已替换为数字',
              'flutter.compileSdkVersion' not in groovy_text.split('OGL')[0])

        # ⑨-b Kotlin DSL 写法：`compileSdk = flutter.compileSdkVersion`
        kts_dir = os.path.join(tmp, 'kts')
        os.makedirs(os.path.join(kts_dir, 'android', 'app'))
        kts_gradle = os.path.join(kts_dir, 'android', 'app', 'build.gradle')
        with open(kts_gradle, 'w', encoding='utf-8') as fh:
            fh.write(FAKE_ANDROID_GRADLE.replace('compileSdk = 35',
                                                'compileSdk = flutter.compileSdkVersion'))
        rk = run(kts_dir, '--target', 'android')
        check('Kotlin DSL 写法退出码 0', rk.returncode == 0, rk.stderr[:200])
        kts_text = open(kts_gradle, encoding='utf-8').read()
        check('Kotlin DSL 写法已注入',
              'OGL_PLATFORM_SPEC compileSdk' in kts_text)

        print()
        if FAILURES:
            print('自检失败 %d 项：' % len(FAILURES))
            for item in FAILURES:
                print('  - %s' % item)
            return 1
        print('自检全部通过')
        return 0
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


if __name__ == '__main__':
    sys.exit(main())