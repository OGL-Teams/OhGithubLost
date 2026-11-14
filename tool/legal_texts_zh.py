#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""法律与声明文本 · 简体中文权威版（正文 + 速览 + 效力声明）。

文风：现代规范书面语，克制、清晰、严谨；不使用文言虚词，也不使用口语。
结构：与各语言一一对应（十七节），便于逐节对照。
"""
from __future__ import annotations

import collections
import json
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ZH = os.path.join(ROOT, 'assets', 'i18n', 'zh', 'onboarding.json')

BODY = """一、许可与权威文本
本应用以 Apache License 2.0 发布。授权条款全文见仓库根目录的 LICENSE 文件，它是唯一具有法律效力的授权文件。本声明是说明性文本，用于告知实际做法，不构成许可，也不增减任何权利或义务。

二、本声明的适用范围
本声明仅适用于本应用本体，不涵盖用户自备的加速通道；加速通道由第三方提供，适用其自身协议，需用户自行阅读并同意。未启用任何加速通道时，本声明即为本应用与用户之间的完整约定。

三、不收集数据
本应用不收集、不存储、不上传任何个人数据，不含遥测、分析、广告与用户画像组件，也不含第三方追踪。仅申请与功能直接相关的系统权限，并在首次启动时逐项说明用途。

四、数据驻留
缓存、草稿、下载文件与运行日志全部存于用户设备，卸载即随之清除。GitHub 访问令牌保存在操作系统的安全存储中，界面与日志一律脱敏；退出登录即从本机删除。本应用不运营接收用户数据的服务器。

五、网络请求
未启用加速时，请求仅发往 GitHub 官方接口与资源域名。启用加速后，部分下载请求改经该通道，其处理适用通道自身协议。有可用摘要时校验内容摘要；无摘要时标注「未校验」，不谎称已验证。

六、可选的 Web 版本
Web 版本默认关闭，不在本声明范围内。浏览器环境涉及浏览器、托管方与网络中间环节，可能记录访问时间、IP 地址与 User-Agent；本应用无法替其作出不收集数据的保证。仅在用户主动启用该功能时，本节例外方适用。

七、账号与令牌
用户自行提供 GitHub 令牌，并自行管理其权限范围。令牌在设备上被窃取的风险由用户承担；发现泄露应立即在 GitHub 撤销令牌并退出登录。本应用不代替用户作出任何授权决定。

八、第三方组件
本应用包含第三方开源组件，各组件适用其自身许可，清单见「关于」页与 NOTICE 文件。本应用以 Apache-2.0 发布，与上述宽松许可兼容。

九、知识产权
本应用软件的著作权归开发者所有；开源许可授予使用与修改的权利，不转移著作权。第三方商标归各自权利人所有。

十、免责声明
本应用按现状提供，不提供任何明示或默示的担保，包括适销性、特定用途适用性与不侵权的担保。开发者不对因使用或无法使用本应用造成的损失承担责任，法律不允许免除的责任除外。

十一、第三方链接与内容
应用内出现的第三方链接与内容由其提供方负责，本应用不对其内容、准确性或可用性作任何保证。用户在第三方服务中提交的个人信息，适用该服务自身的隐私政策。

十二、不可抗力与责任限制
在法律允许的最大范围内，因不可抗力、第三方服务故障或网络中断造成的损失，开发者不承担责任。本条不适用于法律禁止限制责任的事项。

十三、适用法律与争议解决
本声明适用开发者所在地的法律，但不排除消费者惯常居所地的强制性规定。争议应先通过仓库 Issues 协商解决；协商不成的，提交开发者所在地有管辖权的法院处理。

十四、未成年人
本应用不面向 13 周岁以下儿童。因本应用不收集个人信息，若用户认为开发者持有与儿童有关的信息，请按第十三节的方式联系，核实后立即删除。

十五、声明的变更
实质性修改将随版本发布，并在应用内重新征求同意，同意版本号相应提升，不静默生效。本声明自首次启动起适用，以应用内展示的最新文本为准。

十六、终止使用
用户可随时停止使用并卸载本应用，数据随卸载清除。

十七、联系方式
本应用为开源项目，问题与请求请通过仓库 Issues 提交：
https://github.com/OGL-Teams/OhGithubLost/issues"""

HIGHLIGHTS = """要点速览
· 本应用不收集任何个人数据，也不上传任何数据。
· GitHub 令牌只保存在本机的安全存储中，界面与日志一律脱敏。
· 所有数据只存放在你的设备上，卸载即随之清除。
· 未启用加速时，网络请求仅发往 GitHub 官方域名。
· 代码与构建配置全部公开，欢迎自行审阅。
· 本应用以 Apache-2.0 发布，第三方组件各适用其自身许可。
· 授权条款全文见仓库根目录的 LICENSE 文件。"""

SIMPLE = """本应用是开源软件，代码与构建配置全部公开，授权条款写在仓库根目录的 LICENSE 文件中。它不收集任何个人数据，你的 GitHub 令牌只保存在你自己的设备上。"""

INTRO = """本声明如实说明本应用的实际做法，便于用户了解。它是说明性文本，不构成法律协议。唯一具有法律效力的授权文件，是随程序发布的 Apache License 2.0 全文。"""

EFFECTIVE = """本声明以中文文本为准。其他语言的译本仅供理解参考；如与中文原文不一致，以中文原文为准。"""

OFFICIAL = """本声明仅对随本应用官方发布且未经修改的副本有效。任何第三方转载、改动或重新发布，均不代表开发者立场，本应用对其内容不负责任。"""

STATEMENT_ONLY = """本文是说明性声明，不产生法律效力。唯一具有法律效力的文件是随程序发布的 Apache License 2.0 全文。"""

AUTHORITATIVE_LINE = """唯一具有法律效力的是仓库根目录的 LICENSE（Apache License 2.0）全文。本页文字仅为说明，不构成许可，也不增减任何权利或义务。"""

OFFICIAL_LINE = """本声明以中文为准；译本仅供理解，如与原文不一致，以中文原文为准。"""


def main() -> None:
    with open(ZH, encoding='utf-8') as handle:
        data = json.load(handle, object_pairs_hook=collections.OrderedDict)
    data['onboardingLicenseBody'] = BODY
    data['licenseBody'] = BODY
    data['onboardingLicenseHighlights'] = HIGHLIGHTS
    data['licenseHighlights'] = HIGHLIGHTS
    data['licenseSimple'] = SIMPLE
    data['licenseIntro'] = INTRO
    data['licenseAuthoritative'] = EFFECTIVE
    data['legalStatementOnly'] = STATEMENT_ONLY
    data['licenseOfficialCopy'] = OFFICIAL
    data['licenseOfficialLine'] = OFFICIAL_LINE
    data['licenseAuthoritativeLine'] = AUTHORITATIVE_LINE
    with open(ZH, 'w', encoding='utf-8') as handle:
        handle.write(json.dumps(data, ensure_ascii=False, indent=2) + '\n')
    print('zh 法律文本已重写（17 节 / 速览 / 效力声明）')


if __name__ == '__main__':
    main()
