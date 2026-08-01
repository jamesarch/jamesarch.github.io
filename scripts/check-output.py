#!/usr/bin/env python3
"""构建产物的完整性检查:站内引用不断链,样式表覆盖到每个 token class。

两项检查都是"浏览器里才看得见、git diff 和 exit code 全绿"的那类问题:

  · 断链 —— 改导出配置(发布目录、CSS 路径、图片位置)时一漏就是 404;
  · 样式漏覆盖 —— htmlize 按 face 名生成 class,主题里那个 face 若只写
    `:inherit' 而没有自己的 :foreground,生成器可能把它跳过,于是页面上
    某一类 token 悄悄退回默认色。实测抓到过 .org-comment-delimiter:
    注释的 `#' 和注释正文不同色,肉眼几乎看不出来。

外链只查格式不发请求 —— 文章里引的第三方站随时可能挂,不该卡住构建。
"""

import re
import sys
from pathlib import Path
from urllib.parse import unquote, urldefrag

ROOT = Path(__file__).resolve().parent.parent
CSS_DIR = ROOT / "asserts" / "css"

REF = re.compile(r'(?:href|src)="([^"]+)"')
HTML_CLASS = re.compile(r'class="([^"]+)"')
CSS_SELECTOR = re.compile(r"\.(org-[a-z0-9-]+)")
PRE_BLOCK = re.compile(r"<pre\b.*?</pre>", re.S)


def check_links(pages: list[Path]) -> list[str]:
    """站内引用都指向真实文件。"""
    broken = []
    for page in pages:
        for raw in REF.findall(page.read_text(encoding="utf-8")):
            target, _ = urldefrag(raw)
            if not target or target.startswith(
                ("http://", "https://", "mailto:", "data:", "//")
            ):
                continue
            # 404 页的链接是根绝对路径(见 site.el 的 blog--absolutize):Pages 对
            # 任意深度的不存在路径都回 404.html,相对路径会跟着请求路径跑偏。
            # 这类要按站点根解析 —— pathlib 里 `page.parent / "/a/b"` 会丢掉左边,
            # 直接去查真实文件系统的 /a/b,必然不存在,判成假断链。
            base = ROOT if target.startswith("/") else page.parent
            if not (base / unquote(target.lstrip("/"))).resolve().exists():
                broken.append(f"{page.name}: {raw}")
    return broken


def check_class_coverage(pages: list[Path]) -> list[str]:
    """代码块里每个 token class 都有配色规则。

    只看 <pre> 内部。htmlize 按 face 名生成 .org-keyword 这类 class,主题里那个
    face 若只写了 :inherit 而没有自己的 :foreground,生成器可能把它跳过,于是
    页面上某一类 token 悄悄退回默认色 —— 实测抓到过 .org-comment-delimiter,
    注释的 `#' 和注释正文不同色,肉眼几乎看不出来。

    <pre> 之外的 .org-ul / .org-src-container 这些是 ox-html 的结构 class,
    本来就由标签选择器统一管,不在这道闸的射程里。把它们算进来只会逼着往 CSS
    里塞空规则去糊弄检查。
    """
    used: set[str] = set()
    for page in pages:
        html = page.read_text(encoding="utf-8")
        for block in PRE_BLOCK.findall(html):
            for attr in HTML_CLASS.findall(block):
                used.update(c for c in attr.split() if c.startswith("org-"))

    styled: set[str] = set()
    for sheet in sorted(CSS_DIR.glob("*.css")):
        styled.update(CSS_SELECTOR.findall(sheet.read_text(encoding="utf-8")))

    return sorted(used - styled)


def main() -> int:
    pages = sorted(ROOT.glob("*.html"))
    if not pages:
        print("没有找到任何 HTML 产物,先跑 make build", file=sys.stderr)
        return 1

    broken = check_links(pages)
    for item in broken:
        print(f"断链 {item}", file=sys.stderr)

    uncovered = check_class_coverage(pages)
    for name in uncovered:
        print(f"没有样式规则的 class: .{name}", file=sys.stderr)

    print(f"检查 {len(pages)} 个页面,{len(broken)} 处断链,{len(uncovered)} 个 class 无样式")
    return 1 if (broken or uncovered) else 0


if __name__ == "__main__":
    sys.exit(main())
