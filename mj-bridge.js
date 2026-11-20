/* =====================================================================
 * MAHRJAN BRIDGE — runs the old van-sales app unchanged on the new database.
 * The app talks to "the sheet" with fetch(url?action=...) and fetch(url,{POST {stage:...}}).
 * This file answers those same calls from Supabase, in the same reply format as the
 * unit sheet's Apps Script (doGet / doPost), using the same rules (ported functions).
 * ===================================================================== */
(function () {
  'use strict';
  var SB_URL = 'https://xhndwjkqfqmmpfcglqzu.supabase.co', SB_KEY = 'sb_publishable_emOqI1PWaSA7B5s56v-ERg_RrxZ9weu';
  var FAKE = 'https://sheet.mahrjan.local/';                 // the app's "Apps Script URL" for each company
  var UNIT_CODE = { 'AL QUOZ': 'MGAZ', 'AJMAN': 'MGT' }, WH_CODE = { 'AL QUOZ': 'MGAZ', 'AJMAN': 'MGT' };
  var TZ_OFF = 240;
  window.MJ_FAKE = FAKE;
  try {   // both companies point to the bridge
    localStorage.setItem('vs2_endpoint', FAKE + 'AL%20QUOZ/exec');
    localStorage.setItem('vs2aj_endpoint', FAKE + 'AJMAN/exec');
  } catch (e) {}

  // ---------- the password typed on the login screen (the app hashes it before sending) ----------
  var lastPw = null;
  try {
    var imp = crypto.subtle.importKey.bind(crypto.subtle);
    crypto.subtle.importKey = function (fmt, key, alg, ext, use) {
      try { if (fmt === 'raw' && alg && (alg === 'PBKDF2' || alg.name === 'PBKDF2')) lastPw = new TextDecoder().decode(key); } catch (e) {}
      return imp(fmt, key, alg, ext, use);
    };
  } catch (e) {}

  // ---------- Supabase ----------
  var sbP = null;
  function sb() { if (!sbP) sbP = import('https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2/+esm').then(function (m) { return m.createClient(SB_URL, SB_KEY, { auth: { storageKey: window.MJ_AUTH_KEY || 'mj-app-auth' } }); }); return sbP; }
  async function q(p) { var r = await p; if (r.error) throw new Error(r.error.message); return r.data; }
  async function rpc(fn, args) { var c = await sb(); return q(c.rpc(fn, args)); }
  async function all(mk) { var out = []; for (var i = 0; ; i += 1000) { var d = await q(mk().range(i, i + 999)); out = out.concat(d); if (d.length < 1000) break; } return out; }
  async function byIds(table, cols, key, ids) { var c = await sb(), out = []; for (var i = 0; i < ids.length; i += 150) { var part = ids.slice(i, i + 150); out = out.concat(await all(function () { return c.from(table).select(cols).in(key, part); })); } return out; }

  // ---------- helpers (same as the sheet script) ----------
  function num(v) { if (v === null || v === undefined || v === '') return 0; var n = Number(String(v).replace(/,/g, '')); return isNaN(n) ? 0 : n; }
  function up(v) { return String(v == null ? '' : v).replace(/\s+/g, ' ').trim().toUpperCase(); }
  function blank_(n) { return n ? n : ''; }
  function today() { return new Date(Date.now() + (new Date().getTimezoneOffset() + TZ_OFF) * 60000).toISOString().slice(0, 10); }
  function invTail_(v) { var m = String(v == null ? '' : v).replace(/\s+/g, '').match(/(\d+)$/); return m ? String(Number(m[1])) : ''; }
  var CARTON_RATE = { 'CARTON SMALL': 0.5, 'CARTON BIG': 0.25 };
  function cartonQty_(e) { var m = String(e.note || '').match(/^\s*(\d+)\s*@/); if (m) return Number(m[1]); var ty = String(e.type || '').trim().toUpperCase(); var rate = /^CARTON\s*S/.test(ty) ? 0.5 : /^CARTON\s*B/.test(ty) ? 0.25 : 0; return rate ? Math.round(e.amount / rate) : 0; }
  function Sheet_(w) { this.w = w; this.rows = []; this.bold = []; this.head = []; this.money = []; this.segs = {}; this.sign = []; this.fmt = []; this.titles = []; }
  Sheet_.prototype.add = function (arr, kind, segs) { var r = arr.slice(0, this.w); while (r.length < this.w) r.push(''); this.rows.push(r); var i = this.rows.length - 1;
    if (kind === 'head') { this.head.push(i); this.segs[i] = segs || [[1, this.w]]; } if (kind === 'sign') this.sign.push(i); if (kind === 'title') this.titles.push(i);
    if (kind === 'bold' || kind === 'head' || kind === 'total' || kind === 'sign' || kind === 'title') this.bold.push(i); return this; };
  Sheet_.prototype.gap = function () { return this.add([]); };

  // ---------- masters (cached a few minutes per company) ----------
  var M = {};
  async function masters(unit) {
    var m = M[unit]; if (m && Date.now() - m.at < 300000) return m;
    var c = await sb(), code = UNIT_CODE[unit] || 'MGAZ';
    var br = (await q(c.from('branches').select('*'))).filter(function (b) { return b.code === code; })[0]; if (!br) throw new Error('Company ' + unit + ' not found');
    var res = await Promise.all([q(c.from('items').select('*').order('display_order')), q(c.from('staff').select('id,name,role,branch_id,itrade_name,active,can_login')),
      q(c.from('vans').select('*')), q(c.from('routes').select('*')), all(function () { return c.from('customers').select('id,itrade_code,name,branch_id,active').eq('branch_id', br.id); }),
      all(function () { return c.from('customer_assignment').select('customer_id,salesman_id,route_id').is('to_date', null); }), q(c.from('v_fg_bom').select('*'))]);
    m = { at: Date.now(), unit: unit, br: br, items: res[0], staff: res[1], vans: res[2], routes: res[3], customers: res[4], assign: res[5], bom: res[6] };
    m.code = function (it) { return String(it.barcode || it.itrade_code || ''); };
    m.itemByCode = {}; m.items.forEach(function (it) { if (it.barcode) m.itemByCode[String(it.barcode)] = it; if (it.itrade_code && !m.itemByCode[String(it.itrade_code)]) m.itemByCode[String(it.itrade_code)] = it; });
    m.itemById = {}; m.items.forEach(function (it) { m.itemById[it.id] = it; });
    m.staffById = {}; m.staff.forEach(function (s) { m.staffById[s.id] = s; });
    m.salesmen = m.staff.filter(function (s) { return s.role === 'SALESMAN' && s.branch_id === br.id; });
    m.smByName = function (n) { n = up(n); return m.staff.filter(function (s) { return s.role === 'SALESMAN' && (up(s.name) === n || up(s.itrade_name) === n); })[0] || null; };
    var routeOf = {}; m.assign.forEach(function (a) { if (!a.route_id) return; var o = routeOf[a.salesman_id] = routeOf[a.salesman_id] || {}; o[a.route_id] = (o[a.route_id] || 0) + 1; });
    m.routeName = function (sid) { var o = routeOf[sid]; if (!o) return ''; var best = Object.keys(o).sort(function (a, b) { return o[b] - o[a]; })[0]; var r = m.routes.filter(function (x) { return String(x.id) === best; })[0]; return r ? r.name : ''; };
    M[unit] = m; return m;
  }

  // ---------- one day's data in the shapes the sheet script reads ----------
  async function dayData(m, date) {
    var c = await sb();
    var days = await q(c.from('van_day').select('*').eq('branch_id', m.br.id).eq('business_date', date));
    var ids = days.map(function (d) { return d.id; });
    var res = await Promise.all([ids.length ? byIds('loading_lines', '*', 'van_day_id', ids) : [], ids.length ? byIds('return_lines', '*', 'van_day_id', ids) : [],
      ids.length ? byIds('expenses', '*', 'van_day_id', ids) : [], ids.length ? byIds('collections', '*', 'van_day_id', ids) : [],
      all(function () { return c.from('sales_lines').select('*').eq('branch_id', m.br.id).eq('tran_date', date).order('id'); }),
      q(c.from('petty_cash').select('*').eq('branch_id', m.br.id).eq('entry_date', date)).catch(function () { return []; })]);
    var D = { date: date, days: days, load: res[0], ret: res[1], exp: res[2], col: res[3], sales: res[4], petty: res[5] };
    var smOfDay = {}; days.forEach(function (d) { smOfDay[d.id] = (m.staffById[d.salesman_id] || {}).name || ''; });
    var custById = {}; m.customers.forEach(function (x) { custById[x.id] = x; });
    var C = function (it) { return it ? m.code(it) : ''; };
    D.boards = {}; D.load.forEach(function (l) { var sm = smOfDay[l.van_day_id], cd = C(m.itemById[l.item_id]); if (!sm || !cd) return; (D.boards[sm] = D.boards[sm] || {})[cd] = (D.boards[sm][cd] || 0) + num(l.qty); });
    D.rets = {}; D.ret.forEach(function (l) { var sm = smOfDay[l.van_day_id], cd = C(m.itemById[l.item_id]); if (!sm || !cd) return; var o = (D.rets[sm] = D.rets[sm] || {}); var x = o[cd] || { good: 0, dmg: 0, exp: 0, wst: 0, foc: 0 };
      x.good += num(l.good); x.dmg += num(l.damage); x.exp += num(l.expiry); x.wst += num(l.waste); x.foc += num(l.foc); o[cd] = x; });
    D.exps = {}; D.exp.forEach(function (e) { var sm = smOfDay[e.van_day_id]; if (!sm) return; var cu = custById[e.customer_id] || {}, ty = e.expense_type, note = e.note || '';
      if (ty === 'OTHER' && /\s—\s/.test(note) && !/^OTHER$/i.test(note)) { var p = note.split(' — '); ty = p.shift(); note = p.join(' — '); } else if (ty === 'OTHER' && note === 'OTHER') note = '';
      (D.exps[sm] = D.exps[sm] || []).push({ type: ty, amount: num(e.amount), note: note, ref: '', customer: cu.name || '', head: cu.itrade_code || '' }); });
    D.cols = {}; D.col.forEach(function (x) { var sm = smOfDay[x.van_day_id]; if (!sm) return; var cu = custById[x.customer_id] || {};
      (D.cols[sm] = D.cols[sm] || []).push({ tran: /^NA-/.test(x.receipt_no) ? '' : x.receipt_no, invoice: x.invoice_no || '', head: cu.itrade_code || '', customer: cu.name || '', mode: x.mode, amount: num(x.amount) }); });
    // sales: keyed by the salesman (or the iTrade user for store sales), as RAW SALES "User"
    D.lines = D.sales.map(function (l) { var s = m.staffById[l.salesman_id]; return { user: s ? s.name : up(l.itrade_user || l.sales_executive), inv: String(l.invoice_no || '').trim(), type: String(l.tran_type || '').toUpperCase() === 'CR' ? 'CR' : 'SR',
      tender: String(l.tender_type || '').toUpperCase(), head: l.customer_code || '', cust: String(l.customer_name || '').replace(/\s+/g, ' ').trim(), invTotal: null, line: num(l.net_incl_vat),
      deleted: !!l.cancelled && l.cancel_reason === 'DELETE LIST', cancelled: !!l.cancelled, code: l.item_id && m.itemById[l.item_id] ? C(m.itemById[l.item_id]) : String(l.item_code || ''), name: l.item_name || '', qty: num(l.qty) }; });
    D.salesMap = {}; D.grv = {};
    D.lines.forEach(function (l) { if (l.cancelled || !l.user || !l.code) return; (D.salesMap[l.user] = D.salesMap[l.user] || {})[l.code] = (D.salesMap[l.user][l.code] || 0) + l.qty;
      if (l.qty < 0) (D.grv[l.user] = D.grv[l.user] || {})[l.code] = (D.grv[l.user][l.code] || 0) - l.qty; });
    D.office = D.petty.map(function (p) { return { type: p.line_type, ref: p.ref || '', party: p.party || '', note: p.note || '', forDate: p.for_date || '', amount: num(p.amount) }; });
    var hm = function (t) { return t ? String(t).slice(0, 5) : ''; };
    D.temps = {}; days.forEach(function (d) { var sm = smOfDay[d.id]; if (!sm) return; var x = D.temps[sm] = {};
      if (d.load_time) x.load = { time: hm(d.load_time), temp: d.load_temp == null ? '' : String(d.load_temp), km: d.start_km == null ? '' : String(d.start_km) };
      if (d.unload_time) x.unload = { time: hm(d.unload_time), temp: d.unload_temp == null ? '' : String(d.unload_temp), km: d.end_km == null ? '' : String(d.end_km) }; });
    D.vanOf = function (sm) { var d = days.filter(function (x) { return up(smOfDay[x.id]) === up(sm); })[0]; var v = d && m.vans.filter(function (x) { return x.id === d.van_id; })[0]; return v ? v.van_no : ''; };
    D.dayOf = function (sm) { return days.filter(function (x) { return up(smOfDay[x.id]) === up(sm); })[0] || null; };
    return D;
  }
  function readItems(m) { return m.items.filter(function (it) { return it.item_type !== 'MATERIAL' && m.code(it); }).map(function (it) {
    return { code: m.code(it), name: it.name, shortName: it.short_name || '', status: it.active ? 'ACTIVE' : 'INACTIVE', type: it.item_type === 'RAW_EGG' ? 'RAW' : '' }; }); }
  function readRoute(m) { return m.salesmen.filter(function (s) { return s.active; }).map(function (s) { return { salesman: s.name, route: m.routeName(s.id), van: '' }; }); }
  function readCustomers(m) { var cu = {}; m.customers.forEach(function (x) { cu[x.id] = x; });
    return m.assign.filter(function (a) { return cu[a.customer_id] && m.staffById[a.salesman_id]; }).map(function (a) { var x = cu[a.customer_id]; return { salesman: m.staffById[a.salesman_id].name, head: x.itrade_code || '', name: x.name }; }); }
  async function readReqs(m, date) { var c = await sb(), L = await q(c.from('requirement_lines').select('*').eq('branch_id', m.br.id).eq('required_date', date)), out = {};
    L.forEach(function (r) { var s = m.staffById[r.salesman_id], it = m.itemById[r.item_id]; if (!s || !it) return; var k = it.short_name || it.name; (out[s.name] = out[s.name] || {})[k] = (out[s.name][k] || 0) + num(r.qty_cartons); }); return out; }

  // ---------- reports (ported from the sheet script) ----------
  function man_(m, D, who) { var r = readRoute(m).filter(function (x) { return up(x.salesman) === up(who); })[0]; var info = r ? { salesman: r.salesman, route: r.route, van: r.van } : { salesman: who, route: '', van: '' }; var v = D.vanOf(who); if (v) info.van = v; return info; }
  function invoices_(lines) { var by = {}, list = []; lines.forEach(function (l) { if (!l.inv) return; var x = by[l.inv];
      if (!x) { x = by[l.inv] = { user: l.user, inv: l.inv, type: l.type, tender: l.tender, head: l.head, cust: l.cust, deleted: l.deleted, total: 0 }; list.push(x); } x.total += l.line || 0; });
    list.forEach(function (x) { x.total = Math.round(x.total * 100) / 100; }); return list; }
  function erpLines_(D, keepDeleted) { return D.lines.filter(function (l) { return keepDeleted ? (!l.cancelled || l.deleted) : !l.cancelled; }); }
  async function kmFor_(m, D, sm) { var d = D.dayOf(sm), o = { sk: d && d.start_km != null ? d.start_km : '', ek: d && d.end_km != null ? d.end_km : '' };
    if (o.sk === '' && d) { var c = await sb(); var prev = await q(c.from('van_day').select('end_km').eq('salesman_id', d.salesman_id).lt('business_date', D.date).not('end_km', 'is', null).order('business_date', { ascending: false }).limit(1)); if (prev[0]) o.sk = prev[0].end_km; }
    return o; }
  async function loadingSheet_(o, m, D, sm, reqs) {
    if (!sm) { o.add(['Choose a salesman in E2']); return; }
    var info = man_(m, D, sm), items = readItems(m), board = D.boards[sm] || {}, rets = D.rets[sm] || {}, sale = {}, grv = {}, names = {};
    D.lines.forEach(function (l) { if (l.cancelled || up(l.user) !== up(sm)) return; if (l.qty >= 0) sale[l.code] = (sale[l.code] || 0) + l.qty; else grv[l.code] = (grv[l.code] || 0) - l.qty; names[l.code] = l.name; });
    var req = {}; var R = reqs[sm] || {}; items.forEach(function (it) { if (it.shortName && R[it.shortName]) req[it.code] = R[it.shortName]; });
    var t = D.temps[sm] || {}, tt = { lt: t.load ? t.load.time : '', lp: t.load ? t.load.temp : '', ut: t.unload ? t.unload.time : '', up: t.unload ? t.unload.temp : '' };
    var kv = function (k, v) { return k + ':  ' + (v === '' || v == null ? '________' : v); };
    o.add(['', kv('VEHICLE', info.van), kv('ROUTE', info.route), '', '', '', kv('LOADING TIME', tt.lt), '', '', '', kv('UNLOADING TIME', tt.ut)], 'bold');
    var km = await kmFor_(m, D, sm);
    o.add(['', kv('LOADING TEMP', tt.lp), kv('UNLOADING TEMP', tt.up), '', '', '', kv('START KM', km.sk), '', '', '', kv('END KM', km.ek)], 'bold');
    o.gap();
    o.add(['SL', 'ITEM', 'BARCODE', 'REQ', 'LOAD', 'SALE', 'GRV', 'GOOD', 'DAMAGE', 'EXP', 'WST', 'FOC', 'EXCESS', 'SHORT', 'EXP SIGN'], 'head', [[1, 15]]);
    var rawSet = {}; items.forEach(function (i) { if (i.type === 'RAW') rawSet[i.code] = 1; });
    var codes = items.filter(function (i) { return !rawSet[i.code]; }).map(function (i) { return i.code; });
    [board, sale, grv, rets, req].forEach(function (mm) { Object.keys(mm).forEach(function (c) { if (!rawSet[c] && codes.indexOf(c) < 0) codes.push(c); }); });
    var T = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0], sl = 0;
    codes.forEach(function (c) { var it = items.filter(function (i) { return i.code === c; })[0], r = rets[c] || { good: 0, dmg: 0, exp: 0, wst: 0, foc: 0 };
      var v = [req[c] || 0, board[c] || 0, sale[c] || 0, grv[c] || 0, r.good, r.dmg, r.exp, r.wst || 0, r.foc], moved = v.some(function (x) { return x; }), active = it && String(it.status || '').toUpperCase() !== 'INACTIVE';
      if (!moved && !active) return;
      var diff = (r.good + r.dmg + r.exp + (r.wst || 0) + r.foc) - (v[1] - v[2] + v[3]), ex = diff > 0 ? diff : 0, sh = diff < 0 ? -diff : 0;
      v.push(ex, sh); v.forEach(function (x, k) { T[k] += x; }); sl++;
      o.add([sl, it ? it.name : (names[c] || 'NOT IN ITEM_LIST'), c].concat(v.map(blank_), [''])); });
    o.add(['', 'TOTAL', ''].concat(T.map(blank_), ['']), 'total'); o.gap();
    var exps = D.exps[sm] || [], small = 0, big = 0;
    exps.forEach(function (e) { var t2 = String(e.type).trim().toUpperCase(); if (/^CARTON\s*S/.test(t2)) small += cartonQty_(e); if (/^CARTON\s*B/.test(t2)) big += cartonQty_(e); });
    o.add(['', 'EMPTY CARTONS', 'QTY'], 'head', [[2, 3]]); o.add(['', 'CARTON SMALL', small || 'NIL']); o.add(['', 'CARTON BIG', big || 'NIL']); o.gap();
    o.add(['', 'NOTE: Expired and spoiled eggs are not accepted by the company']); o.gap(); o.gap();
    o.add(['', 'SALESMAN SIGN', 'MANAGER SIGN'], 'sign');
  }
  function salesmanSummary_(o, m, D, sm) {
    if (!sm) { o.add(['Choose a salesman in E2']); return; }
    var info = man_(m, D, sm); o.money = [5, 6, 8, 9, 10];
    o.add(['', 'VEHICLE:  ' + info.van, '', 'ROUTE:  ' + info.route], 'bold'); o.gap();
    var lines = erpLines_(D), cs = 0, cr = 0, gc = 0, gr = 0;
    o.add(['SALES'], 'title'); o.add(['SL', 'HEAD NO', 'CUSTOMER', 'SALE INV', 'CASH', 'CREDIT', 'GRV INV', 'GRV CASH', 'GRV CREDIT', 'NET'], 'head', [[1, 10]]);
    var inv = invoices_(lines.filter(function (l) { return up(l.user) === up(sm); })), shops = [], byShop = {}, shortInv = function (s) { var p = String(s).split('-'); return p[p.length - 1]; };
    inv.forEach(function (l) { var k = (l.head || '') + '|' + l.cust, c = byShop[k]; if (!c) { c = byShop[k] = { head: l.head, cust: l.cust, si: [], gi: [], cs: 0, cr: 0, gc: 0, gr: 0 }; shops.push(c); }
      var cash = l.tender === 'CASH', a = Math.abs(l.total); if (l.type === 'SR') { c.gi.push(shortInv(l.inv)); if (cash) c.gc += a; else c.gr += a; } else { c.si.push(shortInv(l.inv)); if (cash) c.cs += a; else c.cr += a; } });
    shops.forEach(function (c, i) { cs += c.cs; cr += c.cr; gc += c.gc; gr += c.gr; o.add([i + 1, c.head, c.cust, c.si.join(', '), c.cs || '', c.cr || '', c.gi.join(', '), c.gc ? -c.gc : '', c.gr ? -c.gr : '', c.cs + c.cr - c.gc - c.gr]); });
    if (!shops.length) o.add(['', 'No invoices for this salesman on this date']);
    o.add(['', '', 'TOTAL', '', cs, cr, '', gc ? -gc : 0, gr ? -gr : 0, cs + cr - gc - gr], 'total'); o.gap();
    var dels = invoices_(erpLines_(D, true).filter(function (l) { return l.deleted && up(l.user) === up(sm); }));
    o.add(['DELETED BILLS (NOT COUNTED ABOVE)'], 'title'); o.add(['SL', 'HEAD NO', 'CUSTOMER', 'INVOICE', 'CASH', 'CREDIT', 'TYPE'], 'head', [[1, 7]]);
    var dc = 0, dr = 0; dels.forEach(function (l, i) { var a = Math.abs(l.total), cash = l.tender === 'CASH'; if (cash) dc += a; else dr += a; o.add([i + 1, l.head, l.cust, l.inv, cash ? a : '', cash ? '' : a, l.type === 'SR' ? 'GRV' : 'SALE']); });
    o.add(['', '', dels.length ? 'TOTAL' : 'None', '', dels.length ? dc : '', dels.length ? dr : '', ''], dels.length ? 'total' : undefined); o.gap();
    var cols = D.cols[sm] || [], exps = D.exps[sm] || [], cc = 0, cq = 0, et = 0;
    cols.forEach(function (c) { if (c.mode === 'CHEQUE') cq += c.amount; else cc += c.amount; }); exps.forEach(function (e) { et += e.amount; });
    var settle = [['CHEQUES TO HAND OVER', cq], ['CREDIT SALES (NET OF GRV)', cr - gr], ['CASH COLLECTION', cc], ['ADD   CASH SALES', cs], ['LESS  CASH GRV', -gc], ['LESS  EXPENSES', -et], ['CASH TO HAND OVER', cc + cs - gc - et]];
    o.money = [5, 6, 8, 9, 10, 12];
    o.add(['COLLECTION (EARLIER INVOICES)', '', '', '', '', '', '', 'EXPENSES', '', '', 'SETTLEMENT'], 'title');
    var hRow = o.rows.length;
    o.add(['SL', 'HEAD NO', 'CUSTOMER', 'INVOICE', 'CASH', 'CHEQUE', '', 'TYPE', 'AMOUNT', '', 'ITEM', 'AMOUNT'], 'head', [[1, 6], [8, 9], [11, 12]]);
    var n = Math.max(cols.length + 1, exps.length + 1, settle.length);
    for (var i = 0; i < n; i++) { var r = ['', '', '', '', '', '', '', '', '', '', '', ''], c = cols[i];
      if (c) { r[0] = i + 1; r[1] = c.head; r[2] = c.customer; r[3] = c.invoice; r[4] = c.mode === 'CHEQUE' ? '' : c.amount; r[5] = c.mode === 'CHEQUE' ? c.amount : ''; }
      else if (i === cols.length) { r[2] = cols.length ? 'TOTAL' : 'None'; if (cols.length) { r[4] = cc; r[5] = cq; } }
      var e = exps[i]; if (e) { var ct = String(e.type).toUpperCase().indexOf('CARTON') === 0 ? cartonQty_(e) : 0; r[7] = e.type + (ct ? ' (' + ct + ')' : ''); r[8] = e.amount; }
      else if (i === exps.length) { r[7] = exps.length ? 'TOTAL' : 'None'; if (exps.length) r[8] = et; }
      var s = settle[i]; if (s) { r[10] = s[0]; r[11] = s[1]; }
      o.add(r, i === 6 ? 'bold' : undefined); }
    o.fmt.push([hRow + 1, 12, settle.length, '#,##0.00']); o.gap(); o.gap(); o.gap();
    o.add(['', 'SALESMAN SIGN', '', 'CASHIER SIGN', '', '', '', 'MANAGER SIGN'], 'sign');
  }
  var EXP_COLS = ['FUEL', 'PARKING', 'CARTON'];
  function expCol_(type) { var t = String(type || '').toUpperCase(); if (t === 'FUEL' || t === 'PARKING' || t === 'CREDIT NOTE' || t === 'SHELF RENT') return t; if (t.indexOf('CARTON') === 0) return 'CARTON'; return 'OTHER'; }
  function payPart_(man, c, e) { var tag = c === 'CREDIT NOTE' ? 'CN' : (c === 'SHELF RENT' ? 'SR' : ''); if (tag && e.customer) return [tag, man, e.head, e.customer, e.note].filter(function (x) { return String(x || '').trim(); }).join(' — ');
    return man + ' — ' + (c === 'OTHER' ? (String(e.type || '').toUpperCase() || 'OTHER') : c) + (e.note ? ' — ' + e.note : ''); }
  async function cashFigures_(m, D) {
    var order = readRoute(m).map(function (r) { return r.salesman; }), vans = order.map(up);
    var F = { order: order, rows: {}, receipts: [], payments: [], deposits: [], cheques: 0 };
    var row = function (k) { return F.rows[k] = F.rows[k] || { cs: 0, cr: 0, gc: 0, gr: 0, FUEL: 0, PARKING: 0, CARTON: 0, 'CREDIT NOTE': 0, 'SHELF RENT': 0, OTHER: 0 }; };
    order.concat(['STORE']).forEach(row);
    invoices_(erpLines_(D)).forEach(function (l) { var at = vans.indexOf(up(l.user)), b = row(at > -1 ? order[at] : 'STORE'), a = Math.abs(l.total), cash = l.tender === 'CASH';
      if (l.type === 'SR') { if (cash) b.gc += a; else b.gr += a; } else { if (cash) b.cs += a; else b.cr += a; } });
    Object.keys(D.exps).forEach(function (s) { var at = vans.indexOf(up(s)), b = row(at > -1 ? order[at] : s);
      D.exps[s].forEach(function (e) { var c = expCol_(e.type); b[c] += e.amount; if (EXP_COLS.indexOf(c) < 0) F.payments.push({ ref: e.ref || '', part: payPart_(at > -1 ? order[at] : s, c, e), amount: e.amount }); }); });
    Object.keys(D.cols).forEach(function (s) { D.cols[s].forEach(function (c) { if (c.mode === 'CHEQUE') { F.cheques += c.amount; return; } F.receipts.push({ ref: invTail_(c.invoice) || c.invoice, part: s + ' — ' + c.customer, amount: c.amount }); }); });
    D.office.forEach(function (p) {
      if (p.type === 'RECEIPT') F.receipts.push({ ref: p.ref, part: 'PETTY CASH — ' + p.party + (p.note ? ' — ' + p.note : ''), amount: p.amount });
      else if (p.type === 'PAYMENT' || p.type === 'FOOD ALLOWANCE' || p.type === 'TRAVEL ALLOWANCE') F.payments.push({ ref: p.ref, part: 'PETTY CASH — ' + (p.type === 'PAYMENT' ? '' : p.type + ' — ') + p.party + (p.note ? ' — ' + p.note : ''), amount: p.amount }); });
    var c2 = await sb();
    var sus = await q(c2.from('petty_cash').select('entry_date,line_type,party,amount').eq('branch_id', m.br.id).in('line_type', ['SUSPENSE', 'SUSPENSE CLEARED']).lte('entry_date', D.date)).catch(function () { return []; });
    var by = {}, list = []; sus.forEach(function (r) { var nm = up(r.party) || 'UNNAMED', b = by[nm]; if (!b) { b = by[nm] = { name: nm, given: 0, cleared: 0, before: 0, today: false }; list.push(b); }
      var a = num(r.amount); if (r.line_type === 'SUSPENSE') b.given += a; else b.cleared += a; if (r.entry_date < D.date) b.before += r.line_type === 'SUSPENSE' ? a : -a; if (r.entry_date === D.date) b.today = true; });
    F.suspense = list.filter(function (b) { return Math.abs(b.given - b.cleared) > 0.004 || Math.abs(b.before) > 0.004 || b.today; }).sort(function (a, b) { return a.name < b.name ? -1 : 1; });
    var dep = await q(c2.from('petty_cash').select('*').eq('branch_id', m.br.id).eq('line_type', 'DEPOSIT').or('for_date.eq.' + D.date + ',and(for_date.is.null,entry_date.eq.' + D.date + ')')).catch(function () { return []; });
    F.deposits = dep.map(function (p) { return { on: p.entry_date, party: p.party || '', ref: p.ref || '', amount: num(p.amount) }; });
    var sum = function (l) { return l.reduce(function (a, x) { return a + x.amount; }, 0); };
    var T = { cs: 0, cr: 0, gc: 0, gr: 0, FUEL: 0, PARKING: 0, CARTON: 0, 'CREDIT NOTE': 0, 'SHELF RENT': 0, OTHER: 0 };
    Object.keys(F.rows).forEach(function (k) { Object.keys(T).forEach(function (f) { T[f] += F.rows[k][f]; }); });
    F.tot = T; F.rc = sum(F.receipts); F.pay = sum(F.payments); F.dep = sum(F.deposits); F.et = EXP_COLS.reduce(function (a, c) { return a + T[c]; }, 0);
    return F;
  }
  function susOut_(F) { return (F.suspense || []).reduce(function (a, x) { return a + (x.given - x.cleared); }, 0); }
  function cashPosition_(F, o) { o = Number(o) || 0; var cl = o + F.tot.cs - F.tot.gc + F.rc - F.pay - F.et - F.dep;
    return [['OPENING CASH BALANCE', o], ['+ CASH SALES', F.tot.cs], ['− CASH SALES RETURN', F.tot.gc], ['+ CASH RECEIPTS', F.rc], ['− PAYMENTS', F.pay], ['− EXPENSES', F.et], ['− BANK DEPOSITS', F.dep], ['CLOSING BALANCE', cl], ['− SUSPENSE OUTSTANDING', susOut_(F)], ['CASH IN HAND', cl - susOut_(F)]]; }
  function cashRows_(o, F, opening) {
    o.money = [2, 3, 4, 5, 6, 7, 8, 10]; var T = F.tot;
    var men = F.order.concat(['STORE']).map(function (k) { var r = F.rows[k]; return [k === 'STORE' ? 'STORE SALE' : k, r.cs, r.cr, r.gc, r.gr, r.FUEL, r.PARKING, r.CARTON]; });
    men.push(['TOTAL', T.cs, T.cr, T.gc, T.gr, T.FUEL, T.PARKING, T.CARTON]);
    var pos = cashPosition_(F, opening), put = function (row, at, vals) { vals.forEach(function (v, j) { row[at - 1 + j] = v; }); return row; }, blank = function () { return ['', '', '', '', '', '', '', '', '', '']; };
    o.add(put(put(blank(), 1, ['SALES · RETURNS · EXPENSES']), 9, ['CASH SETTLEMENT']), 'title');
    o.add(put(put(blank(), 1, ['SALESMAN', 'SALE CASH', 'SALE CREDIT', 'RET CASH', 'RET CREDIT', 'FUEL', 'PARKING', 'CARTON']), 9, ['ITEM', 'AMOUNT']), 'head', [[1, 8], [9, 10]]);
    for (var i = 0; i < Math.max(men.length, pos.length); i++) { var r = blank(); if (men[i]) put(r, 1, men[i]); if (pos[i]) put(r, 9, pos[i]); o.add(r); }
    o.gap();
    var ref = function (v) { return v === '' || v == null ? '' : String(v); };
    var rec = F.receipts.map(function (x) { return [ref(x.ref), x.part, x.amount]; }); rec.push(['', 'TOTAL RECEIPTS', F.rc]);
    var pay = F.payments.map(function (x) { return [ref(x.ref), x.part, x.amount]; }); pay.push(['', 'TOTAL PAYMENTS', F.pay]);
    var sus = F.suspense.filter(function (x) { return Math.abs(x.given - x.cleared) > 0.004; }).map(function (x) { return [x.name, x.given - x.cleared]; }); sus.push(['TOTAL', sus.reduce(function (a, x) { return a + x[1]; }, 0)]);
    o.add(put(put(put(blank(), 1, ['RECEIPTS']), 5, ['PAYMENTS']), 9, ['SUSPENSE']), 'title');
    o.add(put(put(put(blank(), 1, ['REF', 'PARTICULARS', 'AMOUNT']), 5, ['REF', 'PARTICULARS', 'AMOUNT']), 9, ['PARTICULARS', 'AMOUNT']), 'head', [[1, 3], [5, 7], [9, 10]]);
    for (var k = 0; k < Math.max(rec.length, pay.length, sus.length); k++) { var qq = blank(); if (rec[k]) put(qq, 1, rec[k]); if (pay[k]) put(qq, 5, pay[k]); if (sus[k]) put(qq, 9, sus[k]);
      if (rec[k] && rec[k][0] === '') qq[0] = ' '; if (pay[k] && pay[k][0] === '') qq[4] = ' '; o.add(qq); }
    o.gap(); o.add(['CREATED BY', 'VERIFIED BY', 'APPROVED BY'], 'sign');
  }
  async function salesmanClosing_(o, m, D, sm, reqs) {
    await loadingSheet_(o, m, D, sm, reqs); if (!sm) return;
    o.gap(); o.add(['MAHRJAN GENERAL TRADING LLC — SALESMAN SUMMARY'], 'title'); o.gap();
    var t = new Sheet_(12); salesmanSummary_(t, m, D, sm);
    var MAP = { 1: 1, 2: 3, 3: 2, 4: 4, 5: 5, 6: 6, 7: 7, 8: 8, 9: 9, 10: 10 }, remap = function (r) { var n = ['', '', '', '', '', '', '', '', '', '', '', '', '']; for (var c = 1; c <= 10; c++) n[MAP[c] - 1] = r[c - 1]; return n; };
    var splitAt = -1; for (var i = 0; i < t.rows.length; i++) if (t.head.indexOf(i) > -1 && t.segs[i].length > 1) { splitAt = i; break; }
    var upto = splitAt > -1 ? splitAt - 1 : t.rows.length;
    for (var k = 1; k < upto; k++) { var r = t.rows[k], kind = t.head.indexOf(k) > -1 ? 'head' : (t.titles.indexOf(k) > -1 ? 'title' : (t.bold.indexOf(k) > -1 ? 'bold' : undefined)); o.add(remap(r), kind, kind === 'head' ? [[1, 10]] : undefined); }
    if (splitAt < 0) return;
    var titleRow = t.rows[splitAt - 1], pull = function (a, b) { var out = []; for (var k2 = splitAt + 1; k2 < t.rows.length; k2++) { var src = t.rows[k2].slice(a - 1, b); if (!src.some(function (v) { return v !== '' && v != null; })) break; out.push(src); } return out; };
    o.gap(); o.add([titleRow[0] || 'COLLECTION'], 'title');
    var hr = ['', '', '', '', '', '', '', '', '', '', '', '', '']; [[1, 'SL'], [3, 'HEAD NO'], [2, 'CUSTOMER'], [4, 'INVOICE'], [5, 'CASH'], [6, 'CHEQUE']].forEach(function (x) { hr[x[0] - 1] = x[1]; });
    o.add(hr, 'head', [[1, 6]]);
    pull(1, 6).forEach(function (src) { var nr = ['', '', '', '', '', '', '', '', '', '', '', '', '']; [1, 3, 2, 4, 5, 6].forEach(function (cc, j) { nr[cc - 1] = src[j]; });
      o.add(nr, src.some(function (v) { return String(v).toUpperCase() === 'TOTAL'; }) ? 'total' : undefined); });
    var ex = pull(8, 9), st = pull(11, 12); o.gap();
    var tr = ['', '', '', '', '', '', '', '', '', '', '', '', '']; tr[1] = titleRow[7] || 'EXPENSES'; tr[3] = titleRow[10] || 'SETTLEMENT'; o.add(tr, 'title');
    o.add(['', 'TYPE', 'AMOUNT', 'ITEM', '', '', '', 'AMOUNT', '', '', '', '', ''], 'head', [[2, 3], [4, 8]]);
    for (var q2 = 0; q2 < Math.max(ex.length, st.length); q2++) { var nr2 = ['', '', '', '', '', '', '', '', '', '', '', '', '']; if (ex[q2]) { nr2[1] = ex[q2][0]; nr2[2] = ex[q2][1]; } if (st[q2]) { nr2[3] = st[q2][0]; nr2[7] = st[q2][1]; }
      o.add(nr2, (ex[q2] && String(ex[q2][0]).toUpperCase() === 'TOTAL') || (st[q2] && String(st[q2][0]).toUpperCase() === 'CASH TO HAND OVER') ? 'total' : undefined); }
    o.gap(); o.gap(); o.add(['', 'SALESMAN SIGN', '', 'CASHIER SIGN', '', '', '', 'MANAGER SIGN'], 'sign');
  }

  // ---------- login / session ----------
  function emailOf(name) { return String(name).toLowerCase().replace(/[^a-z0-9]/g, '') + '@mahrjan.app'; }
  var ME = null;
  async function me() { if (ME && ME.at > Date.now() - 600000) return ME; var c = await sb(), s = (await c.auth.getSession()).data.session; if (!s) return null; var x = await rpc('me'); if (!x || !x.role) return null; ME = { at: Date.now(), s: x }; return ME; }
  function unitOf(s) { return s.branch_id == null ? 'BOTH' : ((M['AJMAN'] && M['AJMAN'].br.id === s.branch_id) ? 'AJMAN' : 'AL QUOZ'); }
  async function userPublic(s, unit) { var u = s.branch_id == null ? 'BOTH' : null; if (!u) { var c = await sb(), b = (await q(c.from('branches').select('*'))).filter(function (x) { return x.id === s.branch_id; })[0]; u = b && b.code === 'MGT' ? 'AJMAN' : 'AL QUOZ'; }
    return { name: s.name, role: s.role, salesman: s.role === 'SALESMAN' ? s.name : '', unit: u === 'BOTH' ? unit : u, access: 'BOTH' }; }

  // ---------- GET ----------
  async function doGet(unit, P) {
    var action = P.get('action') || 'ping';
    if (action === 'ping') return { ok: true, service: 'Mahrjan Van Sales', version: '6.0 (Supabase)', unit: unit, time: new Date() };
    var who = await me(); if (!who) return { ok: false, error: 'SESSION_EXPIRED' };
    var m = await masters(unit);
    if (action === 'day') {
      var date = P.get('date') || today(), reqDate = P.get('reqdate') || date, D = await dayData(m, date);
      return { ok: true, date: date, reqDate: reqDate, items: readItems(m), route: readRoute(m), customers: readCustomers(m), boards: D.boards, rets: D.rets, sales: D.salesMap, grv: D.grv,
        reqs: await readReqs(m, reqDate), exps: D.exps, cols: D.cols, office: D.office, temps: D.temps };
    }
    if (action === 'deletes') { var c = await sb(), dd = P.get('date') || '', du = up(P.get('user') || '');
      var L = await q(c.from('sales_deletes').select('*').eq('branch_id', m.br.id).order('id', { ascending: false }).limit(1000));
      return { ok: true, list: L.map(function (x) { return { date: x.del_date, invoice: x.invoice, user: x.user_name || '' }; }).filter(function (x) { return (!dd || x.date === dd) && (!du || up(x.user) === du); }).slice(0, 300) }; }
    if (action === 'cash') { var cd = P.get('date') || today(), D2 = await dayData(m, cd), F = await cashFigures_(m, D2), cp = cashPosition_(F, 0);
      return { ok: true, date: cd, opening: 0, sales: F.tot.cs, returns: F.tot.gc, receipts: F.rc, payments: F.pay, expenses: F.et, deposits: F.dep, inHand: cp[cp.length - 1][1], counted: 0, suspense: F.suspense }; }
    if (action === 'report') {
      var rname = up(P.get('name')), rdate = P.get('date') || today(), rsm = String(P.get('salesman') || '').trim();
      if (['SALESMAN CLOSING', 'LOADING SHEET', 'SALESMAN SUMMARY', 'CASH SHEET'].indexOf(rname) < 0) return { ok: false, error: 'Unknown report' };
      var D3 = await dayData(m, rdate), o = new Sheet_(rname === 'LOADING SHEET' || rname === 'SALESMAN CLOSING' ? 15 : (rname === 'SALESMAN SUMMARY' ? 12 : 10)), pos = null;
      if (rname === 'SALESMAN CLOSING') await salesmanClosing_(o, m, D3, rsm, await readReqs(m, rdate));
      else if (rname === 'LOADING SHEET') await loadingSheet_(o, m, D3, rsm, await readReqs(m, rdate));
      else if (rname === 'SALESMAN SUMMARY') salesmanSummary_(o, m, D3, rsm);
      else { var RF = await cashFigures_(m, D3); cashRows_(o, RF, 0); pos = cashPosition_(RF, 0).map(function (p) { return [p[0], '', p[1]]; }); }
      return { ok: true, name: rname, date: rdate, salesman: rsm, rows: o.rows, head: o.head, bold: o.bold, money: o.money, segs: o.segs, titles: o.titles, sign: o.sign, position: pos };
    }
    if (action === 'wh') return whInit(m, who.s);
    return { ok: false, error: 'Unknown action: ' + action };
  }

  // ---------- POST ----------
  function allowed(stage, p, s) {   // auAllowed of the sheet script
    var r = s.role;
    if (stage === 'PASSWORD') return '';
    if (stage === 'OFFICE') return 'Petty cash is now entered in the portal';
    if (r === 'VIEWER') return 'Viewer cannot change data';
    if (stage === 'USERS') return 'Users are managed in the portal (Admin → Staff & access).';
    if (stage.indexOf('WH_') === 0 && ['ADMIN', 'RECEIVER', 'ACCOUNTANT'].indexOf(r) < 0) return 'Only admin, receiver or accountant can use the warehouse';
    if ((stage === 'DELETE' || stage === 'UNDELETE') && ['ADMIN', 'ACCOUNTANT', 'RECEIVER'].indexOf(r) < 0) return 'You cannot delete invoices';
    if (r === 'RECEIVER' && ['COLLECTION', 'EXPENSE', 'REQUIREMENT'].indexOf(stage) >= 0) return 'A receiver cannot post ' + stage.toLowerCase();
    if (r === 'ACCOUNTANT' && ['COLLECTION', 'EXPENSE', 'REQUIREMENT'].indexOf(stage) >= 0) return 'An accountant cannot post ' + stage.toLowerCase();
    if (r === 'SALESMAN') { if (['BOARD', 'RETURN', 'OFFICE', 'DELETE', 'UNDELETE'].indexOf(stage) >= 0) return 'A salesman cannot post ' + stage.toLowerCase();
      if (p.salesman !== undefined && up(p.salesman) !== up(s.name)) return 'You can only post for ' + s.name; }
    return '';
  }
  async function doPost(unit, p) {
    var stage = up(p.stage);
    if (stage === 'LOGIN_CHALLENGE') { var u = 'AL QUOZ'; try { u = await rpc('login_unit', { p_username: p.username }); } catch (e) {}
      var salt = Array.from(crypto.getRandomValues(new Uint8Array(16)), function (v) { return v.toString(16).padStart(2, '0'); }).join('');
      return { ok: true, salt: salt, iterations: 600000, unit: u }; }
    if (stage === 'LOGIN') {
      if (!lastPw) return { ok: false, error: 'Incorrect username or password.' };
      var c = await sb(), r = await c.auth.signInWithPassword({ email: emailOf(p.username), password: lastPw }); lastPw = null;
      if (r.error) return { ok: false, error: 'Incorrect username or password.' };
      ME = null; var w = await me(); if (!w) { await c.auth.signOut(); return { ok: false, error: 'This login is not linked to an active staff member. Ask the admin.' }; }
      if (w.s.role === 'PACKER') return { ok: false, error: 'User type not set. Ask the admin.' };
      return { ok: true, token: 'sb', user: await userPublic(w.s, unit) };
    }
    var who = await me(); if (!who) return { ok: false, error: 'SESSION_EXPIRED' };
    var deny = allowed(stage, p, who.s); if (deny) return { ok: false, error: deny };
    if (stage === 'PASSWORD') return { ok: false, error: 'Ask the admin to change your password.' };
    var m = await masters(unit);
    if (stage.indexOf('WH_') === 0) return whPost(m, who.s, stage, p);
    if (['BOARD', 'RETURN', 'EXPENSE', 'COLLECTION', 'SUMMARY'].indexOf(stage) > -1 && p.date) {
      var wd = new Date(Date.now() + (new Date().getTimezoneOffset() + TZ_OFF) * 60000 - 2 * 3600000).toISOString().slice(0, 10);
      if (String(p.date) !== wd && String(p.date) !== today()) return { ok: false, error: 'Phone date is wrong (' + p.date + '). Set the phone to automatic date and time, then send again.' };
    }
    var sm = p.salesman ? m.smByName(p.salesman) : null;
    var itemId = function (code) { var it = m.itemByCode[String(code).trim()]; if (!it) throw new Error('Item ' + code + ' is not in the item list'); return it.id; };
    var dayId = async function (create) { var c = await sb(); var d = (await q(c.from('van_day').select('id,status').eq('salesman_id', sm.id).eq('business_date', p.date)))[0];
      if (d) return d.id; if (!create) return null; return rpc('app_day', { p_salesman: sm.id, p_date: p.date }); };
    try {
      if (['BOARD', 'RETURN', 'EXPENSE', 'COLLECTION', 'SUMMARY', 'REQUIREMENT'].indexOf(stage) > -1 && !sm) return { ok: false, error: 'Salesman ' + p.salesman + ' not found' };
      if (stage === 'BOARD') {
        var v = String(p.van == null ? '' : p.van).trim(); if (!/^\d{1,5}$/.test(v)) return { ok: false, error: 'Vehicle number must be numbers only, max 5 digits (now "' + v + '").' };
        var vanId = await rpc('app_van', { p_branch: m.br.id, p_van_no: v });
        var lines = (p.rows || []).map(function (r) { return { item_id: itemId(r.code), qty: num(r.qty) }; }).filter(function (x) { return x.qty > 0; });
        await rpc('post_loading', { p_salesman: sm.id, p_date: p.date, p_van: vanId, p_start_km: p.loadKm === '' || p.loadKm == null ? null : Math.round(num(p.loadKm)), p_load_temp: p.loadTemp === '' || p.loadTemp == null ? null : num(p.loadTemp), p_lines: lines });
        return { ok: true, written: lines.length };
      }
      if (stage === 'RETURN') {
        var id = await dayId(false); if (!id) return { ok: false, error: 'Board first: no loading for ' + p.salesman + ' on ' + p.date };
        var rl = (p.rows || []).map(function (r) { return { item_id: itemId(r.code), good: num(r.good), damage: num(r.dmg), expiry: num(r.exp), waste: num(r.wst), foc: num(r.foc) }; });
        await rpc('post_return', { p_van_day: id, p_end_km: p.unloadKm === '' || p.unloadKm == null ? null : Math.round(num(p.unloadKm)), p_unload_temp: p.unloadTemp === '' || p.unloadTemp == null ? null : num(p.unloadTemp),
          p_carton_small: p.cartonSmall == null ? null : Math.round(num(p.cartonSmall)), p_carton_big: p.cartonBig == null ? null : Math.round(num(p.cartonBig)), p_lines: rl });
        return { ok: true, written: rl.length || 1 };
      }
      if (stage === 'SUMMARY') { var id2 = await dayId(true); await rpc('app_summary', { p_van_day: id2, p_summary: Object.assign({}, p.totals || {}, { reason: p.reason || '' }) }); return { ok: true, written: 1 }; }
      if (stage === 'REQUIREMENT') {
        var byShort = {}; m.items.forEach(function (it) { if (it.short_name) byShort[up(it.short_name)] = it; });
        var miss = Object.keys(p.wide || {}).filter(function (k) { return num(p.wide[k]) !== 0 && !byShort[up(k)]; });
        if (miss.length) return { ok: false, error: 'Column ' + miss.join(', ') + ' is missing in REQUIREMENT. Add it (same as the Short Name in ITEM_LIST) and send again. Nothing was saved.' };
        var rq = Object.keys(p.wide || {}).filter(function (k) { return num(p.wide[k]) > 0; }).map(function (k) { return { item_id: byShort[up(k)].id, qty_cartons: num(p.wide[k]) }; });
        await rpc('save_requirement', { p_salesman: sm.id, p_date: p.forDate || p.date, p_lines: rq }); return { ok: true, written: 1, unknownColumns: [] };
      }
      if (stage === 'EXPENSE') {
        var id3 = await dayId(true), cu = {}; m.customers.forEach(function (x) { cu[up(x.itrade_code)] = x; cu['N:' + up(x.name)] = x; });
        var STD = ['FUEL', 'PARKING', 'SHELF RENT', 'CREDIT NOTE', 'OTHER'];
        var el = (p.rows || []).filter(function (r) { return !/^CARTON/i.test(String(r.type || '').trim()) && num(r.amount) > 0; }).map(function (r) {
          var t = up(r.type), x = cu[up(r.head)] || cu['N:' + up(r.customer)] || null, std = STD.indexOf(t) > -1;
          if ((t === 'SHELF RENT' || t === 'CREDIT NOTE') && !x) return { expense_type: 'OTHER', amount: num(r.amount), note: t + ' — ' + (r.customer || 'customer not found') + (r.note ? ' — ' + r.note : '') };
          return { expense_type: std ? t : 'OTHER', amount: num(r.amount), customer_id: x ? x.id : null, note: std ? (t === 'OTHER' ? (r.note || 'OTHER') : (r.note || '')) : String(r.type).trim() + (r.note ? ' — ' + r.note : '') }; });
        await rpc('save_expenses', { p_van_day: id3, p_lines: el }); M[unit] = null; return { ok: true, written: el.length };
      }
      if (stage === 'COLLECTION') { var id4 = await dayId(true), res = await rpc('app_collections', { p_van_day: id4, p_rows: p.rows || [], p_allow_dup: !!p.allowDup }); if (res && res.ok) M[unit] = null; return res; }
      if (stage === 'DELETE' || stage === 'UNDELETE') { await rpc('app_delete', { p_branch: m.br.id, p_date: p.date || today(), p_invoice: p.invoice, p_user: p.user || '', p_undo: stage === 'UNDELETE' }); return stage === 'DELETE' ? { ok: true, written: 1 } : { ok: true, removed: 1 }; }
      return { ok: false, error: 'Unknown stage: ' + stage };
    } catch (e) { return { ok: false, error: String(e && e.message || e) }; }
  }

  // ---------- WAREHOUSE (production & cleaning) ----------
  function shiftNow() { var d = new Date(Date.now() + (new Date().getTimezoneOffset() + TZ_OFF) * 60000), h = d.getHours(), w = new Date(d.getTime() - (h < 5 ? 86400000 : 0));
    return { shift: h >= 5 && h < 17 ? 'DAY' : 'NIGHT', work: w.toISOString().slice(0, 10) }; }
  function whMasters(m) {
    var fg = {}, raws = {};
    m.items.filter(function (i) { return i.item_type === 'RAW_EGG' && i.active; }).forEach(function (i) { raws[m.code(i)] = { n: i.name, t: i.pcs_per_tray || 30, c: i.pcs_per_carton || 360, noCtn: /QUAIL/i.test(i.name) }; });
    m.items.filter(function (i) { return i.item_type === 'FG' && i.active; }).forEach(function (i) {
      var B = m.bom.filter(function (b) { return b.fg_item_id === i.id; }); var egg = B.filter(function (b) { return b.item_type === 'RAW_EGG'; })[0]; if (!egg) return;
      var mats = B.filter(function (b) { return b.item_type !== 'RAW_EGG'; }).map(function (b) { var it = m.itemById[b.item_id] || {}; return [m.code(it), it.name || '', num(b.per_pack) || 1]; });
      var tray = mats.filter(function (x) { return !/STICKER|LABEL/i.test(x[1]); })[0] || null, label = mats.filter(function (x) { return x !== tray; })[0] || null;
      fg[m.code(i)] = { n: i.name, epp: num(egg.per_pack), raw: m.code(m.itemById[egg.item_id] || {}), tray: tray, label: label }; });
    return { fg: fg, raws: raws };
  }
  function batchOut(m, b, L) {
    var nm = function (id) { return (m.staffById[id] || {}).name || ''; }, cd = function (id) { return id ? m.code(m.itemById[id] || {}) : ''; };
    var fmt = function (ts) { return ts ? new Date(new Date(ts).getTime() + (new Date().getTimezoneOffset() + TZ_OFF) * 60000).toISOString().slice(0, 16).replace('T', ' ') : ''; };
    return { no: b.batch_no, type: b.process === 'CLEANING' ? 'C' : 'P', work: b.work_date, shift: b.shift, status: b.status, issuedAt: fmt(b.issued_at), by: nm(b.issued_by), staff: (b.staff_ids || []).map(nm),
      returnedAt: fmt(b.returned_at), recvBy: nm(b.received_by), hours: b.hours == null ? '' : num(b.hours), beyond: b.beyond_shift == null ? '' : num(b.beyond_shift), output: b.output_per_staff_hour == null ? '' : num(b.output_per_staff_hour),
      lines: L.filter(function (l) { return l.batch_id === b.id; }).map(function (l) { var it = m.itemById[l.item_id] || {}, egg = it.item_type === 'RAW_EGG';
        return { slip: b.batch_no + '-' + l.slip, t: l.line_type, f: cd(l.for_item_id), code: cd(l.item_id), name: it.name || '', raw: egg ? cd(l.item_id) : '', qty: num(l.qty), egg: num(l.egg_pcs),
          calc: l.calculated == null ? '' : num(l.calculated), diff: l.difference == null ? '' : num(l.difference), reason: l.reason || '', exp: l.exp_date || '', origin: l.origin || '' }; }) };
  }
  async function whBatches(m) { var c = await sb(), from = new Date(Date.parse(shiftNow().work + 'T12:00:00Z') - 86400000).toISOString().slice(0, 10);
    var B = await q(c.from('wh_batches').select('*').eq('branch_id', m.br.id).or('status.eq.ISSUED,work_date.gte.' + from).neq('status', 'CANCELLED').order('id'));
    var L = B.length ? await byIds('wh_lines', '*', 'batch_id', B.map(function (b) { return b.id; })) : []; return B.map(function (b) { return batchOut(m, b, L); }); }
  async function whInit(m, s) {
    if (['ADMIN', 'RECEIVER', 'ACCOUNTANT'].indexOf(s.role) < 0) return { ok: false, error: 'Only admin, receiver or accountant can use the warehouse' };
    var W = whMasters(m), sh = shiftNow(), ppl = m.staff.filter(function (x) { return x.active && (x.branch_id == null || x.branch_id === m.br.id); });
    return { ok: true, unit: m.unit, unitCode: WH_CODE[m.unit], shift: sh.shift, work: sh.work,
      supervisors: ppl.filter(function (x) { return x.role === 'ACCOUNTANT' || x.role === 'RECEIVER'; }).map(function (x) { return up(x.name); }).sort(),
      packers: ppl.filter(function (x) { return x.role === 'PACKER'; }).map(function (x) { return up(x.name); }).sort(), fg: W.fg, raws: W.raws, batches: await whBatches(m) };
  }
  async function whPost(m, s, stage, p) {
    try {
      var c = await sb(), staffId = function (n) { var x = m.staff.filter(function (y) { return up(y.name) === up(n); })[0]; if (!x) throw new Error(n + ' is not in staff'); return x.id; };
      var idOf = function (code) { var it = m.itemByCode[String(code).trim()]; if (!it) throw new Error('Item ' + code + ' is not in the item list'); return it.id; };
      if (stage === 'WH_REPRINT') return { ok: true };
      if (stage === 'WH_ISSUE') {
        var type = p.type === 'C' ? 'C' : 'P', lines = [];
        (p.lines || []).forEach(function (l) { var pcs = Math.round(num(l.pcs)); if (!pcs) return;
          if (type === 'C') lines.push({ fg_item_id: idOf(l.f), qty: pcs });
          else lines.push({ fg_item_id: idOf(l.f), item_id: idOf(l.code), qty: pcs, exp_date: l.exp || null, origin: l.origin || null }); });
        if (!lines.length) throw new Error('Enter at least one qty.');
        var r = await rpc('wh_issue', { p_branch: m.br.id, p_process: type === 'C' ? 'CLEANING' : 'PRODUCTION', p_duty: staffId(p.duty), p_staff: (p.staff || []).map(staffId), p_lines: lines });
        var B = await q(c.from('wh_batches').select('*').eq('id', r.batch_id)), L = await q(c.from('wh_lines').select('*').eq('batch_id', r.batch_id));
        return { ok: true, batch: batchOut(m, B[0], L) };
      }
      if (stage === 'WH_RETURN') {
        var b = (await q(c.from('wh_batches').select('*').eq('batch_no', String(p.batch).trim())))[0]; if (!b) throw new Error('Batch ' + p.batch + ' not found.');
        var ids = function (o, f) { var out = {}; Object.keys(o || {}).forEach(function (k) { var v = f ? f(o[k]) : o[k]; if (v !== '' && v != null) out[idOf(k)] = v; }); return out; };
        var data = b.process === 'PRODUCTION'
          ? { fg: ids(p.fg), broken: ids(p.broken), waste: ids(p.waste), mwaste: ids(p.mwaste), counted: ids(p.counted, function (x) { return x && x.pcs !== '' && x.pcs != null ? x.pcs : ''; }), reason: ids(p.reason) }
          : { good: ids(p.good), near: ids(p.near), broken: ids(p.broken), waste: ids(p.waste), reuse: ids(p.reuse), reason: ids(p.reason) };
        await rpc('wh_return', { p_batch: b.id, p_duty: staffId(p.duty), p_data: data });
        var B2 = await q(c.from('wh_batches').select('*').eq('id', b.id)), L2 = await q(c.from('wh_lines').select('*').eq('batch_id', b.id));
        return { ok: true, batch: batchOut(m, B2[0], L2) };
      }
      return { ok: false, error: 'Unknown stage: ' + stage };
    } catch (e) { return { ok: false, error: String(e && e.message || e) }; }
  }

  // ---------- read-only test hook (?mjdebug=1): reuse the portal's signed-in session ----------
  if (/[?&]mjdebug=1/.test(location.search)) window.MJ_DEBUG = { doGet: doGet, portalCall: function (f, a) { return portalCall(f, a); }, usePortalSession: function () { sbP = import('https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2/+esm').then(function (m) { return m.createClient(SB_URL, SB_KEY); }); ME = null; } };


  // =====================================================================
  // PORTAL — the old SALES_PORTAL posts {fn, args} to its Apps Script. Same replies, from Supabase.
  // =====================================================================
  var PORTAL_UNIT_NAMES = { 'AL QUOZ': 'MAHRJAN GENERAL TRADING LLC-ALQUOZ', 'AJMAN': 'MAHRJAN GENERAL TRADING LLC-AJMAN' };
  var PU = (function () { try { return sessionStorage.getItem('mjPortalUnit') || localStorage.getItem('mahrjanUnit') || 'AL QUOZ'; } catch (e) { return 'AL QUOZ'; } })();
  function hexR(n) { return Array.from(crypto.getRandomValues(new Uint8Array(n)), function (v) { return v.toString(16).padStart(2, '0'); }).join(''); }
  function dayShift_(d, n) { return new Date(Date.parse(d + 'T12:00:00Z') + n * 86400000).toISOString().slice(0, 10); }
  function ymdOf(v) { return v ? String(v).slice(0, 10) : ''; }
  function hmOf(v) { if (!v) return ''; var d = new Date(v); if (isNaN(d)) return String(v).slice(0, 5); return new Date(d.getTime() + (d.getTimezoneOffset() + TZ_OFF) * 60000).toTimeString().slice(0, 5); }
  async function pWho() { var w = await me(); if (!w || w.s.role === 'PACKER') throw new Error('SESSION_EXPIRED'); return w.s; }
  async function pUnits(s) { if (s.branch_id == null) return ['AL QUOZ', 'AJMAN']; var c = await sb(), b = (await q(c.from('branches').select('*'))).filter(function (x) { return x.id === s.branch_id; })[0]; return [b && b.code === 'MGT' ? 'AJMAN' : 'AL QUOZ']; }
  async function pSession(s, unit) { var units = await pUnits(s); if (units.indexOf(unit) < 0) throw new Error('You do not have access to ' + PORTAL_UNIT_NAMES[unit] + '.');
    PU = unit; try { sessionStorage.setItem('mjPortalUnit', unit); } catch (e) {}
    return { token: hexR(32), username: up(s.name), role: s.role, unit: unit, unitName: PORTAL_UNIT_NAMES[unit], units: units, expires: Date.now() + 8 * 3600000 }; }
  function needRole(s, roles, msg) { if (roles.indexOf(s.role) < 0) throw new Error(msg || 'You cannot open this.'); }
  async function pRoster() { var m = await masters(PU); return { roster: readRoute(m).map(function (r) { return { name: r.salesman, route: r.route, van: r.van }; }), today: today() }; }

  // CASH BALANCE + openingFor (same rule as the old portal: latest counted or locked day, then every later day's cash movement)
  var CASH_LOCK_DAYS = 5;
  async function openingFor_(m, date, s) {
    var c = await sb(), rows = await q(c.from('cash_balance').select('*').eq('branch_id', m.br.id).lt('close_date', date).order('close_date')).catch(function () { return []; });
    if (!rows.length) return null;
    var locked = function (d) { return d <= dayShift_(today(), -CASH_LOCK_DAYS); }, by = {}, a = null;
    rows.forEach(function (x) { by[x.close_date] = x; });
    for (var i = rows.length - 1; i >= 0; i--) { if (num(rows[i].counted) > 0 || locked(rows[i].close_date)) { a = rows[i]; break; } }
    if (!a) a = rows[0];
    var o = num(a.closing), d = dayShift_(a.close_date, 1), g = 0, save = [];
    while (d < date && g++ < 40) { var x = by[d];
      if (x && (num(x.counted) > 0 || locked(d))) o = num(x.closing);
      else { var F = await cashFigures_(m, await dayData(m, d)); o = o + F.tot.cs - F.tot.gc + F.rc - F.pay - F.et - F.dep; if (locked(d) && !x) save.push({ date: d, expected: Math.round(o * 100) / 100, counted: null, closing: Math.round(o * 100) / 100 }); }
      d = dayShift_(d, 1); }
    if (save.length && s && (s.role === 'ADMIN' || s.role === 'ACCOUNTANT')) { try { await rpc('save_cash_balance', { p_branch: m.br.id, p_rows: save, p_only_new: true }); } catch (e) {} }
    return Math.round(o * 100) / 100;
  }
  function cashExport_(F, opening) { var r2 = function (v) { return Math.round((Number(v) || 0) * 100) / 100; }, ref = function (v) { return v === '' || v == null ? '' : String(v); };
    return { opening: r2(opening), dep: r2(F.dep),
      men: F.order.concat(['STORE']).map(function (k) { var r = F.rows[k]; return [k === 'STORE' ? 'STORE SALE' : k, r2(r.cs), r2(r.cr), r2(r.gc), r2(r.gr), r2(r.FUEL), r2(r.PARKING), r2(r.CARTON)]; }),
      receipts: F.receipts.map(function (x) { return [ref(x.ref), x.part, r2(x.amount)]; }), payments: F.payments.map(function (x) { return [ref(x.ref), x.part, r2(x.amount)]; }),
      suspense: (F.suspense || []).filter(function (x) { return Math.abs(x.given - x.cleared) > 0.004; }).map(function (x) { return [x.name, r2(x.given - x.cleared)]; }) }; }
  // PICKING SHEET: items down, salesmen across (only those who raised a requirement), then who has not entered.
  function picking_(m, reqs) { var R = {}, items = readItems(m), men = [], pending = [];
    Object.keys(reqs).forEach(function (k) { R[up(k)] = reqs[k]; });
    readRoute(m).forEach(function (r) { var x = R[up(r.salesman)] || {}; if (Object.keys(x).some(function (k) { return x[k] > 0; })) men.push(r.salesman); else pending.push(r.salesman); });
    var byKey = {}; items.forEach(function (it) { [it.shortName, it.name, it.code].forEach(function (k) { if (k && !byKey[up(k)]) byKey[up(k)] = it; }); });
    var lines = {}, order = [];
    men.forEach(function (sm) { var x = R[up(sm)] || {}; Object.keys(x).forEach(function (h) { var qn = Number(x[h]) || 0; if (qn <= 0) return; var it = byKey[up(h)], key = it ? 'C' + it.code : 'H' + up(h);
      if (!lines[key]) { lines[key] = { name: it ? (it.shortName || it.name) : h, q: {} }; order.push(key); } lines[key].q[sm] = (lines[key].q[sm] || 0) + qn; }); });
    var pos = {}; items.forEach(function (it, i) { pos['C' + it.code] = i; });
    order.sort(function (a, b) { var x = a in pos ? pos[a] : 1e9, y = b in pos ? pos[b] : 1e9; return x - y || lines[a].name.localeCompare(lines[b].name); });
    return { w: Math.max(4, men.length + 3), fill: function (o) {
      if (!men.length) o.add(['', 'No requirement entered for this date.']);
      else { o.add(['SL', 'ITEM'].concat(men, ['TOTAL']), 'head'); var col = men.map(function () { return 0; }), grand = 0;
        order.forEach(function (k, i) { var L = lines[k], tot = 0, cells = men.map(function (sm, j) { var qn = L.q[sm] || 0; tot += qn; col[j] += qn; return blank_(qn); }); grand += tot; o.add([i + 1, L.name].concat(cells, [tot])); });
        o.add(['', 'TOTAL'].concat(col.map(blank_), [grand]), 'total'); }
      o.gap(); o.add(['', 'NOT ENTERED', pending.length ? pending.join(', ') : 'None'], 'bold'); } }; }
  async function pReport(s, name, date, sm) {
    if (['LOADING SHEET', 'SALESMAN SUMMARY', 'CASH SHEET', 'PICKING SHEET'].indexOf(name) < 0) throw new Error('Unknown report.');
    if (!/^\d{4}-\d{2}-\d{2}$/.test(String(date))) throw new Error('Choose a valid report date.');
    var m = await masters(PU);
    if (name !== 'CASH SHEET' && name !== 'PICKING SHEET' && !readRoute(m).some(function (r) { return up(r.salesman) === up(sm); })) throw new Error('Choose a salesman from the route table.');
    if (name === 'PICKING SHEET') { var pk = picking_(m, await readReqs(m, date)), po = new Sheet_(pk.w); pk.fill(po);
      return { ok: true, name: name, date: date, salesman: '', rows: po.rows, head: po.head, bold: po.bold, money: po.money, segs: po.segs, titles: po.titles, sign: po.sign, position: null, cash: null }; }
    var D = await dayData(m, date), o = new Sheet_(name === 'SALESMAN SUMMARY' ? 12 : name === 'CASH SHEET' ? 10 : 15), pos = null, cx = null;
    if (name === 'LOADING SHEET') await loadingSheet_(o, m, D, sm, await readReqs(m, date));
    else if (name === 'SALESMAN SUMMARY') salesmanSummary_(o, m, D, sm);
    else { var F = await cashFigures_(m, D), op = (await openingFor_(m, date, s)) || 0; cashRows_(o, F, op); cx = cashExport_(F, op); pos = cashPosition_(F, op).map(function (p) { return [p[0], '', p[1]]; }); }
    return JSON.parse(JSON.stringify({ ok: true, name: name, date: date, salesman: sm, rows: o.rows, head: o.head, bold: o.bold, money: o.money, segs: o.segs, titles: o.titles, sign: o.sign, position: pos, cash: cx }));
  }

  // SNAPSHOT: the unit sheet's tables with the same headings, for the analysis pages.
  async function pSnapshot(days) {
    var m = await masters(PU), c = await sb(), cutoff = days > 0 ? dayShift_(today(), -days) : '';
    var vdq = function () { var x = c.from('van_day').select('*').eq('branch_id', m.br.id); return cutoff ? x.gte('business_date', cutoff) : x; };
    var slq = function () { var x = c.from('sales_lines').select('*').eq('branch_id', m.br.id); if (cutoff) x = x.gte('tran_date', cutoff); return x.order('id'); };
    var res = await Promise.all([all(vdq), all(slq), all(function () { return c.from('sales_deletes').select('*').eq('branch_id', m.br.id).order('id'); })]);
    var days_ = res[0], sales = res[1], dels = res[2], ids = days_.map(function (d) { return d.id; });
    var more = await Promise.all([ids.length ? byIds('loading_lines', '*', 'van_day_id', ids) : [], ids.length ? byIds('return_lines', '*', 'van_day_id', ids) : [],
      ids.length ? byIds('expenses', '*', 'van_day_id', ids) : [], ids.length ? byIds('collections', '*', 'van_day_id', ids) : []]);
    var vd = {}; days_.forEach(function (d) { vd[d.id] = d; });
    var smName = function (id) { return (m.staffById[id] || {}).name || ''; }, vanNo = function (id) { var v = m.vans.filter(function (x) { return x.id === id; })[0]; return v ? v.van_no : ''; };
    var routeOf = function (d) { var r = d.route_id && m.routes.filter(function (x) { return x.id === d.route_id; })[0]; return r ? r.name : m.routeName(d.salesman_id); };
    var tag = function (p, d) { return p + '-' + d.business_date.replace(/-/g, '') + '-' + smName(d.salesman_id); };
    var custById = {}; m.customers.forEach(function (x) { custById[x.id] = x; });
    var it = function (id) { return m.itemById[id] || {}; }, raw = function (id) { return it(id).item_type === 'RAW_EGG'; };
    var row = 2, R = function (o) { o._row = row++; return o; };
    var T = {};
    T['RAW SALES'] = sales.filter(function (l) { return !l.cancelled || l.cancel_reason === 'DELETE LIST'; }).map(function (l) { var s = m.staffById[l.salesman_id];
      return R({ 'Tran Date': l.tran_date, 'Tran No': l.tran_no || '', 'Invoice No': l.invoice_no, 'User': s ? s.name : up(l.itrade_user), 'Sales Executive': l.sales_executive || '', 'Tran Type': l.tran_type, 'Tender Type': l.tender_type,
        'Head No': l.customer_code || '', 'Account Name': l.customer_name || '', 'Item Code': l.item_id ? m.code(it(l.item_id)) || l.item_code : l.item_code, 'Item Name': l.item_name || '', 'CF': num(l.cf), 'Unit': l.unit || '',
        'Qty': num(l.qty), 'Rate': num(l.rate), 'Gross': num(l.gross), 'Disc': num(l.disc), 'Net': num(l.net), 'VAT': num(l.vat), 'Net Incl VAT': num(l.net_incl_vat), 'Profit': num(l.profit), 'Margin %': num(l.net) ? Math.round(num(l.profit) / num(l.net) * 10000) / 100 : 0 }); });
    row = 2; T.BOARD = more[0].filter(function (l) { return vd[l.van_day_id] && !raw(l.item_id); }).map(function (l) { var d = vd[l.van_day_id];
      return R({ 'DATE': ymdOf(l.created_at), 'BOARD DATE': d.business_date, 'SALESMAN': smName(d.salesman_id), 'VEHCLE NUMBER': vanNo(d.van_id), 'ROUTE': routeOf(d), 'BARCODE': m.code(it(l.item_id)), 'ITEM NAME': it(l.item_id).name || '', 'QTY': num(l.qty), 'ID': tag('BOARD', d) }); });
    // RETURN DIFF = board − sold (net of GRV) − returned, as the unit sheet works it out
    var boardQ = {}, soldQ = {}; more[0].forEach(function (l) { var k = l.van_day_id + '|' + l.item_id; boardQ[k] = (boardQ[k] || 0) + num(l.qty); });
    var dayKey = {}; days_.forEach(function (d) { dayKey[d.salesman_id + '|' + d.business_date] = d.id; });
    sales.forEach(function (l) { if (l.cancelled || !l.item_id) return; var id = l.van_day_id || dayKey[l.salesman_id + '|' + l.tran_date]; if (!id) return; var k = id + '|' + l.item_id; soldQ[k] = (soldQ[k] || 0) + num(l.qty); });
    row = 2; T.RETURN = more[1].filter(function (l) { return vd[l.van_day_id] && !raw(l.item_id); }).map(function (l) { var d = vd[l.van_day_id], k = l.van_day_id + '|' + l.item_id, tot = num(l.good) + num(l.damage) + num(l.expiry) + num(l.waste) + num(l.foc);
      return R({ 'DATE': ymdOf(l.created_at), 'RETURN DATE': d.business_date, 'SALESMAN': smName(d.salesman_id), 'VEHCLE NUMBER': vanNo(d.van_id), 'ROUTE': routeOf(d), 'BARCODE': m.code(it(l.item_id)), 'ITEM NAME': it(l.item_id).name || '',
        'GOOD': num(l.good), 'DMG': num(l.damage), 'EXP': num(l.expiry), 'WST': num(l.waste), 'FOC': num(l.foc), 'TOTAL RETURN': tot, 'DIFF': (boardQ[k] || 0) - (soldQ[k] || 0) - tot, 'ID': tag('RETURN', d) }); });
    row = 2; T['VAN LOG'] = days_.filter(function (d) { return d.load_time || d.unload_time || d.start_km != null; }).map(function (d) {
      return R({ 'DATE': d.business_date, 'SALESMAN': smName(d.salesman_id), 'VAN': vanNo(d.van_id), 'ROUTE': routeOf(d), 'LOADING TIME': d.load_time ? String(d.load_time).slice(0, 5) : '', 'LOADING TEMP': d.load_temp == null ? '' : num(d.load_temp),
        'UNLOADING TIME': d.unload_time ? String(d.unload_time).slice(0, 5) : '', 'UNLOADING TEMP': d.unload_temp == null ? '' : num(d.unload_temp), 'ID': tag('LOG', d), 'START KM': d.start_km == null ? '' : d.start_km, 'END KM': d.end_km == null ? '' : d.end_km }); });
    row = 2; T.COLLECTION = more[3].filter(function (x) { return vd[x.van_day_id]; }).map(function (x) { var d = vd[x.van_day_id], cu = custById[x.customer_id] || {};
      return R({ 'DATE': d.business_date, 'SALESMAN': smName(d.salesman_id), 'RECEIPT NO': /^NA-/.test(x.receipt_no) ? '' : String(x.receipt_no).replace(/-\d+$/, ''), 'INVOICE NUMBER': x.invoice_no || '', 'HEAD NO': cu.itrade_code || '', 'CUSTOMER NAME': cu.name || '', 'MODE OF PAYMENT': x.mode, 'AMOUNT': num(x.amount), 'ID': tag('COLL', d) }); });
    row = 2; T.EXPENSE = more[2].filter(function (e) { return vd[e.van_day_id]; }).map(function (e) { var d = vd[e.van_day_id], cu = custById[e.customer_id] || {}, ty = e.expense_type, note = e.note || '';
      if (ty === 'OTHER' && /\s—\s/.test(note) && !/^OTHER$/i.test(note)) { var p = note.split(' — '); ty = p.shift(); note = p.join(' — '); } else if (ty === 'OTHER' && note === 'OTHER') note = '';
      return R({ 'DATE': ymdOf(e.created_at), 'EXPENSE DATE': d.business_date, 'SALESMAN': smName(d.salesman_id), 'VEHCLE NUMBER': vanNo(d.van_id), 'ROUTE': routeOf(d), 'TYPE': ty, 'AMOUNT': num(e.amount), 'NOTE': note, 'ID': tag('EXP', d), 'CUSTOMER NAME': cu.name || '', 'HEAD NO': cu.itrade_code || '' }); });
    row = 2; T.SUMMARY = days_.filter(function (d) { return d.summary; }).map(function (d) { var x = d.summary || {};
      return R({ 'Timestamp': hmOf(d.updated_at || d.created_at), 'Date': d.business_date, 'Salesman': smName(d.salesman_id), 'Van': vanNo(d.van_id), 'Route': routeOf(d), 'Board': num(x.board), 'Sales': num(x.sales), 'Good': num(x.good),
        'Damage': num(x.damage), 'Expiry': num(x.expiry), 'Waste': num(x.waste), 'FOC': num(x.foc), 'Variance': num(x.variance), 'Reason': x.reason || '', 'Ref': tag('SUMMARY', d) }); });
    // CUSTOMERS: salesman · head no · name · last visit (latest bill in the loaded sales)
    var last = {}; sales.forEach(function (l) { if (l.customer_code && (!last[l.customer_code] || last[l.customer_code] < l.tran_date)) last[l.customer_code] = l.tran_date; });
    var smOfCust = {}; m.assign.forEach(function (a) { smOfCust[a.customer_id] = a.salesman_id; });
    row = 2; T.CUSTOMERS = m.customers.filter(function (x) { return x.active && smOfCust[x.id] && m.staffById[smOfCust[x.id]] && m.staffById[smOfCust[x.id]].branch_id === m.br.id; }).map(function (x) {
      return R({ 'Salesman': smName(smOfCust[x.id]), 'Head No': x.itrade_code || '', 'Customer Name': x.name, 'last visit': last[x.itrade_code] || '', 'LAST BILLED': last[x.itrade_code] || '' }); });
    row = 2; T.DELETE = dels.map(function (x) { return R({ 'DATE': x.del_date, 'INVOICE NUMBER': x.invoice, 'USER': x.user_name || '' }); });
    var HEAD = { 'RAW SALES': ['Tran Date', 'Tran No', 'Invoice No', 'User', 'Sales Executive', 'Tran Type', 'Tender Type', 'Head No', 'Account Name', 'Item Code', 'Item Name', 'CF', 'Unit', 'Qty', 'Rate', 'Gross', 'Disc', 'Net', 'VAT', 'Net Incl VAT', 'Profit', 'Margin %'],
      BOARD: ['DATE', 'BOARD DATE', 'SALESMAN', 'VEHCLE NUMBER', 'ROUTE', 'BARCODE', 'ITEM NAME', 'QTY', 'ID'], RETURN: ['DATE', 'RETURN DATE', 'SALESMAN', 'VEHCLE NUMBER', 'ROUTE', 'BARCODE', 'ITEM NAME', 'GOOD', 'DMG', 'EXP', 'WST', 'FOC', 'TOTAL RETURN', 'DIFF', 'ID'],
      'VAN LOG': ['DATE', 'SALESMAN', 'VAN', 'ROUTE', 'LOADING TIME', 'LOADING TEMP', 'UNLOADING TIME', 'UNLOADING TEMP', 'ID', 'START KM', 'END KM'], COLLECTION: ['DATE', 'SALESMAN', 'RECEIPT NO', 'INVOICE NUMBER', 'HEAD NO', 'CUSTOMER NAME', 'MODE OF PAYMENT', 'AMOUNT', 'ID'],
      EXPENSE: ['DATE', 'EXPENSE DATE', 'SALESMAN', 'VEHCLE NUMBER', 'ROUTE', 'TYPE', 'AMOUNT', 'NOTE', 'ID', 'CUSTOMER NAME', 'HEAD NO'], SUMMARY: ['Timestamp', 'Date', 'Salesman', 'Van', 'Route', 'Board', 'Sales', 'Good', 'Damage', 'Expiry', 'Waste', 'FOC', 'Variance', 'Reason', 'Ref'],
      CUSTOMERS: ['Salesman', 'Head No', 'Customer Name', 'last visit', 'LAST BILLED'], DELETE: ['DATE', 'INVOICE NUMBER', 'USER'] };
    var out = {}, schema = []; Object.keys(HEAD).forEach(function (k) { out[k] = T[k] || []; schema.push({ sheet: k, headers: HEAD[k], rows: out[k].length }); });
    out.roster = (await pRoster()).roster;
    out.meta = { live: true, source: 'Google Sheets', snapshotDate: today(), days: days || 0, from: cutoff, schema: schema, ignoredSheets: [] };
    return out;
  }

  var NOT_YET = 'This page is not moved to the new system yet.';
  async function portalCall(fn, a) {
    a = a || [];
    if (fn === 'portalUnits') return Object.keys(PORTAL_UNIT_NAMES).map(function (k) { return { unit: k, name: PORTAL_UNIT_NAMES[k], ready: true }; });
    if (fn === 'portalUrl') return location.href.split('#')[0];
    if (fn === 'portalChallenge') return { salt: hexR(16), iterations: 600000 };
    if (fn === 'portalLogin') { var un = up(a[2] || 'AL QUOZ'); if (!PORTAL_UNIT_NAMES[un]) throw new Error('Choose a company.');
      if (!lastPw) throw new Error('Incorrect username or password.');
      var c = await sb(), r = await c.auth.signInWithPassword({ email: emailOf(a[0]), password: lastPw }); lastPw = null;
      if (r.error) throw new Error('Incorrect username or password.');
      ME = null; var w = await me(); if (!w || w.s.role === 'PACKER') { await c.auth.signOut(); throw new Error('Incorrect username or password.'); }
      try { var ss = await pSession(w.s, un); } catch (e) { await c.auth.signOut(); throw e; }
      try { ss.roster = await pRoster(); } catch (e) {} ss.device = hexR(32); return ss; }
    if (fn === 'portalResume') { ME = null; var w2 = await me(); if (!w2 || w2.s.role === 'PACKER') throw new Error('DEVICE_EXPIRED'); return pSession(w2.s, PU); }
    if (fn === 'portalRemember') { await pWho(); return { key: hexR(32) }; }
    if (fn === 'portalLogout') { try { var c2 = await sb(); await c2.auth.signOut(); } catch (e) {} ME = null; return { ok: true }; }
    if (fn === 'portalSetup') throw new Error('Accounts are made by the admin in the new system.');
    var s = await pWho();
    if (fn === 'portalSwitchUnit') { var u2 = up(a[1]); if (!PORTAL_UNIT_NAMES[u2]) throw new Error('Choose a company.'); return pSession(s, u2); }
    if (fn === 'portalRoster') return pRoster();
    if (fn === 'portalSnapshot') { var n = Math.floor(Number(a[1])); return pSnapshot(n > 0 && n <= 3660 ? n : 0); }
    if (fn === 'portalReport') return pReport(s, String(a[1] || ''), String(a[2] || ''), String(a[3] || ''));
    if (fn === 'portalChangePassword' || fn === 'portalResetPassword') throw new Error('Passwords are changed by the admin in the new system (Supabase → Authentication).');
    throw new Error(NOT_YET);
  }

  // ---------- fetch: answer the app's "sheet" calls ----------
  var realFetch = window.fetch.bind(window);
  function reply(obj) { return new Response(JSON.stringify(obj), { status: 200, headers: { 'Content-Type': 'application/json' } }); }
  window.fetch = function (input, init) {
    var url = typeof input === 'string' ? input : (input && input.url) || '';
    if (url.indexOf(FAKE) !== 0) return realFetch(input, init);
    if (url.indexOf(FAKE + 'PORTAL/') === 0) { var b = {}; try { b = JSON.parse((init && init.body) || '{}'); } catch (e) {}
      return portalCall(String(b.fn || ''), Array.isArray(b.args) ? b.args : []).then(function (r) { return reply({ ok: true, result: r }); }, function (e) { return reply({ ok: false, error: String(e && e.message || e) }); }); }
    var u = new URL(url), unit = decodeURIComponent(u.pathname.split('/')[1] || 'AL QUOZ').toUpperCase(); if (!UNIT_CODE[unit]) unit = 'AL QUOZ';
    var job = (init && String(init.method || '').toUpperCase() === 'POST') ? doPost(unit, JSON.parse(init.body || '{}')) : doGet(unit, u.searchParams);
    return job.then(reply, function (e) { return reply({ ok: false, error: String(e && e.message || e) }); });
  };
})();
