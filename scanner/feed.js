/* Börsensystem nach SK: Daten-Sammler.
   Läuft automatisch in GitHub Actions. Holt den Wirtschaftskalender und die Börsen-Indizes und sammelt rund
   8 Minuten lang echte Liquidationen (Binance, Bybit, OKX). Das Ergebnis wird als feed.json und liq.json im Branch
   sk-data abgelegt, die App liest es von dort. */
const fs=require('fs'),path=require('path');
const WebSocket=require('ws');
const OUT=process.env.OUT_DIR||path.resolve(__dirname,'..','data');
const DUR=(+process.env.COLLECT_SEC||480)*1000;
const COINS=['BTC','ETH','SOL','BNB','XRP','ADA','DOGE','AVAX','LINK','DOT','LTC','TON'];
const FF=process.env.FF_URL||'https://nfs.faireconomy.media/ff_calendar_thisweek.json';
const STOOQ=process.env.STOOQ_URL||'https://stooq.com/q/l/?s=^spx,^ndx,^dax,^ukx,^nkx,^hsi&f=sd2t2ohlcv&h&e=csv';
const rd=(f,d)=>{try{return JSON.parse(fs.readFileSync(path.join(OUT,f),'utf8'))}catch(e){return d}};
const get=async(u,t)=>{const r=await fetch(u,{headers:{'User-Agent':'Mozilla/5.0 Boersensystem-SK'},signal:AbortSignal.timeout(20000)});if(!r.ok)throw new Error(u+' '+r.status);return t?r.text():r.json()};
fs.mkdirSync(OUT,{recursive:true});

(async()=>{
  const old=rd('feed.json',{}),feed={ts:Date.now(),cal:old.cal||[],calTs:old.calTs||0,calSrc:old.calSrc||'',markets:old.markets||[]};
  /* Kalender */
  try{const j=await get(FF);if(Array.isArray(j)&&j.length>5){feed.cal=j;feed.calTs=Date.now();feed.calSrc='Forex Factory'}}catch(e){console.log('Kalender:',e.message)}
  /* Indizes */
  try{const csv=await get(STOOQ,1),nm={'^SPX':'S&P 500','^NDX':'Nasdaq 100','^DAX':'DAX','^UKX':'FTSE 100','^NKX':'Nikkei 225','^HSI':'Hang Seng'},m=[];
    csv.trim().split(/\r?\n/).slice(1).forEach(l=>{const c=l.split(',');const n=nm[(c[0]||'').toUpperCase()],o=+c[3],cl=+c[6];if(n&&o>0&&cl>0)m.push({n,v:cl,p:(cl/o-1)*100})});
    if(m.length)feed.markets=m}catch(e){console.log('Indizes:',e.message)}
  fs.writeFileSync(path.join(OUT,'feed.json'),JSON.stringify(feed));
  console.log('Kalender:',feed.cal.length,'Termine, Indizes:',feed.markets.length);

  /* Liquidationen sammeln */
  const liq=rd('liq.json',{b:{},start:Date.now(),src:{}});
  const lim=Date.now()-864e5;for(const k in liq.b)if(+k.split('|')[0]+3e5<lim)delete liq.b[k];
  if(!liq.start)liq.start=Date.now();
  const add=(coin,long,usd)=>{if(!(usd>0))return;const c=COINS.includes(coin)?coin:'Andere',bk=Math.floor(Date.now()/3e5)*3e5,k=bk+'|'+c;const e=liq.b[k]||(liq.b[k]=[0,0]);e[long?0:1]+=usd};
  const st={Binance:0,Bybit:0,OKX:0},cnt={Binance:0,Bybit:0,OKX:0};
  const strip=s=>String(s).replace(/(USDT|USDC|BUSD|USD)$/,'');
  const open=(name,url,onOpen,onMsg)=>{
    let ws;try{ws=new WebSocket(url)}catch(e){return}
    ws.on('open',()=>{st[name]=1;try{onOpen&&onOpen(ws)}catch(e){}});
    ws.on('message',m=>{try{onMsg(JSON.parse(String(m)))}catch(e){}});
    ws.on('error',e=>{if(!st[name])st[name]=-1;console.log(name,'Fehler:',e.message)});
    ws.on('close',()=>{});
    return ws};
  const socks=[];
  socks.push(open('Binance','wss://fstream.binance.com/ws/!forceOrder@arr',null,j=>{const o=j&&j.o;if(o&&o.s){add(strip(o.s),o.S==='SELL',+o.q*+(o.ap||o.p));cnt.Binance++}}));
  socks.push(open('Bybit','wss://stream.bybit.com/v5/public/linear',ws=>{ws.send(JSON.stringify({op:'subscribe',args:COINS.map(c=>'allLiquidation.'+c+'USDT')}));setInterval(()=>{try{ws.send('{"op":"ping"}')}catch(e){}},20000).unref()},
    j=>{if(j&&/^allLiquidation/.test(j.topic||'')&&Array.isArray(j.data))j.data.forEach(x=>{add(strip(x.s),x.S==='Buy',+x.v*+x.p);cnt.Bybit++})}));
  let ct={};
  try{const j=await get('https://www.okx.com/api/v5/public/instruments?instType=SWAP');(j.data||[]).forEach(i=>{ct[i.instId]={v:+i.ctVal*(+i.ctMult||1),usd:i.ctValCcy==='USD'}})}catch(e){console.log('OKX Instrumente:',e.message)}
  socks.push(open('OKX','wss://ws.okx.com:8443/ws/v5/public',ws=>{ws.send(JSON.stringify({op:'subscribe',args:[{channel:'liquidation-orders',instType:'SWAP'}]}));setInterval(()=>{try{ws.send('ping')}catch(e){}},20000).unref()},
    j=>{(j.data||[]).forEach(x=>(x.details||[]).forEach(d=>{const c=ct[x.instId];if(!c)return;const px=+d.bkPx,usd=c.usd?+d.sz*c.v:+d.sz*c.v*px;add(String(x.instId).split('-')[0],d.posSide==='long'||(d.posSide==='net'&&d.side==='sell'),usd);cnt.OKX++}))}));
  await new Promise(r=>setTimeout(r,DUR));
  socks.forEach(s=>{try{s&&s.terminate()}catch(e){}});
  liq.ts=Date.now();liq.src=st;liq.n=cnt;
  fs.writeFileSync(path.join(OUT,'liq.json'),JSON.stringify(liq));
  console.log('Liquidationen gesammelt:',JSON.stringify(cnt),'Verbindungen:',JSON.stringify(st),'Eimer:',Object.keys(liq.b).length);
  process.exit(0);
})().catch(e=>{console.error(e);process.exit(1)});
