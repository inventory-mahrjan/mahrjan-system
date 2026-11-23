/* =====================================================================
   Mahrjan — STOCK COUNT in the app (Warehouse → Stock count).
   Batches are created in the portal. Here the receiver: picks a batch → Download (saved on the device)
   → counts OFFLINE (shelf, category, scan, qty, expiry, country) → Save (on the device) → Post when online.
   Blind count: the system / iTrade stock is never shown here.
   ===================================================================== */
(function () {
  if (window.MJSC) return;
  var CAT = { RAW: 'Raw egg', FG: 'Finished goods', TRAY: 'Plain tray', LTRAY: 'Labelled tray', LABEL: 'Label roll' };
  var TYPES = { RAW: ['FRESH', 'CLEANED'], FG: ['FRESH', 'GRV', 'DAMAGE'] };
  var TNAME = { FRESH: 'Fresh', GRV: 'Repacked', CLEANED: 'Cleaned', DAMAGE: 'Damage' };
  var KEY = 'mjsc:', root = null, V = { view: 'list' }, LIST = [], busy = false, err = '';

  var CSS = '#mjsc{position:fixed;inset:0;z-index:2100;background:#f2f2ee;display:none;flex-direction:column;font-family:Archivo,system-ui,sans-serif;color:#14181a}'
    + '#mjsc .hd{background:#1B4332;color:#fff;padding:12px 14px;display:flex;align-items:center;gap:10px}#mjsc .hd b{font-size:16px;flex:1}#mjsc .hd small{display:block;font-weight:400;opacity:.8;font-size:11px}'
    + '#mjsc .hd button{background:rgba(255,255,255,.15);color:#fff;border:0;border-radius:8px;padding:8px 11px;font:600 13px Archivo}'
    + '#mjsc .bd{flex:1;overflow:auto;padding:12px}#mjsc .ft{display:flex;gap:8px;padding:10px 12px;background:#fff;border-top:1px solid #ddd}'
    + '#mjsc .ft button{flex:1;padding:13px;border-radius:10px;border:1px solid #c9cfca;background:#fff;font:700 14px Archivo}#mjsc .ft .pri{background:linear-gradient(90deg,#F2994A,#F2C94C);color:#0D2818;border-color:#F2B04B}'
    + '#mjsc .card{background:#fff;border:1px solid rgba(20,24,26,.12);border-radius:12px;padding:12px;margin-bottom:10px}'
    + '#mjsc .bt{display:block;width:100%;text-align:left;font:inherit;cursor:pointer}#mjsc .bt .t{font-weight:700;font-size:15px}#mjsc .bt .s{color:#68716b;font-size:12px;margin-top:3px}'
    + '#mjsc .lbl{font:700 10.5px Archivo;letter-spacing:.06em;color:#68716b;margin:10px 0 5px}'
    + '#mjsc input,#mjsc select{width:100%;box-sizing:border-box;padding:11px;border:1px solid #c9cfca;border-radius:9px;font:15px Archivo;background:#fff}'
    + '#mjsc .pills{display:flex;flex-wrap:wrap;gap:6px}#mjsc .pills button{padding:9px 12px;border-radius:20px;border:1px solid #c9cfca;background:#fff;font:600 13px Archivo}#mjsc .pills .on{background:#147b3d;color:#fff;border-color:#147b3d}'
    + '#mjsc .q{display:flex;gap:8px}#mjsc .q label{flex:1;font:600 11px Archivo;color:#68716b}#mjsc .q input{text-align:center;font:600 18px "IBM Plex Mono",monospace;margin-top:4px}'
    + '#mjsc .tot{font:700 15px "IBM Plex Mono",monospace;color:#147b3d;margin-top:8px}#mjsc .it{font-weight:700;font-size:15px}#mjsc .mut{color:#68716b;font-size:12px}'
    + '#mjsc .err{background:#fdecea;color:#a1271b;border-radius:9px;padding:10px;margin-bottom:10px;font-size:13px}#mjsc .ok{background:#e6f2ea;color:#147b3d;border-radius:9px;padding:10px;margin-bottom:10px;font-size:13px}'
    + '#mjsc .row{display:flex;justify-content:space-between;align-items:center;gap:8px;padding:8px 0;border-bottom:1px solid #eee;font-size:13px}#mjsc .row:last-child{border:0}'
    + '#mjsc .row button{border:1px solid #e0b4ae;color:#a1271b;background:#fff;border-radius:8px;padding:6px 9px;font:600 12px Archivo}'
    + '#mjsc .mono{font-family:"IBM Plex Mono",monospace}#mjsc .two{display:flex;gap:8px}#mjsc .two>*{flex:1}#mjsc .big{width:100%;padding:14px;border-radius:10px;border:0;background:#147b3d;color:#fff;font:700 15px Archivo;margin-top:10px}';

  function esc(s) { return String(s == null ? '' : s).replace(/[&<>"']/g, function (c) { return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]; }); }
  function num(v) { var n = parseFloat(v); return isNaN(n) ? 0 : n; }
  function sbc() { return window.MJ_SB ? window.MJ_SB() : Promise.reject(new Error('Not signed in')); }
  async function rpc(fn, args) { var c = await sbc(); var r = await c.rpc(fn, args); if (r.error) throw new Error(r.error.message); return r.data; }
  function load(id) { try { return JSON.parse(localStorage.getItem(KEY + id) || 'null'); } catch (e) { return null; } }
  function store(id, d) { d.savedAt = new Date().toISOString(); localStorage.setItem(KEY + id, JSON.stringify(d)); }
  function drop(id) { localStorage.removeItem(KEY + id); }
  function localIds() { var a = []; for (var i = 0; i < localStorage.length; i++) { var k = localStorage.key(i); if (k && k.indexOf(KEY) === 0) a.push(+k.slice(KEY.length)); } return a; }
  function beep(ok) { try { var C = window.AudioContext || window.webkitAudioContext, a = new C(), o = a.createOscillator(), g = a.createGain(); o.frequency.value = ok ? 1200 : 300; o.connect(g); g.connect(a.destination); g.gain.value = .15; o.start(); o.stop(a.currentTime + (ok ? .08 : .3)); } catch (e) {} if (navigator.vibrate) navigator.vibrate(ok ? 30 : [80, 60, 80]); }
  function fmtD(s) { if (!s) return ''; var d = new Date(s + (s.length === 10 ? 'T00:00:00' : '')); return d.toLocaleDateString('en-GB', { day: '2-digit', month: 'short', year: 'numeric' }); }

  function shell(title, sub, body, foot, back) {
    root.innerHTML = '<div class="hd"><button onclick="MJSC.' + (back || 'close') + '()">←</button><b>' + esc(title) + '<small>' + esc(sub || '') + '</small></b>'
      + (V.view === 'list' ? '<button onclick="MJSC.refresh()">↻</button>' : '') + '</div><div class="bd">' + (err ? '<div class="err">' + esc(err) + '</div>' : '') + body + '</div>'
      + (foot ? '<div class="ft">' + foot + '</div>' : '');
  }

  // ---------------- batch list ----------------
  async function refresh() {
    busy = true; err = ''; render();
    try {
      var c = await sbc(), r = await c.from('sc_batches').select('id,batch_no,count_date,count_type,categories,status,branch_id,parent_id').in('status', ['OPEN', 'DOWNLOADED']).order('count_date').order('id');
      if (r.error) throw new Error(r.error.message);
      LIST = r.data || [];
    } catch (e) { err = navigator.onLine ? (e.message || String(e)) : 'Offline — showing batches saved on this device.'; }
    busy = false; render();
  }
  function vList() {
    var ids = localIds(), all = LIST.slice();
    ids.forEach(function (id) { if (!all.some(function (b) { return b.id === id; })) { var d = load(id); if (d) all.push({ id: id, batch_no: d.batch.no, count_date: d.batch.date, count_type: d.batch.type, categories: d.batch.categories, status: 'DOWNLOADED', local: true }); } });
    var h = '<div class="lbl">STOCK COUNT BATCHES</div>';
    if (busy && !all.length) h += '<div class="card mut">Loading…</div>';
    all.forEach(function (b) {
      var d = load(b.id), n = d ? d.lines.length : 0;
      h += '<div class="card"><button class="bt" onclick="MJSC.pick(' + b.id + ')" style="border:0;background:none;padding:0"><div class="t">' + esc(b.batch_no) + (b.parent_id ? ' · recount' : '') + '</div>'
        + '<div class="s">' + fmtD(b.count_date) + ' · ' + (b.count_type === 'WEEKLY' ? 'Weekly' : 'Daily') + ' · ' + (b.categories || []).map(function (c) { return CAT[c]; }).join(', ') + '</div>'
        + '<div class="s">' + (d ? '📱 On this device · ' + n + ' entr' + (n === 1 ? 'y' : 'ies') + (d.savedAt ? ' · saved ' + new Date(d.savedAt).toLocaleTimeString('en-GB', { hour: '2-digit', minute: '2-digit' }) : '') : 'Not downloaded') + '</div></button>'
        + (V.sel === b.id ? (d ? '<button class="big" onclick="MJSC.count(' + b.id + ')">Continue counting</button>' : '<button class="big" onclick="MJSC.download(' + b.id + ')"' + (busy ? ' disabled' : '') + '>' + (busy ? 'Downloading…' : '⬇ Download') + '</button>') : '') + '</div>';
    });
    if (!busy && !all.length) h += '<div class="card mut">No open count batch. The office creates the batch in the portal (Stock count → New count batch).</div>';
    shell('Stock count', navigator.onLine ? 'Online' : 'Offline', h, '');
  }
  async function download(id) {
    busy = true; err = ''; render();
    try { var data = await rpc('sc_download', { p_id: id });
      var d = { batch: data.batch, items: data.items, bom: data.bom, countries: data.countries, lines: (data.lines || []).map(function (l) { return { entry_no: l.entry_no, shelf: l.shelf, category: l.category, stock_type: l.stock_type, scanned_barcode: l.scanned_barcode, item_id: l.item_id, qty_big: +l.qty_big, qty_tray: +l.qty_tray, qty_small: +l.qty_small, total_qty: +l.total_qty, unit: l.unit, exp_date: l.exp_date, country: l.country, pair_key: l.pair_key, zero_confirmed: l.zero_confirmed, scanned_at: l.scanned_at }; }) };
      store(id, d); busy = false; count(id);
    } catch (e) { busy = false; err = 'Download failed: ' + (e.message || e); render(); }
  }

  // ---------------- counting ----------------
  var D = null, C = null;   // D = downloaded batch, C = current entry state
  function count(id) { refreshMaster(id); D = load(id); if (!D) { err = 'Download the batch first.'; V.view = 'list'; render(); return; } V.view = 'count'; V.id = id;
    C = C && C.id === id ? C : { id: id, shelf: localStorage.getItem('mjsc_shelf') || '', cat: D.batch.categories[0], type: 'FRESH', found: null, msg: '' }; err = ''; render(); setTimeout(focusScan, 50); }
  // when online, refresh the item list and BOM of a downloaded batch (office changes in Items & BOM reach the device); counted lines stay as they are
  function refreshMaster(id) { if (!navigator.onLine) return Promise.resolve(false); return rpc('sc_download', { p_id: id }).then(function (data) { var d = load(id); if (!d) return;
      d.items = data.items; d.bom = data.bom; d.countries = data.countries; retot(d); store(id, d); if (D && V.id === id) { D.items = d.items; D.bom = d.bom; D.countries = d.countries; D.lines = d.lines; if (V.view === 'count') render(); } return true; }).catch(function () { return false; }); }
  // box / carton sizes can change in Items & BOM after counting started: work every raw egg and finished-good total out again from the current sizes
  function retot(d) { if (!d || !d.lines) return; d.lines.forEach(function (l) { if (l.category !== 'FG' && l.category !== 'RAW') return;
      var it = (d.items || []).find(function (i) { return i.id === l.item_id; }); if (!it) return; var b = +l.qty_big || 0, t = +l.qty_tray || 0, sm = +l.qty_small || 0;
      if (!b && !t) return; l.total_qty = l.category === 'RAW' ? b * (it.pcc || 0) + t * (it.ppt || 0) + sm : b * (it.ppc || 0) + sm; }); }
  function itemsBy(id) { return D.items.find(function (i) { return i.id === id; }); }
  function isRecount(id) { return !D.batch.recount_items || D.batch.recount_items.indexOf(id) >= 0; }
  function nm(i) { return i ? (i.s || i.n) : ''; }
  function mats(fgId, kind) { return D.bom.filter(function (b) { return b.fg === fgId; }).map(function (b) { return itemsBy(b.m); }).filter(function (m) { return m && m.k === kind; }); }
  function bigOf(cat, it) { return cat === 'RAW' ? (it.pcc || 0) : cat === 'FG' ? (it.ppc || 0) : (it.ppb || 0); }
  function units(cat, it) {
    if (cat === 'RAW') return [['qty_big', 'Ctn'], ['qty_tray', 'Tray'], ['qty_small', 'Pcs']];
    if (cat === 'FG') return [['qty_big', 'Box'], ['qty_small', 'Pkts']];
    if (cat === 'TRAY' || cat === 'LTRAY') return [['qty_big', 'Box'], ['qty_small', 'Pcs']];   // trays come in boxes
    return [['qty_small', 'Pcs']];   // label roll: counted in pcs
  }
  function totalOf(cat, it, v) { var b = num(v.qty_big), t = num(v.qty_tray), s = num(v.qty_small);
    if (cat === 'RAW') return b * (it.pcc || 0) + t * (it.ppt || 0) + s;
    return b * bigOf(cat, it) + s; }
  function scan(code) {
    code = String(code || '').trim(); if (!code) return;
    var cat = C.cat, it = null;
    var byCode = D.items.filter(function (i) { return i.bc === code || i.code === code || String(i.bc || '').toUpperCase() === code.toUpperCase(); });
    if (cat === 'RAW' || cat === 'FG') {
      it = byCode.find(function (i) { return i.t === (cat === 'RAW' ? 'RAW_EGG' : 'FG'); });
      // raw egg has no barcode of its own: a finished-good barcode finds its raw egg through the BOM
      var viaFg = null;
      if (!it && cat === 'RAW') { viaFg = byCode.find(function (i) { return i.t === 'FG'; });
        if (viaFg) { it = D.bom.filter(function (b) { return b.fg === viaFg.id; }).map(function (b) { return itemsBy(b.m); }).find(function (m) { return m && m.t === 'RAW_EGG'; }) || null;
          if (!it && !C.retried) { C.retried = true; C.msg = 'Checking the BOM…'; render(); refreshMaster(V.id).then(function () { scan(code); }); return; }
          C.retried = false;
          if (!it) { beep(false); C.msg = 'No raw egg in the BOM of ' + nm(viaFg) + '. Ask the office to add it in Items & BOM.'; C.found = null; render(); return; } } }
      if (!it) { beep(false); C.msg = 'Not a ' + CAT[cat].toLowerCase() + ' barcode: ' + code; C.found = null; render(); return; }
      if (!isRecount(it.id)) { beep(false); C.msg = nm(it) + ' is not in this recount.'; render(); return; }
      C.found = { cat: cat, items: [it], scanned: code, fg: viaFg || undefined };
    } else {
      var fg = byCode.find(function (i) { return i.t === 'FG'; }) || byCode.find(function (i) { return i.t === 'MATERIAL'; });
      if (!fg) { beep(false); C.msg = 'Barcode not found: ' + code; C.found = null; render(); return; }
      var list = fg.t === 'MATERIAL' ? [fg] : cat === 'TRAY' ? mats(fg.id, 'TRAY') : cat === 'LABEL' ? mats(fg.id, 'LABEL') : mats(fg.id, 'TRAY').slice(0, 1).concat(mats(fg.id, 'LABEL').slice(0, 1));
      if (!list.length || (cat === 'LTRAY' && list.length < 2)) { beep(false); C.msg = 'No ' + (cat === 'LABEL' ? 'label' : cat === 'TRAY' ? 'tray' : 'tray and label') + ' in the BOM of ' + nm(fg) + '. Ask the office to add it in Items & BOM.'; C.found = null; render(); return; }
      if (!list.some(function (m) { return isRecount(m.id); })) { beep(false); C.msg = 'Not in this recount.'; render(); return; }
      C.found = { cat: cat, items: list, scanned: code, fg: fg };
    }
    C.retried = false; beep(true); C.msg = ''; C.v = {}; C.exp = ''; C.country = C.country || ''; render();
    setTimeout(function () { var f = root.querySelector('.q input'); if (f) f.focus(); }, 30);
  }
  function addEntry() {
    var f = C.found; if (!f) return;
    var lead = f.items[0], v = C.v || {}, tot = totalOf(f.cat, lead, v);
    if (!(tot > 0)) { C.msg = 'Enter the quantity.'; render(); return; }
    if ((f.cat === 'TRAY' || f.cat === 'LTRAY') && num(v.qty_big) > 0 && !(lead.ppb > 0)) { C.msg = 'Pcs per box is not set for ' + nm(lead) + '. Count in pcs, or ask the office to fill it in Items & BOM.'; render(); return; }
    if (!C.shelf) { C.msg = 'Enter or scan the shelf ID first.'; render(); return; }
    if (num(v.qty_big) >= 100 && !confirm(num(v.qty_big) + ' ' + (f.cat === 'RAW' ? 'cartons' : 'boxes') + ' of ' + nm(lead) + ' — are you sure?')) return;
    if ((f.cat === 'RAW' || f.cat === 'FG') && !C.exp && !confirm('No expiry date entered. Add without expiry?')) return;
    var no = D.lines.reduce(function (m, l) { return Math.max(m, l.entry_no || 0); }, 0) + 1, pair = f.cat === 'LTRAY' ? 'P' + Date.now() : null, at = new Date().toISOString();
    f.items.forEach(function (it, k) {
      var u = units(f.cat, it), t = f.cat === 'LTRAY' && k > 0 ? tot : totalOf(f.cat, it, v);
      D.lines.push({ entry_no: no + k, shelf: C.shelf, category: f.cat, stock_type: (f.cat === 'RAW' || f.cat === 'FG') ? C.type : null, scanned_barcode: f.scanned, item_id: it.id,
        qty_big: u.some(function (x) { return x[0] === 'qty_big'; }) ? num(v.qty_big) : 0, qty_tray: f.cat === 'RAW' ? num(v.qty_tray) : 0, qty_small: num(v.qty_small),
        total_qty: t, unit: f.cat === 'FG' ? 'PACKS' : 'PCS', exp_date: (f.cat === 'RAW' || f.cat === 'FG') ? (C.exp || null) : null,
        country: f.cat === 'TRAY' ? null : (C.country || '').toUpperCase() || null, pair_key: pair, zero_confirmed: false, scanned_at: at });
    });
    store(V.id, D); C.found = null; C.v = {}; C.msg = '✓ Added ' + f.items.map(nm).join(' + ') + ' · ' + tot; render(); setTimeout(focusScan, 30);
  }
  function undo(no) { var l = D.lines.find(function (x) { return x.entry_no === no; }); if (!l) return;
    if (!confirm('Remove ' + nm(itemsBy(l.item_id)) + ' · ' + l.total_qty + '?')) return;
    D.lines = D.lines.filter(function (x) { return x.entry_no !== no && !(l.pair_key && x.pair_key === l.pair_key); }); store(V.id, D); render(); }
  function focusScan() { var s = root && root.querySelector('#mjscScan'); if (s) s.focus(); }
  function vCount() {
    var b = D.batch, f = C.found, h = '';
    if (C.msg) h += '<div class="' + (C.msg.charAt(0) === '✓' ? 'ok' : 'err') + '">' + esc(C.msg) + '</div>';
    h += '<div class="lbl">SHELF ID (stays until you change it)</div><input id="mjscShelf" value="' + esc(C.shelf) + '" placeholder="Type or scan the shelf" onchange="MJSC.shelf(this.value)" onkeydown="if(event.key===\'Enter\'){this.blur();}">';
    h += '<div class="lbl">CATEGORY</div><div class="pills">' + b.categories.map(function (c) { return '<button class="' + (C.cat === c ? 'on' : '') + '" onclick="MJSC.cat(\'' + c + '\')">' + CAT[c] + '</button>'; }).join('') + '</div>';
    h += '<div class="lbl">SCAN ' + (C.cat === 'RAW' ? 'THE FINISHED-GOOD BARCODE (finds its raw egg)' : 'THE PRODUCT BARCODE') + (C.cat === 'TRAY' || C.cat === 'LTRAY' || C.cat === 'LABEL' ? ' (finds its ' + (C.cat === 'LABEL' ? 'label' : C.cat === 'TRAY' ? 'tray' : 'tray + label') + ')' : '') + '</div>'
      + '<input id="mjscScan" placeholder="Scan or type barcode, then Enter" onkeydown="if(event.key===\'Enter\'){MJSC.scan(this.value);this.value=\'\';}">'
      + (C.cat === 'RAW' ? '<div class="pills" style="margin-top:6px">' + D.items.filter(function (i) { return i.t === 'RAW_EGG' && isRecount(i.id) && !D.bom.some(function (x) { return x.m === i.id; }); }).map(function (i) { return '<button onclick="MJSC.scan(\'' + esc(i.bc || i.code) + '\')">' + esc(nm(i)) + '</button>'; }).join('') + '</div>' : '');
    if (f) {
      var lead = f.items[0], u = units(f.cat, lead), v = C.v || {};
      h += '<div class="card" style="margin-top:10px"><div class="it">' + f.items.map(function (i) { return esc(nm(i)); }).join(' + ') + '</div><div class="mut">' + CAT[f.cat] + (f.fg ? ' · from ' + esc(nm(f.fg)) : '') + '</div>'
        + '<div class="q" style="margin-top:8px">' + u.map(function (x) { return '<label>' + x[1] + '<input type="number" inputmode="decimal" min="0" value="' + esc(v[x[0]] || '') + '" oninput="MJSC.q(\'' + x[0] + '\',this.value)"></label>'; }).join('') + '</div>'
        + '<div class="tot" id="mjscTot">= ' + totalOf(f.cat, lead, v) + ' ' + (f.cat === 'FG' ? 'packs' : 'pcs') + '</div>';
      if (f.cat === 'RAW' || f.cat === 'FG') h += '<div class="lbl">EXPIRY DATE</div><input type="date" value="' + esc(C.exp || '') + '" onchange="MJSC.exp(this.value)">';
      if (f.cat !== 'TRAY') h += '<div class="lbl">COUNTRY OF ORIGIN</div><select onchange="MJSC.cty(this.value)"><option value="">Choose…</option>' + D.countries.map(function (c) { return '<option' + (String(C.country || '').toUpperCase() === c ? ' selected' : '') + '>' + esc(c) + '</option>'; }).join('') + '</select>';
      if (TYPES[f.cat]) h += '<div class="lbl">STOCK TYPE</div><div class="pills">' + TYPES[f.cat].map(function (t) { return '<button data-sct="' + t + '" class="' + (C.type === t ? 'on' : '') + '" onclick="MJSC.type(\'' + t + '\')">' + TNAME[t] + '</button>'; }).join('') + '</div>';   // just above Add entry
      h += '<button class="big" onclick="MJSC.add()">Add entry</button></div>';
    }
    var last = D.lines.slice().sort(function (x, y) { return y.entry_no - x.entry_no; }).slice(0, 5);
    h += '<div class="lbl">LAST ENTRIES · ' + D.lines.length + ' in total</div><div class="card">' + (last.length ? last.map(function (l) { var it = itemsBy(l.item_id) || {};
      return '<div class="row"><div><b>' + esc(nm(it)) + '</b><div class="mut">#' + l.entry_no + ' · ' + esc(l.shelf || '') + ' · ' + CAT[l.category] + (l.stock_type ? ' · ' + TNAME[l.stock_type] : '') + (l.exp_date ? ' · exp ' + fmtD(l.exp_date) : '') + (l.country ? ' · ' + esc(l.country) : '') + '</div></div><span class="mono">' + l.total_qty + '</span><button onclick="MJSC.undo(' + l.entry_no + ')">Undo</button></div>'; }).join('') : '<div class="mut">No entries yet.</div>')
      + (D.lines.length > 5 ? '<button class="big" style="background:#fff;color:#147b3d;border:1px solid #147b3d" onclick="MJSC.all()">See all ' + D.lines.length + ' entries</button>' : '') + '</div>';
    shell(b.no, fmtD(b.date) + ' · ' + (b.counted_by || '') + (navigator.onLine ? '' : ' · OFFLINE'), h, '<button onclick="MJSC.save()">💾 Save</button><button class="pri" onclick="MJSC.prePost()">Post count</button>', 'toList');
  }
  function vAll() {
    var h = '<div class="card">' + D.lines.slice().sort(function (x, y) { return y.entry_no - x.entry_no; }).map(function (l) { var it = itemsBy(l.item_id) || {};
      return '<div class="row"><div><b>' + esc(nm(it)) + '</b><div class="mut">#' + l.entry_no + ' · ' + esc(l.shelf || '') + ' · ' + CAT[l.category] + (l.stock_type ? ' · ' + TNAME[l.stock_type] : '') + (l.exp_date ? ' · exp ' + fmtD(l.exp_date) : '') + (l.country ? ' · ' + esc(l.country) : '') + (l.zero_confirmed ? ' · zero' : '') + '</div></div><span class="mono">' + l.total_qty + '</span><button onclick="MJSC.undo(' + l.entry_no + ')">✕</button></div>'; }).join('') + '</div>';
    shell('All entries', D.batch.no + ' · ' + D.lines.length, h, '<button onclick="MJSC.count(' + V.id + ')">Back to counting</button>', 'backCount');
  }
  // items expected in the ticked categories but not counted → confirm zero before posting
  function missing() {
    var counted = {}; D.lines.forEach(function (l) { counted[l.category + '|' + l.item_id] = 1; });
    var out = [];
    D.batch.categories.forEach(function (cat) {
      var pool = cat === 'RAW' ? D.items.filter(function (i) { return i.t === 'RAW_EGG'; }) : cat === 'FG' ? D.items.filter(function (i) { return i.t === 'FG'; })
        : D.items.filter(function (i) { return i.t === 'MATERIAL' && i.k === (cat === 'LABEL' ? 'LABEL' : 'TRAY'); });
      pool.filter(function (i) { return isRecount(i.id) && !counted[cat + '|' + i.id]; }).forEach(function (i) { out.push({ cat: cat, it: i }); });
    });
    return out;
  }
  function vPost() {
    var m = missing(), h = '<div class="card"><b>' + D.lines.length + ' entries</b> will be posted for ' + esc(D.batch.no) + '.</div>';
    if (m.length) h += '<div class="lbl">NOT COUNTED — CONFIRM ZERO (' + m.length + ')</div><div class="card mut" style="margin-bottom:6px">These items of the ticked categories were not scanned. If there is really no stock, they are posted as zero. If there is stock, go back and count it.</div><div class="card">'
      + m.map(function (x) { return '<div class="row"><div>' + esc(nm(x.it)) + '<div class="mut">' + CAT[x.cat] + '</div></div><span class="mono">0</span></div>'; }).join('') + '</div>';
    shell('Post count', navigator.onLine ? 'Online' : 'OFFLINE — connect to post', h, '<button onclick="MJSC.count(' + V.id + ')">Back to counting</button><button class="pri" onclick="MJSC.post()"' + (busy ? ' disabled' : '') + '>' + (busy ? 'Posting…' : (m.length ? 'Confirm zero & post' : 'Post')) + '</button>', 'backCount');
  }
  async function save(quiet) {
    retot(D); store(V.id, D);
    if (!navigator.onLine) { C.msg = '✓ Saved on this device (offline). Post when you are online.'; render(); return; }
    try { await rpc('sc_upload', { p_id: V.id, p_lines: D.lines, p_post: false }); C.msg = '✓ Saved on this device and in the system (' + D.lines.length + ' entries).'; }
    catch (e) { C.msg = '✓ Saved on this device. (System: ' + (e.message || e) + ')'; }
    render();
  }
  async function post() {
    if (!navigator.onLine) { err = 'You are offline. Your count is saved on this device — post when connected.'; render(); return; }
    retot(D); var m = missing(), lines = D.lines.slice(), no = lines.reduce(function (x, l) { return Math.max(x, l.entry_no || 0); }, 0);
    m.forEach(function (x) { lines.push({ entry_no: ++no, shelf: null, category: x.cat, stock_type: (x.cat === 'RAW' || x.cat === 'FG') ? 'FRESH' : null, scanned_barcode: null, item_id: x.it.id, qty_big: 0, qty_tray: 0, qty_small: 0, total_qty: 0, unit: x.cat === 'FG' ? 'PACKS' : 'PCS', zero_confirmed: true, scanned_at: new Date().toISOString() }); });
    busy = true; err = ''; render();
    try { await rpc('sc_upload', { p_id: V.id, p_lines: lines, p_post: true }); busy = false; drop(V.id); D = null; C = null; V = { view: 'list', posted: true }; err = ''; await refresh(); root.querySelector('.bd').insertAdjacentHTML('afterbegin', '<div class="ok">✓ Count posted. Thank you.</div>'); }
    catch (e) { busy = false; err = 'Post failed — your count is still saved on this device. ' + (e.message || e); render(); }
  }

  function render() { if (!root) return; if (V.view === 'count' && D) vCount(); else if (V.view === 'all' && D) vAll(); else if (V.view === 'post' && D) vPost(); else { V.view = 'list'; vList(); } }

  window.MJSC = {
    open: function () { if (!root) { var st = document.createElement('style'); st.textContent = CSS; document.head.appendChild(st); root = document.createElement('div'); root.id = 'mjsc'; document.body.appendChild(root); }
      root.style.display = 'flex'; V = { view: 'list' }; err = ''; render(); refresh(); },
    close: function () { if (root) root.style.display = 'none'; },
    refresh: refresh, download: download, count: count,
    pick: function (id) { V.sel = V.sel === id ? null : id; render(); },
    toList: function () { if (D) store(V.id, D); V = { view: 'list' }; err = ''; render(); refresh(); },
    backCount: function () { V.view = 'count'; err = ''; render(); },
    shelf: function (v) { C.shelf = String(v || '').trim().toUpperCase(); localStorage.setItem('mjsc_shelf', C.shelf); render(); setTimeout(focusScan, 30); },
    cat: function (c) { C.cat = c; C.found = null; C.msg = ''; if (TYPES[c] && TYPES[c].indexOf(C.type) < 0) C.type = 'FRESH'; render(); setTimeout(focusScan, 30); },
    type: function (t) { C.type = t; root.querySelectorAll('[data-sct]').forEach(function (b) { b.className = b.getAttribute('data-sct') === t ? 'on' : ''; }); },   // update in place: the screen stays where it is
    scan: scan, add: addEntry, undo: undo,
    q: function (k, v) { C.v = C.v || {}; C.v[k] = v; var t = root.querySelector('#mjscTot'); if (t && C.found) t.textContent = '= ' + totalOf(C.found.cat, C.found.items[0], C.v) + ' ' + (C.found.cat === 'FG' ? 'packs' : 'pcs'); },
    exp: function (v) { C.exp = v; }, cty: function (v) { C.country = v; },
    all: function () { V.view = 'all'; render(); },
    save: function () { save(); }, prePost: function () { store(V.id, D); V.view = 'post'; err = ''; render(); }, post: post
  };
  window.addEventListener('online', function () { if (root && root.style.display === 'flex') render(); });
  window.addEventListener('offline', function () { if (root && root.style.display === 'flex') render(); });
})();
