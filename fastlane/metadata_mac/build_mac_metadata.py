#!/usr/bin/env python3
"""Writes fastlane/metadata_mac/<locale>/{description,promotional_text}.txt for the Mac 1.0 version
and validates App Store limits. Copy only claims what the Mac build has (see .claude/mac-parity-audit.md):
no Sentinel, no widgets, no voice notes, no encryption or cross-device sync claims (unverified on a signed Mac build)."""
import os, sys

HERE = os.path.dirname(os.path.abspath(__file__))
TERMS = "https://mirrornotes.org/terms.html"

L = {}

L["en-GB"] = dict(
promo="Your private journal, now on Mac. Write with the keyboard, capture from the menu bar, and reflect with AI that runs on your Mac. Free to write and read.",
desc=f"""MirrorNotes is a private journal for your Mac. Write, reflect, and see your patterns over time, in a calm window that stays out of your way.

Write in a rich-text editor with photos, mood labels, and the menus and keyboard shortcuts you expect on a Mac. Press ⌘N for a new entry, or open quick capture from the menu bar to jot something down without switching apps. Browse your history as a list or a calendar, with the entry open beside it, and search everything you have written.

MirrorNotes also helps you reflect with private, on-device AI: daily reflections, weekly digests, mood timelines, monthly reports, and Brain View, a constellation of the themes that keep coming back. The AI runs on your Mac, so your journal text is not sent to a server.

Features:
  • Rich-text writing with photos, mood labels, Mac menus and shortcuts
  • Quick capture from the menu bar
  • Browse entries as a list or a calendar, with search
  • Daily reflections and weekly digests
  • Mood timeline and monthly reports
  • Brain View: explore recurring themes in 3D
  • Ask questions about your journal patterns
  • Private sync with iCloud
  • Reading preferences in a native Settings window

Writing and reading your journal is free, forever. Core and Deep add the AI layer.

MirrorNotes is built for people who want a calm, private place to think without an audience.
{TERMS}""")

L["de-DE"] = dict(
promo="Dein privates Tagebuch, jetzt für den Mac. Schreibe mit der Tastatur, erfasse per Menüleiste und reflektiere mit KI auf deinem Mac. Schreiben und Lesen: kostenlos.",
desc=f"""MirrorNotes ist ein privates Tagebuch für deinen Mac. Schreibe, reflektiere und erkenne deine Muster im Laufe der Zeit, in einem ruhigen Fenster, das dir nicht im Weg ist.

Schreibe in einem Rich-Text-Editor mit Fotos, Stimmungs-Labels sowie den Menüs und Tastaturkürzeln, die du vom Mac kennst. Mit ⌘N beginnst du einen neuen Eintrag, oder du öffnest die Schnellerfassung in der Menüleiste und notierst etwas, ohne die App zu wechseln. Durchstöbere deinen Verlauf als Liste oder Kalender, mit dem geöffneten Eintrag daneben, und durchsuche alles, was du geschrieben hast.

MirrorNotes hilft dir außerdem beim Reflektieren mit privater KI auf dem Gerät: tägliche Reflexionen, Wochenrückblicke, Stimmungsverläufe, Monatsberichte und die Denkkarte, eine Konstellation der Themen, die immer wiederkehren. Die KI läuft auf deinem Mac, deine Journal-Texte werden also nicht an einen Server gesendet.

Funktionen:
  • Rich-Text-Schreiben mit Fotos, Stimmungs-Labels, Mac-Menüs und Tastaturkürzeln
  • Schnellerfassung aus der Menüleiste
  • Einträge als Liste oder Kalender durchstöbern, mit Suche
  • Tägliche Reflexionen und Wochenrückblicke
  • Stimmungsverlauf und Monatsberichte
  • Denkkarte: wiederkehrende Themen in 3D erkunden
  • Fragen zu deinen Journal-Mustern stellen
  • Private Synchronisierung mit iCloud
  • Leseeinstellungen in einem nativen Einstellungsfenster

Schreiben und Lesen deines Tagebuchs ist für immer kostenlos. Core und Deep fügen die KI-Ebene hinzu.

MirrorNotes ist für Menschen gemacht, die einen ruhigen, privaten Ort zum Nachdenken suchen – ganz ohne Publikum.
{TERMS}""")

L["fr-FR"] = dict(
promo="Votre journal intime, désormais sur Mac. Écrivez au clavier, notez depuis la barre des menus et réfléchissez avec une IA sur votre Mac. Écrire et lire : gratuit.",
desc=f"""MirrorNotes est un journal intime privé pour votre Mac. Écrivez, réfléchissez et observez vos habitudes au fil du temps, dans une fenêtre calme qui ne vous gêne pas.

Écrivez dans un éditeur de texte enrichi avec des photos, des étiquettes d'humeur, ainsi que les menus et raccourcis clavier que vous connaissez sur Mac. Appuyez sur ⌘N pour une nouvelle entrée, ou ouvrez la saisie rapide depuis la barre des menus pour noter une idée sans changer d'app. Parcourez votre historique en liste ou en calendrier, avec l'entrée ouverte à côté, et recherchez tout ce que vous avez écrit.

MirrorNotes vous aide aussi à réfléchir grâce à une IA privée, exécutée sur l'appareil : réflexions quotidiennes, résumés hebdomadaires, chronologies de l'humeur, rapports mensuels et la Carte mentale, une constellation des thèmes qui reviennent sans cesse. L'IA tourne sur votre Mac : le texte de votre journal n'est envoyé à aucun serveur.

Fonctionnalités :
  • Écriture en texte enrichi avec photos, étiquettes d'humeur, menus et raccourcis Mac
  • Saisie rapide depuis la barre des menus
  • Entrées en liste ou en calendrier, avec recherche
  • Réflexions quotidiennes et résumés hebdomadaires
  • Chronologie de l'humeur et rapports mensuels
  • Carte mentale : explorez les thèmes récurrents en 3D
  • Posez des questions sur les tendances de votre journal
  • Synchronisation privée avec iCloud
  • Préférences de lecture dans une fenêtre Réglages native

Écrire et relire votre journal est gratuit, pour toujours. Core et Deep ajoutent la couche IA.

MirrorNotes est conçu pour celles et ceux qui veulent un endroit calme et privé pour réfléchir, sans public.
{TERMS}""")

L["es-ES"] = dict(
promo="Tu diario privado, ahora en el Mac. Escribe con el teclado, anota desde la barra de menús y reflexiona con una IA que se ejecuta en tu Mac. Escribir y leer es gratis.",
desc=f"""MirrorNotes es un diario privado para tu Mac. Escribe, reflexiona y descubre tus patrones con el tiempo, en una ventana tranquila que no se interpone.

Escribe en un editor de texto enriquecido con fotos, etiquetas de ánimo y los menús y atajos de teclado que esperas en un Mac. Pulsa ⌘N para una nueva entrada, o abre la captura rápida desde la barra de menús para apuntar algo sin cambiar de app. Explora tu historial como lista o calendario, con la entrada abierta al lado, y busca todo lo que has escrito.

MirrorNotes también te ayuda a reflexionar con IA privada en el dispositivo: reflexiones diarias, resúmenes semanales, cronologías del estado de ánimo, informes mensuales y el Mapa mental, una constelación de los temas que vuelven una y otra vez. La IA se ejecuta en tu Mac, así que el texto de tu diario no se envía a ningún servidor.

Funciones:
  • Escritura en texto enriquecido con fotos, etiquetas de ánimo, menús y atajos de Mac
  • Captura rápida desde la barra de menús
  • Entradas en lista o calendario, con búsqueda
  • Reflexiones diarias y resúmenes semanales
  • Cronología del estado de ánimo e informes mensuales
  • Mapa mental: explora los temas recurrentes en 3D
  • Haz preguntas sobre los patrones de tu diario
  • Sincronización privada con iCloud
  • Preferencias de lectura en una ventana de Ajustes nativa

Escribir y leer tu diario es gratis, para siempre. Core y Deep añaden la capa de IA.

MirrorNotes está hecho para quienes quieren un lugar tranquilo y privado para pensar, sin público.
{TERMS}""")

L["it"] = dict(
promo="Il tuo diario privato, ora su Mac. Scrivi con la tastiera, annota dalla barra dei menu e rifletti con un'IA che gira sul tuo Mac. Scrivere e leggere è gratis.",
desc=f"""MirrorNotes è un diario privato per il tuo Mac. Scrivi, rifletti e scopri i tuoi schemi nel tempo, in una finestra tranquilla che non ti intralcia.

Scrivi in un editor di testo formattato con foto, etichette dell'umore e i menu e le scorciatoie da tastiera che ti aspetti su Mac. Premi ⌘N per una nuova voce, oppure apri l'acquisizione rapida dalla barra dei menu per annotare qualcosa senza cambiare app. Sfoglia la cronologia come elenco o calendario, con la voce aperta accanto, e cerca tutto ciò che hai scritto.

MirrorNotes ti aiuta anche a riflettere con un'IA privata sul dispositivo: riflessioni quotidiane, riepiloghi settimanali, cronologia dell'umore, report mensili e la Mappa mentale, una costellazione dei temi che tornano di continuo. L'IA gira sul tuo Mac, quindi il testo del tuo diario non viene inviato a nessun server.

Funzionalità:
  • Scrittura con testo formattato, foto, etichette dell'umore, menu e scorciatoie Mac
  • Acquisizione rapida dalla barra dei menu
  • Voci come elenco o calendario, con ricerca
  • Riflessioni quotidiane e riepiloghi settimanali
  • Cronologia dell'umore e report mensili
  • Mappa mentale: esplora i temi ricorrenti in 3D
  • Fai domande sugli schemi del tuo diario
  • Sincronizzazione privata con iCloud
  • Preferenze di lettura in una finestra Impostazioni nativa

Scrivere e leggere il tuo diario è gratis, per sempre. Core e Deep aggiungono il livello IA.

MirrorNotes è pensato per chi vuole un posto tranquillo e privato in cui pensare, senza pubblico.
{TERMS}""")

L["pt-BR"] = dict(
promo="Seu diário privado, agora no Mac. Escreva com o teclado, anote pela barra de menus e reflita com uma IA que roda no seu Mac. Escrever e ler é grátis.",
desc=f"""O MirrorNotes é um diário privado para o seu Mac. Escreva, reflita e perceba seus padrões ao longo do tempo, em uma janela tranquila que não atrapalha.

Escreva em um editor de texto formatado com fotos, rótulos de humor e os menus e atalhos de teclado que você espera em um Mac. Pressione ⌘N para uma nova entrada ou abra a captura rápida pela barra de menus para anotar algo sem trocar de app. Navegue pelo histórico em lista ou calendário, com a entrada aberta ao lado, e pesquise tudo o que você escreveu.

O MirrorNotes também ajuda você a refletir com IA privada no dispositivo: reflexões diárias, resumos semanais, linhas do tempo de humor, relatórios mensais e o Mapa mental, uma constelação dos temas que sempre voltam. A IA roda no seu Mac, então o texto do seu diário não é enviado a nenhum servidor.

Recursos:
  • Escrita com texto formatado, fotos, rótulos de humor, menus e atalhos do Mac
  • Captura rápida pela barra de menus
  • Entradas em lista ou calendário, com busca
  • Reflexões diárias e resumos semanais
  • Linha do tempo de humor e relatórios mensais
  • Mapa mental: explore temas recorrentes em 3D
  • Faça perguntas sobre os padrões do seu diário
  • Sincronização privada com o iCloud
  • Preferências de leitura em uma janela de Ajustes nativa

Escrever e ler o seu diário é grátis, para sempre. Core e Deep adicionam a camada de IA.

O MirrorNotes foi feito para quem quer um lugar calmo e privado para pensar, sem plateia.
{TERMS}""")

L["ru"] = dict(
promo="Ваш личный дневник теперь на Mac. Пишите с клавиатуры, записывайте из строки меню и размышляйте с ИИ, который работает на вашем Mac. Писать и читать бесплатно.",
desc=f"""MirrorNotes — личный дневник для вашего Mac. Пишите, размышляйте и замечайте свои закономерности со временем в спокойном окне, которое не мешает.

Пишите в редакторе форматированного текста с фото, метками настроения, а также меню и сочетаниями клавиш, привычными на Mac. Нажмите ⌘N для новой записи или откройте быстрый ввод из строки меню, чтобы записать мысль, не переключая приложение. Просматривайте историю списком или календарём, с открытой записью рядом, и ищите по всему, что вы написали.

MirrorNotes также помогает размышлять с помощью приватного ИИ на устройстве: ежедневные рефлексии, еженедельные сводки, хронология настроения, ежемесячные отчёты и «Карта мыслей» — созвездие тем, которые постоянно возвращаются. ИИ работает на вашем Mac, поэтому текст дневника не отправляется на сервер.

Возможности:
  • Форматированный текст, фото, метки настроения, меню и сочетания клавиш Mac
  • Быстрый ввод из строки меню
  • Записи списком или календарём, с поиском
  • Ежедневные рефлексии и еженедельные сводки
  • Хронология настроения и ежемесячные отчёты
  • Карта мыслей: повторяющиеся темы в 3D
  • Вопросы о закономерностях вашего дневника
  • Приватная синхронизация через iCloud
  • Настройки чтения в стандартном окне настроек

Писать и читать дневник бесплатно, навсегда. Core и Deep добавляют слой ИИ.

MirrorNotes создан для тех, кому нужно спокойное личное место для размышлений, без зрителей.
{TERMS}""")

L["ja"] = dict(
promo="あなたのプライベートな日記が、Macに。キーボードで書き、メニューバーからすばやく記録し、Mac上で動くAIで振り返れます。書く・読むは無料です。",
desc=f"""MirrorNotesは、Mac用のプライベートな日記アプリです。静かで邪魔にならないウインドウで、書き、振り返り、時間とともに現れるパターンに気づけます。

写真、気分ラベル、Macならではのメニューとキーボードショートカットに対応したリッチテキストエディタで書けます。⌘Nで新しいエントリを作成するか、メニューバーのクイックキャプチャでアプリを切り替えずにすぐ書き留められます。履歴はリストまたはカレンダーで閲覧でき、隣にエントリを開いたまま、書いたものすべてを検索できます。

プライベートなオンデバイスAIによる振り返りもできます。毎日のリフレクション、週間ダイジェスト、ムードタイムライン、月次レポート、そして繰り返し現れるテーマを星座のように表示するマインドマップ。AIはMac上で動作するため、日記のテキストがサーバーに送信されることはありません。

機能:
  • 写真、気分ラベル、Macのメニューとショートカットに対応したリッチテキスト
  • メニューバーからのクイックキャプチャ
  • リストまたはカレンダーでエントリを閲覧、検索
  • 毎日のリフレクションと週間ダイジェスト
  • ムードタイムラインと月次レポート
  • マインドマップ：繰り返し現れるテーマを3Dで探索
  • 日記のパターンについて質問
  • iCloudによるプライベートな同期
  • Mac標準の設定ウインドウで読書設定を調整

日記を書く・読むのは、ずっと無料です。CoreとDeepでAI機能が加わります。

MirrorNotesは、誰にも見られない、静かでプライベートな考える場所を求める人のためのアプリです。
{TERMS}""")

L["ko"] = dict(
promo="나만의 비공개 일기, 이제 Mac에서. 키보드로 쓰고, 메뉴 막대에서 바로 기록하고, Mac에서 실행되는 AI로 돌아보세요. 쓰기와 읽기는 무료입니다.",
desc=f"""MirrorNotes는 Mac을 위한 비공개 일기 앱입니다. 방해되지 않는 차분한 창에서 글을 쓰고, 돌아보고, 시간에 따른 나만의 패턴을 발견하세요.

사진, 기분 라벨, 그리고 Mac에서 익숙한 메뉴와 키보드 단축키를 지원하는 서식 있는 텍스트 편집기로 작성할 수 있습니다. ⌘N으로 새 항목을 만들거나, 메뉴 막대의 빠른 기록으로 앱을 전환하지 않고 바로 메모하세요. 기록은 목록이나 캘린더로 살펴보고, 옆에 항목을 열어 둔 채 작성한 모든 글을 검색할 수 있습니다.

비공개 온디바이스 AI로 돌아보는 기능도 있습니다. 데일리 리플렉션, 주간 다이제스트, 기분 타임라인, 월간 리포트, 그리고 반복되는 주제를 별자리처럼 보여 주는 마인드맵. AI는 Mac에서 실행되므로 일기 텍스트가 서버로 전송되지 않습니다.

기능:
  • 사진, 기분 라벨, Mac 메뉴와 단축키를 지원하는 서식 있는 텍스트
  • 메뉴 막대에서 빠른 기록
  • 목록 또는 캘린더로 항목 보기, 검색
  • 데일리 리플렉션과 주간 다이제스트
  • 기분 타임라인과 월간 리포트
  • 마인드맵: 반복되는 주제를 3D로 탐색
  • 일기 패턴에 대해 질문하기
  • iCloud로 비공개 동기화
  • Mac 기본 설정 창에서 읽기 환경 조정

일기를 쓰고 읽는 것은 언제나 무료입니다. Core와 Deep이 AI 기능을 더합니다.

MirrorNotes는 아무도 지켜보지 않는, 조용하고 비공개적인 생각의 공간을 원하는 분들을 위해 만들었습니다.
{TERMS}""")

L["zh-Hans"] = dict(
promo="你的私密日记，现在登陆 Mac。用键盘书写，从菜单栏快速记录，并借助在 Mac 上运行的 AI 回顾。书写和阅读免费。",
desc=f"""MirrorNotes 是专为 Mac 打造的私密日记。在安静、不打扰你的窗口里书写、回顾，并看见自己随时间变化的规律。

使用富文本编辑器书写，支持照片、心情标签，以及你熟悉的 Mac 菜单和键盘快捷键。按 ⌘N 新建条目，或从菜单栏打开快速记录，无需切换应用就能随手记下想法。你可以用列表或日历浏览历史记录，旁边同时打开条目，并搜索你写过的所有内容。

MirrorNotes 还能通过私密的设备端 AI 帮你回顾：每日反思、每周摘要、情绪时间线、每月报告，以及思维导图——把反复出现的主题绘成一片星座。AI 在你的 Mac 上运行，因此你的日记文本不会发送到任何服务器。

功能：
  • 富文本书写，支持照片、心情标签、Mac 菜单和快捷键
  • 菜单栏快速记录
  • 以列表或日历浏览条目，并支持搜索
  • 每日反思和每周摘要
  • 情绪时间线和每月报告
  • 思维导图：以 3D 方式探索反复出现的主题
  • 针对日记规律提问
  • 通过 iCloud 私密同步
  • 在原生“设置”窗口中调整阅读偏好

书写和阅读日记永久免费。Core 和 Deep 则提供 AI 功能。

MirrorNotes 为想要一个安静、私密、无人旁观的思考空间的人而设计。
{TERMS}""")

LIMITS = dict(desc=4000, promo=170)
ok = True
for loc, d in L.items():
    for k, lim in LIMITS.items():
        n = len(d[k])
        flag = "" if n <= lim else "  <-- OVER"
        if n > lim: ok = False
        print(f"{loc:8} {k:5} {n:5}/{lim}{flag}")
    out = os.path.join(HERE, loc)
    os.makedirs(out, exist_ok=True)
    open(os.path.join(out, "description.txt"), "w", encoding="utf-8").write(d["desc"] + "\n")
    open(os.path.join(out, "promotional_text.txt"), "w", encoding="utf-8").write(d["promo"] + "\n")
sys.exit(0 if ok else 1)
