#!/bin/bash
# Fetches Phase-2 render runtimes into Sources/MotStar/Resources/web/ and
# produces katex-embed.css with all KaTeX fonts inlined as data URIs
# (WKWebView loadHTMLString pages cannot fetch local files).
set -euo pipefail
cd "$(dirname "$0")/.."

WEB="Sources/MotStar/Resources/web"
TMP="build/web-assets"
mkdir -p "$WEB" "$TMP"

HIGHLIGHT_VER="11.9.0"
KATEX_VER="0.16.11"
BASE_HLJS="https://cdn.jsdelivr.net/gh/highlightjs/cdn-release@${HIGHLIGHT_VER}/build"
BASE_KATEX="https://cdn.jsdelivr.net/npm/katex@${KATEX_VER}/dist"

echo "==> highlight.js ${HIGHLIGHT_VER}"
curl -sL --max-time 90 -o "$WEB/highlight.min.js" "${BASE_HLJS}/highlight.min.js"

echo "==> KaTeX ${KATEX_VER}"
curl -sL --max-time 90 -o "$TMP/katex.min.js" "${BASE_KATEX}/katex.min.js"
curl -sL --max-time 90 -o "$TMP/katex.min.css" "${BASE_KATEX}/katex.min.css"
cp "$TMP/katex.min.js" "$WEB/katex.min.js"

mkdir -p "$TMP/fonts"
FONTS=$(grep -oE "fonts/[A-Za-z0-9_.-]+\.(woff2|woff|ttf)" "$TMP/katex.min.css" | sort -u || true)
for font in $FONTS; do
    name=$(basename "$font")
    [ -f "$TMP/fonts/$name" ] || curl -sL --max-time 60 -o "$TMP/fonts/$name" "${BASE_KATEX}/$font"
done

python3 - "$TMP" "$WEB" <<'PY'
import base64, os, re, sys
tmp, web = sys.argv[1], sys.argv[2]
css_path = os.path.join(tmp, "katex.min.css")
with open(css_path, "r", encoding="utf-8") as f:
    css = f.read()

def repl(m):
    rel = m.group(1)
    name = os.path.basename(rel)
    path = os.path.join(tmp, "fonts", name)
    if os.path.exists(path):
        with open(path, "rb") as fh:
            b64 = base64.b64encode(fh.read()).decode("ascii")
        return f"url(data:font/woff2;base64,{b64})"
    return m.group(0)

css = re.sub(r"url\((fonts/[^)]+)\)", repl, css)
with open(os.path.join(web, "katex-embed.css"), "w", encoding="utf-8") as f:
    f.write(css)
print("katex-embed.css written")
PY

ls -la "$WEB"
