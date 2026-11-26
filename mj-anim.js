/* Posting animations for the van sales app: Board, Return, Collection, Expense, Delete invoice.
   Plays while the post is being saved; the green tick shows only after the database confirms it.
   Only runs for a post the user just tapped (not for background re-sends). Tap the card to close it once done. */
(function () {
  var FOREST = '#0D2818', FOREST2 = '#1B4332', AMBER = '#F2994A', AMBER2 = '#F2C94C', RED = '#B3261E', CART = '#C4925C', CART2 = '#A87644';
  var lastTap = 0; ['pointerdown', 'touchstart', 'mousedown', 'click', 'keydown'].forEach(function (e) { document.addEventListener(e, function () { lastTap = Date.now(); }, true); });
  var reduce = window.matchMedia && matchMedia('(prefers-reduced-motion: reduce)').matches;
  var clamp = function (t) { return t < 0 ? 0 : t > 1 ? 1 : t; }, ease = function (t) { t = clamp(t); return t * t * (3 - 2 * t); };
  var seg = function (t, a, b) { return clamp((t - a) / (b - a)); }, lerp = function (a, b, t) { return a + (b - a) * t; };
  function rr(c, x, y, w, h, r) { c.beginPath(); c.moveTo(x + r, y); c.arcTo(x + w, y, x + w, y + h, r); c.arcTo(x + w, y + h, x, y + h, r); c.arcTo(x, y + h, x, y, r); c.arcTo(x, y, x + w, y, r); c.closePath(); }
  function poly(c, pts, fill, stroke) { c.beginPath(); pts.forEach(function (p, i) { i ? c.lineTo(p[0], p[1]) : c.moveTo(p[0], p[1]); }); c.closePath(); if (fill) { c.fillStyle = fill; c.fill(); } if (stroke) { c.strokeStyle = stroke; c.lineWidth = 1.5; c.stroke(); } }

  function van(c, x, y, door) {   // cab-forward panel van, front on the right, rear door on the left (scale 0.5 of the preview)
    c.save(); c.translate(x, y); c.scale(.5, .5);
    poly(c, [[0, 8], [300, 0], [352, 4], [392, 70], [404, 150], [404, 186], [0, 186]], '#FAFAF8', '#C8CDC8');
    c.fillStyle = '#464B4E'; rr(c, -4, 150, 412, 46, 10); c.fill();
    poly(c, [[304, 12], [348, 14], [384, 72], [304, 72]], '#28404A'); poly(c, [[236, 14], [296, 12], [296, 72], [236, 72]], '#28404A');
    c.strokeStyle = '#C8CDC8'; c.lineWidth = 3; c.beginPath(); c.moveTo(230, 10); c.lineTo(230, 150); c.moveTo(120, 10); c.lineTo(120, 150); c.stroke();
    c.fillStyle = FOREST2; c.fillRect(2, 84, 398, 44); c.fillStyle = AMBER2; c.fillRect(2, 128, 400, 6);
    c.fillStyle = AMBER2; c.font = 'bold 34px sans-serif'; c.fillText('mahrjan', 40, 120);
    c.fillStyle = '#FFECAA'; rr(c, 386, 100, 18, 22, 5); c.fill(); c.fillStyle = '#464B4E'; rr(c, 298, 40, 12, 22, 3); c.fill();
    [78, 320].forEach(function (wx) { c.fillStyle = '#373A3C'; c.beginPath(); c.arc(wx, 176, 44, Math.PI, 0); c.fill();
      c.fillStyle = '#191919'; c.beginPath(); c.arc(wx, 186, 34, 0, 7); c.fill(); c.fillStyle = '#AFB2B4'; c.beginPath(); c.arc(wx, 186, 15, 0, 7); c.fill(); });
    if (door > 0) { c.fillStyle = '#0C1410'; c.fillRect(0, 14, 24, 134); var dw = 70 * door; poly(c, [[0, 10], [-dw, 2], [-dw, 156], [0, 150]], '#ECEEEA', '#C8CDC8'); }
    c.restore();
  }
  function carton(c, x, y, s) { var w = 48 * s, h = 36 * s; c.fillStyle = CART; c.strokeStyle = CART2; c.lineWidth = 1.5; rr(c, x, y, w, h, 3); c.fill(); c.stroke();
    c.beginPath(); c.moveTo(x, y + h * .32); c.lineTo(x + w, y + h * .32); c.stroke(); c.fillStyle = '#DCBE8C'; c.fillRect(x + w * .42, y, w * .16, h * .32);
    for (var i = 0; i < 3; i++) { c.fillStyle = '#FAF3E4'; c.beginPath(); c.ellipse(x + w * (.22 + i * .28), y + h * .66, 4.5 * s, 5.5 * s, 0, 0, 7); c.fill(); c.stroke(); } }
  function note(c, x, y, s, rot) { c.save(); c.translate(x, y); c.rotate(rot * Math.PI / 180); var w = 65 * s, h = 32 * s;
    c.fillStyle = '#78AA6E'; c.strokeStyle = '#46783C'; c.lineWidth = 1.5; rr(c, -w / 2, -h / 2, w, h, 3); c.fill(); c.stroke();
    c.beginPath(); c.arc(0, 0, 9 * s, 0, 7); c.stroke(); c.fillStyle = '#285023'; c.font = 'bold ' + Math.max(7, 8 * s) + 'px sans-serif'; c.fillText('AED', -w / 2 + 4, -h / 2 + 10 * s); c.restore(); }
  function cashbox(c, x, y) { c.fillStyle = AMBER2; c.strokeStyle = '#C89628'; c.lineWidth = 2; rr(c, x, y, 130, 85, 8); c.fill(); c.stroke();
    c.fillStyle = FOREST; rr(c, x + 30, y - 4, 70, 9, 4); c.fill(); c.font = 'bold 20px sans-serif'; c.fillText('CASH', x + 36, y + 50); c.fillStyle = '#C89628'; rr(c, x + 55, y + 60, 20, 15, 3); c.fill(); }

  var SCENES = {
    BOARD: function (c, p, d) { van(c, 100, 70, 1 - ease(d * 2)); for (var i = 0; i < 3; i++) { var q = ease(seg(p, .1 + i * .25, .35 + i * .25)); if (q >= 1) continue;
        carton(c, lerp(10, 104, q), lerp(150 - i * 38, 100, q) - Math.sin(q * Math.PI) * 45, lerp(1, .55, q)); } },
    RETURN: function (c, p, d) { van(c, 100, 70, 1 - ease(d * 2)); for (var i = 0; i < 3; i++) { var q = ease(seg(p, .1 + i * .25, .35 + i * .25)); if (q <= 0) continue;
        carton(c, lerp(104, 10, q), lerp(100, 150 - i * 38, q) - Math.sin(q * Math.PI) * 45, lerp(.55, 1, q)); } },
    COLLECTION: function (c, p) { cashbox(c, 95, 120); for (var i = 0; i < 3; i++) { var q = ease(seg(p, .1 + i * .25, .4 + i * .25)); if (q <= 0 || q >= 1) continue;
        note(c, lerp(50 + i * 110, 160, q), lerp(30, 110, q) - Math.sin(q * Math.PI) * 25, lerp(1, .5, q), lerp(-15 + i * 15, 0, q)); } },
    EXPENSE: function (c, p, d) { cashbox(c, 20, 130); c.fillStyle = '#fff'; c.strokeStyle = '#D7DCD7'; c.lineWidth = 1.5; rr(c, 200, 50, 105, 150, 6); c.fill(); c.stroke();
        c.fillStyle = FOREST; c.font = 'bold 12px sans-serif'; c.fillText('RECEIPT', 212, 72); c.font = '13px sans-serif'; c.fillText('Paid out', 212, 96);
        for (var i = 0; i < 2; i++) { var q = ease(seg(p, .15 + i * .35, .55 + i * .35)); if (q <= 0 || q >= 1) continue;
          note(c, lerp(85, 252, q), lerp(120, 140, q) - Math.sin(q * Math.PI) * 55, lerp(.5, .7, q), lerp(0, 12, q)); }
        if (d > 0) { c.fillStyle = '#EEF4F0'; rr(c, 212, 150, 80 * ease(d * 1.5), 30, 5); c.fill(); if (d > .5) { c.fillStyle = FOREST; c.font = 'bold 16px sans-serif'; c.fillText('PAID', 228, 171); } } },
    DELETE: function (c, p, d) {   // the invoice crumples, flies into the dustbin; the lid shuts once the delete is saved
        var bx = 235, rim = 128, open = ease(seg(p, 0, .22)) * (1 - ease(seg(d, 0, .45))), shut = d > .45 ? Math.sin(clamp((d - .45) / .4) * Math.PI) * .12 : 0;
        c.fillStyle = '#3A403C'; c.beginPath(); c.ellipse(bx, rim, 44, 8, 0, 0, 7); c.fill();   // dark opening
        var f = ease(seg(p, .18, .72)), dr = ease(seg(p, .72, .9)), t = f, u = 1 - t;
        var x = u * u * 85 + 2 * u * t * 150 + t * t * bx, y = u * u * 110 + 2 * u * t * -5 + t * t * (rim - 8) + dr * 40;
        var sc = lerp(1, .32, ease(seg(p, .1, .7))), rot = lerp(0, 4.2, f), crum = seg(p, .1, .45);
        c.save(); if (dr > 0) { c.beginPath(); c.rect(0, 0, 320, rim); c.clip(); }
        c.translate(x, y); c.rotate(rot); c.scale(sc, sc);
        if (crum < 1) { var k = 1 - crum * .35; c.fillStyle = '#fff'; c.strokeStyle = '#C9D0CB'; c.lineWidth = 2;
          poly(c, [[-48 * k, -62], [44 * k, -60 + crum * 10], [50 * k, 60], [-46 * k, 58 - crum * 12]], '#fff', '#C9D0CB');
          c.fillStyle = FOREST; c.font = 'bold 12px sans-serif'; c.fillText('INVOICE', -38 * k, -40);
          c.fillStyle = '#9AA19C'; for (var i = 0; i < 4; i++) c.fillRect(-38 * k, -24 + i * 16, (54 + (i % 2) * 18) * k, 4);
          c.fillStyle = FOREST; c.fillRect(-38 * k, 44, 40 * k, 5); }
        else { c.fillStyle = '#F4F5F2'; c.strokeStyle = '#B9C1BB'; c.lineWidth = 3; c.beginPath();
          for (var a = 0; a < 12; a++) { var r = 44 + (a % 3) * 7; c.lineTo(Math.cos(a / 12 * 6.283) * r, Math.sin(a / 12 * 6.283) * r); } c.closePath(); c.fill(); c.stroke();
          c.beginPath(); c.moveTo(-20, -18); c.lineTo(10, 4); c.lineTo(-6, 24); c.moveTo(18, -26); c.lineTo(4, -6); c.stroke(); }
        c.restore();
        poly(c, [[bx - 46, rim], [bx + 46, rim], [bx + 36, 218], [bx - 36, 218]], '#6B7A72', '#4E5A54');   // bin body
        c.strokeStyle = '#59665F'; c.lineWidth = 3; [-20, 0, 20].forEach(function (o) { c.beginPath(); c.moveTo(bx + o * 1.05, rim + 16); c.lineTo(bx + o * .8, 206); c.stroke(); });
        c.fillStyle = '#56635C'; rr(c, bx - 49, rim - 3, 98, 8, 4); c.fill();
        c.save(); c.translate(bx + 50, rim - 3); c.rotate(open * 1.75 - shut);   // lid hinged on the right
        c.fillStyle = '#7D8C84'; rr(c, -102, -10, 104, 11, 5); c.fill(); c.fillStyle = '#56635C'; rr(c, -62, -17, 24, 8, 3); c.fill(); c.restore(); }
  };
  var LABEL = { BOARD: ['Loading the van\u2026', 'Board posted'], RETURN: ['Unloading\u2026', 'Return posted'], COLLECTION: ['Receiving money\u2026', 'Collection posted'],
    EXPENSE: ['Paying out\u2026', 'Expense posted'], DELETE: ['Deleting invoice\u2026', 'Invoice deleted'] };

  function start(kind) {
    if (!SCENES[kind] || document.visibilityState === 'hidden' || Date.now() - lastTap > 20000) return null;   // shown even when the phone has animations turned off (PDTs often do)
    var ov = document.createElement('div');
    ov.style.cssText = 'position:fixed;inset:0;z-index:2147483647;background:rgba(13,40,24,.35);display:flex;align-items:center;justify-content:center;opacity:0;transition:opacity .2s';
    ov.innerHTML = '<div style="background:#fff;border-radius:22px;padding:18px 18px 16px;width:300px;max-width:88vw;text-align:center;box-shadow:0 12px 40px rgba(0,0,0,.25);font-family:inherit">' +
      '<canvas width="320" height="230" style="width:100%;height:auto;display:block"></canvas><div class="mjal" style="font:700 17px sans-serif;color:' + FOREST + ';margin-top:6px;min-height:24px"></div></div>';
    var hide = document.createElement('style'); hide.textContent = '#postOv{display:none!important}';   // the plain "Posting… %" screen steps aside while the animation shows
    document.head.appendChild(hide); document.body.appendChild(ov); requestAnimationFrame(function () { ov.style.opacity = '1'; });
    var cv = ov.querySelector('canvas'), lab = ov.querySelector('.mjal'), dpr = Math.min(2, window.devicePixelRatio || 1);
    cv.width = 320 * dpr; cv.height = 230 * dpr; var c = cv.getContext('2d');
    var t0 = performance.now(), state = 'run', tEnd = 0, msg = '', raf, closeAt = 0;
    lab.textContent = LABEL[kind][0];
    function tick(now) {
      var el = (now - t0) / 1000, p = Math.min(.92, el / 1.5), d = 0;   // main motion takes 1.5 s; holds near the end until the save is confirmed
      if (state !== 'run') { var ed = (now - tEnd) / 1000; p = lerp(Math.min(.92, (tEnd - t0) / 1500), 1, clamp(ed / .35)); d = state === 'ok' ? clamp(ed / .7) : 0; }
      c.setTransform(dpr, 0, 0, dpr, 0, 0); c.clearRect(0, 0, 320, 230);
      if (state === 'run' && p >= .92) { c.globalAlpha = .75 + .25 * Math.sin(el * 6); }
      SCENES[kind](c, state === 'fail' ? p * (1 - clamp((now - tEnd) / 400)) : p, d); c.globalAlpha = 1;
      if (state === 'ok' && d > .2) { var r = 24 * ease((d - .2) / .5); c.fillStyle = FOREST2; c.beginPath(); c.arc(285, 32, r, 0, 7); c.fill();
        if (d > .5) { c.strokeStyle = AMBER2; c.lineWidth = 5; c.lineCap = 'round'; c.beginPath(); c.moveTo(275, 33); c.lineTo(283, 41); c.lineTo(296, 24); c.stroke(); } }
      if (state === 'fail') { c.fillStyle = RED; c.beginPath(); c.arc(285, 32, 22, 0, 7); c.fill(); c.strokeStyle = '#fff'; c.lineWidth = 4; c.beginPath(); c.moveTo(277, 24); c.lineTo(293, 40); c.moveTo(293, 24); c.lineTo(277, 40); c.stroke(); }
      if (closeAt && now >= closeAt) return close();
      raf = requestAnimationFrame(tick);
    }
    function close() { cancelAnimationFrame(raf); ov.style.opacity = '0';
      setTimeout(function () { ov.remove(); var po = document.getElementById('postOv'); if (state === 'ok' && po) po.className = ''; hide.remove(); }, 220); }   // saved: the old "posted" card is not shown again; not saved: its error card stays with the reason
    ov.addEventListener('click', function () { if (state !== 'run') close(); });
    raf = requestAnimationFrame(tick);
    return {
      done: function () { state = 'ok'; tEnd = performance.now(); lab.textContent = LABEL[kind][1]; closeAt = tEnd + 1300; },
      fail: function (m) { state = 'fail'; tEnd = performance.now(); lab.style.color = RED; lab.textContent = 'Not saved'; closeAt = tEnd + 700; }
    };
  }
  window.MJAnim = { start: start };
})();
