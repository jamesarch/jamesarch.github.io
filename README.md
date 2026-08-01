# jamesarch.github.io

Org mode 写作、导出成静态 HTML、由 GitHub Pages 直接托管的博客。

## 仓库结构

```
org/                 文章源文件,唯一需要手写的地方
  index.org          首页目录,新增文章要在这里加一行链接
*.html               org 导出的产物,提交进仓库 —— Pages 发布的就是它们
asserts/img/         文章插图
asserts/css/org.css  排版主题(vendored,见下)
publish.el           导出配置,构建的唯一事实来源
lib/htmlize.el       源码高亮(vendored)
lib/doom-one-faces.el  配色表,由 make faces 从本机 Doom 生成
scripts/gen-faces.el   上面那张表的生成脚本
scripts/check-links.py 站内引用断链检查
```

## 日常操作

需要 Emacs 30.2(`brew install emacs`)和 python3,不需要装任何 Emacs 包。

```sh
make build    # 重建全部 HTML
make serve    # 构建后起 http://localhost:8000/ 预览
make links    # 检查站内引用没有断链
make check    # 校验提交的 HTML 与 org 源同步(CI 跑的就是它)
make faces    # 从本机 Doom 重新导出配色表,换主题时才需要
```

在 Doom Emacs 里可以直接 `M-x +make/run` 选目标(`:tools make` 模块),不用切终端。

## 写一篇新文章

1. 在 `org/` 下新建 `foo.org`,开头写 `#+TITLE:` 和 `#+DATE:`;
2. 在 `org/index.org` 里加一行 `- [[file:foo.org][标题]]`;
3. `make build && make links`;
4. 把 `foo.html`、`index.html` 和 org 源一起提交。

**产物必须和源一起提交** —— Pages 发布的是仓库里的 HTML,不是 CI 现构建的。忘了重建的话
CI 的 `make check` 会拦下来。

## 构建为什么是确定性的

同一份 org 在任何机器上都产出逐字节相同的 HTML。这不是自然结果,org 默认有三处非确定性,
`publish.el` 逐个消掉了:

| 非确定性 | 默认行为 | 处理 |
| --- | --- | --- |
| 锚点 ID | `(random most-positive-fixnum)`,每次构建全变 | 改成按文档顺序递增 |
| 页头时间戳 | 嵌入构建时刻 | `org-export-time-stamp-file nil` |
| 页脚日期 | 取 org 文件 mtime | 改用各文章的 `#+DATE:` |

外加:`org-publish` 的缓存会复用上次的锚点(于是"有缓存"和"无缓存"产出不同),构建前清掉;
`sh-mode` 的方言取自 `$SHELL`(本机 zsh、CI 多半 bash),不同方言的关键字表不同会着出不同的
色,钉成 bash。

有了这些,`make check` 才能是朴素的 `git diff --exit-code`,而不用为一行时间戳写过滤特例。

## 为什么 htmlize 和配色表在仓库里

**htmlize**:提供源码块语法高亮。缺了它 org 只在 stderr 打一行 warning 就静默降级成纯文本 ——
产物少掉所有颜色而构建照样是绿的。本机 Doom 里其实装了同一份(`build-30.2/htmlize`),但构建
不该依赖用户装没装 Doom、装的哪个版本,所以 vendored 一份进 `lib/`。

**配色表**:batch Emacs 没有图形帧,`font-lock` face 的 `:foreground` 全是 `unspecified`,
htmlize 于是输出不带颜色的 `<span>`。加载主题包也救不了 —— 主题的 face spec 带
`((class color) (min-colors 257))` 条件,tty 帧同样不匹配。

`make faces` 从本机 Doom 的 doom-themes 里把**求值后**的 GUI 配色导出成
`lib/doom-one-faces.el`(1262 个 face),构建时用 `face-override-spec` 无条件套上。配色因此
和作者在 Doom 里看到的完全一致,而发布产物又不跟着谁的编辑器主题漂移。生成脚本带断言:
几个从线上 HTML 核对过的锚点色对不上就直接失败,不让"静默丢色"溜过去。

## 排版主题

`asserts/css/org.css` 是 [orgcss](https://gongzhitaao.org/orgcss/) 的本地副本。原先是外链,
第三方主机哪天没了整站就变裸样式,所以 vendored。

## 域名

`CNAME` 里的 `lefix.me` 已过期,站点当前只能通过 `jamesarch.github.io` 访问。
换域名或续期后改 `CNAME` 即可。
