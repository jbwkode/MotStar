// MotStar phase-2 preview enhancements, run after libraries load:
// callouts, Mermaid, inline maths (KaTeX), text linkify + emoji,
// fenced maths, then code highlighting. EMOJI_MAP is injected beforehand.
(function () {
  'use strict';
  function ready(fn) {
    if (document.readyState !== 'loading') { fn(); }
    else { document.addEventListener('DOMContentLoaded', fn); }
  }
  ready(function () {
    try { renderCallouts(); } catch (e) {}
    try { renderMermaid(); } catch (e) {}
    try { transformText(); } catch (e) {}
    try { markTags(); } catch (e) {}
    try { renderMathFences(); renderInlineMath(); } catch (e) {}
    try { highlightCode(); } catch (e) {}
    wireWikilinkClicks();
  });

  // 0) Obsidian-style wikilink clicks → open the file in MotStar
  function wireWikilinkClicks() {
    document.addEventListener('click', function (e) {
      var el = e.target && e.target.closest ? e.target.closest('a.motstar-wikilink') : null;
      if (!el) return;
      e.preventDefault();
      var path = el.getAttribute('data-path');
      if (path && window.webkit && window.webkit.messageHandlers &&
          window.webkit.messageHandlers.motstarOpen) {
        window.webkit.messageHandlers.motstarOpen.postMessage(path);
      }
    });
  }

  // 1b) Style #tags in prose (skips code/links/pre)
  function markTags() {
    var article = document.querySelector('article');
    if (!article) return;
    walk(article);
    function walk(node) {
      var children = Array.prototype.slice.call(node.childNodes);
      for (var i = 0; i < children.length; i++) {
        var child = children[i];
        if (child.nodeType === 3) { processText(node, child); }
        else if (child.nodeType === 1) {
          var tag = child.tagName;
          if (tag === 'PRE' || tag === 'CODE' || tag === 'A' || tag === 'SCRIPT' ||
              tag === 'STYLE' || child.classList.contains('katex')) continue;
          walk(child);
        }
      }
    }
    function processText(parent, textNode) {
      var text = textNode.nodeValue;
      if (!text || text.indexOf('#') < 0) return;
      var frag = document.createDocumentFragment();
      var re = /(^|[\s(])(#(?:[A-Za-z0-9_\-\/]+))(?=[\s.,;:!?)\]]|$)/g;
      var last = 0, m;
      while ((m = re.exec(text)) !== null) {
        if (m.index > last) frag.appendChild(document.createTextNode(text.slice(last, m.index)));
        frag.appendChild(document.createTextNode(m[1]));
        var span = document.createElement('span');
        span.className = 'motstar-tag';
        span.textContent = m[2];
        frag.appendChild(span);
        last = m.index + m[0].length;
      }
      if (last < text.length) frag.appendChild(document.createTextNode(text.slice(last)));
      parent.replaceChild(frag, textNode);
    }
  }

  // 1) Obsidian-style callouts: > [!type] Title
  function renderCallouts() {
    var map = {
      note: { c: '#0969da', i: 'ℹ️' }, info: { c: '#0969da', i: 'ℹ️' },
      tip: { c: '#1a7f37', i: '💡' }, success: { c: '#1a7f37', i: '✅' },
      warning: { c: '#9a6700', i: '⚠️' }, warn: { c: '#9a6700', i: '⚠️' },
      danger: { c: '#cf222e', i: '⛔' }, error: { c: '#cf222e', i: '⛔' },
      abstract: { c: '#8250df', i: '📋' }, summary: { c: '#8250df', i: '📋' },
      question: { c: '#8250df', i: '❓' }, example: { c: '#8250df', i: '📐' }
    };
    var qs = document.querySelectorAll('blockquote');
    for (var i = 0; i < qs.length; i++) {
      var bq = qs[i];
      var first = bq.querySelector(':scope > p');
      if (!first) continue;
      var m = /^\[!(\w+)\]\s*(.*)$/.exec(first.textContent || '');
      if (!m) continue;
      var type = m[1].toLowerCase();
      var spec = map[type] || map.note;
      var title = m[2].trim();
      first.textContent = '';
      bq.classList.add('motstar-callout', 'callout-' + type);
      bq.style.borderLeftColor = spec.c;
      var head = document.createElement('div');
      head.className = 'callout-title';
      head.textContent = (spec.i ? spec.i + ' ' : '') + (title || type.charAt(0).toUpperCase() + type.slice(1));
      bq.insertBefore(head, first);
    }
  }

  // 2) Mermaid diagrams
  function renderMermaid() {
    if (typeof mermaid === 'undefined') return;
    mermaid.initialize({
      startOnLoad: false,
      theme: (window.matchMedia && window.matchMedia('(prefers-color-scheme: dark)').matches) ? 'dark' : 'default',
      securityLevel: 'strict',
      fontFamily: 'ui-sans-serif, -apple-system, sans-serif'
    });
    var blocks = Array.prototype.slice.call(document.querySelectorAll('pre > code.language-mermaid'));
    var i = 0;
    function next() {
      if (i >= blocks.length) return;
      var code = blocks[i++];
      var pre = code.parentNode;
      mermaid.render('mmd' + i, code.textContent).then(function (r) {
        var div = document.createElement('div');
        div.className = 'mermaid';
        div.innerHTML = r.svg;
        pre.parentNode.replaceChild(div, pre);
        next();
      }).catch(function (e) {
        var div = document.createElement('div');
        div.className = 'mermaid-error';
        div.textContent = 'Mermaid error: ' + e.message;
        pre.parentNode.replaceChild(div, pre);
        next();
      });
    }
    next();
  }

  // 3) Linkify bare URLs + emoji shortcodes in text nodes
  function transformText() {
    var article = document.querySelector('article');
    if (!article) return;
    walk(article);
    function walk(node) {
      var children = Array.prototype.slice.call(node.childNodes);
      for (var i = 0; i < children.length; i++) {
        var child = children[i];
        if (child.nodeType === 3) { processText(node, child); }
        else if (child.nodeType === 1) {
          var tag = child.tagName;
          if (tag === 'PRE' || tag === 'CODE' || tag === 'A' || tag === 'SCRIPT' ||
              tag === 'STYLE' || child.classList.contains('katex')) continue;
          walk(child);
        }
      }
    }
    function processText(parent, textNode) {
      var text = textNode.nodeValue;
      if (!text || (!/https?:\/\/|www\.|:[\w+_-]+:/.test(text))) return;
      var frag = document.createDocumentFragment();
      var re = /(https?:\/\/[^\s<]+|www\.[^\s<]+)|:([A-Za-z0-9_+\-]+):/g;
      var last = 0, m;
      while ((m = re.exec(text)) !== null) {
        if (m.index > last) frag.appendChild(document.createTextNode(text.slice(last, m.index)));
        if (m[1]) {
          var href = m[1];
          if (href.indexOf('http') !== 0) href = 'http://' + href;
          var a = document.createElement('a');
          a.href = href;
          a.textContent = m[1];
          frag.appendChild(a);
        } else if (m[2] && typeof EMOJI_MAP === 'object' && EMOJI_MAP[m[2]]) {
          frag.appendChild(document.createTextNode(EMOJI_MAP[m[2]]));
        } else {
          frag.appendChild(document.createTextNode(':' + m[2] + ':'));
        }
        last = m.index + m[0].length;
      }
      if (last < text.length) frag.appendChild(document.createTextNode(text.slice(last)));
      parent.replaceChild(frag, textNode);
    }
  }

  // 4) KaTeX: fenced ```math …``` (display) and inline $…$ / $$…$$ / \(…\)
  function hasKatex() { return typeof katex !== 'undefined'; }
  function texToHtml(tex, display) {
    return katex.renderToString(tex, { throwOnError: false, displayMode: display, strict: 'ignore' });
  }
  function renderMathFences() {
    if (!hasKatex()) return;
    var blocks = Array.prototype.slice.call(document.querySelectorAll('pre > code.language-math'));
    for (var i = 0; i < blocks.length; i++) {
      var code = blocks[i], pre = code.parentNode;
      var div = document.createElement('div');
      div.className = 'math-display';
      try { div.innerHTML = texToHtml(code.textContent, true); }
      catch (e) { div.textContent = 'Math error: ' + e.message; }
      pre.parentNode.replaceChild(div, pre);
    }
  }
  function renderInlineMath() {
    if (!hasKatex()) return;
    var article = document.querySelector('article');
    if (!article) return;
    walk(article);
    function walk(node) {
      var children = Array.prototype.slice.call(node.childNodes);
      for (var i = 0; i < children.length; i++) {
        var child = children[i];
        if (child.nodeType === 3) { processText(node, child); }
        else if (child.nodeType === 1) {
          var tag = child.tagName;
          if (tag === 'PRE' || tag === 'CODE' || tag === 'A' || tag === 'SCRIPT' ||
              tag === 'STYLE' || child.classList.contains('katex')) continue;
          walk(child);
        }
      }
    }
    function processText(parent, textNode) {
      var text = textNode.nodeValue;
      if (!text || (text.indexOf('$') < 0 && text.indexOf('\\(') < 0 && text.indexOf('\\[') < 0)) return;
      var frag = document.createDocumentFragment();
      var re = /\$\$([\s\S]+?)\$\$|\$([^$\n]+?)\$|\\\[([\s\S]+?)\\\]|\\\(([\s\S]+?)\\\)/g;
      var last = 0, m;
      while ((m = re.exec(text)) !== null) {
        if (m.index > last) frag.appendChild(document.createTextNode(text.slice(last, m.index)));
        var display = !!(m[1] || m[3]);
        var tex = m[1] || m[2] || m[3] || m[4];
        try {
          var span = document.createElement('span');
          span.innerHTML = texToHtml(tex, display);
          if (display) span.className = 'math-display-inline';
          frag.appendChild(span);
        } catch (e) {
          frag.appendChild(document.createTextNode(m[0]));
        }
        last = m.index + m[0].length;
      }
      if (last < text.length) frag.appendChild(document.createTextNode(text.slice(last)));
      parent.replaceChild(frag, textNode);
    }
  }

  // 5) Syntax highlighting (highlight.js), skipping rendered diagram code
  function highlightCode() {
    if (typeof hljs === 'undefined') return;
    var blocks = Array.prototype.slice.call(document.querySelectorAll('pre > code'));
    for (var i = 0; i < blocks.length; i++) {
      var code = blocks[i];
      var cls = (code.className || '') + ' ' + ((code.parentNode && code.parentNode.className) || '');
      if (/language-mermaid/.test(cls)) continue;
      try {
        hljs.highlightElement(code);
        code.classList.add('hljs');
      } catch (e) {}
    }
  }
})();
