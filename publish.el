;;; publish.el --- 构建 jamesarch.github.io -*- lexical-binding: t; -*-

;; 用法: emacs -Q --batch -l publish.el --funcall blog-publish  (或 make build)
;;
;; 源文件在 org/,产物直接落到仓库根目录 —— 图片引用是 ./asserts/img/...,
;; 相对根目录解析,发布目录换成别处会全部断链。
;;
;; 构建是纯函数:同一份 org 在任何机器上产出逐字节相同的 HTML,没有例外项。
;; macOS 本地与 Ubuntu CI 上重建的产物 git diff 为空。为此做了四件事 ——
;;   1. 零网络依赖:htmlize、CSS、配色表都在仓库里,不连 MELPA、不连第三方主机;
;;   2. 锚点 ID 确定性递增,不再是随机数;
;;   3. 去掉页头构建时间戳,页脚日期改由各文章的 #+DATE 提供;
;;   4. 每次构建前清掉 org-publish 缓存,产物不依赖机器状态。

(require 'ox-publish)
(require 'ox-html)

(defconst blog-root
  (file-name-directory (or load-file-name buffer-file-name default-directory))
  "仓库根目录。")

;;; 源码高亮

;; htmlize 提供源码块语法高亮。缺它 org 只在 stderr 打一行 warning 就静默降级成
;; 纯文本,产物少掉所有 <span style="color:...">,光看 exit code 发现不了。
;; vendored 在 lib/ 而不是 package-install:装包会引入未固定的版本漂移和网络依赖,
;; 而 htmlize 就是单个文件。
(load (expand-file-name "lib/htmlize.el" blog-root) nil t)

;; 注意这里不再往 face 上套颜色。htmlize 在 `css' 输出模式下只按 face 名生成
;; class,压根不读 :foreground —— batch 无图形帧导致颜色 unspecified 这件事
;; 对产物没有影响了。颜色改由 asserts/css/code.css 提供(make code-css 生成),
;; 这样同一份 HTML 能跟着系统在深浅两套配色之间切,inline-css 模式做不到。

;; org-src 起 sh-mode 时方言取自 $SHELL(本机 zsh、CI 多半 bash/sh),而 sh/bash/zsh
;; 三套 keywords 与 builtins 表不同,同一段代码会着出不同的色。钉成 bash。
(setq sh-shell-file "/bin/bash")
(add-hook 'sh-mode-hook (lambda () (sh-set-shell "bash" nil nil)))

;; 把语言名放进 data-lang,样式表就能用 content: attr(data-lang) 显示角标。
;; org 只把语言编进 class(src-shell / src-rust / …),而 CSS 取不出 class 的
;; 子串,只能一条条穷举 —— 那样写篇 ruby 的文章会有高亮却没角标。
(defun blog--src-block-lang (html backend _info)
  "给 HTML 里的源码块补上 data-lang 属性。"
  (when (org-export-derived-backend-p backend 'html)
    (replace-regexp-in-string
     "<pre class=\"src src-\\([^\"]+\\)\""
     "<pre data-lang=\"\\1\" class=\"src src-\\1\""
     html t)))
(add-to-list 'org-export-filter-src-block-functions #'blog--src-block-lang)

;; org 默认把 json 找成 json-mode(第三方包)。内置的 js-json-mode 是纯 elisp,
;; 不需要 tree-sitter 的 .dylib,导出结果跨机器一致 —— 这是选它而不选
;; json-ts-mode 的原因,后者的 grammar 是机器本地的二进制,CI 上没有。
(require 'org-src)
(add-to-list 'org-src-lang-modes '("json" . js-json))

;;; 确定性锚点 ID

;; org 默认用 (random most-positive-fixnum) 生成 #orgXXXXXXX,同一份 org 每次构建
;; 都不一样;org-publish 靠缓存里的 crossrefs 才能勉强稳住,于是产物变成机器状态的
;; 函数(本地和 CI 必然对不上,git diff 也就没法当验证信号)。
;; 改成按文档出现顺序递增:纯函数、跨机器一致、不依赖任何缓存。
(defun blog--sequential-reference (references)
  "按顺序分配下一个未占用的引用编号,REFERENCES 是已分配的 alist。"
  (let ((n (1+ (length references))))
    (while (assq n references) (setq n (1+ n)))
    n))
(advice-add 'org-export-new-reference :override #'blog--sequential-reference)

;;; 导出参数

(setq user-full-name "jamesarch"
      org-export-default-language "zh-CN"
      ;; postamble 的日期走 C locale,否则中文环境下星期会变成 "六"。
      system-time-locale "C")

;; 页头那行 <!-- 构建时刻 --> 注释是构建产物里唯一的非确定项,去掉它之后
;; make check 才能退化成朴素的 git diff --exit-code。
;; postamble 的日期改由各文章的 #+DATE 提供 —— 原先跟 org 文件 mtime 走,
;; 结果 2022 年写的文章在页面上显示成构建当天,是错的。
(setq org-export-time-stamp-file nil
      org-export-with-date t
      org-export-with-section-numbers nil
      org-export-with-author t
      org-export-with-email nil
      org-export-with-creator nil
      ;; 目录深度和标题层级分开定:正文要认到 5 级,目录只列 3 级 ——
      ;; 跟着 headline-levels 走的话 block_app 的目录会从 9 项涨到 13 项,
      ;; 比正文第一屏还长。
      org-export-with-toc 3
      ;; 默认只有 3 —— 超过的标题不会变成 <hN>,而是塞进 <li> 加个 <br>。
      ;; block_app.org 有 `**** string 模块' 这种四级标题,默认值下它们在页面上
      ;; 就是列表项,看着像 org 没解析。
      org-export-headline-levels 5
      org-export-with-sub-superscripts '{}
      org-html-validation-link nil
      org-html-doctype "html5"
      org-html-html5-fancy t
      ;; 不要 org 自带的那 190 行内联 <style>:它会和主题打特异性架,
      ;; 而且每页重复一遍。排版全部由 asserts/css/ 下的两张表接管。
      org-html-head-include-default-style nil
      org-html-head-include-scripts nil
      ;; css 模式让 htmlize 输出 <span class="org-keyword">,颜色进样式表 ——
      ;; 这样才能跟着系统深浅色切换;inline-css 的内联 style 顶不掉。
      org-html-htmlize-output-type 'css
      org-html-head
      (concat
       "<link rel=\"stylesheet\" href=\"./asserts/css/code.css\"/>\n"
       "<link rel=\"stylesheet\" href=\"./asserts/css/theme.css\"/>\n"
       ;; 深色底,让浏览器把表单控件与滚动条也切过去
       "<meta name=\"color-scheme\" content=\"dark light\"/>")
      org-html-link-up "index.html"
      org-html-link-home "index.html")

;; 批量导出时不要卡在交互提问上
(setq org-confirm-babel-evaluate nil
      org-export-use-babel nil
      make-backup-files nil)

;;; 项目定义

;; org-publish 的缓存同时存时间戳(增量构建用)和 crossrefs(上次分配的锚点 ID)。
;; crossrefs 会被优先复用,于是"有缓存"和"无缓存"两次构建产出不同的 HTML。
;; 锚点已经确定性了,缓存纯属有害,blog-publish 每次构建前清掉。
(setq org-publish-use-timestamps-flag nil
      org-publish-timestamp-directory
      (expand-file-name ".cache/org-timestamps/" blog-root))

(setq org-publish-project-alist
      `(("blog-pages"
         :base-directory ,(expand-file-name "org" blog-root)
         :base-extension "org"
         :publishing-directory ,blog-root
         :publishing-function org-html-publish-to-html
         :recursive nil
         ;; project property 会盖掉全局的 org-export-with-toc,得同步写 3
         :with-toc 3
         :section-numbers nil
         :html-link-up "index.html"
         :html-link-home "index.html")
        ("blog" :components ("blog-pages"))))

(defun blog--check-src-languages ()
  "扫一遍 org 源里的 #+begin_src,语言不可用的直接报错。

高亮是构建期由 Emacs 的 major-mode 驱动的,所以任何 Emacs 认识的语言都自动上色。
反过来,不认识的语言 org 不会吭声 —— 照常导出一个纯文本 pre,构建绿、verify 也绿
(class 对账只查已出现的 class,查不出本该出现却没有的),只有肉眼看页面才发现
代码块是一片灰。这道闸把它变成硬失败。

三种情况都拦:
  · 找不到 major-mode(如 rust,rust-mode 是第三方包);
  · 解析到 *-ts-mode —— 它 fboundp 为 t 所以能骗过 fboundp 检查,但没有
    tree-sitter 的 .dylib 就是一片灰,而那是机器本地的二进制,CI 上没有,
    产物会因机器而异;
  · 裸 #+begin_src 不写语言 —— 导出成 src-nil,既没高亮,角标还会显示 nil。"
  (require 'org-src)
  (let (bad)
    (dolist (file (directory-files (expand-file-name "org" blog-root) t "\\.org\\'"))
      (with-temp-buffer
        (insert-file-contents file)
        (goto-char (point-min))
        (while (re-search-forward "^[ \t]*#\\+begin_src\\(?:[ \t]+\\([^ \t\n]+\\)\\)?" nil t)
          (let* ((lang (match-string 1))
                 (mode (and lang (org-src-get-lang-mode lang)))
                 (where (format "  %s:%d  " (file-name-nondirectory file)
                                (line-number-at-pos)))
                 (reason
                  (cond
                   ((null lang) "没写语言,会导出成 src-nil:纯文本 + 角标显示 nil")
                   ((string-suffix-p "-ts-mode" (symbol-name mode))
                    (format "%s 解析到 %s,它要 tree-sitter grammar(机器本地二进制)"
                            lang mode))
                   ((not (fboundp mode)) (format "%s 找不到 %s" lang mode)))))
            (when reason (push (concat where reason) bad))))))
    (when bad
      (error "这些源码块导出后不会有高亮:\n%s\n\n出路:\n  · 映射到内置的纯 elisp mode —— (add-to-list 'org-src-lang-modes '(\"LANG\" . MODE))\n  · 或把 mode vendored 进 lib/ 再 load,像 htmlize 那样\n  · 裸 #+begin_src 若确实只是示例文本,改用 #+begin_example"
             (mapconcat #'identity (nreverse bad) "\n")))))

(defun blog-publish ()
  "全量重建站点。"
  (blog--check-src-languages)
  (when (file-directory-p org-publish-timestamp-directory)
    (delete-directory org-publish-timestamp-directory t))
  (setq org-publish-cache nil)
  (org-publish "blog" t))

(provide 'publish)
;;; publish.el ends here
