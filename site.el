;;; site.el --- 站点级元数据:导航、feed、sitemap、社交预览 -*- lexical-binding: t; -*-

;; 由 publish.el 加载。这里管的是"页面之外"的东西:导航栏、Atom feed、
;; sitemap.xml、每页的 description 与 Open Graph 标签。
;;
;; 一条贯穿的原则:**数据留在 org 源里,不在这里维护清单**。
;; 哪些页面进导航,由那个页面自己的 `#+NAV: 序号 标签' 决定;标题、日期、摘要
;; 同理。手写一份页面列表在这里,新增页面忘了加就会静默漏掉 —— 和之前
;; theme.css 里那 22 条语言白名单是同一个毛病。
;;
;; 另一条:生成物里不许出现构建时刻。feed 的 <updated> 和 sitemap 的 <lastmod>
;; 都取各文章 #+DATE 的最大值,纯函数、跨机器一致 —— 否则 make check 的零 diff
;; 当场失效,和当初删掉 org-export-time-stamp-file 是同一个坑。

(require 'cl-lib)
(require 'subr-x)

;;; 站点常量

(defconst blog-base-url "https://jamesarch.github.io"
  "站点的绝对地址,feed / sitemap / og:url 都从这里拼。

CNAME 里写的是 lefix.me,该域名已过期 —— 只要那个文件还在,Pages 就会把
github.io 301 过去,两个地址都打不开。这里先指向 github.io:删掉 CNAME
后它立刻是对的;将来续期或换域名,改这一处即可。")

(defconst blog-site-title "Jamesarch")
(defconst blog-site-description "网络、流量分析与运维笔记。")
(defconst blog-author "jamesarch")

;;; org 源的元数据

(defconst blog--keyword-re
  "^[ \t]*#\\+\\(TITLE\\|DATE\\|DESCRIPTION\\|NAV\\|EXCLUDE\\):[ \t]*\\(.*?\\)[ \t]*$"
  "抓 org 文件头部关键字。用正则而不是 `org-collect-keywords':
后者要先把 buffer 切成 org-mode,batch 下为几个文件起全套 major-mode 不划算。")

(defun blog--read-keywords (file)
  "读 FILE 的头部关键字,返回 alist。只扫到第一个标题行为止。"
  (with-temp-buffer
    (insert-file-contents file)
    (goto-char (point-min))
    (let (result)
      (while (and (not (eobp)) (not (looking-at "^\\*+ ")))
        (when (looking-at blog--keyword-re)
          (push (cons (upcase (match-string 1)) (match-string 2)) result))
        (forward-line 1))
      (nreverse result))))

(defun blog--org-files ()
  (sort (directory-files (expand-file-name "org" blog-root) t "\\.org\\'")
        #'string<))

(defun blog-pages ()
  "扫 org/ 收集每页的元数据,返回 plist 列表。

:html 是产物文件名,:date 形如 \"2022-05-05\",:nav-order 为 nil 表示不进导航。
排序按 :date 倒序,同日期按文件名 —— 纯函数,不看 mtime。"
  (let (pages)
    (dolist (file (blog--org-files))
      (let* ((kw (blog--read-keywords file))
             (nav (cdr (assoc "NAV" kw)))
             (base (file-name-base file)))
        (push (list :file file
                    :base base
                    :html (concat base ".html")
                    :title (or (cdr (assoc "TITLE" kw)) base)
                    :date (cdr (assoc "DATE" kw))
                    :description (cdr (assoc "DESCRIPTION" kw))
                    ;; #+NAV: 10 文章  ->  序号 10、标签"文章"
                    :nav-order (and nav (string-match "\\`\\([0-9]+\\)[ \t]+" nav)
                                    (string-to-number (match-string 1 nav)))
                    :nav-label (and nav (if (string-match "\\`[0-9]+[ \t]+\\(.*\\)\\'" nav)
                                            (match-string 1 nav)
                                          nav))
                    :exclude (cdr (assoc "EXCLUDE" kw)))
              pages)))
    (sort (nreverse pages)
          (lambda (a b)
            (let ((da (or (plist-get a :date) "")) (db (or (plist-get b :date) "")))
              (if (string= da db)
                  (string< (plist-get a :base) (plist-get b :base))
                (string> da db)))))))

(defun blog-articles ()
  "只要文章:有 #+DATE、不进导航、也没被 #+EXCLUDE 标记的页面。"
  (cl-remove-if (lambda (p) (or (null (plist-get p :date))
                                (plist-get p :nav-order)
                                (plist-get p :exclude)))
                (blog-pages)))

(defun blog-check-page-roles ()
  "每个 org 文件都得表明自己是什么,否则报错。

页面的归属完全由头部关键字决定:有 #+DATE 是文章(进首页列表和 feed)、
有 #+NAV 是导航页、有 #+EXCLUDE 是有意不列出的(404 之类)。
三样都没有的话它照样导出成 HTML、照样进 sitemap,却**不进首页列表也不进
feed** —— 而 make verify 只查断链和 token class、make check 只查零 diff,
两道闸都是绿的。新写一篇文章忘了写 #+DATE 正是最高频的翻车路径,
所以在这里拦掉。"
  (let (bad)
    (dolist (p (blog-pages))
      (unless (or (plist-get p :date) (plist-get p :nav-order) (plist-get p :exclude))
        (push (format "  %s" (file-name-nondirectory (plist-get p :file))) bad)))
    (when bad
      (error "这些页面没有表明身份,会导出但不出现在首页列表和 feed 里:\n%s\n\n三选一:\n  · 文章 -> 加 #+DATE: YYYY-MM-DD\n  · 导航页 -> 加 #+NAV: 序号 标签\n  · 有意不列出(如 404) -> 加 #+EXCLUDE: 原因"
             (mapconcat #'identity (nreverse bad) "\n")))))

(defun blog-latest-date ()
  "全站最新的文章日期。feed 的 <updated> 用它,不用 current-time。"
  (or (car (sort (delq nil (mapcar (lambda (p) (plist-get p :date)) (blog-pages)))
                 #'string>))
      "1970-01-01"))

;;; 工具

(defun blog--escape (s)
  "XML/HTML 文本转义。"
  (let ((s (or s "")))
    (dolist (pair '(("&" . "&amp;") ("<" . "&lt;") (">" . "&gt;") ("\"" . "&quot;")) s)
      (setq s (replace-regexp-in-string (regexp-quote (car pair)) (cdr pair) s t t)))))

(defun blog--rfc3339 (date)
  "把 \"2022-05-05\" 变成 Atom 要的 RFC 3339。固定 00:00:00Z —— 文章只精确到天,
补一个假的时分秒不会更真实,但必须是常量,否则产物不可复现。"
  (concat (or date "1970-01-01") "T00:00:00Z"))

(defun blog--url (path)
  (concat blog-base-url "/" path))

(defun blog--current-base (info)
  "当前正在导出的页面的文件名主干。"
  (let ((file (plist-get info :input-file)))
    (and file (file-name-base file))))

;;; 导航栏

;; 平铺、无下拉、无汉堡 —— 隐藏式菜单会让任务完成率下降(NN/g),而这个站总共
;; 也就三五个入口,没有藏起来的理由。当前页用 aria-current 标出,既是无障碍
;; 语义也是样式钩子。
(defun blog--nav-html (current-base)
  "生成导航栏 HTML。CURRENT-BASE 是当前页的文件名主干。"
  (let ((items (sort (cl-remove-if-not (lambda (p) (plist-get p :nav-order)) (blog-pages))
                     (lambda (a b) (< (plist-get a :nav-order) (plist-get b :nav-order))))))
    (concat
     "<a class=\"skip-link\" href=\"#content\">跳到正文</a>\n"
     "<nav id=\"site-nav\" aria-label=\"站点导航\">\n"
     (format "<a class=\"brand\" href=\"%s\">%s</a>\n"
             (if (equal current-base "index") "#content" "index.html")
             (blog--escape blog-site-title))
     "<ul>\n"
     (mapconcat
      (lambda (p)
        (let ((here (equal (plist-get p :base) current-base)))
          (format "<li><a href=\"%s\"%s>%s</a></li>\n"
                  (plist-get p :html)
                  (if here " aria-current=\"page\"" "")
                  (blog--escape (plist-get p :nav-label)))))
      items "")
     "<li><a href=\"atom.xml\">RSS</a></li>\n"
     "</ul>\n</nav>\n")))

(defun blog-preamble (info)
  (blog--nav-html (blog--current-base info)))

;;; 每页的 description 与社交预览

(defun blog--head-meta (info)
  "当前页的 description / Open Graph / canonical。"
  (let* ((base (blog--current-base info))
         (page (cl-find base (blog-pages)
                        :key (lambda (p) (plist-get p :base)) :test #'equal))
         (title (or (plist-get page :title) blog-site-title))
         (desc (or (plist-get page :description)
                   (and (null (plist-get page :date)) blog-site-description)
                   ;; 文章没写 #+DESCRIPTION 就退回站点描述加标题,
                   ;; 总比让搜索引擎自己截一段正文强。
                   (format "%s —— %s" title blog-site-description)))
         (url (blog--url (or (plist-get page :html) "index.html"))))
    (concat
     ;; 页面自己写了 #+DESCRIPTION 时 ox-html 已经输出过一条 meta description,
     ;; 这里只补没写的那些,否则每页两条重复。og:description 不受影响,
     ;; ox-html 不管 Open Graph。
     (unless (plist-get page :description)
       (format "<meta name=\"description\" content=\"%s\"/>\n" (blog--escape desc)))
     (format "<link rel=\"canonical\" href=\"%s\"/>\n" (blog--escape url))
     (format "<meta property=\"og:type\" content=\"%s\"/>\n"
             (if (plist-get page :date) "article" "website"))
     (format "<meta property=\"og:title\" content=\"%s\"/>\n" (blog--escape title))
     (format "<meta property=\"og:description\" content=\"%s\"/>\n" (blog--escape desc))
     (format "<meta property=\"og:url\" content=\"%s\"/>\n" (blog--escape url))
     (format "<meta property=\"og:site_name\" content=\"%s\"/>\n" (blog--escape blog-site-title))
     (when-let* ((date (plist-get page :date)))
       (format "<meta property=\"article:published_time\" content=\"%s\"/>\n"
               (blog--rfc3339 date)))
     "<meta name=\"twitter:card\" content=\"summary\"/>\n"
     (format "<link rel=\"alternate\" type=\"application/atom+xml\" title=\"%s\" href=\"%s\"/>\n"
             (blog--escape blog-site-title) (blog--url "atom.xml"))
     "<link rel=\"icon\" href=\"./asserts/img/favicon.svg\" type=\"image/svg+xml\"/>\n")))

;;; 文章列表

(defun blog--article-list-html ()
  "首页的文章列表:日期 + 标题,按日期倒序。"
  (concat
   "<ul class=\"post-list\">\n"
   (mapconcat
    (lambda (p)
      (format "<li><time datetime=\"%s\">%s</time><a href=\"%s\">%s</a></li>\n"
              (plist-get p :date) (plist-get p :date)
              (plist-get p :html) (blog--escape (plist-get p :title))))
    (blog-articles) "")
   "</ul>\n"))

;;; 产物后处理

(defconst blog--article-list-marker "<!--ARTICLE-LIST-->")

(defun blog--absolutize (html)
  "把站内相对链接改成根绝对路径。

只给 404 页用。GitHub Pages 对任意深度的不存在路径都返回 404.html 的内容,
但浏览器按**请求路径**解析相对链接 —— 访客打开 /foo/bar 时,页面里的
./asserts/css/theme.css 会去要 /foo/asserts/css/theme.css,导航也全指到 /foo/ 下。
结果是裸样式加一排死链。本地 http.server 直接开 /404.html 看不出来(深度恰好是 0),
check-output.py 按仓库根解析也全绿。"
  (let ((html (replace-regexp-in-string "\\(href\\|src\\)=\"\\./" "\\1=\"/" html t)))
    (replace-regexp-in-string
     "\\(href\\)=\"\\([a-z0-9_-]+\\.\\(?:html\\|xml\\)\\)\"" "\\1=\"/\\2\"" html t)))

(defun blog-finalize (html backend info)
  "产物的最后一道加工:注入 head、展开文章列表、404 的路径绝对化。

`org-html-head' 是一个全站共用的字符串,塞不进随页面变化的内容;
`#+HTML_HEAD_EXTRA:' 又要每篇手写。用 final-output filter 统一生成。"
  (if (not (org-export-derived-backend-p backend 'html))
      html
    (let ((base (blog--current-base info)))
      (when (string-match-p "</head>" html)
        (setq html (replace-regexp-in-string
                    "</head>" (concat (blog--head-meta info) "</head>") html t t)))
      (when (string-match-p blog--article-list-marker html)
        (setq html (replace-regexp-in-string
                    (regexp-quote blog--article-list-marker)
                    (blog--article-list-html) html t t)))
      (when (equal base "404")
        (setq html (blog--absolutize html)))
      html)))

;;; Atom feed

(defconst blog-feed-limit 20
  "feed 里最多放几条。

Atom 惯例是只给最近若干条,不是全量 —— 全量的话文章涨到几百篇后 atom.xml
会变成几百 KB,每个订阅端每次轮询都要传一遍。历史文章由 sitemap.xml 和
首页列表负责被发现,feed 的职责是「最近更新了什么」。")

(defun blog-write-feed ()
  "生成 atom.xml。"
  (let* ((articles (seq-take (blog-articles) blog-feed-limit))
         (updated (blog--rfc3339 (blog-latest-date)))
         (path (expand-file-name "atom.xml" blog-root)))
    (with-temp-file path
      (insert
       "<?xml version=\"1.0\" encoding=\"utf-8\"?>\n"
       "<feed xmlns=\"http://www.w3.org/2005/Atom\" xml:lang=\"zh-CN\">\n"
       (format "  <title>%s</title>\n" (blog--escape blog-site-title))
       (format "  <subtitle>%s</subtitle>\n" (blog--escape blog-site-description))
       (format "  <link href=\"%s\" rel=\"self\" type=\"application/atom+xml\"/>\n"
               (blog--url "atom.xml"))
       (format "  <link href=\"%s/\" rel=\"alternate\" type=\"text/html\"/>\n" blog-base-url)
       (format "  <id>%s/</id>\n" blog-base-url)
       (format "  <updated>%s</updated>\n" updated)
       (format "  <author><name>%s</name></author>\n" (blog--escape blog-author))
       (mapconcat
        (lambda (p)
          (let ((url (blog--url (plist-get p :html))))
            (concat
             "  <entry>\n"
             (format "    <title>%s</title>\n" (blog--escape (plist-get p :title)))
             (format "    <link href=\"%s\" rel=\"alternate\" type=\"text/html\"/>\n" url)
             (format "    <id>%s</id>\n" url)
             (format "    <published>%s</published>\n" (blog--rfc3339 (plist-get p :date)))
             (format "    <updated>%s</updated>\n" (blog--rfc3339 (plist-get p :date)))
             (when-let* ((d (plist-get p :description)))
               (format "    <summary>%s</summary>\n" (blog--escape d)))
             "  </entry>\n")))
        articles "")
       "</feed>\n"))
    path))

;;; sitemap.xml / robots.txt

(defun blog-write-sitemap ()
  (let ((path (expand-file-name "sitemap.xml" blog-root)))
    (with-temp-file path
      (insert
       "<?xml version=\"1.0\" encoding=\"utf-8\"?>\n"
       "<urlset xmlns=\"http://www.sitemaps.org/schemas/sitemap/0.9\">\n"
       (mapconcat
        (lambda (p)
          (concat "  <url>\n"
                  (format "    <loc>%s</loc>\n" (blog--url (plist-get p :html)))
                  ;; lastmod 取 #+DATE;没有日期的页面(about)用全站最新日期,
                  ;; 总之不能是 current-time —— 那会让每次构建的产物都不一样。
                  (format "    <lastmod>%s</lastmod>\n"
                          (or (plist-get p :date) (blog-latest-date)))
                  "  </url>\n"))
        ;; #+EXCLUDE 标记的页面不交给搜索引擎 —— 404 是错误页,不是内容页。
        ;; 用标记而不是写死文件名:将来多一个这类页面时不用回来改代码。
        (cl-remove-if (lambda (p) (plist-get p :exclude)) (blog-pages))
        "")
       "</urlset>\n"))
    path))

(defun blog-write-robots ()
  (let ((path (expand-file-name "robots.txt" blog-root)))
    (with-temp-file path
      (insert "User-agent: *\nAllow: /\n\n"
              (format "Sitemap: %s\n" (blog--url "sitemap.xml"))))
    path))

(defun blog-write-site-files ()
  "生成所有非 org 派生的站点文件。"
  (blog-write-feed)
  (blog-write-sitemap)
  (blog-write-robots))

(provide 'site)
;;; site.el ends here
