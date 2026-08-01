# jamesarch.github.io

Org mode 写作、导出成静态 HTML、由 GitHub Pages 直接托管的博客。

## 仓库结构

```
org/                    文章与页面的源文件,唯一需要手写的地方
*.html                  导出产物,提交进仓库 —— Pages 发布的就是它们
atom.xml sitemap.xml    构建时生成
robots.txt
asserts/img/            插图与 favicon
asserts/css/theme.css   主题:排版、配色、布局
asserts/css/code.css    代码高亮,由 make code-css 从本机 Doom 生成
publish.el              导出配置与 org-publish 项目定义
site.el                 站点级元数据:导航、feed、sitemap、社交预览
lib/htmlize.el          源码高亮(vendored)
scripts/gen-code-css.el 高亮配色的生成脚本
scripts/check-output.py 产物完整性检查
```

## 发布:两条路,同一段代码

**Emacs 内**(Doom):

| | |
| --- | --- |
| `SPC m e P p` | `org-export-dispatch` → publish current project |
| `M-x blog-publish` | 同上,一步到位 |
| `M-x +blog/verify` | 构建 + 断链与样式覆盖检查 |
| `M-x +blog/serve` | 起本地预览 |

**终端**:

```sh
make build      # 重建站点
make serve      # 构建后起 http://localhost:8000/
make verify     # 站内引用不断链 + 每个 token class 都有样式
make check      # 校验提交的产物与 org 源同步(CI 跑的就是它)
make code-css   # 从本机 Doom 重新生成高亮样式,换主题时才需要
```

两条路走的是**同一套 project 配置**:语言检查、清缓存、生成 feed/sitemap 全挂在
项目的 `:preparation-function` / `:completion-function` 上,`blog-publish` 只是一层薄壳。
实测 `doom emacs --batch` 与 `emacs -Q --batch` 导出的 8 个产物 md5 全等,改动标题
制造锚点重排后仍然全等。

Doom 侧的命令定义在 `~/.config/doom/config.el`,它 `after! ox-publish` 时加载
本仓库的 `publish.el`。

**发布用 `P p`,不要用 `P f`** —— 后者只发当前文件,不触发项目钩子,feed 和 sitemap
不会更新。

## 写一篇新文章

1. 在 `org/` 下新建 `foo.org`,写 `#+TITLE:` 和 `#+DATE:`(建议再加 `#+DESCRIPTION:`,
   它会进 meta description、Open Graph 和 feed 摘要);
2. `make verify` 或 `M-x +blog/verify`;
3. 把 `foo.html` 和所有变更的产物一起提交。

首页列表是自动生成的,按 `#+DATE` 倒序 —— **不用回来改 `index.org`**。

**产物必须和源一起提交** —— Pages 发布的是仓库里的文件,不是 CI 现构建的。忘了重建
CI 会拦下来:`make check` 同时查 `git diff` 和 untracked,范围覆盖 HTML、`atom.xml`、
`sitemap.xml`、`robots.txt`。

代码块必须写语言(`#+begin_src shell`)。构建前有一道闸扫所有 `#+begin_src`,三种情况
报错并指出文件行号:找不到 major-mode、裸块不写语言、解析到 `*-ts-mode`(它要
tree-sitter grammar,那是机器本地的 `.dylib`,CI 上没有)。纯示例文本用 `#+begin_example`。

高亮由 Emacs 的 major-mode 驱动,所以**任何 `emacs -Q` 认识的语言都自动上色**,语言角标
也由导出 filter 写进 `data-lang` 后用 `content: attr(data-lang)` 显示。站内现用
shell / conf / bat。**不必查表**:写完跑一次构建,不支持的会被闸拦下并给出两条出路。

## 导航栏:页面自己声明

在 org 头部写一行就进导航:

```org
#+NAV: 20 关于
```

序号决定排序,后面是显示的标签。`site.el` 在构建期扫 `org/` 收集,当前页自动带
`aria-current="page"`(既是无障碍语义,也是高亮用的样式钩子)。

这里**不维护页面清单** —— 手写清单和之前从 `theme.css` 删掉的 22 条语言白名单是同一个
失效模式:新增页面忘了加就静默漏掉。导航身份跟着页面自己走。

样式取平铺、无下拉、无汉堡:隐藏式菜单会让任务完成率下降(NN/g 的数据是 21%),而这个站
总共三五个入口,没有藏起来的理由。参考了 [matklad](https://matklad.github.io/) 与
[protesilaos](https://protesilaos.com/) 的做法 —— 站名兼首页链接,其余平铺在右侧。

## 构建为什么是确定性的

同一份 org 在任何机器、任何会话里都产出逐字节相同的 HTML。这不是自然结果:

| 非确定性 | 默认行为 | 处理 |
| --- | --- | --- |
| 锚点 ID | `(random most-positive-fixnum)`,每次全变 | 改成按文档顺序递增 |
| 页头时间戳 | 嵌入构建时刻 | `org-export-time-stamp-file nil` |
| 页脚日期 | 取 org 文件 mtime | 改用各文章的 `#+DATE:` |
| feed `<updated>` | 惯例用当前时间 | 取全站 `#+DATE` 的最大值 |
| **未显式设的导出选项** | 继承当前会话 | 先归零到 defcustom 出厂默认 |

最后一条最隐蔽:Doom 的 `:lang org` 把 `org-export-with-smart-quotes` 设成 `t`,而
`emacs -Q` 下是 `nil` —— 同一份 org,从 Doom 里发布一次就会产出不同的字节。所以导出前
把 `org-export-options-alist` 与 html backend 声明的**全部 102 个**选项变量归零到各自的
`defcustom` 出厂默认,再由 project plist 显式覆盖。新增选项自动纳入,不用在这里手维护
一份清单。

外加:`org-publish` 的缓存会复用上次的锚点(crossrefs 优先于新分配),构建前清掉;
`sh-mode` 的方言取自 `$SHELL`(本机 zsh、CI 多半 bash),不同方言的关键字表不同会着出
不同的色,钉成 bash;Makefile 断言 Emacs 版本,用错版本立刻失败而不是静默产出不同 HTML。

有了这些,`make check` 才能是朴素的 `git diff --exit-code`。

## 主题

设计取向是**把 Doom Emacs 里的信息层级搬到网页**,不是做"终端风"装饰。几处依据:

- `doom-theme` 是 `doom-one`,所以深色是默认态,浅色跟随系统 —— 纯 CSS
  `prefers-color-scheme`,零 JS;
- 作者把 `lsp-ui` 的 sideline 和 doc 都关了(改用 `K` 主动看),所以主题里没有任何自动
  冒出来的东西:目录不浮动、无 hover 卡片、无滚动动画、无粘性 header;
- 3 篇文章 17 个源码块,代码是主角 —— 代码块是页面上唯一比底色亮的区域;
- 标题层级靠字号、上方留白、以及第四级往下切等宽字体来表达,不用颜色也不用色条;
- 正文中英混排且不加空格,所以行宽按中文字数定(约 38 字/行),字间距靠
  `text-spacing-trim` 自动处理。

字体上,`Maple Mono NF CN` 是作者本机的编辑器字体,访客机上没有就退到系统等宽 —— 不自托管
woff2,一份中文等宽 20MB+,为几个代码块不值。

试过又撤掉的:在 h2/h3/h4 前用 `::before` 加 `## / ### / ####` 呼应 org 源的星号数。
读者第一眼看到的是"markdown 没渲染成功",而且 org 一级标题导出成 h2、井号数比源码多一个,
更像是坏了。同理,h5 一度改成灰色降权,结果它比自己管的正文还淡 —— 改成切等宽字体。

### 配色与对比度

页面配色取自 doom-one / doom-one-light 的调色板,但有两处压暗过:浅色的
`--accent` `#4078f2 → #3868d3`、`--literal` `#50a14f → #387037`。原值在 `#f0f0f0` 上
只有 3.55:1 / 2.81:1 —— 编辑器里它们落在 `#fafafa`、字号更大、还有语法结构做冗余,
搬到网页顶不住。色相没动,只压亮度。

两档标准,按元素类型分:

| | 阈值 | 用在哪 |
| --- | --- | --- |
| 页面文本与链接 | 4.5:1(WCAG AA) | 正文、链接、`em`、行内代码、导航、页脚、语言角标 |
| 纯装饰 | 3:1 | 列表符号、list marker |
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
  2.26:1,远低于 WCAG 的 3:1。给代码块上深色底是设计改动,得自己把账补上,所以生成时按
  3:1 提亮,并在 CSS 注释里标出调过哪几个。

htmlize 本身 vendored 在 `lib/`:本机 Doom 里装着同一份,但构建不该依赖用户装没装 Doom。
缺了它 org 只在 stderr 打一行 warning 就静默降级成纯文本,exit code 照样是 0。

## 404 与绝对路径

`org/404.org` 导出的 `404.html` 里,所有站内链接和资源引用都会被改写成**根绝对路径**。

GitHub Pages 对任意深度的不存在路径都返回 `404.html` 的内容,但浏览器按**请求路径**解析
相对链接 —— 访客打开 `/foo/bar` 时,`./asserts/css/theme.css` 会去要
`/foo/asserts/css/theme.css`。结果是裸样式加一排死链。本地 `http.server` 直接开
`/404.html` 看不出来(深度恰好是 0)。

`404.html` 不进 `sitemap.xml`。

## 绝对 URL 与域名

feed、sitemap、`og:url`、canonical 里的绝对地址都从 `site.el` 的 `blog-base-url` 拼,
只有这一处。

`CNAME` 指定了自定义域名 `lefix.me`,该域名已过期。只要这个文件还在,Pages 就会把
`https://jamesarch.github.io/` 301 到 `http://lefix.me/`(实测如此),所以线上两个地址
目前都打不开。续期,或删掉 `CNAME` 让 github.io 直接生效 —— 后者做完把 `blog-base-url`
一并确认即可,它现在就指向 github.io。
