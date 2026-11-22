/* Shows every date as DD-MMM-YYYY (22-Nov-2026) on screen, in print and in Excel.
   Only text on the page changes; date boxes, saved data and calculations keep their own format. */
(function () {
  var M = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
  var ISO = /\b(\d{4})-(\d{2})-(\d{2})(?!\d)/g, DMY = /\b(\d{2})\/(\d{2})\/(\d{4})\b/g, TEST = /\d{4}-\d{2}-\d{2}|\d{2}\/\d{2}\/\d{4}/;
  function ok(m, d) { return +m >= 1 && +m <= 12 && +d >= 1 && +d <= 31; }
  function fmt(s) {
    if (typeof s !== 'string' || !TEST.test(s)) return s;
    return s.replace(ISO, function (a, y, m, d) { return ok(m, d) ? d + '-' + M[m - 1] + '-' + y : a; })
            .replace(DMY, function (a, d, m, y) { return ok(m, d) ? d + '-' + M[m - 1] + '-' + y : a; });
  }
  window.mjFmtDates = fmt;
  var SKIP = { SCRIPT: 1, STYLE: 1, TEXTAREA: 1, INPUT: 1, NOSCRIPT: 1 };
  function fixText(n) { var p = n.parentNode; if (!p || SKIP[p.nodeName] || p.isContentEditable) return; var t = n.data; if (t.length < 8) return; var u = fmt(t); if (u !== t) n.data = u; }
  function walk(root) {
    if (root.nodeType === 3) return fixText(root);
    if (root.nodeType !== 1 || SKIP[root.nodeName]) return;
    var w = document.createTreeWalker(root, NodeFilter.SHOW_TEXT, null), n;
    while ((n = w.nextNode())) fixText(n);
  }
  function start() {
    walk(document.body);
    new MutationObserver(function (recs) {
      for (var i = 0; i < recs.length; i++) {
        var r = recs[i];
        if (r.type === 'characterData') fixText(r.target);
        else for (var j = 0; j < r.addedNodes.length; j++) walk(r.addedNodes[j]);
      }
    }).observe(document.body, { childList: true, subtree: true, characterData: true });
  }
  if (document.body) start(); else document.addEventListener('DOMContentLoaded', start);
})();
