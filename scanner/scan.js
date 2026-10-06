/* Börsensystem nach SK: Hintergrund-Scanner.
   Läuft automatisch in GitHub Actions, öffnet die App unsichtbar, prüft alle Coins auf SK-Signale
   und schickt neue Signale per ntfy aufs Handy. Es wird dieselbe SK-Logik wie in der App benutzt. */
const {chromium}=require('playwright');
const fs=require('fs'),path=require('path');
const ROOT=path.resolve(__dirname,'..');
const STATE=path.join(__dirname,'state.json');
const TOPIC=(process.env.NTFY_TOPIC||'').trim();
const TFS=(process.env.SK_TFS||'1h,4h,1d').split(',').map(s=>s.trim()).filter(Boolean);
const APP=process.env.SK_APP_URL||('file://'+path.join(ROOT,'docs','index.html'));
const SITE='https://marcbohn1312.github.io/i/';
const st=(()=>{try{return JSON.parse(fs.readFileSync(STATE,'utf8'))}catch(e){return{seen:[],started:0}}})();

async function ntfy(title,body,prio,tags){
  if(!TOPIC)return;
  const r=await fetch('https://ntfy.sh/'+encodeURIComponent(TOPIC),{method:'POST',body,headers:{Title:title,Priority:prio||'default',Tags:tags||'chart_with_upwards_trend',Click:SITE}});
  console.log('ntfy',r.status,title);
}
(async()=>{
  if(!TOPIC)console.log('Hinweis: NTFY_TOPIC ist nicht gesetzt, es werden keine Nachrichten gesendet.');
  const b=await chromium.launch(process.env.SK_CHROMIUM?{executablePath:process.env.SK_CHROMIUM}:{});
  const p=await (await b.newContext({viewport:{width:1200,height:900}})).newPage();
  await p.addInitScript(()=>{window.WebSocket=function(){throw new Error('no ws')};try{localStorage.setItem('sk_intro','1')}catch(e){}});
  p.on('pageerror',e=>console.log('Seitenfehler:',e.message));
  await p.goto(APP);await p.waitForTimeout(1500);
  const sigs=await p.evaluate(async tfs=>{
    const out=[];
    for(const tf of tfs){
      for(const c of COINS){
        try{
          const r=await fetchCandles(c,tf);
          board[c]={candles:r.candles,live:true,src:r.src,ts:Date.now(),err:''};
          const s=analyse(r.candles,c+'|'+tf);
          for(const x of [s,s&&s.alt]){
            if(!x||!x.seq||x.dir==='none')continue;
            const key=[c,tf,x.dir,x.state==='counter'?'g':'h',x.seq.O.p,x.seq.A.p].join('|');
            const kind=x.state==='counter'?'Gegentrade':x.seq.kind==='neu'?'Haupt':x.seq.kind.indexOf('Wieder')===0?'Wiedereinstieg':x.seq.kind.indexOf('verl')===0?'Verlängert':'Manuell';
            const e={coin:c,tf,dir:x.dir,kind,entry:x.lv.entry,sl:x.lv.sl,tp1:x.lv.tp1,crv:x.crv};
            let ed=null;try{ed=await edgeCheck(c,x,e)}catch(err){}
            out.push({key,e,ed,fmt:{entry:fmt(e.entry),sl:fmt(e.sl),tp1:fmt(e.tp1)}});
          }
        }catch(err){console.log('Fehler bei',c,tf,String(err&&err.code||err))}
      }
    }
    return out;
  },TFS);
  await b.close();
  console.log('Aktive Signale gefunden:',sigs.length);
  const first=!st.started;let sent=0;
  for(const s of sigs){
    if(st.seen.includes(s.key))continue;
    if(!first&&sent>=6)continue;           /* nicht mehr als 6 pro Lauf, der Rest kommt beim nächsten Lauf */
    st.seen.push(s.key);
    if(first)continue;                     /* erster Lauf: nur merken, nicht alle alten Signale melden */
    const L=s.e.dir==='long',ed=s.ed&&s.ed.n;
    const title=(ed?'★ '+(ed>4?'Fünffacher':ed>3?'Vierfacher':ed>2?'Dreifacher':'Doppelter')+' Vorteil: ':'')+(L?'KAUFEN ':'VERKAUFEN ')+s.e.coin+' ('+s.e.tf+')';
    const body=`${s.e.coin}/USDT ${s.e.tf} · ${s.e.kind}\nEinstieg ${s.fmt.entry}\nVerlustgrenze ${s.fmt.sl}\nGewinnziel ${s.fmt.tp1}\nChance zu Risiko ${(+s.e.crv).toFixed(1)} zu 1`+(ed?'\n★ '+s.ed.f.join('\n★ '):'');
    await ntfy(title,body,'urgent',L?'chart_with_upwards_trend':'chart_with_downwards_trend');sent++;
  }
  if(first){st.started=Date.now();await ntfy('Börsensystem nach SK: Hintergrund-Alarm aktiv','Der Scanner läuft jetzt alle paar Minuten in deinem GitHub und meldet neue SK-Signale ('+TFS.join(', ')+').','default','white_check_mark')}
  st.seen=st.seen.slice(-400);
  fs.writeFileSync(STATE,JSON.stringify(st));
  console.log('Fertig. Neu gemeldet:',sent);
})().catch(e=>{console.error(e);process.exit(1)});
