;;; publish.el --- 构建 jamesarch.github.io -*- lexical-binding: t; -*-

;; 用法: emacs -Q --batch -l publish.el --funcall blog-publish  (或 make build)
;;
;; 源文件在 org/,产物直接落到仓库根目录 —— 图片引用是 ./asserts/img/...,
;; 相对根目录解析,发布目录换成别处会全部断链。
;;
;; 设计目标是构建纯函数化:同一份 org 在任何机器上产出逐字节相同的 HTML
;; (只有嵌入的构建时间戳会变)。为此这里做了三件事 ——
;;   1. 零网络依赖:htmlize 与 CSS 都 vendored 进仓库,不连 MELPA、不连第三方主机;
;;   2. 锚点 ID 确定性递增,不再是随机数;
;;   3. 每次构建前清掉 org-publish 缓存,产物不依赖机器状态。

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

;; 配色。batch Emacs 没有图形帧,font-lock face 的 :foreground 全是 unspecified,
;; htmlize 于是输出不带颜色的 <span>;加载主题包也救不了,主题 spec 带
;; `((class color) (min-colors …))' 条件,tty 帧同样不匹配。
;; lib/doom-one-faces.el 是从本机 Doom 的 doom-themes 里把求值后的 GUI 配色导出来
;; 的一张表(见 scripts/gen-faces.el),用 face-override-spec 无条件套上。
;; 生成物进仓库,构建就不依赖谁装了 Doom —— 发布产物的配色是仓库的一部分。
(load (expand-file-name "lib/doom-one-faces.el" blog-root) nil t)

;; org-src 起 sh-mode 时方言取自 $SHELL(本机 zsh、CI 多半 bash/sh),而 sh/bash/zsh
;; 三套 keywords 与 builtins 表不同,同一段代码会着出不同的色。钉成 bash。
(setq sh-shell-file "/bin/bash")
(add-hook 'sh-mode-hook (lambda () (sh-set-shell "bash" nil nil)))

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
      org-export-with-toc t
      org-export-with-sub-superscripts '{}
      org-html-validation-link nil
      org-html-doctype "html5"
      org-html-html5-fancy t
      org-html-head-include-default-style t
      org-html-head-include-scripts nil
      org-html-htmlize-output-type 'inline-css
      ;; 排版主题。2023 年那批 HTML 引的是 gongzhitaao.org 的外链,
      ;; 已 vendored 到 asserts/css/org.css —— 第三方主机哪天没了页面不会变裸样式。
      org-html-head
      "<link rel=\"stylesheet\" type=\"text/css\" href=\"./asserts/css/org.css\"/>"
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
         :with-toc t
         :section-numbers nil
         :html-link-up "index.html"
         :html-link-home "index.html")
        ("blog" :components ("blog-pages"))))

(defun blog-publish ()
  "全量重建站点。"
  (when (file-directory-p org-publish-timestamp-directory)
    (delete-directory org-publish-timestamp-directory t))
  (setq org-publish-cache nil)
  (org-publish "blog" t))

(provide 'publish)
;;; publish.el ends here
