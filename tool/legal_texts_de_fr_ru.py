#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""法律与声明文本 · 德语 / 法语 / 俄语版本（结构与中文逐节对应）。"""
from __future__ import annotations

import collections
import json
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def load(loc: str):
    path = os.path.join(ROOT, 'assets', 'i18n', loc, 'onboarding.json')
    with open(path, encoding='utf-8') as handle:
        return path, json.load(handle, object_pairs_hook=collections.OrderedDict)


DE_BODY = """1. Lizenz und maßgeblicher Text
Diese Anwendung wird unter der Apache License 2.0 veröffentlicht. Der vollständige Wortlaut steht in der LICENSE-Datei im Stammverzeichnis des Repositorys; nur diese Datei ist rechtsverbindlich. Diese Erklärung ist eine reine Information: Sie beschreibt das tatsächliche Verhalten und gewährt keine Rechte und begründet keine Pflichten.

2. Geltungsbereich
Diese Erklärung gilt für die Anwendung selbst. Beschleunigungskanäle stellt der Nutzer selbst bereit; sie unterliegen ihren eigenen Bedingungen und sind gesondert zu lesen und zu akzeptieren. Solange kein Beschleunigungskanal aktiviert ist, gilt diese Erklärung als vollständige Vereinbarung zwischen Anwendung und Nutzer.

3. Keine Datenerhebung
Die Anwendung erhebt, speichert und überträgt keine personenbezogenen Daten. Sie enthält keine Telemetrie-, Analyse-, Werbe- oder Profilbildungsbestandteile und kein Tracking Dritter. Sie fordert ausschließlich die für ihre Funktionen erforderlichen Systemberechtigungen an und erläutert jede davon beim ersten Start.

4. Speicherort der Daten
Zwischenspeicher, Entwürfe, heruntergeladene Dateien und Protokolle liegen auf dem Gerät und werden beim Deinstallieren entfernt. Das GitHub-Token liegt im sicheren Speicher des Betriebssystems, wird in Oberfläche und Protokollen durchgehend maskiert und beim Abmelden vom Gerät gelöscht. Die Anwendung betreibt keinen Server, der Nutzerdaten empfängt.

5. Netzwerkanfragen
Ohne Beschleunigung gehen Anfragen ausschließlich an die offiziellen GitHub-Schnittstellen und Asset-Domains. Mit aktivierter Beschleunigung laufen manche Download-Anfragen über den jeweiligen Kanal und werden nach dessen Bedingungen behandelt. Inhalts-Prüfsummen werden geprüft, sofern eine verfügbar ist; andernfalls wird der Eintrag als ungeprüft gekennzeichnet, statt eine Prüfung zu behaupten.

6. Optionale Web-Version
Die Web-Version ist standardmäßig deaktiviert und nicht von dieser Erklärung erfasst. Browserumgebungen umfassen Browser, Hosting-Anbieter und Netzwerkvermittler, die Zeitstempel, IP-Adressen und User-Agents protokollieren können; die Anwendung kann dafür keine Datenerhebung zusagen. Die Ausnahme dieses Abschnitts greift nur, wenn der Nutzer die Web-Version bewusst aktiviert.

7. Konten und Tokens
Der Nutzer stellt sein GitHub-Token selbst bereit und verwaltet dessen Berechtigungen selbst. Das Risiko, dass das Token auf dem Gerät abhanden kommt, trägt der Nutzer; bei Verlust ist es sofort auf GitHub zu widerrufen und danach abzumelden. Die Anwendung trifft keine Autorisierungsentscheidungen für den Nutzer.

8. Komponenten Dritter
Die Anwendung enthält Open-Source-Komponenten Dritter, die jeweils unter ihrer eigenen Lizenz stehen; die Liste findet sich auf der Seite „Über“ und in der Datei NOTICE. Die Anwendung wird unter Apache-2.0 veröffentlicht und ist mit den dort genannten permissiven Lizenzen vereinbar.

9. Geistiges Eigentum
Das Urheberrecht am Anwendungscode verbleibt bei den Entwicklern. Die Open-Source-Lizenz gewährt das Recht zur Nutzung und Änderung, überträgt das Urheberrecht aber nicht. Marken Dritter bleiben bei ihren jeweiligen Inhabern.

10. Haftungsausschluss
Die Anwendung wird ohne jede ausdrückliche oder stillschweigende Gewährleistung bereitgestellt, einschließlich der Gewährleistung der Eignung für den Handel, für einen bestimmten Zweck und der Nichtverletzung von Rechten Dritter. Die Entwickler haften nicht für Schäden aus der Nutzung oder der Nichtnutzbarkeit, soweit die Haftung gesetzlich nicht ausgeschlossen werden darf.

11. Links und Inhalte Dritter
Für Links und Inhalte Dritter, die in der Anwendung erscheinen, sind deren Anbieter verantwortlich; für Inhalt, Richtigkeit oder Verfügbarkeit wird keine Gewähr übernommen. Für personenbezogene Daten, die bei Dritten eingereicht werden, gelten deren eigene Datenschutzhinweise.

12. Höhere Gewalt und Haftungsbeschränkung
Soweit gesetzlich zulässig, haften die Entwickler nicht für Schäden aus höherer Gewalt, dem Ausfall Dritter oder Netzausfällen. Diese Regelung gilt nicht, soweit eine Haftungsbeschränkung gesetzlich ausgeschlossen ist.

13. Anwendbares Recht und Streitbeilegung
Diese Erklärung unterliegt dem Recht des Sitzes der Entwickler, ohne dass zwingende Verbraucherschutzvorschriften am Wohnsitz des Nutzers unberührt bleiben. Streitigkeiten sind zuerst über das Issue-Tracker des Repositorys zu klären; gelingt dies nicht, entscheidet das Gericht am Sitz der Entwickler.

14. Minderjährige
Die Anwendung richtet sich nicht an Kinder unter 13 Jahren. Da sie keine personenbezogenen Daten erhebt, wenden Sie sich bitte nach Abschnitt 13, falls Sie annehmen, dass Informationen zu einem Kind vorliegen; nach Prüfung werden sie unverzüglich gelöscht.

15. Änderungen
Materielle Änderungen werden mit einer Version veröffentlicht und in der Anwendung erneut zur Zustimmung gestellt, wobei die Zustimmungsversion entsprechend erhöht wird; sie treten nie stillschweigend in Kraft. Diese Erklärung gilt ab dem ersten Start; maßgeblich ist der in der Anwendung gezeigte aktuelle Text.

16. Beendigung
Der Nutzer kann die Anwendung jederzeit beenden und deinstallieren; die Daten werden damit entfernt.

17. Kontakt
Dies ist ein Open-Source-Projekt. Fragen und Anregungen bitte über das Repository:
https://github.com/OGL-Teams/OhGithubLost/issues"""

FR_BODY = """1. Licence et texte faisant foi
Cette application est publiée sous licence Apache 2.0. Le texte intégral figure dans le fichier LICENSE à la racine du dépôt ; ce seul document fait foi. Le présent avis est purement informatif : il décrit le comportement réel de l'application, n'accorde aucun droit et n'impose aucune obligation.

2. Champ d'application
Le présent avis ne concerne que l'application elle-même. Les canaux d'accélération sont fournis par l'utilisateur, relèvent de leurs propres conditions et doivent être lus et acceptés séparément. Tant qu'aucun canal d'accélération n'est activé, le présent avis constitue l'accord complet entre l'application et l'utilisateur.

3. Aucune collecte de données
L'application ne collecte, ne stocke et ne transmet aucune donnée personnelle. Elle ne contient ni télémétrie, ni analyse, ni publicité, ni profilage, ni traçage par des tiers. Elle ne demande que les autorisations système strictement requises par ses fonctions, et explique chacune d'elles au premier lancement.

4. Localisation des données
Cache, brouillons, fichiers téléchargés et journaux résident sur l'appareil et sont supprimés à la désinstallation. Le jeton GitHub est conservé dans le stockage sécurisé du système d'exploitation, masqué dans l'interface et les journaux, et effacé de l'appareil à la déconnexion. L'application n'exploite aucun serveur recevant des données utilisateur.

5. Requêtes réseau
Sans accélération, les requêtes vont uniquement vers les API et domaines de ressources officiels de GitHub. Avec accélération, certaines requêtes de téléchargement passent par le canal concerné et sont traitées selon ses conditions. Les empreintes de contenu sont vérifiées lorsqu'elles existent ; à défaut, l'élément est signalé comme non vérifié plutôt que présenté comme vérifié.

6. Version web facultative
La version web est désactivée par défaut et n'entre pas dans le champ du présent avis. Un environnement navigateur implique le navigateur, l'hébergeur et les intermédiaires réseau, qui peuvent enregistrer horodatages, adresses IP et agents utilisateur ; l'application ne peut garantir qu'ils ne collectent rien. L'exception du présent paragraphe ne s'applique que si l'utilisateur active délibérément la version web.

7. Comptes et jetons
L'utilisateur fournit son propre jeton GitHub et gère lui-même ses droits. Le risque d'une compromission du jeton sur l'appareil pèse sur l'utilisateur ; en cas de fuite, il doit le révoquer immédiatement sur GitHub puis se déconnecter. L'application ne prend aucune décision d'autorisation à sa place.

8. Composants tiers
L'application inclut des composants open source tiers, chacun sous sa propre licence ; la liste figure sur la page « À propos » et dans le fichier NOTICE. L'application est publiée sous Apache-2.0, compatible avec les licences permissives qui y sont listées.

9. Propriété intellectuelle
Les droits d'auteur sur le logiciel appartiennent aux développeurs. La licence open source accorde le droit d'utiliser et de modifier le logiciel, sans transférer la titularité des droits d'auteur. Les marques de tiers restent la propriété de leurs titulaires.

10. Exclusion de garantie
L'application est fournie en l'état, sans garantie d'aucune sorte, expresse ou implicite, y compris de commercialisabilité, d'aptitude à un usage particulier et de non-atteinte de droits. Les développeurs ne sont pas responsables des pertes résultant de l'utilisation ou de l'impossibilité d'utiliser l'application, sauf obligation d'exclusion que la loi interdirait.

11. Liens et contenus tiers
Les liens et contenus tiers présentés dans l'application relèvent de leurs fournisseurs ; aucune garantie n'est donnée quant à leur contenu, exactitude ou disponibilité. Les informations personnelles transmises à des services tiers relèvent de leur propre politique de confidentialité.

12. Force majeure et limitation de responsabilité
Dans toute la mesure permise par la loi, les développeurs ne sont pas responsables des pertes dues à la force majeure, à la défaillance de services tiers ou à des interruptions réseau. La présente limitation ne s'applique pas aux cas où la loi interdit toute limitation.

13. Droit applicable et litiges
Le présent avis est régi par le droit du siège des développeurs, sans préjudice des protections impératives du lieu de résidence du consommateur. Les différends doivent d'abord être exposés via le suivi des tickets du dépôt ; à défaut d'accord, ils sont portés devant les tribunaux compétents du siège des développeurs.

14. Mineurs
L'application ne s'adresse pas aux enfants de moins de 13 ans. Comme elle ne collecte aucune donnée personnelle, si l'utilisateur estime que des informations relatives à un enfant sont détenues, qu'il contacte les développeurs par le canal du paragraphe 13 ; après vérification, elles seront supprimées sans délai.

15. Modification
Les modifications substantielles sont publiées avec une version et soumises à nouveau consentement dans l'application, la version de consentement étant incrémentée en conséquence ; elles n'entrent jamais en vigueur silencieusement. Le présent avis s'applique dès le premier lancement ; le texte affiché dans l'application fait foi.

16. Cessation
L'utilisateur peut arrêter d'utiliser l'application et la désinstaller à tout moment ; les données sont supprimées avec elle.

17. Contact
Il s'agit d'un projet open source. Questions et demandes via le dépôt :
https://github.com/OGL-Teams/OhGithubLost/issues"""

RU_BODY = """1. Лицензия и юридически значимый текст
Приложение распространяется по лицензии Apache License 2.0. Полный текст находится в файле LICENSE в корне репозитория; именно он имеет юридическую силу. Настоящее уведомление носит информационный характер: оно описывает фактическое поведение приложения, не предоставляет прав и не устанавливает обязанностей.

2. Сфера применения
Настоящее уведомление относится только к самому приложению. Каналы ускорения предоставляются пользователем, регулируются их собственными условиями и должны быть прочитаны и приняты отдельно. Пока ни один канал ускорения не включён, настоящее уведомление является полным соглашением между приложением и пользователем.

3. Данные не собираются
Приложение не собирает, не хранит и не передаёт никаких персональных данных. В нём нет телеметрии, аналитики, рекламы, профилирования и стороннего отслеживания. Приложение запрашивает только те системные разрешения, которые необходимы его функциям, и объясняет каждое из них при первом запуске.

4. Место хранения данных
Кэш, черновики, загруженные файлы и журналы находятся на устройстве и удаляются при деинсталляции. Токен GitHub хранится в защищённом хранилище операционной системы, маскируется в интерфейсе и журналах и удаляется с устройства при выходе из учётной записи. Приложение не эксплуатирует сервер, принимающий пользовательские данные.

5. Сетевые запросы
Без ускорения запросы направляются только к официальным интерфейсам и доменам ресурсов GitHub. При включённом ускорении часть запросов загрузки проходит через соответствующий канал и обрабатывается по его условиям. Контрольные суммы содержимого проверяются, когда они доступны; если суммы нет, элемент помечается как непроверенный, а не как проверенный.

6. Необязательная веб-версия
Веб-версия по умолчанию отключена и не охватывается настоящим уведомлением. Браузерная среда включает браузер, хостинг-провайдера и сетевых посредников, которые могут фиксировать время обращения, IP-адреса и User-Agent; приложение не может гарантировать, что они ничего не собирают. Исключение этого пункта действует только при осознанном включении пользователем веб-версии.

7. Учётные записи и токены
Пользователь сам предоставляет токен GitHub и сам управляет его правами. Риск компрометации токена на устройстве несёт пользователь; при утечке его следует немедленно отозвать на GitHub и выйти из учётной записи. Приложение не принимает решений о разрешениях за пользователя.

8. Сторонние компоненты
Приложение включает сторонние компоненты с открытым исходным кодом, каждый под своей лицензией; перечень приведён на странице «О программе» и в файле NOTICE. Приложение распространяется по Apache-2.0, что совместимо с перечисленными там свободными лицензиями.

9. Интеллектуальная собственность
Авторские права на программное обеспечение приложения принадлежат его разработчикам. Лицензия с открытым исходным кодом предоставляет право на использование и изменение, но не переносит авторские права. Товарные знаки третьих лиц остаются за их правообладателями.

10. Отказ от гарантий
Приложение предоставляется «как есть», без какой-либо прямой или подразумеваемой гарантии, включая гарантии товарной пригодности, пригодности для определённой цели и ненарушения прав. Разработчики не отвечают за убытки, возникшие вследствие использования или невозможности использования приложения, кроме случаев, когда ответственность не может быть исключена по закону.

11. Сторонние ссылки и содержимое
За сторонние ссылки и содержимое, показываемые в приложении, отвечают их поставщики; приложение не даёт никаких гарантий относительно их содержания, достоверности или доступности. К персональным данным, переданным сторонним сервисам, применяется их собственная политика конфиденциальности.

12. Форс-мажор и ограничение ответственности

В той мере, в какой это допускается законом, разработчики не отвечают за убытки вследствие форс-мажорных обстоятельств, отказа сторонних сервисов или перебоев в сети. Данное ограничение не применяется к случаям, когда ограничение ответственности запрещено законом.

13. Применимое право и разрешение споров
К настоящему уведомлению применяется право по месту нахождения разработчиков, без ущерба обязательным нормам защиты прав потребителей по месту жительства пользователя. Споры следует сначала урегулировать через систему задач репозитория; если это не удастся, они передаются в суды по месту нахождения разработчиков.

14. Несовершеннолетние
Приложение не предназначено для детей младше 13 лет. Поскольку оно не собирает персональных данных, если пользователь полагает, что разработчики располагают сведениями о ребёнке, следует обратиться способом, указанным в пункте 13; после проверки сведения будут немедленно удалены.

15. Изменения
Существенные изменения публикуются вместе с выпуском и повторно выносятся на согласие в приложении, при этом номер версии согласия повышается; они никогда не вступают в силу молча. Настоящее уведомление действует с момента первого запуска; приоритет имеет текст, показанный в приложении.

16. Прекращение использования
Пользователь в любой момент может прекратить использование и удалить приложение; вместе с ним удаляются и данные.

17. Контакты
Это проект с открытым исходным кодом. Вопросы и обращения — через репозиторий:
https://github.com/OGL-Teams/OhGithubLost/issues"""


def main() -> None:
    versions = {
        'de': (DE_BODY, None),
        'fr': (FR_BODY, None),
        'ru': (RU_BODY, None),
    }
    for loc, (body, _unused) in versions.items():
        path, data = load(loc)
        data['onboardingLicenseBody'] = body
        data['licenseBody'] = body
        with open(path, 'w', encoding='utf-8') as handle:
            handle.write(json.dumps(data, ensure_ascii=False, indent=2) + '\n')
        print('%s 正文已更新' % loc)


if __name__ == '__main__':
    main()
