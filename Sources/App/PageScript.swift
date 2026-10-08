import WebKit

enum PageScript {
    /// Injected into the preview: highlights blocks for a line range, selects text on request,
    /// and reports clicks/selections back to the editor via the `select` message handler.
    static let source = #"""
    (() => {
      const lines = el => [+el.dataset.line, +el.dataset.end];
      const tagged = n => (n && (n.nodeType === 1 ? n : n.parentElement))?.closest('[data-line]');
      // A block's own lines stop where its first tagged child starts (e.g. a list item's text vs. its sub-list).
      const own = el => {
        let [s, e] = lines(el);
        for (const k of el.querySelectorAll('[data-line]')) e = Math.min(e, +k.dataset.line);
        return [s, Math.max(e, s + 1)];
      };
      window.mdSync = false;
      window.mdSetSync = on => { window.mdSync = on; if (!on) mdHighlight(-1, -1, false); };
      window.mdHighlight = (s, e, scroll) => {
        document.querySelectorAll('.md-active').forEach(el => el.classList.remove('md-active'));
        const hit = el => { const [a, b] = lines(el); return a < e && b > s; };
        const els = [...document.querySelectorAll('[data-line]')]
          .filter(el => hit(el) && ![...el.querySelectorAll('[data-line]')].some(hit));
        els.forEach(el => el.classList.add('md-active'));
        if (scroll && els.length) {
          const r = els[0].getBoundingClientRect();
          if (r.top < 0 || r.bottom > innerHeight) els[0].scrollIntoView({ block: 'center', behavior: 'smooth' });
        }
      };
      // Plain text of some blocks, whitespace collapsed, with a map back to DOM positions.
      const textIndex = roots => {
        let str = '', map = [], space = true;
        for (const root of roots) {
          const w = document.createTreeWalker(root, NodeFilter.SHOW_TEXT);
          for (let n; (n = w.nextNode());) {
            if (n.parentElement.closest('annotation')) continue; // TeX source hidden inside MathML
            const t = n.nodeValue;
            for (let i = 0; i < t.length; i++) {
              const sp = /\s/.test(t[i]);
              if (sp && space) continue;
              str += sp ? ' ' : t[i]; map.push([n, i]); space = sp;
            }
          }
          if (!space) { str += ' '; map.push(null); space = true; }
        }
        return { str, map };
      };
      const norm = s => s.replace(/\s+/g, ' ').trim();
      const suffixScore = (a, b) => { let k = 0; while (k < a.length && k < b.length && a[a.length - 1 - k] === b[b.length - 1 - k]) k++; return k; };

      // Editor → page: select `text` within the blocks for lines [s, e), choosing the occurrence whose preceding text matches `before`.
      window.mdSelectText = (s, e, text, before) => {
        mdHighlight(-1, -1, false);
        const hit = el => { const [a, b] = lines(el); return a < e && b > s; };
        // Outermost tagged blocks overlapping the lines (their children are covered by the text walk).
        const outermost = el => { const p = el.parentElement.closest('[data-line]'); return !p || !hit(p); };
        const { str, map } = textIndex([...document.querySelectorAll('[data-line]')].filter(el => hit(el) && outermost(el)));
        let best = -1, bestScore = -1;
        for (let i = str.indexOf(text); i >= 0; i = str.indexOf(text, i + 1)) {
          const sc = suffixScore(norm(str.slice(0, i)), before);
          if (sc > bestScore) { best = i; bestScore = sc; }
        }
        if (best < 0) return false;
        const a = map[best], z = map[best + text.length - 1];
        if (!a || !z) return false;
        const r = document.createRange();
        r.setStart(a[0], a[1]); r.setEnd(z[0], z[1] + 1);
        const sel = getSelection(); sel.removeAllRanges(); sel.addRange(r);
        const box = r.getBoundingClientRect();
        if (box.top < 0 || box.bottom > innerHeight) scrollBy({ top: box.top - innerHeight / 3, behavior: 'smooth' });
        return true;
      };

      // Page → editor: report the block, the selected text and the text just before it.
      document.addEventListener('mouseup', ev => {
        if (!window.mdSync || ev.button !== 0 || ev.target.closest('a')) return;
        const sel = getSelection();
        if (!sel.rangeCount) return;
        const range = sel.getRangeAt(0);
        const a = tagged(range.startContainer), b = tagged(range.endContainer);
        if (!a || !b) return;
        const [s1, e1] = own(a), [s2, e2] = own(b);
        const pre = document.createRange();
        pre.setStart(a, 0); pre.setEnd(range.startContainer, range.startOffset);
        const before = pre.toString().replace(/\s+/g, ' ').replace(/^ /, '').slice(-40);
        const text = norm(sel.toString());
        if (text) mdHighlight(-1, -1, false); else mdHighlight(s1, e1, false);
        webkit.messageHandlers.select.postMessage({ start: Math.min(s1, s2), end: Math.max(e1, e2), text, before });
      });
    })();
    """#
}

/// WKUserContentController retains its handlers; this breaks the cycle with the window controller.
final class WeakScriptHandler: NSObject, WKScriptMessageHandler {
    weak var target: WKScriptMessageHandler?
    init(_ target: WKScriptMessageHandler) { self.target = target }
    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.userContentController(controller, didReceive: message)
    }
}
