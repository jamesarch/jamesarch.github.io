;;; gen-code-css.el --- 从 Doom 主题生成代码高亮样式表 -*- lexical-binding: t; -*-

;; 用法: emacs -Q --batch -l scripts/gen-code-css.el  (或 make code-css)
;;
;; 产出 asserts/css/code.css:htmlize 在 `css' 输出模式下给每个 token 打
;; `.org-keyword' 这类 class,颜色由这张表提供。深色取 doom-one、浅色取
;; doom-one-light,套在 prefers-color-scheme 里 —— 这是 inline-css 模式做不到的
;; (内联 style 优先级最高,双色只能靠满屏 !important 硬顶)。
;;
;; class 名一律由 `htmlize-face-css-name' 算,不手推:htmlize 的规则是剥
;; `font-lock-' 前缀、剥 `-face' 后缀、非字母数字换 X、再拼前缀,所以
;; `font-lock-keyword-face' → `.org-keyword' 而 `sh-quoted-exec' →
;; `.org-sh-quoted-exec'。推错就是满页死规则、代码块变回黑白,而构建照样绿。
;;
;; 两处不能照搬主题的地方:
;;   · `:inherit'。doom-one 里 `font-lock-comment-delimiter-face' 只写
;;     `(:inherit font-lock-comment-face)',没有自己的 :foreground。只收有
;;     :foreground 的 face 会把它漏掉,于是注释的 `#' 和注释正文不同色。
;;   · 对比度。编辑器配色搬到网页会掉可读性:注释 #5B6268 落在 #282c34 上只有
;;     2.26:1,远低于 WCAG 的 3:1。这不是"线上一直这样" —— 2023 那批 HTML 是
;;     orgcss 的白底,同一个灰有 6.19:1。给代码块上深色底是设计改动,得自己把
;;     账补上,所以这里按 3:1 兜底提亮。
;;
;; 为什么要生成而不是构建时直接读 Doom:
;;   - 直接遍历 `doom-themes-base-faces' 不行,那里是未求值的调色板符号
;;     (`builtin'、`(doom-blend ...)'),只在 def-doom-theme 的 let 作用域有绑定;
;;   - `load-theme' 之后 `face-attribute' 也不行,batch 没有图形帧,主题 spec 带
;;     `((class color) (min-colors 257))' 条件,tty 帧匹配不上,全返回 unspecified;
;;   - `org-html-htmlize-generate-css' 同理,它读的也是 face-attribute。
;;   已求值的三档 display 分支存在 `theme-settings' 里,取 257 那档就是 GUI 下的
;;   真实效果。生成物进仓库,构建就不依赖谁装了 Doom;换主题重跑本脚本即可。

(require 'cl-lib)
(require 'subr-x)

(defconst gen-css-themes '((dark . doom-one) (light . doom-one-light))
  "深色/浅色各取哪个主题。")

(defconst gen-css-min-contrast 3.0
  "token 色与代码块底色的对比度下限(WCAG AA 对非正文文本的要求)。
不用 4.5 是因为注释本来就该是次要信息,提到正文强度会压掉层次。")

(defconst gen-css-root
  (expand-file-name ".." (file-name-directory (or load-file-name buffer-file-name)))
  "仓库根目录。")

(defconst gen-css-output (expand-file-name "asserts/css/code.css" gen-css-root))

(defconst gen-css-expected
  '((doom-one       . ((font-lock-keyword-face . "#51afef")
                       (font-lock-builtin-face . "#c678dd")
                       (font-lock-string-face  . "#98be65")))
    (doom-one-light . ((font-lock-keyword-face . "#e45649")
                       (font-lock-builtin-face . "#a626a4")
                       (font-lock-string-face  . "#50a14f"))))
  "锚点值,对不上就报错。
解析要靠形状去猜 spec 结构,猜错时最坏的结果是静默丢色 —— 产物没了颜色而构建
照样是绿的。doom-one 那几条是从 2023 年线上 HTML 里核对过的。
这里只放对比度足够、不会被提亮改写的颜色。")

;;; 颜色

(defun gen-css--rgb (hex)
  "把 \"#rrggbb\" 拆成 0..1 的三元组。"
  (mapcar (lambda (i) (/ (string-to-number (substring hex i (+ i 2)) 16) 255.0))
          '(1 3 5)))

(defun gen-css--hex (rgb)
  (apply #'format "#%02x%02x%02x"
         (mapcar (lambda (c) (round (* 255 (max 0.0 (min 1.0 c))))) rgb)))

(defun gen-css--luminance (hex)
  "WCAG 相对亮度。"
  (cl-loop for c in (gen-css--rgb hex)
           for w in '(0.2126 0.7152 0.0722)
           sum (* w (if (<= c 0.03928)
                        (/ c 12.92)
                      (expt (/ (+ c 0.055) 1.055) 2.4)))))

(defun gen-css--contrast (a b)
  (let ((la (gen-css--luminance a))
        (lb (gen-css--luminance b)))
    (/ (+ (max la lb) 0.05) (+ (min la lb) 0.05))))

(defun gen-css--lift (fg bg)
  "把 FG 朝远离 BG 的方向推,直到与 BG 的对比度达到 `gen-css-min-contrast'。
返回 (HEX . ADJUSTED-P)。推不动就返回能取到的极值。"
  (if (>= (gen-css--contrast fg bg) gen-css-min-contrast)
      (cons fg nil)
    (let* ((target (if (< (gen-css--luminance bg) 0.5) '(1.0 1.0 1.0) '(0.0 0.0 0.0)))
           (src (gen-css--rgb fg))
           (best (gen-css--hex target)))
      (cl-loop for step from 1 to 50
               for ratio = (/ step 50.0)
               for mixed = (gen-css--hex
                            (cl-mapcar (lambda (s d) (+ s (* ratio (- d s)))) src target))
               when (>= (gen-css--contrast mixed bg) gen-css-min-contrast)
               return (cons mixed t)
               finally return (cons best t)))))

;;; 主题解析

(defun gen-css--gui-attributes (spec)
  "从主题 SPEC 里取图形帧那一档的属性 plist,取不到返回 nil。"
  (condition-case nil
      (let (found)
        (dolist (entry spec found)
          (when (and (not found) (consp entry) (consp (cdr entry)))
            (let ((display (car entry))
                  (attrs (cadr entry)))
              (when (and (listp attrs)
                         (or (eq display t)
                             (and (consp display)
                                  (member '(min-colors 257) display))))
                (setq found attrs))))))
    (error nil)))

(defun gen-css--face-table (theme)
  "THEME 里全部 face 的属性表 (FACE . ATTRS),用于解析 :inherit 链。"
  (let (table)
    ;; theme-settings 里混着 custom-theme-set-variables 留下的 `theme-value' 条目
    ;; (值可能是 vector 或 dotted cons)。pcase-dolist 只解构不校验,会把它们也当
    ;; face spec 处理;这里用 pcase 显式匹配 `theme-face' 把它们挡掉。
    (dolist (setting (get theme 'theme-settings) table)
      (pcase setting
        (`(theme-face ,face ,th ,spec)
         (when (eq th theme)
           (when-let* ((attrs (gen-css--gui-attributes spec)))
             (push (cons face attrs) table))))))))

(defun gen-css--attr (face key table &optional depth)
  "取 FACE 的 KEY 属性,顺着 :inherit 往上找。TABLE 是 `gen-css--face-table' 的结果。"
  (when (and (< (or depth 0) 8) face)
    (let* ((attrs (cdr (assq face table)))
           (own (plist-get attrs key)))
      (if (and own (not (eq own 'unspecified)))
          own
        (let ((parent (plist-get attrs :inherit)))
          ;; :inherit 可以是符号、'(quote sym) 或 face 列表
          (setq parent (cond ((and (consp parent) (eq (car parent) 'quote)) (cadr parent))
                             (t parent)))
          (cond
           ((symbolp parent) (gen-css--attr parent key table (1+ (or depth 0))))
           ((consp parent)
            (cl-loop for p in parent
                     for v = (gen-css--attr p key table (1+ (or depth 0)))
                     when v return v))))))))

(defun gen-css--tokens (table)
  "挑出要写进样式表的 face:font-lock-* 全家。
主题定义了 1200+ 个 face,其余是 UI 组件的,进不了代码块,全导出只会让样式表
白白胖上两倍。"
  (sort (cl-remove-if-not
         (lambda (entry) (string-prefix-p "font-lock-" (symbol-name (car entry))))
         table)
        (lambda (a b) (string< (symbol-name (car a)) (symbol-name (car b))))))

(defun gen-css--assert (theme table)
  "校验 THEME 的锚点配色。"
  (pcase-dolist (`(,face . ,expected) (cdr (assq theme gen-css-expected)))
    (let ((got (gen-css--attr face :foreground table)))
      (unless (equal got expected)
        (error "%s / %s 的前景色是 %s,期望 %s —— 主题或解析逻辑变了"
               theme face got expected)))))

(defun gen-css--rules (table bg indent)
  "渲染 CSS 规则。返回 (TEXT . ADJUSTED),ADJUSTED 是被提亮过的 face 名列表。"
  (let (out adjusted)
    (pcase-dolist (`(,face . ,_) (gen-css--tokens table))
      (let ((fg (gen-css--attr face :foreground table))
            (weight (gen-css--attr face :weight table))
            (slant (gen-css--attr face :slant table))
            decls)
        (when (stringp fg)
          (pcase-let ((`(,color . ,changed) (gen-css--lift fg bg)))
            (when changed (push (symbol-name face) adjusted))
            (push (format "color:%s" color) decls)))
        (when (memq weight '(bold semi-bold)) (push "font-weight:600" decls))
        (when (memq slant '(italic oblique)) (push "font-style:italic" decls))
        (when decls
          (push (format "%s.%s{%s}\n" indent (htmlize-face-css-name face)
                        (mapconcat #'identity (nreverse decls) ";"))
                out))))
    (cons (apply #'concat (nreverse out)) (nreverse adjusted))))

;;; 生成

(let ((dir (expand-file-name
            (format ".local/straight/build-%s/doom-themes" emacs-version)
            (or (getenv "EMACSDIR") "~/.config/emacs"))))
  (unless (file-directory-p dir)
    (error "找不到 doom-themes: %s。先在 Doom 里跑 doom sync,或用 EMACSDIR= 指定" dir))
  (add-to-list 'load-path dir)
  (add-to-list 'custom-theme-load-path dir))
(require 'doom-themes)
(load (expand-file-name "lib/htmlize.el" gen-css-root) nil t)
(setq htmlize-css-name-prefix "org-")

(let (blocks)
  (pcase-dolist (`(,scheme . ,theme) gen-css-themes)
    (mapc #'disable-theme custom-enabled-themes)
    (load-theme theme t)
    (let* ((table (gen-css--face-table theme))
           (bg (or (gen-css--attr 'default :background table) "#ffffff"))
           (fg (or (gen-css--attr 'default :foreground table) "#000000")))
      (gen-css--assert theme table)
      (pcase-let ((`(,text . ,adjusted) (gen-css--rules table bg "  ")))
        (push (list scheme theme bg fg text adjusted) blocks))))
  (setq blocks (nreverse blocks))
  (with-temp-file gen-css-output
    (insert "/* code.css --- 代码块语法高亮\n"
            " *\n"
            " * 由 `make code-css' 从本机 Doom 的 doom-themes 生成,不要手改。\n"
            " * 生成脚本与背景说明见 scripts/gen-code-css.el。\n"
            (format " * 深色 %s / 浅色 %s   Emacs %s   对比度下限 %.1f:1\n"
                    (cdr (assq 'dark gen-css-themes))
                    (cdr (assq 'light gen-css-themes))
                    emacs-version gen-css-min-contrast)
            " */\n")
    (pcase-dolist (`(,scheme ,theme ,bg ,fg ,text ,adjusted) blocks)
      (insert (format "\n/* %s —— 底色 %s */\n" theme bg))
      (when adjusted
        (insert (format "/* 提亮至 %.1f:1: %s */\n"
                        gen-css-min-contrast
                        (mapconcat (lambda (f) (string-remove-suffix
                                                "-face" (string-remove-prefix
                                                         "font-lock-" f)))
                                   adjusted " "))))
      (pcase scheme
        ('dark (insert (format ":root{--code-bg:%s;--code-fg:%s}\n" bg fg)
                       (replace-regexp-in-string "^  " "" text)))
        ('light (insert "@media (prefers-color-scheme: light) {\n"
                        (format "  :root{--code-bg:%s;--code-fg:%s}\n" bg fg)
                        text
                        "}\n"))))
    (message "写入 %s" gen-css-output)))

;;; gen-code-css.el ends here
