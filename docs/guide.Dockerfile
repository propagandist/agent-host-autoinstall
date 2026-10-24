# 詳細な設定手順書(docs/setup-guide.tex)を作るための TeX Live。just guide が使う。
# Ubuntu 26.04 の TeX Live 2025 に、日本語(LuaLaTeX + luatexja、原ノ味フォント)、tcolorbox、TikZ を入れる
FROM ubuntu:26.04
RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        texlive-luatex texlive-lang-japanese texlive-latex-recommended texlive-latex-extra \
        texlive-pictures texlive-fonts-recommended latexmk \
    && rm -rf /var/lib/apt/lists/*
# フォントの索引を先に作っておく(毎回の作成を速くし、root 以外の利用者でも使えるようにする)
ENV TEXMFVAR=/var/lib/texmf-var HOME=/tmp
RUN mkdir -p "$TEXMFVAR" && luaotfload-tool -u && chmod -R a+rwX "$TEXMFVAR"
WORKDIR /repo
