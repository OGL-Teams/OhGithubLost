#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""法律与声明文本 · 繁體中文與英文權威版（結構與簡體版逐節對應）。"""
from __future__ import annotations

import collections
import json
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def load(loc: str) -> tuple[str, collections.OrderedDict]:
    path = os.path.join(ROOT, 'assets', 'i18n', loc, 'onboarding.json')
    with open(path, encoding='utf-8') as handle:
        return path, json.load(handle, object_pairs_hook=collections.OrderedDict)


ZH_HANT_BODY = """一、授權與權威文本
本應用以 Apache License 2.0 發布。授權條款全文見儲存庫根目錄的 LICENSE 檔案，它是唯一具有法律效力的授權文件。本聲明是說明性文本，用於告知實際做法，不構成許可，也不增減任何權利或義務。

二、本聲明的適用範圍
本聲明僅適用於本應用本體，不涵蓋使用者自備的加速通道；加速通道由第三方提供，適用其自身協議，需使用者自行閱讀並同意。未啟用任何加速通道時，本聲明即為本應用與使用者之間的完整約定。

三、不收集資料
本應用不收集、不儲存、不上傳任何個人資料，不含遙測、分析、廣告與使用者畫像元件，也不含第三方追蹤。僅申請與功能直接相關的系統權限，並在首次啟動時逐項說明用途。

四、資料留駐
快取、草稿、下載檔案與執行記錄全部存於使用者裝置，解除安裝即隨之清除。GitHub 存取權杖保存在作業系統的安全儲存中，介面與記錄一律遮蔽；登出即從本機刪除。本應用不營運接收使用者資料的伺服器。

五、網路請求
未啟用加速時，請求僅送往 GitHub 官方介面與資源網域。啟用加速後，部分下載請求改經該通道，其處理適用通道自身協議。有可用摘要時校驗內容摘要；無摘要時標註「未校驗」，不謊稱已驗證。

六、可選的 Web 版本
Web 版本預設關閉，不在本聲明範圍內。瀏覽器環境涉及瀏覽器、託管方與網路中間環節，可能記錄存取時間、IP 位址與 User-Agent；本應用無法替其作出不收集資料的保證。僅在使用者主動啟用該功能時，本節例外方適用。

七、帳號與權杖
使用者自行提供 GitHub 權杖，並自行管理其權限範圍。權杖在裝置上被竊取的風險由使用者承擔；發現外洩應立即在 GitHub 撤銷權杖並登出。本應用不代替使用者作出任何授權決定。

八、第三方元件
本應用包含第三方開源元件，各元件適用其自身許可，清單見「關於」頁與 NOTICE 檔案。本應用以 Apache-2.0 發布，與上述寬鬆許可相容。

九、智慧財產權
本應用軟體的著作權歸開發者所有；開源許可授予使用與修改的權利，不轉移著作權。第三方商標歸各自權利人所有。

十免責聲明
本應用按現狀提供，不提供任何明示或默示的擔保，包括適銷性、特定用途適用性與不侵權的擔保。開發者不對因使用或無法使用本應用造成的損失承擔責任，法律不允許免除的責任除外。

十一、第三方連結與內容
應用內出現的第三方連結與內容由其提供方負責，本應用不對其內容、準確性或可用性作任何保證。使用者在第三方服務中提交的個人資料，適用該服務自身的隱私權政策。

十二、不可抗力與責任限制
在法律允許的最大範圍內，因不可抗力、第三方服務故障或網路中斷造成的損失，開發者不承擔責任。本條不適用於法律禁止限制責任的事項。

十三、適用法律與爭議解決
本聲明適用開發者所在地的法律，但不排除消費者慣常居所地的強制性規定。爭議應先透過儲存庫 Issues 協商解決；協商不成的，提交開發者所在地有管轄權的法院處理。

十四、未成年人
本應用不面向 13 週歲以下兒童。因本應用不收集個人資料，若使用者認為開發者持有與兒童有關的資訊，請依第十三節的方式聯絡，核實後立即刪除。

十五、聲明的變更
實質性修改將隨版本發布，並在應用內重新徵求同意，同意版本號相應提升，不靜默生效。本聲明自首次啟動起適用，以應用內展示的最新文本為準。

十六、終止使用
使用者可隨時停止使用並解除安裝本應用，資料隨解除安裝清除。

十七、聯絡方式
本應用為開源專案，問題與請求請透過儲存庫 Issues 提交：
https://github.com/OGL-Teams/OhGithubLost/issues"""

ZH_HANT_HIGHLIGHTS = """重點速覽
· 本應用不收集任何個人資料，也不上傳任何資料。
· GitHub 權杖只保存在本機的安全儲存中，介面與記錄一律遮蔽。
· 所有資料只存放在你的裝置上，解除安裝即隨之清除。
· 未啟用加速時，網路請求僅送往 GitHub 官方網域。
· 程式碼與建置設定全部公開，歡迎自行審閱。
· 本應用以 Apache-2.0 發布，第三方元件各適用其自身許可。
· 授權條款全文見儲存庫根目錄的 LICENSE 檔案。"""

ZH_HANT_SIMPLE = """本應用是開源軟體，程式碼與建置設定全部公開，授權條款寫在儲存庫根目錄的 LICENSE 檔案中。它不收集任何個人資料，你的 GitHub 權杖只保存在你自己的裝置上。"""

EN_BODY = """1. Licence and authoritative text
This application is released under the Apache License 2.0. The full terms are in the LICENSE file at the repository root; that file is the only legally binding grant. This notice is explanatory: it states what the application actually does, and grants no rights or imposes no obligations.

2. Scope
This notice covers the application only. Acceleration channels are provided by the user, are governed by their own terms, and must be read and accepted separately. With no acceleration channel enabled, this notice is the complete agreement between the application and the user.

3. No data collection
The application collects, stores and uploads no personal data. It contains no telemetry, analytics, advertising or profiling components, and no third-party tracking. It requests only the system permissions its features require, and explains each of them at first launch.

4. Data location
Cache, drafts, downloads and logs are stored on the device and removed when the application is uninstalled. The GitHub token is kept in the operating system's secure storage, is masked everywhere in the interface and logs, and is deleted from the device on sign-out. The application runs no server that receives user data.

5. Network requests
Without acceleration, requests go only to GitHub's official API and asset domains. With acceleration enabled, some download requests are routed through that channel and are handled under its terms. Content digests are verified when a digest is available; when none is available the item is marked unverified rather than reported as verified.

6. Optional web version
The web version is disabled by default and is outside the scope of this notice. Browser environments involve the browser, the hosting provider and network intermediaries, which may record timestamps, IP addresses and user agents; the application cannot guarantee that they collect nothing. The exception in this section applies only when the user enables the web version deliberately.

7. Accounts and tokens
The user supplies their own GitHub token and manages its permissions. The risk of that token being compromised on the device rests with the user; a leak should be revoked on GitHub immediately, followed by signing out. The application makes no authorisation decisions on the user's behalf.

8. Third-party components
The application includes third-party open-source components, each under its own licence; the list is on the About page and in the NOTICE file. The application is released under Apache-2.0, which is compatible with the permissive licences listed there.

9. Intellectual property
Copyright in the application's software remains with its developers. The open-source licence grants the right to use and modify it; it does not transfer copyright. Third-party trademarks belong to their respective owners.

10. Disclaimer
The application is provided as is, without warranty of any kind, express or implied, including merchantability, fitness for a particular purpose and non-infringement. The developers are not liable for loss arising from use of, or inability to use, the application, except where liability cannot be excluded by law.

11. Third-party links and content
Third-party links and content shown in the application are the responsibility of their providers. The application makes no warranty as to their content, accuracy or availability. Personal information submitted to third-party services is governed by those services' own privacy policies.

12. Force majeure and limitation of liability
To the fullest extent permitted by law, the developers are not liable for loss caused by force majeure, third-party service failure or network interruption. Nothing in this section limits liability where limitation is prohibited by law.

13. Governing law and disputes
This notice is governed by the law of the developers' location, without prejudice to mandatory consumer protections in the user's place of residence. Disputes should first be raised through the repository's issue tracker; if they cannot be settled there, they are submitted to the courts with jurisdiction at the developers' location.

14. Minors
The application is not directed at children under 13. Because it collects no personal information, if a user believes the developers hold any information relating to a child, contact through the channel in section 13; it will be verified and deleted immediately.

15. Changes
Material changes are published with a release and re-consented to in the application, with the consent version incremented; they never take effect silently. This notice applies from first launch, and the latest text shown in the application prevails.

16. Termination
The user may stop using and uninstall the application at any time; data is removed with it.

17. Contact
This is an open-source project. Please report issues and requests through the repository:
https://github.com/OGL-Teams/OhGithubLost/issues"""

EN_HIGHLIGHTS = """At a glance
· The application collects no personal data and uploads none.
· Your GitHub token stays in the device's secure storage, masked in the interface and logs.
· All data lives on your device and is removed when you uninstall.
· Without acceleration, network requests go only to GitHub's official domains.
· The source and build configuration are public; review them yourself.
· The application is released under Apache-2.0; third-party components keep their own licences.
· The full terms are in the LICENSE file at the repository root."""

EN_SIMPLE = """This is open-source software: the source and build configuration are public, and the terms are in the LICENSE file at the repository root. It collects no personal data, and your GitHub token stays on your own device."""


def main() -> None:
    path, data = load('zh_Hant')
    data['onboardingLicenseBody'] = ZH_HANT_BODY
    data['licenseBody'] = ZH_HANT_BODY
    data['onboardingLicenseHighlights'] = ZH_HANT_HIGHLIGHTS
    data['licenseHighlights'] = ZH_HANT_HIGHLIGHTS
    data['licenseSimple'] = ZH_HANT_SIMPLE
    with open(path, 'w', encoding='utf-8') as handle:
        handle.write(json.dumps(data, ensure_ascii=False, indent=2) + '\n')
    print('zh_Hant 已更新')

    path, data = load('en')
    data['onboardingLicenseBody'] = EN_BODY
    data['licenseBody'] = EN_BODY
    data['onboardingLicenseHighlights'] = EN_HIGHLIGHTS
    data['licenseHighlights'] = EN_HIGHLIGHTS
    data['licenseSimple'] = EN_SIMPLE
    with open(path, 'w', encoding='utf-8') as handle:
        handle.write(json.dumps(data, ensure_ascii=False, indent=2) + '\n')
    print('en 已更新')


if __name__ == '__main__':
    main()
