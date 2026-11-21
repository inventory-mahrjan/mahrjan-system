/* =====================================================================
 * MAHRJAN MAILER — scheduled report emails for the NEW system (Supabase).
 * Separate Apps Script project; the old "Mahrjan Daily Check" keeps running until switch-over.
 *
 * One-time setup (5 minutes):
 *   1. script.google.com → New project → name it "Mahrjan Mailer". Paste this file into Code.gs. Save.
 *   2. Project Settings → Script properties → add:
 *        MAIL_USER  = mailer            (a portal login with role VIEWER and branch "Both")
 *        MAIL_PASS  = <that login's password — type it yourself>
 *   3. Choose "setup" → Run → allow permissions (it creates the timers).
 *   4. Choose "testAll" → Run → every report for yesterday goes to the people ticked in the portal
 *      (Admin → Email reports).
 *
 * SCHEDULE (Dubai): same as the old Daily Check
 *   11:00            VAN_LOAD   van load & boarded qty (today)
 *   20:30 – 01:00    SALES_QTY, DAMAGE, GRV, VISIT for today's work day — sent once every boarded van has a
 *                    return and sales are imported; at 01:00 sent anyway
 *   03:05            HEALTH     daily check (yesterday)
 *   Sunday 03:20     VARIANCE, FOC, EXPIRY (last Sunday–Saturday)
 *   1st/11th/21st    QTY_MTD    monthly sales qty
 *   07:45            ALERTS     a report that should have gone did not
 *   09:00 / 21:00    STOCK_COUNT a WEEKLY stock count batch that was posted → its count report (once per batch)
 *   02:30            BACKUP     every table saved as one .zip in Google Drive folder "Mahrjan Backup" (kept 30 days)
 * Each report is sent once per day/period (email_log). A failed send is retried on the next timer.
 * ===================================================================== */
var SB_URL = 'https://xhndwjkqfqmmpfcglqzu.supabase.co';
var SB_KEY = 'sb_publishable_emOqI1PWaSA7B5s56v-ERg_RrxZ9weu';   // public key; the data is protected by the login
var TZ = 'Asia/Dubai';
var TITLES = { VAN_LOAD: 'VAN LOAD & BOARDED QTY', SALES_QTY: 'DAILY SALES QTY', DAMAGE: 'SALESMAN WISE SALES & DAMAGE', GRV: 'GRV VS DAMAGE / WASTE / EXPIRY',
  VISIT: 'CUSTOMER VISIT STATUS', HEALTH: 'MAHRJAN DAILY CHECK', VARIANCE: 'WEEKLY SHORT & EXCESS', FOC: 'WEEKLY FOC', EXPIRY: 'WEEKLY EXPIRY', QTY_MTD: 'MONTHLY SALES QTY (MTD)', STOCK_COUNT: 'WEEKLY STOCK COUNT' };

// ---------- Supabase ----------
function token_() {
  var c = CacheService.getScriptCache(), t = c.get('sbt'); if (t) return t;
  var P = PropertiesService.getScriptProperties(), u = P.getProperty('MAIL_USER'), pw = P.getProperty('MAIL_PASS');
  if (!u || !pw) throw new Error('Set MAIL_USER and MAIL_PASS in Project Settings → Script properties.');
  var r = UrlFetchApp.fetch(SB_URL + '/auth/v1/token?grant_type=password', { method: 'post', contentType: 'application/json', muteHttpExceptions: true,
    headers: { apikey: SB_KEY }, payload: JSON.stringify({ email: u.indexOf('@') > 0 ? u : u + '@mahrjan.app', password: pw }) });
  if (r.getResponseCode() !== 200) throw new Error('Login failed: ' + r.getContentText().slice(0, 200));
  t = JSON.parse(r.getContentText()).access_token; c.put('sbt', t, 3000); return t;
}
function rpc_(fn, args) {
  var r = UrlFetchApp.fetch(SB_URL + '/rest/v1/rpc/' + fn, { method: 'post', contentType: 'application/json', muteHttpExceptions: true,
    headers: { apikey: SB_KEY, Authorization: 'Bearer ' + token_() }, payload: JSON.stringify(args || {}) });
  if (r.getResponseCode() >= 300) throw new Error(fn + ': ' + r.getContentText().slice(0, 300));
  var t = r.getContentText(); return t ? JSON.parse(t) : null;
}
// read a table (all rows, 1000 at a time); q = PostgREST filter, e.g. 'status=eq.POSTED'
function rest_(table, q, cols) { var out = [], i = 0;
  while (true) { var r = UrlFetchApp.fetch(SB_URL + '/rest/v1/' + table + '?select=' + encodeURIComponent(cols || '*') + (q ? '&' + q : '') + '&order=' + (table === 'sc_system' || table === 'role_access' ? 'batch_id' : 'id') + '&limit=1000&offset=' + i,
      { muteHttpExceptions: true, headers: { apikey: SB_KEY, Authorization: 'Bearer ' + token_() } });
    if (r.getResponseCode() >= 300) { var r2 = UrlFetchApp.fetch(SB_URL + '/rest/v1/' + table + '?select=' + encodeURIComponent(cols || '*') + (q ? '&' + q : '') + '&limit=1000&offset=' + i, { muteHttpExceptions: true, headers: { apikey: SB_KEY, Authorization: 'Bearer ' + token_() } });
      if (r2.getResponseCode() >= 300) throw new Error(table + ': ' + r2.getContentText().slice(0, 200)); r = r2; }
    var d = JSON.parse(r.getContentText()); out = out.concat(d); if (d.length < 1000) return out; i += 1000; } }
function log_(rep, period, to, status, note) { try { rpc_('mail_log', { p_report: rep, p_period: period, p_recipient: to || null, p_status: status, p_note: note || null }); } catch (e) { Logger.log('log failed: ' + e.message); } }

// ---------- dates ----------
function day_(msBack) { return Utilities.formatDate(new Date(Date.now() - (msBack || 0)), TZ, 'yyyy-MM-dd'); }
function nice_(d) { var M = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'], q = d.split('-'); return q[2] + '-' + M[Number(q[1]) - 1] + '-' + q[0]; }
function lastWeek_() { var now = new Date(), dow = Number(Utilities.formatDate(now, TZ, 'u')), back = dow % 7 + 1, D = 864e5;
  return { from: Utilities.formatDate(new Date(now.getTime() - (back + 6) * D), TZ, 'yyyy-MM-dd'), to: Utilities.formatDate(new Date(now.getTime() - back * D), TZ, 'yyyy-MM-dd') }; }
function mtdRange_() { var now = new Date(), d = Number(Utilities.formatDate(now, TZ, 'd')), y = Number(Utilities.formatDate(now, TZ, 'yyyy')), m = Number(Utilities.formatDate(now, TZ, 'M'));
  var p = function (n) { return (n < 10 ? '0' : '') + n; };
  if (d === 1) { var py = m === 1 ? y - 1 : y, pm = m === 1 ? 12 : m - 1, last = new Date(Date.UTC(py, pm, 0)).getUTCDate(); return { from: py + '-' + p(pm) + '-01', to: py + '-' + p(pm) + '-' + p(last) }; }
  if (d === 11 || d === 21) return { from: y + '-' + p(m) + '-01', to: y + '-' + p(m) + '-' + p(d - 1) };
  return null; }

// ---------- HTML / PDF (portal style: light-green heading row, thin lines, numbers centred) ----------
function esc_(s) { return String(s == null ? '' : s).replace(/[&<>"]/g, function (c) { return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]; }); }
function fmt_(v) { if (typeof v === 'number') { var r = Math.round(v * 100) / 100; return (Math.abs(r % 1) > 0 ? r.toFixed(2) : String(r)).replace(/\B(?=(\d{3})+(?!\d))/g, ','); } return esc_(v); }
function html_(D, units, title, period) {
  var th = 'background:#e8f3ee;color:#0c363b;font-weight:600;font-size:9.5px;border:1px solid #d8dad5;padding:4px 5px;text-align:center',
      td = 'border:1px solid #e1e3de;padding:3px 5px;font-size:9.5px;text-align:center', tl = td + ';text-align:left';
  var body = units.map(function (u, ui) {
    return '<div style="' + (ui ? 'page-break-before:always;' : '') + '">'
      + '<table style="width:100%;border-collapse:collapse;margin-bottom:6px"><tr><td style="font-weight:700;font-size:15px;color:#0f5f57">mahrjan</td>'
      + '<td style="text-align:center;font-weight:700;font-size:13px">' + esc_(title) + '</td><td style="text-align:right;font-size:11px">' + esc_(period) + '<br><b>' + esc_(String(u.unit).toUpperCase()) + '</b></td></tr></table>'
      + u.sections.map(function (s) {
        if (!s.rows || !s.rows.length) return '<p style="font-size:11px;color:#6b7370">' + esc_(s.heading) + ': nothing for this period.</p>';
        var nf = s.num_from == null ? 1 : s.num_from;
        return '<div style="font-weight:600;font-size:11px;margin:8px 0 4px">' + esc_(s.heading) + '</div><table style="width:100%;border-collapse:collapse">'
          + '<tr>' + s.columns.map(function (c, i) { return '<th style="' + th + (i < nf ? ';text-align:left' : '') + '">' + esc_(c) + '</th>'; }).join('') + '</tr>'
          + s.rows.map(function (r) { return '<tr>' + r.map(function (v, i) { var bad = typeof v === 'string' && /^(Short|Excess|No GRV)$/.test(v) || (s.columns[0] === 'Check' && i === 1 && v !== 'OK');
              return '<td style="' + (i < nf ? tl : td) + (bad ? ';color:#b0432e;font-weight:600' : '') + '">' + fmt_(v) + '</td>'; }).join('') + '</tr>'; }).join('')
          + (s.total ? '<tr>' + s.total.map(function (v, i) { return '<td style="' + (i < nf ? tl : td) + ';font-weight:700;background:#f4f7f2">' + fmt_(v) + '</td>'; }).join('') + '</tr>' : '')
          + '</table>';
      }).join('') + (u.note ? '<p style="font-size:10.5px;color:#b0432e;margin-top:6px">' + esc_(u.note) + '</p>' : '') + '</div>';
  }).join('');
  return '<html><head><style>@page{size:A4 landscape;margin:8mm}*{-webkit-print-color-adjust:exact;print-color-adjust:exact}</style></head><body style="font-family:Arial,sans-serif;color:#1b1f1e">' + body + '</body></html>';
}
function summary_(rep, D) {
  var S = D.summary || {}, m = function (v) { return 'AED ' + (Math.round((v || 0) * 100) / 100).toFixed(2); };
  switch (rep) {
    case 'VAN_LOAD':  return 'boarded ' + S.a + ' of ' + S.b;
    case 'SALES_QTY': return S.a + ' salesmen · ' + fmt_(S.c) + ' pcs/pk';
    case 'QTY_MTD':   return fmt_(S.d) + ' ctn';
    case 'DAMAGE':    return 'damage ' + (S.c > 0 ? (S.d / S.c * 100).toFixed(2) : '0.00') + '% of sales';
    case 'GRV':       return S.b ? S.b + ' salesmen not matched' : 'all matched';
    case 'VISIT':     return 'served ' + S.b + ' of ' + S.a + ' · 30+ days ' + (S.b30 || 0);
    case 'HEALTH':    return S.a ? S.a + ' need attention' : 'All OK';
    case 'VARIANCE':  return 'short ' + fmt_(S.a) + ' · excess ' + fmt_(S.b) + ' · ' + m(S.value);
    default:          return 'qty ' + fmt_(S.a) + ' · ' + m(S.value);
  }
}

// ---------- send one report ----------
function sendReport(rep, from, to, force) {
  to = to || from; var period = from === to ? from : from + '..' + to;
  if (!force && rpc_('mail_sent', { p_report: rep, p_period: period })) { Logger.log(rep + ' ' + period + ': already sent'); return 'done'; }
  var rc = rpc_('mail_recipients', { p_report: rep }) || [];
  if (!rc.length) { Logger.log(rep + ': nobody ticked in Admin → Email reports'); log_(rep, period, null, 'SKIPPED', 'no recipients'); return 'none'; }
  var D = rpc_('mail_data', { p_report: rep, p_from: from, p_to: to });
  if (rep === 'VAN_LOAD' && !(D.summary && D.summary.a)) { log_(rep, period, null, 'SKIPPED', 'nobody boarded'); return 'none'; }
  var title = TITLES[rep], per = from === to ? nice_(from) : nice_(from) + ' to ' + nice_(to), n = 0, groups = {};
  rc.forEach(function (x) { var k = x.branch_id ? String(x.branch_id) : 'ALL'; (groups[k] = groups[k] || []).push(x); });
  Object.keys(groups).forEach(function (k) {
    var units = k === 'ALL' ? D.units : D.units.filter(function (u) { return String(u.branch_id) === k; }); if (!units.length) return;
    var html = html_(D, units, title, per), pdf = Utilities.newBlob(html, 'text/html', 'r.html').getAs('application/pdf').setName(title.replace(/[\/]/g, '-') + '_' + per + '.pdf');
    var subj = 'Mahrjan ' + title.toLowerCase() + ' ' + per + ' · ' + summary_(rep, D) + (force === 'CORRECTED' ? ' (CORRECTED)' : '');
    groups[k].forEach(function (x) {
      var body = '<div style="font-family:Arial,sans-serif;font-size:13px;color:#12261a">Dear ' + esc_(x.name) + ',<br><br>Please find attached the ' + esc_(title.toLowerCase()) + ' report for <b>' + esc_(per) + '</b> ('
        + units.map(function (u) { return esc_(u.unit); }).join(' and ') + ').<br>' + esc_(summary_(rep, D)) + '.<br><br>Mahrjan Sales Portal</div>';
      try { MailApp.sendEmail({ to: x.email, name: 'Mahrjan Sales Portal', subject: subj, htmlBody: body, attachments: [pdf] }); n++; log_(rep, period, x.email, 'SENT'); }
      catch (e) { log_(rep, period, x.email, 'FAILED', e.message); Logger.log(rep + ' → ' + x.email + ': ' + e.message); }
    });
  });
  if (!n) throw new Error(rep + ': no email could be sent');
  Logger.log(rep + ' ' + period + ' sent to ' + n); return 'sent';
}
function safe_(rep, from, to) { try { return sendReport(rep, from, to); } catch (e) { Logger.log(rep + ' failed: ' + e.message); log_(rep, to ? from + '..' + to : from, null, 'FAILED', e.message); return 'failed'; } }

// ---------- timers ----------
function jobVanLoad() { safe_('VAN_LOAD', day_(0)); }
function jobSameDay() {   // 20:30 – 01:00: today's work day (work day ends 02:00)
  var d = day_(6 * 3600000), h = Number(Utilities.formatDate(new Date(), TZ, 'H')), last = h >= 1 && h < 4;
  var R = rpc_('mail_ready', { p_date: d }) || [], boarded = R.reduce(function (a, x) { return a + (x.boarded || 0); }, 0);
  var miss = []; R.forEach(function (x) { (x.no_return || []).forEach(function (s) { miss.push(s + ' (' + x.branch + ')'); }); if (x.boarded && !x.sales) miss.push('sales not imported (' + x.branch + ')'); });
  if (!boarded) { Logger.log(d + ': nobody boarded'); return; }
  if (miss.length && !last) { Logger.log(d + ': waiting for ' + miss.join(', ')); return; }
  ['SALES_QTY', 'DAMAGE', 'GRV', 'VISIT'].forEach(function (r) { safe_(r, d); });
}
function jobNight() {     // 03:05: health; Sunday: weekly; 1st/11th/21st: MTD
  safe_('HEALTH', day_(864e5));
  if (Utilities.formatDate(new Date(), TZ, 'u') === '7') { var w = lastWeek_(); ['VARIANCE', 'FOC', 'EXPIRY'].forEach(function (r) { safe_(r, w.from, w.to); }); }
  var m = mtdRange_(); if (m) safe_('QTY_MTD', m.from, m.to);
}
function jobMorningCheck() {   // 07:45: anything that should have gone and did not → ALERTS
  var y = day_(864e5 + 6 * 3600000), out = [], chk = function (r, p) { if (!rpc_('mail_sent', { p_report: r, p_period: p })) out.push(TITLES[r] + ' ' + p); };
  chk('HEALTH', day_(864e5)); ['SALES_QTY', 'DAMAGE', 'GRV', 'VISIT'].forEach(function (r) { chk(r, y); });
  if (!out.length) return;
  (rpc_('mail_recipients', { p_report: 'ALERTS' }) || []).forEach(function (x) {
    MailApp.sendEmail({ to: x.email, name: 'Mahrjan Sales Portal', subject: 'Mahrjan: report not sent',
      htmlBody: '<div style="font-family:Arial,sans-serif;font-size:13px">Not sent (or no recipients ticked):<br>• ' + out.map(esc_).join('<br>• ') + '<br><br>To send now: Mahrjan Mailer → run sendNow.</div>' }); });
}
// ---------- weekly stock count: emailed once when a WEEKLY batch is posted ----------
function jobStockCount() {
  var since = new Date(Date.now() - 8 * 864e5).toISOString();
  var B = rest_('sc_batches', 'status=eq.POSTED&count_type=eq.WEEKLY&posted_at=gte.' + since), done = 0;
  if (!B.length) return;
  var br = {}; rest_('branches', '', 'id,name').forEach(function (b) { br[b.id] = b.name; });
  var it = {}; rest_('items', '', 'id,name,short_name,itrade_code,unit_cost,display_order').forEach(function (x) { it[x.id] = x; });
  B.forEach(function (b) { try {
    if (rpc_('mail_sent', { p_report: 'STOCK_COUNT', p_period: b.batch_no })) return;
    var L = rest_('sc_lines', 'batch_id=eq.' + b.id), Sy = {}; try { rest_('sc_system', 'batch_id=eq.' + b.id).forEach(function (x) { Sy[x.item_id] = Number(x.qty); }); } catch (e) {}
    var CAT = { RAW: 'Raw egg', FG: 'Finished goods', TRAY: 'Plain tray', LTRAY: 'Labelled tray', LABEL: 'Label roll' }, by = {};
    L.forEach(function (l) { var k = l.item_id + '|' + l.category, o = by[k] = by[k] || { id: l.item_id, cat: l.category, fresh: 0, other: 0, dmg: 0, tot: 0 }, q = Number(l.total_qty) || 0;
      if (l.stock_type === 'DAMAGE') o.dmg += q; else if (l.stock_type === 'GRV' || l.stock_type === 'CLEANED') o.other += q; else o.fresh += q; o.tot += q; });
    var hasSys = Object.keys(Sy).length > 0, rows = [], val = 0, sh = 0, ex = 0;
    Object.keys(by).map(function (k) { return by[k]; }).sort(function (a, c) { return (a.cat < c.cat ? -1 : a.cat > c.cat ? 1 : 0) || ((it[a.id] || {}).display_order || 0) - ((it[c.id] || {}).display_order || 0); }).forEach(function (o) {
      var x = it[o.id] || {}, sys = Sy[o.id], dif = hasSys && sys != null ? Math.round((o.tot - sys) * 100) / 100 : '', v = dif === '' ? '' : Math.round(dif * (Number(x.unit_cost) || 0) * 100) / 100;
      if (v !== '') val += v; if (dif !== '' && dif < 0) sh += -dif; if (dif !== '' && dif > 0) ex += dif;
      rows.push([CAT[o.cat] || o.cat, x.short_name || x.name || ('#' + o.id), o.fresh, o.other, o.dmg, o.tot].concat(hasSys ? [sys == null ? '' : sys, dif, v] : [])); });
    var D = { summary: {}, units: [{ branch_id: b.branch_id, unit: br[b.branch_id] || '', note: hasSys ? '' : 'iTrade stock not uploaded for this batch yet — differences not shown.',
      sections: [{ heading: 'Batch ' + b.batch_no + ' · counted ' + b.count_date + ' · ' + L.length + ' entries', num_from: 2,
        columns: ['Category', 'Item', 'Fresh', 'Repacked / Cleaned', 'Damage', 'Counted'].concat(hasSys ? ['iTrade', 'Difference', 'Difference AED'] : []), rows: rows,
        total: hasSys ? ['Total', '', '', '', '', '', '', '', Math.round(val * 100) / 100] : null }] }] };
    var rc = (rpc_('mail_recipients', { p_report: 'STOCK_COUNT' }) || []).filter(function (x) { return !x.branch_id || String(x.branch_id) === String(b.branch_id); });
    if (!rc.length) { Logger.log('STOCK_COUNT ' + b.batch_no + ': nobody ticked'); return; }
    var title = TITLES.STOCK_COUNT, per = nice_(b.count_date), html = html_(D, D.units, title, per), pdf = Utilities.newBlob(html, 'text/html', 'r.html').getAs('application/pdf').setName('STOCK COUNT_' + b.batch_no + '.pdf');
    var sum = rows.length + ' items' + (hasSys ? ' · short ' + fmt_(sh) + ' · excess ' + fmt_(ex) + ' · AED ' + (Math.round(val * 100) / 100).toFixed(2) : '');
    rc.forEach(function (x) { try { MailApp.sendEmail({ to: x.email, name: 'Mahrjan Sales Portal', subject: 'Mahrjan weekly stock count ' + per + ' · ' + (br[b.branch_id] || '') + ' · ' + sum,
        htmlBody: '<div style="font-family:Arial,sans-serif;font-size:13px">Dear ' + esc_(x.name) + ',<br><br>Please find attached the weekly stock count <b>' + esc_(b.batch_no) + '</b> (' + esc_(br[b.branch_id] || '') + ', ' + esc_(per) + ').<br>' + esc_(sum) + '.<br><br>Mahrjan Sales Portal</div>', attachments: [pdf] });
        log_('STOCK_COUNT', b.batch_no, x.email, 'SENT'); done++; } catch (e) { log_('STOCK_COUNT', b.batch_no, x.email, 'FAILED', e.message); } });
  } catch (e) { Logger.log('stock count ' + b.batch_no + ': ' + e.message); log_('STOCK_COUNT', b.batch_no, null, 'FAILED', e.message); } });
  Logger.log('stock count emails sent: ' + done);
}

// ---------- daily backup to Google Drive (the free database plan has no backups) ----------
var BACKUP_TABLES = ['branches','routes','vans','staff','customers','customer_assignment','items','item_recipe','van_day','loading_lines','return_lines','expenses','collections',
  'requirement_lines','sales_lines','sales_deletes','petty_cash','day_close_items','wh_batches','wh_lines','sc_batches','sc_lines','sc_system','office_log','email_recipients','role_access'];
function jobBackup() {
  var day = day_(0), blobs = [], miss = [];
  BACKUP_TABLES.forEach(function (t) { try { blobs.push(Utilities.newBlob(JSON.stringify(rest_(t, '')), 'application/json', t + '.json')); } catch (e) { miss.push(t); Logger.log('backup ' + t + ': ' + e.message); } });
  var it = DriveApp.getFoldersByName('Mahrjan Backup'), folder = it.hasNext() ? it.next() : DriveApp.createFolder('Mahrjan Backup');
  folder.createFile(Utilities.zip(blobs, 'mahrjan-backup-' + day + '.zip'));
  var old = Date.now() - 30 * 864e5, f = folder.getFiles(); while (f.hasNext()) { var x = f.next(); if (/^mahrjan-backup-/.test(x.getName()) && x.getDateCreated().getTime() < old) x.setTrashed(true); }
  log_('BACKUP', day, null, miss.length ? 'FAILED' : 'SENT', blobs.length + ' tables saved' + (miss.length ? '; not readable by the mailer login: ' + miss.join(', ') : ''));
  Logger.log('backup ' + day + ': ' + blobs.length + ' tables' + (miss.length ? ', missing ' + miss.join(', ') : ''));
}

function setup() {
  var H = ['jobVanLoad', 'jobSameDay', 'jobNight', 'jobMorningCheck', 'jobStockCount', 'jobBackup'];
  ScriptApp.getProjectTriggers().forEach(function (t) { if (H.indexOf(t.getHandlerFunction()) >= 0) ScriptApp.deleteTrigger(t); });
  var at = function (fn, h, m) { ScriptApp.newTrigger(fn).timeBased().atHour(h).nearMinute(m).everyDays(1).inTimezone(TZ).create(); };
  at('jobVanLoad', 11, 0); at('jobNight', 3, 5); at('jobMorningCheck', 7, 45); at('jobStockCount', 9, 0); at('jobStockCount', 21, 0); at('jobBackup', 2, 30);
  [[20, 30], [21, 0], [21, 30], [22, 0], [23, 0], [0, 0], [1, 0]].forEach(function (x) { at('jobSameDay', x[0], x[1]); });
  Logger.log('Timers created. Run testAll to check.');
}
// ---------- manual ----------
function testAll() { var y = day_(864e5 + 6 * 3600000), w = lastWeek_(); ['VAN_LOAD','SALES_QTY','DAMAGE','GRV','VISIT','HEALTH'].forEach(function (r) { Logger.log(r + ': ' + sendReport(r, y, y, true)); });
  ['VARIANCE','FOC','EXPIRY'].forEach(function (r) { Logger.log(r + ': ' + sendReport(r, w.from, w.to, true)); }); Logger.log('QTY_MTD: ' + sendReport('QTY_MTD', y.slice(0, 8) + '01', y, true)); }
/** Re-send one report: change the values below, then Run. */
function sendNow() { sendReport('DAMAGE', '2026-11-20', '2026-11-20', 'CORRECTED'); }
