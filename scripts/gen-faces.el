;;; gen-faces.el --- 从本机 Doom 的 doom-themes 生成配色表 -*- lexical-binding: t; -*-

;; 用法: emacs -Q --batch -l scripts/gen-faces.el  (或 make faces)
;;
;; 为什么要生成,而不是构建时直接读 Doom:
;;   - batch Emacs 没有图形帧,font-lock face 的 :foreground 全是 unspecified,
;;     htmlize 于是输出没有颜色的 <span>。load-theme 也救不了 —— 主题的 spec 带
;;     `((class color) (min-colors 257))' 条件,tty 帧同样匹配不上。
;;     但 `theme-settings' 里存着已经求值完的三档 display 分支,取 257 那档就是
;;     GUI 下的真实效果,与作者在 Doom 里看到的、以及线上那批 HTML 完全一致。
;;   - 直接遍历 `doom-themes-base-faces' 不行:那里的值是未求值的调色板符号
;;     (`builtin'、`(doom-blend ...)'),只在 def-doom-theme 的 let 作用域里有绑定。
;;   - 生成成仓库内的文件,构建就不依赖用户装没装 Doom、装的哪个版本 —— 发布产物
;;     的配色是仓库的一部分,不该跟着谁的编辑器主题漂移。换主题就重跑 make faces。

(require 'cl-lib)

(defconst gen-faces-theme 'doom-one
  "取哪个主题的配色。原站点那批 HTML 的着色就来自它。")

(defconst gen-faces-output
  (expand-file-name "../lib/doom-one-faces.el"
                    (file-name-directory (or load-file-name buffer-file-name)))
  "生成结果的落地路径。")

(defun gen-faces--doom-themes-dir ()
  "定位本机 Doom 装的 doom-themes。找不到就报错,不静默降级成没有配色的构建。"
  (let ((dir (expand-file-name
              (format ".local/straight/build-%s/doom-themes" emacs-version)
              (or (getenv "EMACSDIR") "~/.config/emacs"))))
    (unless (file-directory-p dir)
      (error "找不到 doom-themes: %s。先在 Doom 里跑 doom sync,或用 EMACSDIR= 指定" dir))
    dir))

(defun gen-faces--gui-attributes (spec)
  "从主题 SPEC 里取图形帧那一档的属性 plist,取不到返回 nil。
SPEC 通常是 ((DISPLAY ATTRS) ...),Doom 按 257/256/16 色三档给,第一档即 GUI。
个别 face 的 spec 形状不规范,一律跳过而不是让整个生成过程炸掉。"
  (let (found)
    (dolist (entry spec found)
      (when (and (not found) (consp entry) (consp (cdr entry)))
        (let ((display (car entry))
              (attrs (cadr entry)))
          (when (and (listp attrs)
                     (or (eq display t)
                         (and (consp display) (member '(min-colors 257) display))))
            (setq found attrs)))))))

(defun gen-faces--collect ()
  "收集主题里所有 face 的 GUI 配色,返回按名字排序的 (FACE . ATTRS) 列表。"
  (let (result)
    ;; theme-settings 里混着 custom-theme-set-variables 留下的 `theme-value' 条目
    ;; (值可能是 vector 或 dotted cons)。pcase-dolist 只解构不校验,会把它们也当
    ;; face spec 处理;这里用 pcase 显式匹配 `theme-face' 把它们挡掉。
    (dolist (setting (get gen-faces-theme 'theme-settings))
      (pcase setting
        (`(theme-face ,face ,theme ,spec)
         (when (eq theme gen-faces-theme)
           (when-let* ((attrs (gen-faces--gui-attributes spec)))
             (push (cons face attrs) result))))))
    (sort result (lambda (a b) (string< (symbol-name (car a)) (symbol-name (car b)))))))

(defconst gen-faces-expected
  '((font-lock-keyword-face . "#51afef")
    (font-lock-builtin-face . "#c678dd")
    (font-lock-string-face  . "#98be65")
    (font-lock-comment-face . "#5B6268"))
  "从线上那批 HTML 里核对过的锚点值。
解析要靠形状去猜 spec 的结构,猜错时最坏的结果是静默丢色 —— 产物没了颜色而构建
照样是绿的。这几条对不上就直接失败。")

(defun gen-faces--assert (faces)
  "校验 FACES 里的锚点配色,对不上就报错。"
  (pcase-dolist (`(,face . ,expected) gen-faces-expected)
    (let ((got (plist-get (cdr (assq face faces)) :foreground)))
      (unless (equal got expected)
        (error "%s 的前景色是 %s,期望 %s —— 主题或解析逻辑变了,先核对再落盘"
               face got expected)))))

(let ((dir (gen-faces--doom-themes-dir)))
  (add-to-list 'load-path dir)
  (add-to-list 'custom-theme-load-path dir)
  (require 'doom-themes)
  (load-theme gen-faces-theme t)
  (let ((faces (gen-faces--collect)))
    (gen-faces--assert faces)
    (with-temp-file gen-faces-output
      (insert ";;; doom-one-faces.el --- doom-one 配色表 -*- lexical-binding: t; -*-\n"
              ";;\n"
              ";; 由 `make faces' 从本机 Doom 的 doom-themes 生成,不要手改。\n"
              ";; 生成脚本与背景说明见 scripts/gen-faces.el。\n"
              (format ";; 主题: %s   Emacs: %s   face 数: %d\n"
                      gen-faces-theme emacs-version (length faces))
              "\n"
              "(defconst blog-doom-one-faces\n  '(")
      (let ((first t))
        (pcase-dolist (`(,face . ,attrs) faces)
          (if first (setq first nil) (insert "\n    "))
          (prin1 (cons face attrs) (current-buffer))))
      (insert "))\n\n")
      (insert
       ";; 用 face-spec-set 而不是 set-face-attribute,三个理由:\n"
       ";;   1. 这张表覆盖 1200+ face,其中大多数(cider-*、jdee-* …)对应的包本机没装,\n"
       ";;      set-face-attribute 撞上未定义的 face 会直接报错;\n"
       ";;   2. `(t ATTRS)' 不带 display 条件,batch 的 tty 帧下必然命中 —— 正是\n"
       ";;      主题自带 spec 在这里失效的原因;\n"
       ";;   3. face-override-spec 的优先级高于 defface,org 在 fontify 时才 autoload\n"
       ";;      sh-script / conf-mode,它们的 defface 不会把这里的值盖回去。\n"
       ";; :weight/:slant/:underline 显式置空:默认 face 靠字形而非颜色区分,\n"
       ";; 主题只覆盖它显式声明的属性,不重置就会有多余的 bold/italic 混进产物。\n"
       "(pcase-dolist (`(,face . ,attrs) blog-doom-one-faces)\n"
       "  (unless (facep face) (make-empty-face face))\n"
       "  (face-spec-set face `((t ,(append '(:weight normal :slant normal\n"
       "                                      :underline nil :box nil)\n"
       "                                    attrs)))\n"
       "                 'face-override-spec))\n"
       "\n"
       "(provide 'doom-one-faces)\n"
       ";;; doom-one-faces.el ends here\n"))
    (message "写入 %s (%d 个 face)" gen-faces-output (length faces))))

;;; gen-faces.el ends here
