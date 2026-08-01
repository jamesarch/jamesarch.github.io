EMACS ?= emacs
PORT  ?= 8000

# 产物逐字节可复现的前提是导出器版本固定 —— 换个 Emacs/Org 版本,内嵌 CSS 与标签
# 结构就会变,check 的零 diff 会全线失败而看不出原因。GUI Emacs 的 PATH 常和终端
# 不同源(本机非交互 zsh 里就找不到 emacs),不断言的话会静默用到另一个版本。
EMACS_VERSION := 30.2

.PHONY: build check links serve clean faces emacs-version

emacs-version:
	@v=$$($(EMACS) --batch --eval '(princ emacs-version)' 2>/dev/null); \
	if [ "$$v" != "$(EMACS_VERSION)" ]; then \
	  echo "构建要求 Emacs $(EMACS_VERSION),当前 $(EMACS) 是 '$$v'。"; \
	  echo "  · PATH 里是别的版本 -> make EMACS=/path/to/emacs <目标>"; \
	  echo "  · Emacs 升级了     -> make EMACS_VERSION=$$v build 越过本断言,"; \
	  echo "                        git diff 看清产物差异,确认后回填 EMACS_VERSION 并提交新 HTML"; \
	  exit 1; \
	fi

## 重建全部 HTML。产物直接落在仓库根,和提交进 git 的是同一批文件。
build: emacs-version
	$(EMACS) -Q --batch -l publish.el --funcall blog-publish

## 校验提交的 HTML 与 org 源同步。构建是确定性的,所以这里可以硬要求零 diff。
## 两道闸缺一不可:git diff 看不见 untracked 文件,只查它的话,新增一篇文章却忘了
## 提交 HTML 时 CI 会绿灯放行,而 Pages 上那页是 404 —— 恰好是最常走的路径。
check: build
	@untracked=$$(git ls-files --others --exclude-standard -- '*.html'); \
	if [ -n "$$untracked" ]; then \
	  echo "有构建出来但没提交的 HTML: $$untracked"; exit 1; \
	fi
	@git diff --exit-code -- '*.html' \
	  || { echo "HTML 与 org 源不同步,请提交 make build 的产物"; exit 1; }
	@echo "HTML 与 org 源一致"

## 检查站内引用没有断链。CSS/图片路径改动只在浏览器里才看得出来,这里兜住。
links: build
	@python3 scripts/check-links.py

## 从本机 Doom 的 doom-themes 重新导出 doom-one 配色表。换主题或升级 Doom 后再跑,
## 平时不需要 —— 生成物已提交,构建不依赖 Doom 是否安装。
faces: emacs-version
	$(EMACS) -Q --batch -l scripts/gen-faces.el

## 本地预览。必须用 HTTP 起,file:// 下 ./asserts/ 相对路径行为和线上不一致。
serve: build
	@echo "http://localhost:$(PORT)/"
	@python3 -m http.server $(PORT)

## 只清构建缓存。HTML 是提交进仓库的发布产物,不在这里删。
clean:
	rm -rf .cache
