# jamesarch.github.io

Org mode 写作、导出成静态 HTML、由 GitHub Pages 直接托管的博客。

## 仓库结构

```
org/                    文章源文件,唯一需要手写的地方
  index.org             首页目录,新增文章要在这里加一行链接
*.html                  org 导出的产物,提交进仓库 —— Pages 发布的就是它们
asserts/img/            文章插图
asserts/css/theme.css   主题:排版、配色、布局
asserts/css/code.css    代码高亮,由 make code-css 从本机 Doom 生成
publish.el              导出配置,构建的唯一事实来源
lib/htmlize.el          源码高亮(vendored)
scripts/gen-code-css.el 上面那张高亮表的生成脚本
scripts/check-output.py 产物完整性检查
```

## 日常操作

需要 Emacs 30.2(`brew install emacs`)和 python3,不需要装任何 Emacs 包。

```sh
make build      # 重建全部 HTML
make serve      # 构建后起 http://localhost:8000/ 预览
make verify     # 产物完整性:站内引用不断链 + 每个 token class 都有样式
make check      # 校验提交的 HTML 与 org 源同步(CI 跑的就是它)
make code-css   # 从本机 Doom 重新生成高亮样式,换主题时才需要
```

在 Doom Emacs 里用 `M-x +blog/publish`(构建 + 完整性检查)、`M-x +blog/serve`(预览)、
`M-x +blog/find-file`(跳到 `org/`),定义在 `~/.config/doom/config.el`。它们走的是
子进程里的同一套 make,**不是** `org-publish` —— 交互路径和 batch 路径分叉的话,
下面那条零 diff 不变式就没人守了。

## 写一篇新文章

1. 在 `org/` 下新建 `foo.org`,开头写 `#+TITLE:` 和 `#+DATE:`;
2. 在 `org/index.org` 里加一行 `- [[file:foo.org][标题]]`;
3. `make verify`;
4. 把 `foo.html`、`index.html` 和 org 源一起提交。

**产物必须和源一起提交** —— Pages 发布的是仓库里的 HTML,不是 CI 现构建的。忘了重建的话
CI 的 `make check` 会拦下来(它同时查 `git diff` 和 untracked,新增文章漏提交 HTML 也拦)。

代码块必须写语言(`#+begin_src shell`)。构建前有一道闸会扫所有 `#+begin_src`,
三种情况直接报错并指出文件行号:找不到 major-mode、裸块不写语言、解析到 `*-ts-mode`。
最后一种是因为 tree-sitter grammar 是机器本地的 `.dylib`,CI 上没有,产物会因机器而异。
纯粹的示例文本用 `#+begin_example`。

高亮由 Emacs 的 major-mode 驱动,所以**任何 `emacs -Q` 认识的语言都自动上色**,
语言角标也由导出 filter 写进 `data-lang` 后用 `content: attr(data-lang)` 显示,
不需要为每种语言加规则。当前可用的有 shell / conf / bat / json / python / ruby /
js / sql / c / c++ / toml / makefile / diff / emacs-lisp 等一批纯 elisp mode。
rust、go、yaml、typescript 的 mode 不在 Emacs 内置里,写了会被闸拦下 —— 那时要么在
`publish.el` 里映射到某个内置 mode,要么把它 vendored 进 `lib/`,像 htmlize 那样。

## 构建为什么是确定性的

同一份 org 在任何机器上都产出逐字节相同的 HTML —— macOS 本地与 Ubuntu CI 上重建的产物
`git diff` 为空。这不是自然结果,org 默认有三处非确定性,`publish.el` 逐个消掉了:

| 非确定性 | 默认行为 | 处理 |
| --- | --- | --- |
| 锚点 ID | `(random most-positive-fixnum)`,每次构建全变 | 改成按文档顺序递增 |
| 页头时间戳 | 嵌入构建时刻 | `org-export-time-stamp-file nil` |
| 页脚日期 | 取 org 文件 mtime | 改用各文章的 `#+DATE:` |

外加:`org-publish` 的缓存会复用上次的锚点(于是"有缓存"和"无缓存"产出不同),构建前清掉;
`sh-mode` 的方言取自 `$SHELL`(本机 zsh、CI 多半 bash),不同方言的关键字表不同会着出不同的
色,钉成 bash;Makefile 断言 Emacs 版本,用错版本立刻失败而不是静默产出不同 HTML。

有了这些,`make check` 才能是朴素的 `git diff --exit-code`,而不用为一行时间戳写过滤特例。

## 主题

设计取向是**把 Doom Emacs 里的信息层级搬到网页**,不是做"终端风"装饰。几处依据:

- `doom-theme` 是 `doom-one`,所以深色是默认态,浅色跟随系统 —— 纯 CSS
  `prefers-color-scheme`,零 JS;
- 作者把 `lsp-ui` 的 sideline 和 doc 都关了(改用 `K` 主动看),所以主题里没有任何自动
  冒出来的东西:目录不浮动、无 hover 卡片、无滚动动画、无粘性 header;
- 3 篇文章 17 个源码块,代码是主角 —— 代码块是页面上唯一比底色亮的区域,视线自然落上去;
- 标题层级靠字号、上方留白、以及第四级往下切等宽字体来表达,不用颜色也不用色条 ——
  颜色全留给代码;
- 正文中英混排且不加空格,所以行宽按中文字数定(约 38 字/行),字间距靠
  `text-spacing-trim` 自动处理。

字体上,`Maple Mono NF CN` 是作者本机的编辑器字体,访客机上没有就退到系统等宽 —— 不自托管
woff2,一份中文等宽 20MB+,为几个代码块不值。

试过又撤掉的:在 h2/h3/h4 前用 `::before` 加 `## / ### / ####` 呼应 org 源的星号数。
读者第一眼看到的是"markdown 没渲染成功",而且 org 一级标题导出成 h2、井号数比源码多一个,
更像是坏了。一个需要解释才能看懂的装饰不如没有。同理,h5 一度改成灰色降权,结果它比自己
管的正文还淡 —— 改成切等宽字体。

### 配色与对比度

页面配色取自 doom-one / doom-one-light 的调色板,但有两处压暗过:浅色的
`--accent` `#4078f2 → #3868d3`、`--literal` `#50a14f → #387037`。原值在 `#f0f0f0` 上
只有 3.55:1 / 2.81:1 —— 编辑器里它们落在 `#fafafa`、字号更大、还有语法结构做冗余,
搬到网页顶不住。色相没动,只压亮度。

两档标准,按元素类型分:

| | 阈值 | 用在哪 |
| --- | --- | --- |
| 页面文本与链接 | 4.5:1(WCAG AA) | 正文、链接、`em`、行内代码、页脚导航目录、语言角标 |
| 纯装饰 | 3:1 | 列表符号 `→`、list marker |
| 代码块 token | 3:1 | `code.css` 里的语法高亮 |

代码 token 用 3:1 不是放水:那是代码块底色上的成片代码,语法结构本身提供辨识冗余。
行内代码要按它自己那层 8% tint 的合成底算(`#e1e1e2` / `#2d3138`),按页面底算会得出
偏乐观的数。每个变量旁边都注了实测值。

## 高亮配色为什么要生成

`asserts/css/code.css` 由 `make code-css` 从本机 Doom 的 doom-themes 导出:深色取
`doom-one`、浅色取 `doom-one-light`,两套套在 `prefers-color-scheme` 里。生成物进仓库,
构建就不依赖谁装了 Doom。

绕不开的三个坑,都在 `scripts/gen-code-css.el` 里处理了:

- **不能直接读 face**。batch Emacs 没有图形帧,`face-attribute` 全返回 `unspecified`;
  加载主题也救不了,主题 spec 带 `((class color) (min-colors 257))` 条件,tty 帧匹配不上。
  要从 `theme-settings` 里取已求值的那一档。
- **`:inherit` 要沿链解析**。`font-lock-comment-delimiter-face` 在 doom-one 里只写
  `(:inherit font-lock-comment-face)`,只收有 `:foreground` 的 face 会把它漏掉,结果注释的
  `#` 和注释正文不同色 —— 肉眼几乎看不出来,`make verify` 的 class 覆盖对账能抓到。
- **对比度要兜底**。编辑器配色搬到网页会掉可读性:注释 `#5B6268` 落在 `#282c34` 上只有
  2.26:1,远低于 WCAG 的 3:1。这不是"线上一直这样" —— 2023 那批 HTML 是白底,同一个灰有
  6.19:1。给代码块上深色底是设计改动,得自己把账补上,所以生成时按 3:1 提亮,并在 CSS 注释
  里标出调过哪几个。

htmlize 本身 vendored 在 `lib/`:本机 Doom 里装着同一份,但构建不该依赖用户装没装 Doom、
装的哪个版本。缺了它 org 只在 stderr 打一行 warning 就静默降级成纯文本,exit code 照样是 0。

## 域名

`CNAME` 指定了自定义域名 `lefix.me`,该域名已过期。只要这个文件还在,Pages 就会把
`https://jamesarch.github.io/` 301 到 `http://lefix.me/`(实测如此),所以线上两个地址
目前都打不开 —— 不是"还能用 github.io 顶着"。续期,或删掉 `CNAME` 让 github.io 直接生效。
