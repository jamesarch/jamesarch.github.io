;;; publish.el --- 构建 jamesarch.github.io -*- lexical-binding: t; -*-

;; 两条路都走得通,而且是同一段代码:
;;
;;   终端     make build            (CI 跑的也是它)
;;   Doom     SPC m e P p           org-export-dispatch → publish current project
;;            M-x blog-publish      等价的一键命令,顺带生成 feed/sitemap
;;
;; 源文件在 org/,产物直接落到仓库根目录 —— 图片引用是 ./asserts/img/...,
;; 相对根目录解析,发布目录换成别处会全部断链。
;;
;; 构建是纯函数:同一份 org 在任何机器、任何会话里产出逐字节相同的 HTML。
;; macOS 本地、Ubuntu CI、以及 Doom 会话里导出的结果 git diff 都为空。
;; 为此做了五件事 ——
;;   1. 零网络依赖:htmlize、CSS、配色表都在仓库里,不连 MELPA、不连第三方主机;
;;   2. 锚点 ID 确定性递增,不再是随机数;
;;   3. 去掉页头构建时间戳,页脚日期改由各文章的 #+DATE 提供;
;;   4. 每次构建前清掉 org-publish 缓存,产物不依赖机器状态;
;;   5. 导出选项先归零到 Org 出厂默认,再叠加 project plist —— 见"导出环境"。

(require 'cl-lib)
(require 'ox-publish)
(require 'ox-html)
(require 'org-src)

(defconst blog-root
  (file-name-directory (or load-file-name buffer-file-name default-directory))
  "仓库根目录。")

;; 站点级元数据:导航栏、Atom feed、sitemap、社交预览标签。
;; 拆出去是因为它们的输入是"整个 org/ 目录",而不是当前正在导出的这一篇。
(load (expand-file-name "site.el" blog-root) nil t)

;; htmlize 提供源码块语法高亮。缺它 org 只在 stderr 打一行 warning 就静默降级成
;; 纯文本,产物少掉所有高亮 span,光看 exit code 发现不了。
;; vendored 在 lib/ 而不是 package-install:装包会引入未固定的版本漂移和网络依赖,
;; 而 htmlize 就是单个文件。
(load (expand-file-name "lib/htmlize.el" blog-root) nil t)

;; org 默认把 json 找成 json-mode(第三方包)。内置的 js-json-mode 是纯 elisp,
;; 不需要 tree-sitter 的 .dylib,导出结果跨机器一致 —— 这是选它而不选
;; json-ts-mode 的原因,后者的 grammar 是机器本地的二进制,CI 上没有。
;; 这条是全局的,但它只是让 Emacs 多认一种语言,对交互会话有益无害。
(add-to-list 'org-src-lang-modes '("json" . js-json))

;;; 导出环境
;;
;; 这个文件要能在 Doom 会话里加载(SPC m e P p 走的就是它注册的 project),
;; 于是有两个方向的问题,都得堵:
;;
;;   往外:全局 setq 会改掉此后所有 org 导出和所有 sh 缓冲区。
;;   往里 —— 这个更隐蔽 —— **没显式设的选项会继承当前会话的值**。
;;         例如 Doom 的 :lang org 把 `org-export-with-smart-quotes' 设成 t,
;;         而 emacs -Q 下它是 nil。同一份 org,两边导出的字节就不一样,
;;         从 Doom 发布一次,make check 的零 diff 立刻莫名其妙变红。
;;
;; 所以导出前把 `org-export-options-alist' 和 html backend 声明的**全部**选项
;; 变量归零到各自的 defcustom 出厂默认值,再由 project plist 显式覆盖需要的。
;; 基线与会话无关,两条路径不可能分叉。

(defun blog--export-option-variables ()
  "所有影响导出结果的选项变量。

取自 `org-export-options-alist' 与 html backend 的 options —— 每条的第 4 个
元素就是它的 defcustom 变量名(没有的为 nil)。这样新增选项自动纳入,
不用在这里手维护一份清单。"
  (delete-dups
   (delq nil (mapcar (lambda (entry)
                       ;; 第 4 个元素是"默认值"槽:defcustom 支持的选项放变量名,
                       ;; 其余放字面量。nil / t / keyword 也满足 symbolp 与 boundp,
                       ;; 混进去的话 cl-progv 会去 set 常量符号,报一句和根因
                       ;; 完全对不上的 "Attempt to set a constant symbol"。
                       (let ((slot (nth 3 entry)))
                         (and (symbolp slot) slot (not (eq slot t))
                              (not (keywordp slot)) (boundp slot) slot)))
                     (append org-export-options-alist
                             (org-export-backend-options
                              (org-export-get-backend 'html)))))))

(defun blog--standard-value (sym)
  "SYM 的 defcustom 出厂默认值;拿不到就退回当前值。"
  (if-let* ((sv (get sym 'standard-value)))
      (condition-case nil (eval (car sv) t) (error (symbol-value sym)))
    (symbol-value sym)))

(defun blog--sequential-reference (references)
  "按顺序分配下一个未占用的引用编号。

org 默认用 (random most-positive-fixnum) 生成 #orgXXXXXXX,同一份 org 每次
构建都不一样;org-publish 靠缓存里的 crossrefs 才能勉强稳住,于是产物变成
机器状态的函数(本地和 CI 必然对不上,git diff 也就没法当验证信号)。
改成按文档出现顺序递增:纯函数、跨机器一致、不依赖任何缓存。"
  (let ((n (1+ (length references))))
    (while (assq n references) (setq n (1+ n)))
    n))

(defun blog--force-bash ()
  "把 org-src 起的 sh-mode 方言钉成 bash。

方言默认取自 $SHELL(本机 zsh、CI 多半 bash/sh),而 sh/bash/zsh 三套 keywords
与 builtins 表不同,同一段代码会着出不同的色。"
  (sh-set-shell "bash" nil nil))

(defun blog--src-block-lang (html backend _info)
  "给源码块补上 data-lang 属性,样式表就能用 content: attr(data-lang) 显示角标。

org 只把语言编进 class(src-shell / src-rust / …),而 CSS 取不出 class 的
子串,只能一条条穷举 —— 那样写篇 ruby 的文章会有高亮却没角标。"
  (when (org-export-derived-backend-p backend 'html)
    (replace-regexp-in-string
     "<pre class=\"src src-\\([^\"]+\\)\""
     "<pre data-lang=\"\\1\" class=\"src src-\\1\""
     html t)))

(defun blog--call-in-export-env (fn)
  "在本站专用的导出环境里调用 FN,退出后完全还原。"
  (let ((vars (blog--export-option-variables)))
    (cl-progv vars (mapcar #'blog--standard-value vars)
      (let (;; 下面这些不在 options-alist 里,project plist 接不住,只能绑。
            (org-html-htmlize-output-type 'css)
            ;; 页头那行 <!-- 构建时刻 --> 是产物里唯一的非确定项,去掉它之后
            ;; make check 才能退化成朴素的 git diff --exit-code。
            (org-export-time-stamp-file nil)
            ;; postamble 的日期走 C locale,否则中文环境下星期会变成"六"。
            (system-time-locale "C")
            (org-export-use-babel nil)
            (org-confirm-babel-evaluate nil)
            (make-backup-files nil)
            (sh-shell-file "/bin/bash")
            (sh-mode-hook (cons #'blog--force-bash sh-mode-hook))
            (org-export-filter-src-block-functions
             (cons #'blog--src-block-lang org-export-filter-src-block-functions))
            ;; per-page 的 description / Open Graph / canonical、首页文章列表、
            ;; 404 的路径绝对化都在这一步。org-html-head 是全站一个字符串,
            ;; 塞不进随页面变化的内容。
            (org-export-filter-final-output-functions
             (cons #'blog-finalize org-export-filter-final-output-functions)))
        (advice-add 'org-export-new-reference :override #'blog--sequential-reference)
        (unwind-protect (funcall fn)
          (advice-remove 'org-export-new-reference #'blog--sequential-reference))))))

(defun blog-publish-to-html (plist filename pub-dir)
  "本站的 publishing-function:套上导出环境再交给 ox-html。

org-publish 对每个文件调一次,所以环境的建立与还原都在单文件粒度上,
中途报错也不会把 advice 留在会话里。"
  (blog--call-in-export-env
   (lambda () (org-html-publish-to-html plist filename pub-dir))))

;;; 项目定义

;; org-publish 的缓存同时存时间戳(增量构建用)和 crossrefs(上次分配的锚点 ID)。
;; crossrefs 会被优先复用,于是"有缓存"和"无缓存"两次构建产出不同的 HTML。
;; 锚点已经确定性了,缓存纯属有害,blog-publish 每次构建前清掉。
;; 这两个是 org-publish 的运行参数而非导出参数,project plist 里没有对应项,
;; 只能全局设 —— 影响仅限于"不用增量、缓存写在仓库内",对交互会话无害。
(setq org-publish-use-timestamps-flag nil
      org-publish-timestamp-directory
      (expand-file-name ".cache/org-timestamps/" blog-root))

;; 导出参数尽量都在这里:project plist 的作用域就是这个站,不会外溢。
(setq org-publish-project-alist
      `(("blog-pages"
         :base-directory ,(expand-file-name "org" blog-root)
         :base-extension "org"
         :publishing-directory ,blog-root
         :publishing-function blog-publish-to-html
         ;; 构建前的两件事都挂在项目上,不能只写在 blog-publish 里 ——
         ;; 走 org-export-dispatch 的 P p 时调的是 org-publish,不经过它。
         ;;
         ;; 1. 源码块语言可用性。不查的话,从 Doom 发一篇带 #+begin_src rust
         ;;    的文章会静默导出成纯文本,make verify 也抓不到(class 对账只查
         ;;    "已出现的 class 有没有样式",查不出本该出现却没出现的 token)。
         ;; 2. 清缓存。org-publish 的缓存除了增量时间戳还存 crossrefs(上次
         ;;    分配的锚点 ID),而 org-export-get-reference 先查 crossrefs、
         ;;    查不到才落到 org-export-new-reference —— 那条递增 advice 会被
         ;;    缓存绕过。内容没变时两边碰巧一致,一旦删掉或移动一个标题,
         ;;    P p 会复用一部分旧编号,和冷启动的 make build 排出的序列对不上,
         ;;    make check 报一片只有 #orgXXXXXXX 变化的 diff,根因极难看出来。
         :preparation-function
         ,(lambda (&rest _)
            (blog--check-src-languages)
            (when (file-directory-p org-publish-timestamp-directory)
              (delete-directory org-publish-timestamp-directory t))
            (setq org-publish-cache nil))
         :recursive nil

         :author "jamesarch"
         :language "zh-CN"
         :with-author t
         :with-email nil
         :with-creator nil
         :with-date t
         :section-numbers nil
         :with-sub-superscript {}
         ;; 目录深度和标题层级分开定:正文要认到 5 级,目录只列 3 级 ——
         ;; 跟着 headline-levels 走的话 block_app 的目录会从 9 项涨到 13 项,
         ;; 比正文第一屏还长。
         :with-toc 3
         ;; 默认只有 3 —— 超过的标题不会变成 <hN>,而是塞进 <li> 加个 <br>。
         ;; block_app.org 有 `**** string 模块' 这种四级标题,默认值下它们在
         ;; 页面上就是列表项,看着像 org 没解析。
         :headline-levels 5

         :html-doctype "html5"
         :html-html5-fancy t
         :html-validation-link nil
         ;; 不要 org 自带的那 190 行内联 <style>:它会和主题打特异性架,
         ;; 而且每页重复一遍。排版全部由 asserts/css/ 下的两张表接管。
         :html-head-include-default-style nil
         :html-head-include-scripts nil
         :html-head ,(concat
                      "<link rel=\"stylesheet\" href=\"./asserts/css/code.css\"/>\n"
                      "<link rel=\"stylesheet\" href=\"./asserts/css/theme.css\"/>\n"
                      ;; 深色底,让浏览器把表单控件与滚动条也切过去
                      "<meta name=\"color-scheme\" content=\"dark light\"/>")
         ;; 导航栏取代了原先的 UP | HOME:后者两个链接都指向 index,和导航重复,
         ;; 而且它是 org 硬塞在 #content 之外的一个 div,样式上够不着。
         :html-link-up ""
         :html-link-home ""
         ;; 导航由 site.el 按各页的 #+NAV 生成,当前页带 aria-current
         :html-preamble blog-preamble
         ;; 三个包裹层默认都是 <div>。换成 landmark 元素:屏幕阅读器可以按
         ;; "导航 / 主要内容 / 页脚"直接跳,配合 .skip-link 就不用一路 Tab
         ;; 穿过导航才够到正文。id 不变,CSS 选择器不受影响。
         :html-divs ((preamble "header" "preamble")
                     (content "main" "content")
                     (postamble "footer" "postamble"))
         ;; feed / sitemap / robots 挂在这里而不是只写在 blog-publish 里:
         ;; 走 org-export-dispatch 的 P p 时调的是 org-publish,不经过
         ;; blog-publish —— 那样页面更新了而 feed 停在上一版,要么事后被
         ;; make check 报一个看不懂的 diff,要么把过期 feed 推上线。
         ;; (P f 只发单个文件,不触发 completion-function,发布请用 P p。)
         :completion-function ,(lambda (&rest _) (blog-write-site-files)))
        ("blog" :components ("blog-pages"))))

;;; 构建期检查

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

;;;###autoload
(defun blog-publish ()
  "全量重建站点。

和 \\[org-export-dispatch] 的 P p 完全等价 —— 语言检查、清缓存、生成
feed/sitemap 全挂在项目的 preparation / completion 钩子上,所以这里只是
一层薄壳,方便终端 --funcall 和 M-x 调用。两条路不会分叉。"
  (interactive)
  (org-publish "blog" t)
  (when (called-interactively-p 'any)
    (message "博客已重建:%s" blog-root)))

(provide 'publish)
;;; publish.el ends here
