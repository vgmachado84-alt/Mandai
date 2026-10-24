const C='mandai-v2';
self.addEventListener('install',e=>{self.skipWaiting();e.waitUntil(caches.open(C).then(c=>c.addAll(['./','index.html','manifest.webmanifest','icon-192.png','icon-512.png'])).catch(()=>{}))});
self.addEventListener('activate',e=>{e.waitUntil(caches.keys().then(k=>Promise.all(k.filter(x=>x!==C).map(x=>caches.delete(x)))).then(()=>self.clients.claim()))});
self.addEventListener('fetch',e=>{if(e.request.method!=='GET'||new URL(e.request.url).origin!==location.origin)return;e.respondWith(fetch(e.request).then(r=>{const c=r.clone();caches.open(C).then(x=>x.put(e.request,c));return r}).catch(()=>caches.match(e.request)))});

self.addEventListener('push',e=>{
  let d={};try{d=e.data?e.data.json():{}}catch(_){d={body:e.data?e.data.text():''}}
  e.waitUntil(self.clients.matchAll({type:'window',includeUncontrolled:true}).then(cs=>{
    if(cs.some(c=>c.visibilityState==='visible'&&c.focused))return;
    return self.registration.showNotification(d.title||'Bippy',{body:d.body||'Nova mensagem',icon:'icon-192.png',badge:'icon-192.png',tag:'c-'+(d.cid||'x'),renotify:true,data:{cid:d.cid||''}})}))});
self.addEventListener('notificationclick',e=>{
  e.notification.close();const cid=(e.notification.data&&e.notification.data.cid)||'';
  e.waitUntil(self.clients.matchAll({type:'window',includeUncontrolled:true}).then(cs=>{
    const c=cs[0];if(c){try{c.postMessage({t:'open',cid})}catch(_){}return c.focus()}
    return self.clients.openWindow('./'+(cid?'?c='+encodeURIComponent(cid):''))}))});
