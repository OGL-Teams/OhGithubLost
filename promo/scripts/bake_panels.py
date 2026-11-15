#!/usr/bin/env python3
"""烘焙 Three.js 一镜到底用的中英文面板贴图（本地 Python/PIL，CI 无需重算）。

输出 promo/assets/panels/panel-00.png … panel-11.png
每个面板 1024×640，浅色 M3 surface，8px 圆角，左侧 4px 主色条，
右侧可放实机截图（由 Three.js 单独作为纹理贴在 3D 面板上，不烘焙进文字图）。

用法: python3 promo/scripts/bake_panels.py
"""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

OUT = Path(__file__).resolve().parent.parent / "assets" / "panels"
OUT.mkdir(parents=True, exist_ok=True)

W, H = 1024, 640
BG = "#F7F9FC"
SURFACE = "#FFFFFF"
OUTLINE = "#C7D0DC"
PRIMARY = "#0B57D0"
ON_SURFACE = "#1B1B1F"
ON_VARIANT = "#5F6368"
TERTIARY = "#B26A00"

FONT_CANDIDATES = [
    "/usr/share/fonts/noto/NotoSansCJK-Regular.ttc",
    "/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc",
    "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
    "/usr/share/fonts/opensans/OpenSans-Regular.ttf",
]
MONO_CANDIDATES = [
    "/var/minis/workspace/OhGithubLost/promo/assets/fonts/UbuntuMono-Regular.ttf",
    "/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf",
]


def pick(cands, size):
    for p in cands:
        if Path(p).exists():
            return ImageFont.truetype(p, size)
    return ImageFont.load_default()


F_KICK = pick(MONO_CANDIDATES, 28)
F_TITLE = pick(FONT_CANDIDATES, 62)
F_BODY = pick(FONT_CANDIDATES, 30)
F_MONO = pick(FONT_CANDIDATES, 26)  # 证据行含中文；Ubuntu Mono 无 CJK 字形，改用 Noto Sans CJK

PANELS = [
    dict(kicker="00 · OGL / v12.6.9",
         title="GitHub 工作流\n在本地完成",
         body="仓库、议题、Pull Request、Release、Actions、Gist\n单一客户端内的完整协作链路",
         mono="Android / Windows / Linux / Web · Apache-2.0"),
    dict(kicker="01 · REPOSITORY",
         title="仓库，直接读到文件",
         body="分支、目录、文件大小同屏\n点一行就能进文件，不用等网页重排",
         mono="org/repo · main · index.html 1.2 KB · README.md 22 B"),
    dict(kicker="02 · CODE",
         title="长文件，照样读",
         body="行号、语法高亮、横向不折行\n滚动位置留在原处，回来接着读",
         mono="HTML · 55 行 · 1243 字符 · UTF-8"),
    dict(kicker="03 · EDIT",
         title="改一行，存下来",
         body="保存、查找、字号、预览都在工具栏\n改动落盘前不会丢",
         mono="保存 → 写回仓库 / 字号 13 → 18 / 预览 Markdown"),
    dict(kicker="04 · ISSUE",
         title="评论，写在这里",
         body="Markdown 渲染、附件引用、@提醒\n提交后立刻出现在线程里",
         mono="#42281 · 37 条评论 · 支持 Markdown"),
    dict(kicker="05 · OBSERVABILITY",
         title="启动花了多少，写得清楚",
         body="分阶段耗时直接落盘\n失败、告警、模块数量都有据可查",
         mono="启动 7946ms · 内核引导 7556ms · 日志落盘 313ms"),
    dict(kicker="06 · NETWORK",
         title="下载与解析，都摆在明面上",
         body="16 连接分片、断点续传\n加速通道默认关闭，开启时明确标出风险",
         mono="16 连接 · 加速默认关闭 · 风险提示可见"),
    dict(kicker="07 · LEGAL",
         title="六种语言，同一份条款",
         body="唯一有法律效力的是仓库根目录的 LICENSE\n其余语言只作理解，不增减权利",
         mono="zh / zh_Hant / en / de / fr / ru · Apache-2.0"),
    dict(kicker="08 · ACCOUNT",
         title="一个账号，三个入口",
         body="仓库、发现、我的各自独立滚动\n切换账号不清缓存，退出才删令牌",
         mono="@yingo-server · 草稿 0 · Gist 6 · 系统密钥库"),
    dict(kicker="09 · ARTIFACTS",
         title="23 个产物，一次发布",
         body="每个版本按平台与架构拆分\nzip 与 7z 双格式，校验写在同页",
         mono="AAB / x64 / arm64 / deb / rpm / AppImage / dart2wasm"),
    dict(kicker="10 · END",
         title="OhGithubLost",
         body="GitHub 仓库管理客户端\n在浏览器之外，把每个日常动作闭环完成",
         mono="github.com/OGL-Teams/OhGithubLost"),
]


def draw_wrapped(draw, text, xy, font, fill, spacing=10, line_h=None):
    x, y = xy
    lh = line_h or (font.size + spacing)
    for line in text.split("\n"):
        draw.text((x, y), line, font=font, fill=fill)
        y += lh


def bake(i, spec):
    img = Image.new("RGB", (W, H), BG)
    d = ImageDraw.Draw(img)
    # 外层 M3 卡片：8px 圆角、1px outline
    d.rounded_rectangle((8, 8, W - 8, H - 8), radius=8, fill=SURFACE, outline=OUTLINE, width=2)
    # 左侧 4px primary 条
    d.rectangle((8, 8, 12, H - 8), fill=PRIMARY)
    # kicker
    d.text((56, 48), spec["kicker"], font=F_KICK, fill=PRIMARY)
    d.line((56, 104, W - 56, 104), fill=OUTLINE, width=2)
    # 标题
    draw_wrapped(d, spec["title"], (56, 138), F_TITLE, ON_SURFACE, spacing=12)
    # 正文
    draw_wrapped(d, spec["body"], (56, 330), F_BODY, ON_VARIANT, spacing=10)
    # mono 证据行
    d.line((56, 500, W - 56, 500), fill=OUTLINE, width=2)
    d.text((56, 528), spec["mono"], font=F_MONO, fill=TERTIARY)
    img.save(OUT / f"panel-{i:02d}.png", optimize=True)


def main():
    for i, spec in enumerate(PANELS):
        bake(i, spec)
    print("wrote", len(PANELS), "panels to", OUT)


if __name__ == "__main__":
    main()
