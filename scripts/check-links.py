#!/usr/bin/env python3
"""检查产物 HTML 里的站内引用是否都指向真实文件。

导出配置一改(发布目录、CSS 路径、图片位置),断链只在浏览器里才看得见,
git diff 和 exit code 都是绿的。这个脚本把它变成构建期的硬失败。
外链只查格式不发请求 —— 文章里引的第三方站随时可能挂,不该卡住构建。
"""

import re
import sys
from pathlib import Path
from urllib.parse import unquote, urldefrag

ROOT = Path(__file__).resolve().parent.parent
REF = re.compile(r'(?:href|src)="([^"]+)"')


def main() -> int:
    broken: list[str] = []
    pages = sorted(ROOT.glob("*.html"))
    if not pages:
        print("没有找到任何 HTML 产物,先跑 make build", file=sys.stderr)
        return 1

    for page in pages:
        for raw in REF.findall(page.read_text(encoding="utf-8")):
            target, _ = urldefrag(raw)
            if not target or target.startswith(("http://", "https://", "mailto:", "data:", "//")):
                continue
            resolved = (page.parent / unquote(target)).resolve()
            if not resolved.exists():
                broken.append(f"{page.name}: {raw}")

    for item in broken:
        print(f"断链 {item}", file=sys.stderr)
    print(f"检查 {len(pages)} 个页面,{len(broken)} 处断链")
    return 1 if broken else 0


if __name__ == "__main__":
    sys.exit(main())
