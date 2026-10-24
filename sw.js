const C='mandai-v4';
self.addEventListener('install',e=>{self.skipWaiting();e.waitUntil(caches.open(C).then(c=>c.addAll(['./','index.html','supabase.js','manifest.webmanifest','icon-192.png','icon-512.png'])).catch(()=>{}))});
self.addEventListener('activate',e=>{e.waitUntil(caches.keys().then(k=>Promise.all(k.filter(x=>x!==C).map(x=>caches.delete(x)))).then(()=>self.clients.claim()))});
self.addEventListener('fetch',e=>{const r=e.request,u0=new URL(r.url);if(r.method!=='GET'||u0.origin!==location.origin||r.cache==='no-store'||u0.searchParams.has('v'))return;
  e.respondWith(caches.open(C).then(async c=>{
    const u=new URL(r.url),key=r.mode==='navigate'?new Request(u.origin+u.pathname):r;const hit=await c.match(key);
    const net=fetch(r).then(res=>{
      if(res&&res.ok){
        c.put(key,res.clone())}
      return res}).catch(()=>hit);
    if(hit){e.waitUntil(net.catch(()=>{}));return hit}
    return net}))});

self.addEventListener('push',e=>{
  let d={};try{d=e.data?e.data.json():{}}catch(_){d={body:e.data?e.data.text():''}}
  e.waitUntil(self.clients.matchAll({type:'window',includeUncontrolled:true}).then(cs=>{
    if(cs.some(c=>c.visibilityState==='visible'&&c.focused))return;
    return self.registration.showNotification(d.title||'Bippy',{body:d.body||'Nova mensagem',icon:'icon-192.png',badge:'icon-192.png',tag:'c-'+(d.cid||'x'),renotify:true,data:{cid:d.cid||''}})}))});
self.addEventListener('notificationclick',e=>{
  e.notification.close();const cid=(e.notification.data&&e.notification.data.cid)||'';
  if(e.action==='snooze'){const lk=(e.notification.data&&e.notification.data.lk)||'';e.waitUntil(self.clients.matchAll({type:'window',includeUncontrolled:true}).then(cs=>{cs.forEach(c=>{try{c.postMessage({t:'snooze',lk})}catch(_){}})}));return}
  e.waitUntil(self.clients.matchAll({type:'window',includeUncontrolled:true}).then(cs=>{
    const c=cs[0];if(c){try{c.postMessage({t:'open',cid})}catch(_){}return c.focus()}
    return self.clients.openWindow('./'+(cid?'?c='+encodeURIComponent(cid):''))}))});
