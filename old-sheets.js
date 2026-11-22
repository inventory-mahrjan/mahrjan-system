/* Daily sheets: the old SALES_PORTAL screen, print and Excel, unchanged (copied from old-portal.html). Data comes live through MJ_SHEET_CTX. */
function mahrjanXlsx(sheets){
 const enc=new TextEncoder(),x=v=>String(v??'').replace(/[&<>"]/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;'}[c])).replace(/[\u0000-\u0008\u000B\u000C\u000E-\u001F]/g,'');
 const colName=n=>{let s='';n++;while(n){const m=(n-1)%26;s=String.fromCharCode(65+m)+s;n=Math.floor((n-1)/26);}return s;};
 const cv=v=>v!==null&&typeof v==='object'?v:{v:v};
 const sheetXml=sh=>{const rows=Array.from(sh.rows||[],r=>Array.from(r||[])),bold=new Set(sh.bold||[]),w=sh.widths?sh.widths.slice():[];if(!sh.widths)rows.forEach(r=>r.forEach((v,c)=>{const l=String(cv(v).v??'').length;w[c]=Math.max(w[c]||6,Math.min(48,l+2));}));
  return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">'+(sh.landscape?'<sheetPr><pageSetUpPr fitToPage="1"/></sheetPr>':'')+(sh.freeze?'<sheetViews><sheetView workbookViewId="0"><pane ySplit="1" topLeftCell="A2" activePane="bottomLeft" state="frozen"/></sheetView></sheetViews>':'')
  +(w.length?'<cols>'+w.map((v,c)=>'<col min="'+(c+1)+'" max="'+(c+1)+'" width="'+(v||8)+'" customWidth="1"/>').join('')+'</cols>':'')+'<sheetData>'
  +rows.map((r,i)=>'<row r="'+(i+1)+'"'+(sh.heights&&sh.heights[i]?' ht="'+sh.heights[i]+'" customHeight="1"':'')+'>'+r.map((cell,c)=>{const ref=colName(c)+(i+1),b=bold.has(i),o=cv(cell),v=o.v,st=o.s;
   if(o.f!=null)return '<c r="'+ref+'" s="'+(st??(b?4:2))+'"><f>'+x(o.f)+'</f>'+(typeof v==='number'&&Number.isFinite(v)?'<v>'+v+'</v>':'')+'</c>';
   if(v===''||v==null)return st!=null?'<c r="'+ref+'" s="'+st+'"/>':(b?'<c r="'+ref+'" s="1"/>':'');
   if(typeof v==='number'&&Number.isFinite(v))return '<c r="'+ref+'" s="'+(st??(b?(Number.isInteger(v)?3:4):(Number.isInteger(v)?0:2)))+'"><v>'+v+'</v></c>';
   return '<c r="'+ref+'" t="inlineStr"'+(st!=null?' s="'+st+'"':(b?' s="1"':''))+'><is><t xml:space="preserve">'+x(v)+'</t></is></c>';}).join('')+'</row>').join('')+'</sheetData>'
  +(sh.merges&&sh.merges.length?'<mergeCells count="'+sh.merges.length+'">'+sh.merges.map(m=>'<mergeCell ref="'+m+'"/>').join('')+'</mergeCells>':'')
  +(sh.landscape?'<pageMargins left="0.3" right="0.3" top="0.4" bottom="0.4" header="0.2" footer="0.2"/><pageSetup paperSize="9" orientation="landscape" fitToWidth="1" fitToHeight="0"/>':'')+(sh.image?'<drawing r:id="rId1"/>':'')+'</worksheet>';};
 const names=sheets.map((s,i)=>(String(s.name||'Sheet'+(i+1)).replace(/[\\\/?*\[\]:]/g,' ').slice(0,31))||'Sheet'+(i+1));
 const files=[['[Content_Types].xml','<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Default Extension="jpeg" ContentType="image/jpeg"/><Default Extension="png" ContentType="image/png"/><Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/><Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>'+sheets.map((s,i)=>'<Override PartName="/xl/worksheets/sheet'+(i+1)+'.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>'+(s.image?'<Override PartName="/xl/drawings/drawing'+(i+1)+'.xml" ContentType="application/vnd.openxmlformats-officedocument.drawing+xml"/>':'')).join('')+'</Types>'],
  ['_rels/.rels','<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>'],
  ['xl/workbook.xml','<?xml version="1.0" encoding="UTF-8" standalone="yes"?><workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets>'+names.map((n,i)=>'<sheet name="'+x(n)+'" sheetId="'+(i+1)+'" r:id="rId'+(i+1)+'"/>').join('')+'</sheets><calcPr calcId="191029" fullCalcOnLoad="1"/></workbook>'],
  ['xl/_rels/workbook.xml.rels','<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'+sheets.map((s,i)=>'<Relationship Id="rId'+(i+1)+'" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet'+(i+1)+'.xml"/>').join('')+'<Relationship Id="rId'+(sheets.length+1)+'" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/></Relationships>'],
  ['xl/styles.xml','<?xml version="1.0" encoding="UTF-8" standalone="yes"?><styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><fonts count="5"><font><sz val="11"/><name val="Calibri"/></font><font><b/><sz val="11"/><name val="Calibri"/></font><font><b/><sz val="11"/><color rgb="FFFFFFFF"/><name val="Calibri"/></font><font><b/><sz val="16"/><color rgb="FF0C363B"/><name val="Calibri"/></font><font><b/><sz val="12"/><name val="Calibri"/></font></fonts><fills count="5"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill><fill><patternFill patternType="solid"><fgColor rgb="FFE7EFE9"/><bgColor indexed="64"/></patternFill></fill><fill><patternFill patternType="solid"><fgColor rgb="FF0F5F57"/><bgColor indexed="64"/></patternFill></fill><fill><patternFill patternType="solid"><fgColor rgb="FFFFF6CC"/><bgColor indexed="64"/></patternFill></fill></fills><borders count="2"><border><left/><right/><top/><bottom/><diagonal/></border><border><left style="thin"><color rgb="FF9AA29D"/></left><right style="thin"><color rgb="FF9AA29D"/></right><top style="thin"><color rgb="FF9AA29D"/></top><bottom style="thin"><color rgb="FF9AA29D"/></bottom><diagonal/></border></borders><cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs><cellXfs count="17"><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/><xf numFmtId="0" fontId="1" fillId="2" borderId="0" xfId="0" applyFont="1" applyFill="1"/><xf numFmtId="4" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/><xf numFmtId="0" fontId="1" fillId="2" borderId="0" xfId="0" applyFont="1" applyFill="1"/><xf numFmtId="4" fontId="1" fillId="2" borderId="0" xfId="0" applyFont="1" applyFill="1" applyNumberFormat="1"/><xf numFmtId="0" fontId="0" fillId="0" borderId="1" xfId="0" applyBorder="1"/><xf numFmtId="4" fontId="0" fillId="0" borderId="1" xfId="0" applyNumberFormat="1" applyBorder="1"/><xf numFmtId="0" fontId="1" fillId="2" borderId="1" xfId="0" applyFont="1" applyFill="1" applyBorder="1"/><xf numFmtId="4" fontId="1" fillId="2" borderId="1" xfId="0" applyNumberFormat="1" applyFont="1" applyFill="1" applyBorder="1"/><xf numFmtId="0" fontId="2" fillId="3" borderId="1" xfId="0" applyFont="1" applyFill="1" applyBorder="1" applyAlignment="1"><alignment horizontal="center"/></xf><xf numFmtId="1" fontId="0" fillId="4" borderId="1" xfId="0" applyNumberFormat="1" applyFill="1" applyBorder="1"/><xf numFmtId="0" fontId="1" fillId="0" borderId="1" xfId="0" applyFont="1" applyBorder="1"/><xf numFmtId="4" fontId="1" fillId="0" borderId="1" xfId="0" applyNumberFormat="1" applyFont="1" applyBorder="1"/><xf numFmtId="0" fontId="1" fillId="0" borderId="0" xfId="0" applyFont="1"/><xf numFmtId="0" fontId="3" fillId="0" borderId="0" xfId="0" applyFont="1" applyAlignment="1"><alignment vertical="center"/></xf><xf numFmtId="0" fontId="4" fillId="0" borderId="0" xfId="0" applyFont="1" applyAlignment="1"><alignment vertical="center"/></xf><xf numFmtId="0" fontId="4" fillId="2" borderId="1" xfId="0" applyFont="1" applyFill="1" applyBorder="1" applyAlignment="1"><alignment horizontal="center" vertical="center"/></xf></cellXfs></styleSheet>']]
  .concat(sheets.map((s,i)=>['xl/worksheets/sheet'+(i+1)+'.xml',sheetXml(s)]));
 // Picture (logo): oneCellAnchor at col/row (0-based) with a size in pixels.
 sheets.forEach((s,i)=>{const im=s.image;if(!im||!im.b64)return;const n=i+1,ext=im.ext||'jpeg',E=v=>Math.round(v*9525);
  const bin=Uint8Array.from(atob(im.b64),ch=>ch.charCodeAt(0));
  files.push(['xl/media/image'+n+'.'+ext,bin]);
  files.push(['xl/worksheets/_rels/sheet'+n+'.xml.rels','<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/drawing" Target="../drawings/drawing'+n+'.xml"/></Relationships>']);
  files.push(['xl/drawings/_rels/drawing'+n+'.xml.rels','<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" Target="../media/image'+n+'.'+ext+'"/></Relationships>']);
  files.push(['xl/drawings/drawing'+n+'.xml','<?xml version="1.0" encoding="UTF-8" standalone="yes"?><xdr:wsDr xmlns:xdr="http://schemas.openxmlformats.org/drawingml/2006/spreadsheetDrawing" xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><xdr:oneCellAnchor><xdr:from><xdr:col>'+(im.col||0)+'</xdr:col><xdr:colOff>'+E(im.dx||0)+'</xdr:colOff><xdr:row>'+(im.row||0)+'</xdr:row><xdr:rowOff>'+E(im.dy||0)+'</xdr:rowOff></xdr:from><xdr:ext cx="'+E(im.w)+'" cy="'+E(im.h)+'"/><xdr:pic><xdr:nvPicPr><xdr:cNvPr id="2" name="Logo"/><xdr:cNvPicPr><a:picLocks noChangeAspect="1"/></xdr:cNvPicPr></xdr:nvPicPr><xdr:blipFill><a:blip r:embed="rId1"/><a:stretch><a:fillRect/></a:stretch></xdr:blipFill><xdr:spPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="'+E(im.w)+'" cy="'+E(im.h)+'"/></a:xfrm><a:prstGeom prst="rect"><a:avLst/></a:prstGeom></xdr:spPr></xdr:pic><xdr:clientData/></xdr:oneCellAnchor></xdr:wsDr>']);});
 const T=new Uint32Array(256);for(let n=0;n<256;n++){let c=n;for(let k=0;k<8;k++)c=c&1?0xEDB88320^(c>>>1):c>>>1;T[n]=c>>>0;}
 const crc=b=>{let c=0xFFFFFFFF;for(let i=0;i<b.length;i++)c=T[(c^b[i])&255]^(c>>>8);return (c^0xFFFFFFFF)>>>0;};
 const parts=[],central=[];let off=0;
 const hdr=(n)=>{const a=new Uint8Array(n);return [a,new DataView(a.buffer)];};
 files.forEach(([name,text])=>{const nm=enc.encode(name),data=typeof text==='string'?enc.encode(text):text,c=crc(data);
  const [l,lv]=hdr(30);lv.setUint32(0,0x04034b50,true);lv.setUint16(4,20,true);lv.setUint16(12,0x21,true);lv.setUint32(14,c,true);lv.setUint32(18,data.length,true);lv.setUint32(22,data.length,true);lv.setUint16(26,nm.length,true);
  parts.push(l,nm,data);
  const [h,hv]=hdr(46);hv.setUint32(0,0x02014b50,true);hv.setUint16(4,20,true);hv.setUint16(6,20,true);hv.setUint16(14,0x21,true);hv.setUint32(16,c,true);hv.setUint32(20,data.length,true);hv.setUint32(24,data.length,true);hv.setUint16(28,nm.length,true);hv.setUint32(42,off,true);
  central.push(h,nm);off+=30+nm.length+data.length;});
 const csize=central.reduce((a,b)=>a+b.length,0),[e,ev]=hdr(22);ev.setUint32(0,0x06054b50,true);ev.setUint16(8,files.length,true);ev.setUint16(10,files.length,true);ev.setUint32(12,csize,true);ev.setUint32(16,off,true);
 return new Blob(parts.concat(central,[e]),{type:'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'});
}
const XLSX_MIME='application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
/* Daily cash sheet as Excel, same layout as the accounts team's template: salesmen A–H, settlement I–J,
   denomination count K–M (QTY left blank to fill in Excel), receipts · payments · suspense below. Totals are live formulas. */
function cashXlsx_(d){
 const C=d.cash,S={t:5,n:6,h:7,hn:8,ti:9,q:10,b:11,bn:12,sg:13},rows=[],merges=[],L=c=>String.fromCharCode(64+c);
 const r2=v=>Math.round((Number(v)||0)*100)/100,set=(r,c,v,s,f)=>{(rows[r-1]=rows[r-1]||[])[c-1]={v:v,s:s,f:f};};
 const box=(r,c1,c2,v,s,mg)=>{set(r,c1,v,s);for(let c=c1+1;c<=c2;c++)set(r,c,'',s);if(mg&&c2>c1)merges.push(L(c1)+r+':'+L(c2)+r);};
 box(1,1,8,'SALES · RETURNS · EXPENSES',S.ti,1);box(1,9,10,'CASH SETTLEMENT',S.ti,1);box(1,11,13,'Petty Cash/Cash in Hand',S.ti,1);
 ['SALESMAN','SALE CASH','SALE CREDIT','RET CASH','RET CREDIT','FUEL','PARKING','CARTON','ITEM','AMOUNT','AED','QTY','TOTAL'].forEach((h,i)=>set(2,i+1,h,S.h));
 C.men.forEach((m,i)=>m.forEach((v,j)=>set(3+i,j+1,v,j?S.n:S.t)));
 const tr=3+C.men.length,tot=j=>r2(C.men.reduce((a,m)=>a+m[j],0));
 set(tr,1,'TOTAL',S.h);for(let j=1;j<8;j++)set(tr,j+1,tot(j),S.hn,'SUM('+L(j+1)+'3:'+L(j+1)+(tr-1)+')');
 const tb=Math.max(tr,13)+1,k=Math.max(C.receipts.length,C.payments.length,C.suspense.length,1),d0=tb+2,tt=d0+k;
 const rec=r2(C.receipts.reduce((a,x)=>a+x[2],0)),pay=r2(C.payments.reduce((a,x)=>a+x[2],0)),sus=r2(C.suspense.reduce((a,x)=>a+x[1],0));
 const exp=r2(tot(5)+tot(6)+tot(7)),nop=C.opening==null,close=nop?'':r2(C.opening+tot(1)-tot(3)+rec-pay-exp-C.dep),hand=nop?'':r2(close-sus);
 [['OPENING CASH BALANCE',nop?'':C.opening],['+ CASH SALES',tot(1),'B'+tr],['− CASH SALES RETURN',tot(3),'D'+tr],['+ CASH RECEIPTS',rec,'F'+tt],['− PAYMENTS',pay,'J'+tt],
  ['− EXPENSES',exp,'F'+tr+'+G'+tr+'+H'+tr],['− BANK DEPOSITS',C.dep],['CLOSING BALANCE',close,'J3+J4-J5+J6-J7-J8-J9',1],['− SUSPENSE OUTSTANDING',sus,'M'+tt],
  ['CASH IN HAND',hand,'J10-J11',1],['SHORT/EXCESS','','IF(COUNT(L3:L13)=0,"",SUM(M3:M13)-J12)',1]]
  .forEach((p,i)=>{set(3+i,9,p[0],p[3]?S.b:S.t);set(3+i,10,p[1],i===0&&nop?S.q:p[3]?S.bn:S.n,p[2]);});
 [0.25,0.5,1,5,10,20,50,100,200,500,1000].forEach((a,i)=>{set(3+i,11,a,S.t);set(3+i,12,'',S.q);set(3+i,13,'',S.n,'IF(L'+(3+i)+'="","",L'+(3+i)+'*K'+(3+i)+')');});
 box(tb,1,6,'RECEIPTS',S.ti,1);box(tb,7,10,'PAYMENTS',S.ti,1);box(tb,11,13,'SUSPENSE',S.ti,1);
 set(tb+1,1,'REF',S.h);box(tb+1,2,5,'PARTICULARS',S.h,1);set(tb+1,6,'AMOUNT',S.h);
 set(tb+1,7,'REF',S.h);box(tb+1,8,9,'PARTICULARS',S.h,1);set(tb+1,10,'AMOUNT',S.h);
 box(tb+1,11,12,'PARTICULARS',S.h,1);set(tb+1,13,'AMOUNT',S.h);
 for(let i=0;i<k;i++){const r=d0+i,a=C.receipts[i],p=C.payments[i],u=C.suspense[i];
  set(r,1,a?a[0]:'',S.t);box(r,2,5,a?a[1]:'',S.t,1);set(r,6,a?a[2]:'',S.n);
  set(r,7,p?p[0]:'',S.t);box(r,8,9,p?p[1]:'',S.t,1);set(r,10,p?p[2]:'',S.n);
  box(r,11,12,u?u[0]:'',S.t,1);set(r,13,u?u[1]:'',S.n);}
 set(tt,1,'',S.h);box(tt,2,5,'TOTAL RECEIPTS',S.h,1);set(tt,6,rec,S.hn,'SUM(F'+d0+':F'+(tt-1)+')');
 set(tt,7,'',S.h);box(tt,8,9,'TOTAL PAYMENTS',S.h,1);set(tt,10,pay,S.hn,'SUM(J'+d0+':J'+(tt-1)+')');
 box(tt,11,12,'TOTAL',S.h,1);set(tt,13,sus,S.hn,'SUM(M'+d0+':M'+(tt-1)+')');
 set(tt+3,1,'CREATED BY',S.sg);set(tt+3,5,'VERIFIED BY',S.sg);set(tt+3,9,'APPROVED BY',S.sg);
 const pos=(d.position||[]).filter(p=>typeof p[2]==='number');
 // Header block on top: logo, company, title and the cash-sheet date. Everything below moves down HD rows.
 const HD=5,sh=s=>String(s).replace(/(\$?[A-Z]{1,2}\$?)(\d+)/g,(m,c,r)=>c+(Number(r)+HD));
 rows.forEach(r=>(r||[]).forEach(c=>{if(c&&c.f!=null)c.f=sh(c.f);}));
 for(let i=0;i<merges.length;i++)merges[i]=sh(merges[i]);
 const dt=new Date(String(d.date).slice(0,10)+'T12:00:00Z'),dLong=isNaN(dt)?String(d.date||''):dt.toLocaleDateString('en-GB',{weekday:'long',day:'2-digit',month:'long',year:'numeric',timeZone:'UTC'});
 const unit=String((window.PortalSession&&PortalSession.unitName)||'MAHRJAN GENERAL TRADING LLC');
 const top=[[],[],[],[],[]],put=(r,c,v,s)=>{top[r][c]={v:v,s:s};};
 put(0,2,unit,14);put(1,2,'DAILY CASH SHEET',15);
 put(0,10,'CASH DATE',16);put(0,11,'',16);put(0,12,'',16);put(1,10,dLong,16);put(1,11,'',16);put(1,12,'',16);
 put(2,2,'Printed '+new Date().toLocaleString('en-GB',{day:'2-digit',month:'short',year:'numeric',hour:'2-digit',minute:'2-digit'}),0);
 merges.push('C1:J1','C2:J2','K1:M1','K2:M2','C3:J3');
 const lg=document.querySelector('img.brandlogo'),src=lg&&lg.src||'',b64=src.split(',')[1]||'',ratio=lg&&lg.naturalHeight?lg.naturalWidth/lg.naturalHeight:2.8,lh=62;
 return [{name:'CASH SHEET',rows:top.concat(rows),merges:merges,landscape:true,heights:[26,22,16,8,8],widths:[13.1,12.8,12,14.4,10.8,9,10.8,10.1,23.8,14.6,11.8,11,10.6],
   image:b64?{b64:b64,ext:/image\/png/.test(src)?'png':'jpeg',col:0,row:0,dx:4,dy:4,w:Math.round(lh*ratio),h:lh}:null},
  {name:'Cash position',widths:[26,14],rows:[[{v:'Cash date: '+dLong,s:S.sg}],[{v:'Item',s:S.h},{v:'Amount',s:S.h}]].concat(pos.map((p,i)=>[{v:p[0],s:S.t},{v:p[2],s:S.n,f:"'CASH SHEET'!J"+(3+HD+i)}]))}];
}
function localToday(){const d=new Date();return new Date(d-d.getTimezoneOffset()*60000).toISOString().slice(0,10);}
/* Pure report logic. No network, storage, or live database calls. */

window.MobileReport = {fmtDate(v){return new Date(v+'T00:00:00').toLocaleDateString('en-GB');},say(v){alert(v);},
  reportPage_(d) {
    const esc = v => String(v == null ? '' : v).replace(/&/g, '&amp;').replace(/</g, '&lt;');
    // VEHICLE and ROUTE go in the page header, under the date and salesman
    let vanLine = '';
    d = Object.assign({}, d, { rows: d.rows.map(r => r.slice()) });
    for (let i = 0; i < Math.min(d.rows.length, 4) && !vanLine; i++) {
      const r = d.rows[i], bits = [];
      r.forEach((v, k) => { if (/^\s*(VEHICLE|ROUTE):/i.test(String(v))) { bits.push(esc(String(v).replace(/:\s+/, ': '))); r[k] = ''; } });
      if (bits.length) vanLine = bits.join('&nbsp;&nbsp;&nbsp;');
    }
    // loading/unloading time, temperature and KM go in the middle of the header
    const TRIP = ['LOADING TIME', 'UNLOADING TIME', 'START KM', 'LOADING TEMP', 'UNLOADING TEMP', 'END KM'];
    const trip = {};
    for (let i = 0; i < Math.min(d.rows.length, 4); i++) {
      d.rows[i].forEach((v, k) => {
        const m = String(v).match(/^\s*(LOADING TIME|UNLOADING TIME|LOADING TEMP|UNLOADING TEMP|START KM|END KM):\s*(.*)$/i);
        if (m) { trip[m[1].toUpperCase()] = m[2].trim(); d.rows[i][k] = ''; }
      });
    }
    const tripHtml = Object.keys(trip).length ? '<div class="mid">' + TRIP.map(k => '<div><b>' + k + '</b><span>' + (trip[k] && !/^_+$/.test(trip[k]) ? String(trip[k]).replace(/</g, '&lt;') + (/TEMP/.test(k) && /^[0-9.\-]+$/.test(trip[k]) ? ' °C' : '') : '') + '</span></div>').join('') + '</div>' : '';
    // rows emptied above disappear instead of leaving blank lines at the top
    while (d.rows.length && !d.rows[0].some(v => !(v === '' || v == null))) {
      d.rows.shift();
      ['head', 'bold', 'titles', 'sign'].forEach(key => { if (d[key]) d[key] = d[key].map(n => n - 1); });
      if (d.segs) { const ns = {}; Object.keys(d.segs).forEach(n => { ns[n - 1] = d.segs[n]; }); d.segs = ns; }
    }
    const money = (d.money || []).map(c => c - 1);
    const rows = d.rows, W = rows.reduce((m, r) => Math.max(m, r.length), 0);
    const empty = v => v === '' || v == null;
    const heads = d.head || [], titles = d.titles || [], signs = d.sign || [];
    const segsOf = h => (d.segs && d.segs[h]) || [[1, W]];
    const f2 = n => n.toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 2 });
    // numbers, invoice numbers and barcodes print centred and bold
    const TEXT = ['HEAD NO', 'CUSTOMER', 'ITEM', 'TYPE', 'PARTICULARS', 'NAME', 'SALESMAN'];
    const td = (v, k, bold, hd) => {
      if (TEXT.indexOf(String(hd || '').toUpperCase()) > -1) return '<td class="l' + (bold ? ' b' : '') + '">' + esc(v) + '</td>';
      if (typeof v === 'number') return '<td class="n' + (bold ? ' b' : '') + '">' + (money.includes(k) ? f2(v) : String(v)) + '</td>';
      const t = String(v == null ? '' : v);
      const numLike = /^-?[0-9][0-9 ,.]*$/.test(t.trim()) || t.trim() === 'NIL';
      return '<td class="' + (numLike ? 'n' : '') + (bold ? ' b' : '') + '">' + esc(t) + '</td>';
    };
    const used = {};
    const out = [];
    let delHtml = '';
    for (let i = 0; i < rows.length; i++) {
      if (used[i]) continue;
      const r = rows[i];
      if (heads.includes(i)) {
        const segs = segsOf(i);
        // a title row just above names each side-by-side table
        const tRow = titles.includes(i - 1) ? rows[i - 1] : null;
        const blocks = segs.map(([x, y]) => {
          const hd = rows[i].slice(x - 1, y);
          const boxed = d.name === 'CASH SHEET' && hd.some(v => String(v).toUpperCase() === 'PARTICULARS');
          if (boxed) {
            let end = i + 1;
            while (end < rows.length && rows[end].slice(x - 1, y).some(v => !empty(v))) end++;
            for (let k = i; k < end; k++) used[k] = true;
            const n = y - x + 1;
            const title = tRow && !empty(tRow[x - 1]) ? String(tRow[x - 1]) : '';
            let h = (title ? '<div class="ti">' + esc(title) + '</div>' : '') + '<table class="bx"><colgroup>' + (n > 2 ? '<col style="width:13mm"><col><col style="width:22mm">' : '<col><col style="width:22mm">') + '</colgroup>'
              + '<tr class="h">' + hd.map(v => '<td>' + esc(v) + '</td>').join('') + '</tr>';
            for (let k = i + 1; k < end; k++) {
              const c = rows[k].slice(x - 1, y).map(v => typeof v === 'string' ? v.trim() : v);
              const label = c.slice(0, n - 1).filter(v => !empty(v)).join(' ');
              const amt = c[n - 1];
              const amtHtml = typeof amt === 'number' ? f2(amt) : esc(amt);
              if (/^TOTAL/i.test(label)) {
                h += '<tr class="bt"><td class="b" colspan="' + (n - 1) + '">' + esc(label) + '</td><td class="n" style="font-weight:400">' + amtHtml + '</td></tr>';
              } else {
                h += '<tr>' + c.slice(0, n - 1).map((v, j) => '<td class="' + (n > 2 && j === 0 ? 'n' : '') + '">' + esc(v) + '</td>').join('') + '<td class="n">' + amtHtml + '</td></tr>';
              }
            }
            return { html: h + '</table>', span: n, boxed: true };
          }
          let end = i + 1;
          while (end < rows.length && rows[end].slice(x - 1, y).some(v => !empty(v))) end++;
          for (let k = i; k < end; k++) used[k] = true;
          // Empty cartons: a compact 3-column box — item left, salesman count and received box centred.
          if (String(rows[i][x - 1] || '').trim().toUpperCase() === 'EMPTY CARTONS') {
            const nc = y - x + 1;
            let h = '<table style="width:' + (nc < 3 ? 80 : 120) + 'mm;margin-top:2mm;table-layout:fixed"><colgroup><col style="width:48mm">' + (nc < 3 ? '<col style="width:32mm">' : '<col style="width:36mm"><col style="width:36mm">') + '</colgroup>'
              + '<tr class="h">' + rows[i].slice(x - 1, y).map((v, j) => '<td style="text-align:' + (j === 0 ? 'left' : 'center') + '">' + esc(v) + '</td>').join('') + '</tr>';
            for (let k = i + 1; k < end; k++) h += '<tr>' + rows[k].slice(x - 1, y).map((v, j) => '<td style="text-align:' + (j === 0 ? 'left' : 'center') + (j === 2 ? ';border-left:1px solid #c9cfcb' : '') + '"' + (j > 0 ? ' class="n"' : '') + '>' + esc(String(v == null ? '' : v).trim()) + '</td>').join('') + '</tr>';
            return { html: h + '</table>', span: y - x + 1 };
          }
          let html = '<table><tr class="h">' + rows[i].slice(x - 1, y).map(v => '<td' + (TEXT.indexOf(String(v).trim().toUpperCase()) > -1 ? ' class="l"' : '') + '>' + esc(v) + '</td>').join('') + '</tr>';
          for (let k = i + 1; k < end; k++) {
            const bold = (d.name !== 'SALESMAN SUMMARY' && (d.bold || []).includes(k)) || rows[k].slice(x - 1, y).some(v => /^(TOTAL|CLOSING|CASH TO HAND OVER|CASH IN HAND)/i.test(String(v).trim()));
            const lab = String(rows[k][x - 1] || '').trim(), trCls = (/^CASH COLLECTION$/i.test(lab) ? 'bt2 ' : '') + (/^CASH TO HAND OVER$/i.test(lab) ? 'big ' : '') + (/^(CHEQUES TO HAND OVER|CREDIT SALES \(NET OF GRV\))$/i.test(lab) ? 'dim' : '');
            html += '<tr' + (trCls.trim() ? ' class="' + trCls.trim() + '"' : '') + '>' + rows[k].slice(x - 1, y).map((v, j) => td(v, x - 1 + j, bold, rows[i][x - 1 + j])).join('') + '</tr>';
          }
          html += '</table>';
          const tt = tRow && !empty(tRow[x - 1]) ? '<div class="ti">' + esc(tRow[x - 1]) + '</div>' : '';
          return { html: tt + html, span: y - x + 1 };
        });
        const summary = d.name === 'SALESMAN SUMMARY';
        // salesman summary: deleted bills sit under collection + expenses, settlement stays on the right
        if (summary && blocks.length === 1 && /DELETED BILLS/.test(blocks[0].html)) { delHtml = blocks[0].html; continue; }
        if (summary && blocks.length === 3) { out.push({ side: blocks }); continue; }
        // Loading sheet: salesman / manager sign lines sit to the right of the empty-cartons table.
        if (blocks.length === 1 && String(rows[i][segsOf(i)[0][0] - 1] || '').trim().toUpperCase() === 'EMPTY CARTONS') {
          const si = signs.find(n => n > i);
          if (si != null) {
            used[si] = true;
            const labs = rows[si].filter(v => !empty(v));
            out.push('<div style="display:flex;align-items:flex-end;gap:14mm"><div style="flex:none">' + blocks[0].html + '</div>'
              + '<div style="flex:1;display:flex;gap:14mm;font-weight:700">' + labs.map(v => '<div style="flex:1;border-top:1px solid #5c655f;padding-top:1.5mm">' + esc(v) + '</div>').join('') + '</div></div>');
            continue;
          }
        }
        if (blocks.length === 1) out.push(blocks[0].html);
        else if (blocks[0].boxed) out.push('<div class="row bxrow">' + blocks.map(bk => '<div class="blk">' + bk.html + '</div>').join('') + '</div>');
        else out.push('<div class="row" style="grid-template-columns:' + blocks.map((bk, bi) => 'minmax(max-content,' + (bi === 0 ? 1.7 : 1) + 'fr)').join(' ') + '">' + blocks.map(bk => '<div class="blk">' + bk.html + '</div>').join('') + '</div>');
        continue;
      }
      if (!r.some(v => !empty(v))) { out.push('<div class="gap"></div>'); continue; }
      if (titles.includes(i)) {
        if (heads.includes(i + 1)) continue;
        out.push('<div class="ti">' + r.filter(v => !empty(v)).map(esc).join('   ') + '</div>');
        continue;
      }
      if (signs.includes(i)) { if (used[i]) continue; out.push('<div class="sig">' + r.filter(v => !empty(v)).map(v => '<div>' + esc(v) + '</div>').join('') + '</div>'); continue; }
      const bold = (d.bold || []).includes(i);
      out.push('<div class="ln' + (bold ? ' lb' : '') + '">' + r.filter(v => !empty(v)).map(v => '<span>' + esc(typeof v === 'number' ? (money.includes(r.indexOf(v)) ? f2(v) : v) : v) + '</span>').join('') + '</div>');
    }
    for (let q = 0; q < out.length; q++) {
      if (typeof out[q] === 'string') continue;
      const [a, b, c] = out[q].side;
      out[q] = '<div class="row" style="margin-top:4mm;grid-template-columns:minmax(0,2.7fr) minmax(max-content,1fr)">'
        + '<div><div class="row" style="grid-template-columns:minmax(max-content,1.7fr) minmax(max-content,1fr)"><div class="blk">' + a.html + '</div><div class="blk">' + b.html + '</div></div>'
        + (delHtml ? '<div class="blk ctr" style="margin-top:4mm">' + delHtml + '</div>' : '') + '</div>'
        + '<div class="blk">' + c.html + '</div></div>';
      delHtml = '';
    }
    if (delHtml) out.push('<div class="ctr">' + delHtml + '</div>');
    const pos = d.name === 'CASH SHEET' ? '' : (d.position || []).filter(p => typeof p[2] === 'number')
      .map((p, i, all) => '<tr class="' + (i === all.length - 1 ? 'h' : '') + '"><td>' + esc(p[0]) + '</td><td class="n">' + f2(p[2]) + '</td></tr>').join('');
    const logo = 'data:image/jpeg;base64,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';
    const title = d.name === 'CASH SHEET' ? 'DAILY CASH SHEET' : d.name;
    const sub = this.fmtDate(d.date) + (d.salesman && d.name !== 'CASH SHEET' ? ' · ' + d.salesman : '');
    return '<div class="page"><div class="top"><img src="' + logo + '"><div class="t">' + esc(d.company || 'MAHRJAN GENERAL TRADING LLC') + '<br>' + esc(title) + '</div>' + tripHtml + '<div class="s">' + esc(sub) + (vanLine ? '<div class="v">' + vanLine + '</div>' : '') + '</div></div>'
      + out.join('')
      + (pos ? '<table class="pos"><tr class="h"><td colspan="2">CASH POSITION</td></tr>' + pos + '</table>' : '')
      + '</div>';
  }
,
  /** PDF / print file name: SALESMAN_REPORT TYPE_27 OCT 2026 (salesman left out for cash and picking sheets). */
  pdfName_(sel) {
    const parts = (sel && sel.parts) || [sel || {}], M = ['JAN','FEB','MAR','APR','MAY','JUN','JUL','AUG','SEP','OCT','NOV','DEC'];
    const iso = String((parts[0] || {}).date || sel.date || ''), q = iso.split('-');
    const day = q.length === 3 ? q[2] + ' ' + M[Number(q[1]) - 1] + ' ' + q[0] : iso;
    const type = String(sel.name || 'REPORT');
    const men = Array.from(new Set(parts.map(x => String(x.salesman || '').trim()).filter(Boolean)));
    const who = ['CASH SHEET', 'PICKING SHEET', 'MONTHLY CLOSING'].includes(sel.name) || !men.length ? '' : (men.length > 1 ? 'ALL SALESMEN' : men[0]);
    return [who, type, day].filter(Boolean).join('_').toUpperCase().replace(/[\\/:*?"<>|]+/g, ' ').replace(/\s+/g, ' ').trim();
  },
  openPrint_(pages, title, win) {
    const html = '<!doctype html><html><head><meta charset="utf-8"><title>' + String(title).replace(/</g, '&lt;') + '</title>'
      + '<link rel="preconnect" href="https://fonts.googleapis.com"><link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>'
      + '<link href="https://fonts.googleapis.com/css2?family=Economica:wght@400;700&display=block" rel="stylesheet"><style>'
      + '@page{size:A4 landscape;margin:0}.sheet{box-sizing:border-box;width:297mm;height:209mm;padding:5mm 8mm;overflow:hidden}.sheet+.sheet{break-before:page;page-break-before:always}'
      + 'body{font:11pt Economica,Arial,sans-serif;color:#000;margin:0}'
      + '.top{display:flex;align-items:center;gap:5mm;border-bottom:2px solid #1B4332;padding-bottom:2mm;margin-bottom:1.5mm}'
      + '.top img{height:14mm;border-radius:1.5mm}.t{font:700 16pt Economica,Arial,sans-serif;color:#1B4332}.s{margin-left:auto;font-weight:700;font-size:12pt;text-align:right}.ctr td:not(.l){text-align:center!important}td.l,tr.h td.l{text-align:left}.t{white-space:nowrap;flex:none;line-height:1.15}.mid{margin:0 auto;display:grid;grid-template-columns:repeat(3,auto);column-gap:5mm;row-gap:1.2mm;font-size:10pt}.mid div{display:flex;gap:2mm;align-items:baseline}.mid b{font-weight:700;color:#3a433d}.mid span{min-width:16mm;border-bottom:1px solid #9aa29d;text-align:center;padding:0 1mm}.s .v{font-size:11pt;margin-top:.6mm}'
      + 'table{border-collapse:collapse;width:100%}td{padding:.8mm 1.4mm;border-bottom:1px solid #c9cfcb;white-space:nowrap;color:#000}'
      + 'td.n{text-align:center;font:400 11.5pt Economica,Arial,sans-serif;font-variant-numeric:tabular-nums}td.b{font-weight:700}'
      + 'tr.h td{background:#e7efe9;font-weight:700;text-align:center;border-top:1px solid #000;border-bottom:1px solid #000}'
      + '.ti{font-weight:700;color:#1B4332;padding:3mm 1.5mm 1mm}.row{display:flex;gap:7mm;align-items:flex-start}'
      + '.ln{display:flex;gap:10mm;padding:1mm 1.5mm}.lb{font-weight:700}.gap{height:0}'
      + '.pos{width:100mm;margin-top:5mm}.sig{display:flex;gap:14mm;margin-top:9mm;font-weight:700}.sig div{flex:1;border-top:1px solid #5c655f;padding-top:1.5mm}'
      + '*{-webkit-print-color-adjust:exact;print-color-adjust:exact}.page{width:281mm;overflow:hidden;margin:0 auto}.row{display:grid;column-gap:6mm;align-items:start}.blk{min-width:0}.blk td{white-space:nowrap}.blk .ti{padding-top:1.5mm}.top+.row .ti,.top+.row .blk .ti{padding-top:.6mm}.page+.page{break-before:page;page-break-before:always}.page{break-inside:avoid}.bxrow{grid-template-columns:37fr 37fr 23fr;column-gap:6mm;margin-top:2.5mm}table.bx{table-layout:fixed}table.bx td{overflow:hidden;text-overflow:clip}table.bx tr.bt td{border-top:1px solid #000}tr.bt2 td{border-top:2px solid #000}tr.big td{font-size:12pt!important}tr.big td.n{font-size:12.5pt!important}tr.dim td{color:#8a8a8a!important}</style></head><body>' + pages.map(function(p){return '<div class="sheet">'+p+'</div>';}).join('')
      + '<scr' + 'ipt>window.onload=function(){(document.fonts&&document.fonts.ready?document.fonts.ready:Promise.resolve()).then(function(){'
      + 'var H=748,W=1060;'
      + 'document.querySelectorAll(".page").forEach(function(p){p.style.zoom=1;p.style.width=W+"px";var z=Math.min(1,H/p.scrollHeight,W/p.scrollWidth);'
      + 'for(var i=0;i<10&&z<1;i++){p.style.width=(W/z)+"px";p.style.zoom=z;var r=p.getBoundingClientRect();if(r.height<=H+2&&r.width<=W+2)break;z=z*0.97;}'
      + 'if(z<1)p.style.zoom=Math.floor(z*100)/100;'
      + 'else{var tds=p.querySelectorAll("tr"),free=H-p.scrollHeight;if(free>20&&tds.length){var add=Math.min(8,(free*0.9)/tds.length);p.querySelectorAll("td").forEach(function(c){var cs=getComputedStyle(c);c.style.paddingTop=(parseFloat(cs.paddingTop)+add/2)+"px";c.style.paddingBottom=(parseFloat(cs.paddingBottom)+add/2)+"px";});}'
      + 'p.style.display="flex";p.style.flexDirection="column";p.style.minHeight=H+"px";var sg=p.querySelector(".sig");if(sg)sg.style.marginTop="auto";}});'
      + 'setTimeout(function(){window.print()},300)})}</scr' + 'ipt></body></html>';
    this._lastPrintHtml = html;
    const w = win || window.open('', '_blank');
    if (!w) { this.say('Allow pop-ups to print'); return; }
    w.document.open(); w.document.write(html); w.document.close();
  }
};


/* Daily sheet controls. */
(function(){
 const labels={'LOADING SHEET':'Loading sheet','SALESMAN SUMMARY':'Salesman summary','CASH SHEET':'Cash sheet','PICKING SHEET':'Picking sheet'};
 const routes={'loading-sheet':'LOADING SHEET','salesman-summary':'SALESMAN SUMMARY','cash-sheet':'CASH SHEET','picking-sheet':'PICKING SHEET'};
 const e=v=>String(v??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
 let host,man='',day='',type='LOADING SHEET',selected=null,ticket=0,busy=false;
 function getHost(){host=document.getElementById('workbookReports');if(!host){host=document.createElement('section');host.id='workbookReports';}return host;}
 function table(d){
   return (d.parts||[d]).map(p=>'<h3>'+e(p.name)+(p.company&&(d.parts||[]).length>1?' — '+e(p.company):'')+'</h3><div class="mobile-report-scroll"><table class="mobile-report"><tbody>'+p.rows.map((r,i)=>{if(!r.some(v=>v!==''&&v!=null))return '';let last=r.length-1;while(last>0&&(r[last]===''||r[last]==null))last--;const head=(p.head||[]).includes(i),bold=head||(p.name!=='SALESMAN SUMMARY'&&(p.bold||[]).includes(i));const L=x=>String(x==null?'':x).trim().toUpperCase(),sep=r.findIndex(x=>L(x)==='CASH COLLECTION'),big=r.findIndex(x=>L(x)==='CASH TO HAND OVER'),dim=r.findIndex(x=>L(x)==='CHEQUES TO HAND OVER'||L(x)==='CREDIT SALES (NET OF GRV)'),on=(j,k)=>j>=0&&(k===j||k===j+1);return '<tr style="background:'+(head?'#f3f4f1':'transparent')+'">'+r.slice(0,last+1).map((v,k)=>'<td style="text-align:'+(typeof v==='number'?'right':'left')+';font-weight:'+(bold||on(big,k)?'700':'400')+(on(sep,k)?';border-top:2px solid #1b1f1e':'')+(on(big,k)?';font-size:13.3px':'')+(on(dim,k)?';color:#8a8a8a':';color:#000')+'">'+e(typeof v==='number'?((p.money||[]).includes(k+1)?v.toFixed(2):String(v)):v)+'</td>').join('')+'</tr>';}).join('')+'</tbody></table></div>').join('')+
   (d.position?'<h3>Cash position</h3><div class="cash-position">'+d.position.filter(p=>typeof p[2]==='number').map(p=>'<div><span>'+e(p[0])+'</span><strong>'+p[2].toFixed(2)+'</strong></div>').join('')+'</div>':'');
 }
 function download(s,mime,ext){const u=URL.createObjectURL(new Blob([s],{type:mime})),a=document.createElement('a');a.href=u;a.download='Mahrjan-'+type.replaceAll(' ','-')+'-'+day+'.'+ext;a.click();setTimeout(()=>URL.revokeObjectURL(u),1000);}
 function draw(){
   const h=getHost();if(!day)day=localToday();
   h.innerHTML='<div class="report-type-tabs">'+Object.keys(labels).map(n=>'<button data-type="'+n+'" class="'+(type===n?'primary':'')+'">'+labels[n]+'</button>').join('')+'</div><div class="panel report-filters"'+((type==='CASH SHEET'||type==='MONTHLY CLOSING'||type==='PICKING SHEET')?' style="grid-template-columns:minmax(0,200px) auto"':'')+'>'+((type==='CASH SHEET'||type==='MONTHLY CLOSING'||type==='PICKING SHEET')?'':'<label>Salesman<select id="reportSalesman"><option value="">Select salesman</option>'+MJ_SHEET_CTX.roster().map(r=>'<option '+(r.name===man?'selected':'')+' value="'+e(r.name)+'">'+e(r.name)+'</option>').join('')+'</select></label>')+'<label>'+(type==='PICKING SHEET'?'Required for':'Date')+'<input id="reportDate" type="date" value="'+e(day)+'"'+(type==='PICKING SHEET'?'':' max="'+localToday()+'"')+'></label><button id="showMobileReport" class="primary" '+(busy||!day||(!(type==='CASH SHEET'||type==='MONTHLY CLOSING'||type==='PICKING SHEET')&&!man)?'disabled':'')+'>'+(busy?'Loading…':'Show Report')+'</button></div><div id="mobileReportResult" class="panel">'+(busy?'<p class="muted">Loading…</p>':selected?'<div class="section-head"><h2>'+e(labels[selected.name])+' · '+e(day)+(!(type==='CASH SHEET'||type==='MONTHLY CLOSING'||type==='PICKING SHEET')?' · '+e(man):'')+'</h2>'+(selected.stale?'<div style="font-size:12.5px;width:100%;order:3;color:#8a6d00;font-weight:600">Updating… showing the copy prepared at '+e(selected.ready||'')+'. Print and downloads unlock when the fresh copy is ready.</div>':selected.ready?'<div class="muted" style="font-size:12.5px;display:flex;align-items:center;gap:8px;flex-wrap:wrap;width:100%;order:3">Prepared at '+e(selected.ready)+' '+e(selected.readyWhy||'')+''+''+'</div>':'')+'<div class="saved-actions">'+(()=>{const dz=selected.stale?' disabled style="opacity:.45;cursor:not-allowed"':'';return '<button id="mobileCsv"'+dz+'>CSV</button><button id="mobileExcel"'+dz+'>Excel</button><button id="mobilePdf"'+dz+'>Save PDF</button><button id="mobilePrint" class="primary"'+dz+'>Print A4</button>';})()+'</div></div>'+table(selected):'<p>'+((type==='CASH SHEET'||type==='MONTHLY CLOSING'||type==='PICKING SHEET')?'Choose a date':'Choose a salesman and date')+', then click Show Report.</p>')+'</div>';
   h.querySelectorAll('[data-type]').forEach(b=>b.onclick=()=>{type=b.dataset.type;if(type==='PICKING SHEET'){const t=new Date(Date.now()+86400000);if(t.getDay()===0)t.setDate(t.getDate()+1);day=new Date(t.getTime()-t.getTimezoneOffset()*60000).toISOString().slice(0,10);}else if(day>localToday())day=localToday();clear();});
   if(h.querySelector('#reportSalesman'))h.querySelector('#reportSalesman').onchange=ev=>{man=ev.target.value;clear();};h.querySelector('#reportDate').onchange=ev=>{day=ev.target.value;clear();};
   const runRep=async fresh=>{const id=++ticket;busy=true;selected=null;draw();try {const d=await MJ_SHEET_CTX.report(type,day,(type==='CASH SHEET'||type==='MONTHLY CLOSING'||type==='PICKING SHEET')?'':man,fresh);if(id!==ticket)return;if(!d.ok)throw new Error(d.error||'Could not build report.');selected=d;busy=false;draw();
     // Stored copy is out of date: show it at once (print greyed out), build the fresh one in the background and swap it in.
     if(d.stale){const f=await MJ_SHEET_CTX.report(type,day,(type==='CASH SHEET'||type==='MONTHLY CLOSING'||type==='PICKING SHEET')?'':man,true);if(id!==ticket)return;if(f&&f.ok){selected=f;draw();}}}catch(err){if(id!==ticket)return;busy=false;draw();h.querySelector('#mobileReportResult').textContent=err.message||'Could not load report.';}};
   h.querySelector('#showMobileReport').onclick=()=>runRep(false);{const fb=h.querySelector('#mobileFresh');if(fb)fb.onclick=()=>runRep(true);}
   if(selected){
     h.querySelector('#mobilePrint').onclick=()=>MobileReport.openPrint_((selected.parts||[selected]).map(p=>MobileReport.reportPage_(p)),MobileReport.pdfName_(selected));
     // Save PDF: same A4 pages; the print window carries the file name, so "Save as PDF" suggests SALESMAN_REPORT_DATE.
     const pdfB=h.querySelector('#mobilePdf');if(pdfB)pdfB.onclick=()=>{const n=MobileReport.pdfName_(selected);MobileReport.openPrint_((selected.parts||[selected]).map(p=>MobileReport.reportPage_(p)),n);const st=h.querySelector('.saved-actions');if(st&&!h.querySelector('#pdfHint')){const s=document.createElement('div');s.id='pdfHint';s.className='muted';s.style.cssText='font-size:12px;margin-top:6px;width:100%';s.textContent='In the print window choose Destination: “Save as PDF” — file name: '+n+'.pdf';st.after(s);}};
     h.querySelector('#mobileCsv').onclick=()=>{const q=v=>'"'+String(typeof v==='string'&&/^\s*[=+@-]/.test(v)?"'"+v:v??'').replaceAll('"','""')+'"';download('\ufeff'+selected.rows.map(r=>r.map(q).join(',')).join('\r\n'),'text/csv;charset=utf-8','csv');};
     h.querySelector('#mobileExcel').onclick=()=>download(selected.name==='CASH SHEET'&&selected.cash?mahrjanXlsx(cashXlsx_(selected)):mahrjanXlsx((selected.parts||[selected]).map(p=>({name:p.name||labels[selected.name]||'Report',rows:p.rows,bold:[...new Set([...(p.head||[]),...(p.bold||[])])]})).concat(selected.position?[{name:'Cash position',rows:[['Item','Amount']].concat(selected.position.filter(p=>typeof p[2]==='number').map(p=>[p[0],p[2]])),bold:[0]}]:[])),XLSX_MIME,'xlsx');
   }
 }
 function clear(){ticket++;busy=false;selected=null;draw();}
 window.MahrjanReports={reset(){host=null;ticket++;busy=false;selected=null;},render(view){getHost().hidden=false;if(routes[view])type=routes[view];clear();},hide(){ticket++;busy=false;if(host)host.hidden=true;}};
})();
