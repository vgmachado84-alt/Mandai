#!/bin/bash
# Ajustes extras do app Android do Bippy (rodam depois do "cap sync")
set -e
R=android/app/src/main/res
# 1) icone do Bippy no lugar do X azul padrao
python3 -m pip install --quiet --break-system-packages pillow || python3 -m pip install --quiet pillow
python3 - <<'PY'
from PIL import Image
import os
R='android/app/src/main/res'
im=Image.open('icon-512.png').convert('RGBA')
for d,s in (('mdpi',48),('hdpi',72),('xhdpi',96),('xxhdpi',144),('xxxhdpi',192)):
    p=f'{R}/mipmap-{d}'
    os.makedirs(p,exist_ok=True)
    r=im.resize((s,s),Image.LANCZOS)
    r.save(f'{p}/ic_launcher.png'); r.save(f'{p}/ic_launcher_round.png'); r.save(f'{p}/ic_launcher_foreground.png')
PY
rm -f $R/mipmap-anydpi-v26/ic_launcher.xml $R/mipmap-anydpi-v26/ic_launcher_round.xml
echo "icone trocado"

# 2) barras do sistema (de cima e de baixo) na cor do app, em vez de pretas
python3 - <<'PY'
import re,os
R='android/app/src/main/res'
f=f'{R}/values/styles.xml'
s=open(f,encoding='utf-8').read()
add_day='''
        <item name="android:statusBarColor">#FFFFFF</item>
        <item name="android:navigationBarColor">#FFFFFF</item>
        <item name="android:windowLightStatusBar">true</item>
        <item name="android:windowLightNavigationBar">true</item>
'''
m=re.search(r'(<style name="AppTheme\.NoActionBar"[^>]*>)(.*?)(</style>)',s,re.S)
if m:
    s=s[:m.end(2)]+add_day+s[m.end(2):]
    open(f,'w',encoding='utf-8').write(s)
    print('barras (dia) ok')
else:
    print('estilo nao encontrado')
os.makedirs(f'{R}/values-night',exist_ok=True)
open(f'{R}/values-night/styles.xml','w',encoding='utf-8').write('''<?xml version="1.0" encoding="utf-8"?>
<resources>
    <style name="AppTheme.NoActionBar" parent="Theme.AppCompat.DayNight.NoActionBar">
        <item name="windowActionBar">false</item>
        <item name="windowNoTitle">true</item>
        <item name="android:background">@null</item>
        <item name="android:statusBarColor">#0A0E18</item>
        <item name="android:navigationBarColor">#0A0E18</item>
        <item name="android:windowLightStatusBar">false</item>
        <item name="android:windowLightNavigationBar">false</item>
    </style>
</resources>
''')
print('barras (noite) ok')
PY

# 3) barras do sistema acompanham a cor do app (ponte nativa)
D=$(dirname $(find android/app/src/main/java -name MainActivity.java | head -1))
PK=$(grep -h "^package" $D/MainActivity.java | sed 's/package \(.*\);/\1/')
cat > $D/MainActivity.java <<JAVA
package $PK;

import android.graphics.Color;
import android.os.Bundle;
import android.webkit.JavascriptInterface;
import androidx.core.view.WindowCompat;
import androidx.core.view.WindowInsetsControllerCompat;
import com.getcapacitor.BridgeActivity;

public class MainActivity extends BridgeActivity {
    public class Bars {
        @JavascriptInterface
        public void set(final String top, final boolean topLight, final String bottom, final boolean bottomLight) {
            runOnUiThread(new Runnable() {
                public void run() {
                    try {
                        getWindow().setStatusBarColor(Color.parseColor(top));
                        getWindow().setNavigationBarColor(Color.parseColor(bottom));
                        WindowInsetsControllerCompat w = WindowCompat.getInsetsController(getWindow(), getWindow().getDecorView());
                        w.setAppearanceLightStatusBars(topLight);
                        w.setAppearanceLightNavigationBars(bottomLight);
                    } catch (Exception e) {}
                }
            });
        }
    }
    @Override
    public void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        getBridge().getWebView().addJavascriptInterface(new Bars(), "BippyBars");
    }
}
JAVA
echo "barras nativas ok"

# 4) aparecer na lista "Compartilhar" do Android (texto e links)
python3 - <<'PY'
import re,glob
f='android/app/src/main/AndroidManifest.xml'
s=open(f,encoding='utf-8').read()
filt='''
            <intent-filter>
                <action android:name="android.intent.action.SEND" />
                <category android:name="android.intent.category.DEFAULT" />
                <data android:mimeType="text/plain" />
            </intent-filter>
'''
filt2='''
            <intent-filter>
                <action android:name="android.intent.action.SEND" />
                <category android:name="android.intent.category.DEFAULT" />
                <data android:mimeType="*/*" />
            </intent-filter>
            <intent-filter>
                <action android:name="android.intent.action.SEND_MULTIPLE" />
                <category android:name="android.intent.category.DEFAULT" />
                <data android:mimeType="*/*" />
            </intent-filter>
'''
if 'android.intent.action.SEND' not in s:
    i=s.index('</activity>')
    s=s[:i]+filt+filt2+'        '+s[i:]
    open(f,'w',encoding='utf-8').write(s)
    print('share ok')
j=glob.glob('android/app/src/main/java/**/MainActivity.java',recursive=True)[0]
t=open(j,encoding='utf-8').read()
t=t.replace('public class MainActivity extends BridgeActivity {','''public class MainActivity extends BridgeActivity {
    private String pend = "";
    private String pcid = "";
    private java.util.ArrayList<String[]> inbox = new java.util.ArrayList<String[]>();
    private void copyIn(android.net.Uri u, String mime) {
        try {
            String name = null;
            android.database.Cursor c = getContentResolver().query(u, null, null, null, null);
            if (c != null) {
                if (c.moveToFirst()) {
                    int ix = c.getColumnIndex(android.provider.OpenableColumns.DISPLAY_NAME);
                    if (ix >= 0) name = c.getString(ix);
                }
                c.close();
            }
            if (name == null || name.length() == 0) name = "arquivo";
            java.io.File dir = new java.io.File(getCacheDir(), "inbox");
            dir.mkdirs();
            java.io.File f = new java.io.File(dir, System.currentTimeMillis() + "_" + name.replaceAll("[^A-Za-z0-9._-]", "_"));
            java.io.InputStream in = getContentResolver().openInputStream(u);
            java.io.FileOutputStream out = new java.io.FileOutputStream(f);
            byte[] b = new byte[65536];
            int n;
            long tot = 0;
            while ((n = in.read(b)) > 0) {
                out.write(b, 0, n);
                tot += n;
                if (tot > 25L * 1024 * 1024) break;
            }
            in.close();
            out.close();
            String mm = mime != null ? mime : getContentResolver().getType(u);
            if (mm == null) mm = "application/octet-stream";
            inbox.add(new String[]{f.getAbsolutePath(), name, mm});
        } catch (Exception e) {}
    }
    private void grab(android.content.Intent i) {
        try {
            if (i == null) return;
            try { String pc = i.getStringExtra("cid"); if (pc != null && pc.length() > 0) pcid = pc; } catch (Exception e) {}
            String act = i.getAction();
            if (android.content.Intent.ACTION_SEND.equals(act)) {
                String x = i.getStringExtra(android.content.Intent.EXTRA_TEXT);
                if (x != null && x.length() > 0) pend = x;
                android.net.Uri u = (android.net.Uri) i.getParcelableExtra(android.content.Intent.EXTRA_STREAM);
                if (u != null) copyIn(u, i.getType());
            } else if (android.content.Intent.ACTION_SEND_MULTIPLE.equals(act)) {
                java.util.ArrayList<android.net.Uri> l = i.getParcelableArrayListExtra(android.content.Intent.EXTRA_STREAM);
                if (l != null) {
                    int k = 0;
                    for (android.net.Uri u : l) {
                        if (k++ >= 5) break;
                        copyIn(u, null);
                    }
                }
            }
        } catch (Exception e) {}
    }
    @Override
    protected void onNewIntent(android.content.Intent i) {
        super.onNewIntent(i);
        setIntent(i);
        grab(i);
        try {
            getBridge().getWebView().postDelayed(new Runnable() {
                public void run() {
                    try { getBridge().getWebView().evaluateJavascript("window.bippyChk&&window.bippyChk()", null); } catch (Exception e) {}
                }
            }, 350);
        } catch (Exception e) {}
    }
''',1)
t=t.replace('        public void set(final String top','''        public String shared() { String x = pend; pend = ""; return x; }

        @JavascriptInterface
        public String pushCid() { String x = pcid; pcid = ""; return x; }

        @JavascriptInterface
        public void openUrl(final String u) {
            runOnUiThread(new Runnable() {
                public void run() {
                    try { startActivity(new android.content.Intent(android.content.Intent.ACTION_VIEW, android.net.Uri.parse(u))); } catch (Exception e) {}
                }
            });
        }

        @JavascriptInterface
        public String sharedFile() {
            try {
                if (inbox.size() == 0) return "";
                String[] it = inbox.remove(0);
                java.io.File f = new java.io.File(it[0]);
                org.json.JSONObject o = new org.json.JSONObject();
                o.put("name", it[1]);
                o.put("mime", it[2]);
                o.put("path", f.getAbsolutePath());
                if (f.length() <= 1500000L) {
                    java.io.FileInputStream in = new java.io.FileInputStream(f);
                    java.io.ByteArrayOutputStream bo = new java.io.ByteArrayOutputStream();
                    byte[] b = new byte[65536];
                    int n;
                    while ((n = in.read(b)) > 0) bo.write(b, 0, n);
                    in.close();
                    o.put("b64", android.util.Base64.encodeToString(bo.toByteArray(), android.util.Base64.NO_WRAP));
                }
                return o.toString();
            } catch (Exception e) {
                return "";
            }
        }

        @JavascriptInterface
        public void openFile(String b64, String mime, String name) {
            try {
                byte[] d = android.util.Base64.decode(b64, android.util.Base64.DEFAULT);
                java.io.File dir = new java.io.File(getCacheDir(), "shared");
                dir.mkdirs();
                java.io.File f = new java.io.File(dir, name);
                java.io.FileOutputStream o = new java.io.FileOutputStream(f);
                o.write(d);
                o.close();
                android.net.Uri u = androidx.core.content.FileProvider.getUriForFile(MainActivity.this, getPackageName() + ".fileprovider", f);
                final android.content.Intent i = new android.content.Intent(android.content.Intent.ACTION_VIEW);
                i.setDataAndType(u, mime);
                i.addFlags(android.content.Intent.FLAG_GRANT_READ_URI_PERMISSION);
                runOnUiThread(new Runnable() {
                    public void run() {
                        try { startActivity(android.content.Intent.createChooser(i, "Abrir com")); } catch (Exception e) { android.widget.Toast.makeText(MainActivity.this, "Nenhum app para abrir este arquivo", android.widget.Toast.LENGTH_LONG).show(); }
                    }
                });
            } catch (Exception e) {}
        }

        @JavascriptInterface
        public void shareFile(String b64, String mime, String name, String text) {
            try {
                final android.content.Intent i = new android.content.Intent(android.content.Intent.ACTION_SEND);
                if (b64 != null && b64.length() > 0) {
                    byte[] d = android.util.Base64.decode(b64, android.util.Base64.DEFAULT);
                    java.io.File dir = new java.io.File(getCacheDir(), "shared");
                    dir.mkdirs();
                    java.io.File f = new java.io.File(dir, name);
                    java.io.FileOutputStream o = new java.io.FileOutputStream(f);
                    o.write(d);
                    o.close();
                    android.net.Uri u = androidx.core.content.FileProvider.getUriForFile(MainActivity.this, getPackageName() + ".fileprovider", f);
                    i.setType(mime);
                    i.putExtra(android.content.Intent.EXTRA_STREAM, u);
                    i.addFlags(android.content.Intent.FLAG_GRANT_READ_URI_PERMISSION);
                } else {
                    i.setType("text/plain");
                }
                if (text != null && text.length() > 0) i.putExtra(android.content.Intent.EXTRA_TEXT, text);
                runOnUiThread(new Runnable() {
                    public void run() {
                        try { startActivity(android.content.Intent.createChooser(i, "Compartilhar")); } catch (Exception e) {}
                    }
                });
            } catch (Exception e) {}
        }

        @JavascriptInterface
        public void set(final String top''',1)
t=t.replace('super.onCreate(savedInstanceState);','super.onCreate(savedInstanceState);\n        grab(getIntent());',1)
t=t.replace('        grab(getIntent());','''        grab(getIntent());
        getOnBackPressedDispatcher().addCallback(this, new androidx.activity.OnBackPressedCallback(true) {
            @Override
            public void handleOnBackPressed() {
                try {
                    getBridge().getWebView().evaluateJavascript("(function(){try{return window.__bBack?(window.__bBack()?1:0):0}catch(e){return 0}})()", new android.webkit.ValueCallback<String>() {
                        public void onReceiveValue(String v) {
                            if (!"1".equals(v)) moveTaskToBack(true);
                        }
                    });
                } catch (Exception e) {
                    moveTaskToBack(true);
                }
            }
        });''',1)
open(j,'w',encoding='utf-8').write(t)
print('java ok')
PY

# 5) pasta de cache liberada para compartilhar arquivos (FileProvider)
mkdir -p android/app/src/main/res/xml
cat > android/app/src/main/res/xml/file_paths.xml <<'XML'
<?xml version="1.0" encoding="utf-8"?>
<paths xmlns:android="http://schemas.android.com/apk/res/android">
    <external-path name="my_images" path="." />
    <cache-path name="my_cache_images" path="." />
</paths>
XML
echo "file_paths ok"

# Notificacoes com o app fechado (Firebase / FCM)
if [ -f google-services.json ]; then
  npm i @capacitor/push-notifications@6 >/dev/null 2>&1 && echo "plugin push ok" || echo "ERRO: plugin push nao instalou"
  npx cap sync android >/dev/null 2>&1 || true
  cp google-services.json android/app/google-services.json
  grep -q "com.google.gms:google-services" android/build.gradle || sed -i "0,/dependencies {/s//dependencies {\n        classpath 'com.google.gms:google-services:4.4.2'/" android/build.gradle
  grep -q "com.google.gms.google-services" android/app/build.gradle || cat >> android/app/build.gradle <<'EOF'

apply plugin: 'com.google.gms.google-services'
EOF
  mkdir -p android/app/src/main/res/drawable-nodpi
  echo "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" | base64 -d > android/app/src/main/res/drawable-nodpi/ic_stat_bippy.png
  grep -q default_notification_icon android/app/src/main/AndroidManifest.xml || sed -i 's#</application>#<meta-data android:name="com.google.firebase.messaging.default_notification_icon" android:resource="@drawable/ic_stat_bippy"/><meta-data android:name="com.google.firebase.messaging.default_notification_color" android:resource="@android:color/holo_purple"/></application>#' android/app/src/main/AndroidManifest.xml
  # --- notificacao nativa com campo "Responder" (so dados vindos do Firebase) ---
  PD=$(dirname $(find android/app/src/main/java -name MainActivity.java | head -1))
  PKG=$(grep -h "^package" $PD/MainActivity.java | sed 's/package \(.*\);/\1/')
  cat > $PD/BippyNotif.java <<'JAVA2'
package PKGNAME;

import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.os.Build;
import androidx.core.app.NotificationCompat;
import androidx.core.app.RemoteInput;
import java.io.OutputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import org.json.JSONArray;
import org.json.JSONObject;

final class BippyNotif {
    static final String CH = "mensagens";
    static android.graphics.Bitmap logoBmp = null;

    static void channel(Context c) {
        try {
            NotificationManager nm = (NotificationManager) c.getSystemService(Context.NOTIFICATION_SERVICE);
            if (Build.VERSION.SDK_INT >= 26 && nm.getNotificationChannel(CH) == null) {
                NotificationChannel ch = new NotificationChannel(CH, "Mensagens", NotificationManager.IMPORTANCE_HIGH);
                ch.setDescription("Novas mensagens");
                nm.createNotificationChannel(ch);
            }
        } catch (Exception e) {}
    }

    static void show(Context c, String cid, String title, String body) {
        show(c, cid, title, body, null);
    }

    static void show(Context c, String cid, String title, String body, String au) {
        try {
            if (cid == null || cid.length() == 0) return;
            if (title == null || title.length() == 0) title = "Bippy";
            if (body == null) body = "";
            body = body.replace("\n", " ");
            SharedPreferences sp = c.getSharedPreferences("bippy_push", 0);
            String old = sp.getString("l_" + cid, "");
            String all = old.length() > 0 ? old + "\n" + body : body;
            String[] parts = all.split("\n");
            if (parts.length > 6) {
                StringBuilder sb = new StringBuilder();
                for (int k = parts.length - 6; k < parts.length; k++) {
                    if (sb.length() > 0) sb.append("\n");
                    sb.append(parts[k]);
                }
                all = sb.toString();
            }
            sp.edit().putString("l_" + cid, all).apply();
            post(c, cid, title, body, all, au, false);
        } catch (Exception e) {}
    }

    static void post(Context c, String cid, String title, String body, String all, String au, boolean quiet) {
        try {
            channel(c);
            NotificationManager nm = (NotificationManager) c.getSystemService(Context.NOTIFICATION_SERVICE);
            int ic = c.getResources().getIdentifier("ic_stat_bippy", "drawable", c.getPackageName());
            if (ic == 0) ic = c.getApplicationInfo().icon;
            int rq = cid.hashCode();

            Intent open = new Intent(c, MainActivity.class);
            open.putExtra("cid", cid);
            open.setFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_CLEAR_TOP | Intent.FLAG_ACTIVITY_SINGLE_TOP);
            PendingIntent pi = PendingIntent.getActivity(c, rq, open, PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);

            Intent rep = new Intent(c, BippyReplyReceiver.class);
            rep.putExtra("cid", cid);
            rep.putExtra("title", title);
            int fl = PendingIntent.FLAG_UPDATE_CURRENT | (Build.VERSION.SDK_INT >= 31 ? PendingIntent.FLAG_MUTABLE : 0);
            PendingIntent rpi = PendingIntent.getBroadcast(c, rq, rep, fl);
            RemoteInput ri = new RemoteInput.Builder("reply").setLabel("Responder").build();
            NotificationCompat.Action act = new NotificationCompat.Action.Builder(ic, "Responder", rpi)
                .addRemoteInput(ri)
                .setAllowGeneratedReplies(true)
                .setSemanticAction(NotificationCompat.Action.SEMANTIC_ACTION_REPLY)
                .setShowsUserInterface(false)
                .build();

            NotificationCompat.Builder b = new NotificationCompat.Builder(c, CH)
                .setSmallIcon(ic)
                .setContentTitle(title)
                .setContentText(body)
                .setStyle(new NotificationCompat.BigTextStyle().bigText(all))
                .setAutoCancel(true)
                .setContentIntent(pi)
                .addAction(act)
                .setPriority(NotificationCompat.PRIORITY_HIGH)
                .setCategory(NotificationCompat.CATEGORY_MESSAGE)
                .setDefaults(NotificationCompat.DEFAULT_ALL)
                .setColor(0xFF0B63FF);
            android.graphics.Bitmap lb = photo(c, cid);
            if (lb != null) b.setLargeIcon(lb);

            boolean aud = au != null && au.length() > 0;
            if (aud) {
                Intent pl = new Intent(c, BippyAudioService.class);
                pl.putExtra("url", au);
                PendingIntent ppi;
                if (Build.VERSION.SDK_INT >= 26) {
                    ppi = PendingIntent.getForegroundService(c, rq + 1, pl, PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);
                } else {
                    ppi = PendingIntent.getService(c, rq + 1, pl, PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);
                }
                b.addAction(new NotificationCompat.Action.Builder(ic, "Ouvir", ppi).build());
            }
            if (!quiet) {
                b.addAction(new NotificationCompat.Action.Builder(ic, "Marcar como lida", actPi(c, cid, title, "read", rq + 2)).build());
                if (!aud) b.addAction(new NotificationCompat.Action.Builder(ic, "Silenciar", actPi(c, cid, title, "mute", rq + 3)).build());
            }
            b.setGroup(GRP);
            b.setGroupAlertBehavior(NotificationCompat.GROUP_ALERT_CHILDREN);
            if (quiet) {
                b.setOnlyAlertOnce(true).setDefaults(0).setTimeoutAfter(6000);
            }
            nm.notify(cid, 1, b.build());
            summary(c, nm, ic);
        } catch (Exception e) {}
    }

    static final String GRP = "bippy_msgs";

    static PendingIntent actPi(Context c, String cid, String title, String act, int rq) {
        Intent it = new Intent(c, BippyReplyReceiver.class);
        it.putExtra("cid", cid);
        it.putExtra("title", title);
        it.putExtra("act", act);
        return PendingIntent.getBroadcast(c, rq, it, PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);
    }

    // resumo do grupo (como no WhatsApp: um cabecalho e cada conversa separada, que sai com um deslize)
    static void summary(Context c, NotificationManager nm, int ic) {
        try {
            Intent open = new Intent(c, MainActivity.class);
            open.setFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_SINGLE_TOP);
            PendingIntent pi = PendingIntent.getActivity(c, 7, open, PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);
            NotificationCompat.Builder g = new NotificationCompat.Builder(c, CH)
                .setSmallIcon(ic)
                .setContentTitle("Bippy")
                .setContentText("Novas mensagens")
                .setGroup(GRP)
                .setGroupSummary(true)
                .setGroupAlertBehavior(NotificationCompat.GROUP_ALERT_CHILDREN)
                .setAutoCancel(true)
                .setContentIntent(pi)
                .setColor(0xFF0B63FF);
            nm.notify("sum", 0, g.build());
        } catch (Exception e) {}
    }

    static boolean temFilhas(NotificationManager nm) {
        try {
            if (Build.VERSION.SDK_INT >= 23) {
                for (android.service.notification.StatusBarNotification n : nm.getActiveNotifications()) {
                    if (n.getId() == 1) return true;
                }
                return false;
            }
        } catch (Exception e) {}
        return true;
    }

    // chamada REST com o login guardado (marcar como lida / silenciar)
    static boolean rest(Context c, String path, String body, String prefer) {
        try {
            SharedPreferences a = c.getSharedPreferences("bippy_auth", 0);
            String url = a.getString("url", "");
            String key = a.getString("key", "");
            String tok = a.getString("tok", "");
            if (url.length() == 0 || tok.length() == 0) return false;
            HttpURLConnection h = (HttpURLConnection) new URL(url + path).openConnection();
            h.setRequestMethod("POST");
            h.setConnectTimeout(10000);
            h.setReadTimeout(15000);
            h.setDoOutput(true);
            h.setRequestProperty("apikey", key);
            h.setRequestProperty("Authorization", "Bearer " + tok);
            h.setRequestProperty("Content-Type", "application/json");
            if (prefer != null) h.setRequestProperty("Prefer", prefer);
            OutputStream o = h.getOutputStream();
            o.write(body.getBytes("UTF-8"));
            o.close();
            int code = h.getResponseCode();
            h.disconnect();
            return code >= 200 && code < 300;
        } catch (Exception e) {
            return false;
        }
    }

    static boolean markRead(Context c, String cid) {
        return rest(c, "/rest/v1/rpc/marcar_lidas", "{\"cid\":\"" + cid + "\"}", null);
    }

    static boolean mute(Context c, String cid, int horas) {
        try {
            String uid = c.getSharedPreferences("bippy_auth", 0).getString("uid", "");
            if (uid.length() == 0) return false;
            java.text.SimpleDateFormat f = new java.text.SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss'Z'", java.util.Locale.US);
            f.setTimeZone(java.util.TimeZone.getTimeZone("UTC"));
            String ate = f.format(new java.util.Date(System.currentTimeMillis() + horas * 3600000L));
            JSONObject j = new JSONObject();
            j.put("usuario_id", uid);
            j.put("conversa_id", cid);
            j.put("ate", ate);
            // avisa o app para refletir o silencio quando abrir
            SharedPreferences sp = c.getSharedPreferences("bippy_push", 0);
            JSONArray q = new JSONArray(sp.getString("q", "[]"));
            JSONObject o = new JSONObject();
            o.put("cid", cid);
            o.put("mute", horas);
            q.put(o);
            sp.edit().putString("q", q.toString()).commit();
            return rest(c, "/rest/v1/conversa_mudo?on_conflict=usuario_id,conversa_id", j.toString(), "resolution=merge-duplicates,return=minimal");
        } catch (Exception e) {
            return false;
        }
    }

    // depois de responder: atualiza a notificacao na hora (acaba o "girando") e ela some sozinha
    static void replied(Context c, String cid, String title, String txt) {
        try {
            c.getSharedPreferences("bippy_push", 0).edit().remove("l_" + cid).apply();
            String t = "Você: " + txt;
            post(c, cid, (title == null || title.length() == 0) ? "Bippy" : title, t, t, null, true);
        } catch (Exception e) {}
    }

    static android.graphics.Bitmap logo(Context c) {
        try {
            if (logoBmp != null) return logoBmp;
            android.graphics.drawable.Drawable d = c.getPackageManager().getApplicationIcon(c.getPackageName());
            int sz = 192;
            android.graphics.Bitmap src = android.graphics.Bitmap.createBitmap(sz, sz, android.graphics.Bitmap.Config.ARGB_8888);
            d.setBounds(0, 0, sz, sz);
            d.draw(new android.graphics.Canvas(src));
            android.graphics.Bitmap out = android.graphics.Bitmap.createBitmap(sz, sz, android.graphics.Bitmap.Config.ARGB_8888);
            android.graphics.Canvas c2 = new android.graphics.Canvas(out);
            android.graphics.Paint p = new android.graphics.Paint(android.graphics.Paint.ANTI_ALIAS_FLAG);
            c2.drawCircle(sz / 2f, sz / 2f, sz / 2f, p);
            p.setXfermode(new android.graphics.PorterDuffXfermode(android.graphics.PorterDuff.Mode.SRC_IN));
            c2.drawBitmap(src, 0, 0, p);
            logoBmp = out;
            return out;
        } catch (Exception e) {
            return null;
        }
    }

    static android.graphics.Bitmap circle(android.graphics.Bitmap src) {
        try {
            int w = src.getWidth(), h = src.getHeight(), m = Math.min(w, h), sz = 192;
            android.graphics.Bitmap sq = android.graphics.Bitmap.createBitmap(src, (w - m) / 2, (h - m) / 2, m, m);
            sq = android.graphics.Bitmap.createScaledBitmap(sq, sz, sz, true);
            android.graphics.Bitmap out = android.graphics.Bitmap.createBitmap(sz, sz, android.graphics.Bitmap.Config.ARGB_8888);
            android.graphics.Canvas cv = new android.graphics.Canvas(out);
            android.graphics.Paint p = new android.graphics.Paint(android.graphics.Paint.ANTI_ALIAS_FLAG);
            cv.drawCircle(sz / 2f, sz / 2f, sz / 2f, p);
            p.setXfermode(new android.graphics.PorterDuffXfermode(android.graphics.PorterDuff.Mode.SRC_IN));
            cv.drawBitmap(sq, 0, 0, p);
            return out;
        } catch (Exception e) {
            return null;
        }
    }

    static android.graphics.Bitmap photo(Context c, String cid) {
        try {
            java.io.File f = new java.io.File(c.getFilesDir(), "ph_" + Math.abs(cid.hashCode()) + ".jpg");
            if (f.exists()) {
                android.graphics.Bitmap b = android.graphics.BitmapFactory.decodeFile(f.getPath());
                if (b != null) {
                    android.graphics.Bitmap r = circle(b);
                    if (r != null) return r;
                }
            }
        } catch (Exception e) {}
        return logo(c);
    }

    static void clear(Context c, String cid) {
        try {
            if (cid == null) return;
            c.getSharedPreferences("bippy_push", 0).edit().remove("l_" + cid).apply();
            NotificationManager nm = (NotificationManager) c.getSystemService(Context.NOTIFICATION_SERVICE);
            nm.cancel(cid, 1);
            if (!temFilhas(nm)) nm.cancel("sum", 0);
        } catch (Exception e) {}
    }

    static boolean send(Context c, String cid, String txt, String mid) {
        try {
            SharedPreferences a = c.getSharedPreferences("bippy_auth", 0);
            String url = a.getString("url", "");
            String key = a.getString("key", "");
            String tok = a.getString("tok", "");
            String uid = a.getString("uid", "");
            if (url.length() == 0 || tok.length() == 0 || uid.length() == 0) return false;
            JSONObject j = new JSONObject();
            if (mid != null && mid.length() > 0) j.put("id", mid);
            j.put("conversa_id", cid);
            j.put("remetente_id", uid);
            j.put("texto", txt);
            HttpURLConnection h = (HttpURLConnection) new URL(url + "/rest/v1/mensagens?on_conflict=id").openConnection();
            h.setRequestMethod("POST");
            h.setConnectTimeout(10000);
            h.setReadTimeout(15000);
            h.setDoOutput(true);
            h.setRequestProperty("apikey", key);
            h.setRequestProperty("Authorization", "Bearer " + tok);
            h.setRequestProperty("Content-Type", "application/json");
            h.setRequestProperty("Prefer", "resolution=ignore-duplicates,return=minimal");
            OutputStream o = h.getOutputStream();
            o.write(j.toString().getBytes("UTF-8"));
            o.close();
            int code = h.getResponseCode();
            h.disconnect();
            return code >= 200 && code < 300;
        } catch (Exception e) {
            return false;
        }
    }

    static void queue(Context c, String cid, String txt, String mid) {
        try {
            SharedPreferences sp = c.getSharedPreferences("bippy_push", 0);
            JSONArray q = new JSONArray(sp.getString("q", "[]"));
            JSONObject o = new JSONObject();
            o.put("id", mid);
            o.put("cid", cid);
            o.put("txt", txt);
            q.put(o);
            sp.edit().putString("q", q.toString()).commit();
        } catch (Exception e) {}
    }

    static void dequeue(Context c, String mid) {
        try {
            SharedPreferences sp = c.getSharedPreferences("bippy_push", 0);
            JSONArray q = new JSONArray(sp.getString("q", "[]"));
            JSONArray n = new JSONArray();
            for (int k = 0; k < q.length(); k++) {
                JSONObject o = q.getJSONObject(k);
                if (!mid.equals(o.optString("id"))) n.put(o);
            }
            sp.edit().putString("q", n.toString()).commit();
        } catch (Exception e) {}
    }
}
JAVA2
  cat > $PD/BippyMsgService.java <<'JAVA2'
package PKGNAME;

import com.google.firebase.messaging.FirebaseMessagingService;
import com.google.firebase.messaging.RemoteMessage;

public class BippyMsgService extends FirebaseMessagingService {
    @Override
    public void onMessageReceived(RemoteMessage m) {
        try {
            java.util.Map<String, String> d = m.getData();
            if (d == null || !"1".equals(d.get("bippy"))) return;
            if (MainActivity.visible) return;
            BippyNotif.show(this, d.get("cid"), d.get("t"), d.get("b"), d.get("au"));
        } catch (Exception e) {}
    }
}
JAVA2
  cat > $PD/BippyAudioService.java <<'JAVA2'
package PKGNAME;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.Service;
import android.content.Intent;
import android.media.AudioAttributes;
import android.media.MediaPlayer;
import android.os.Build;
import android.os.IBinder;
import androidx.core.app.NotificationCompat;
import java.io.File;
import java.io.FileOutputStream;
import java.io.InputStream;
import java.net.HttpURLConnection;
import java.net.URL;

public class BippyAudioService extends Service {
    private MediaPlayer mp;

    @Override
    public IBinder onBind(Intent i) {
        return null;
    }

    @Override
    public int onStartCommand(Intent i, int flags, int startId) {
        final String url = i == null ? null : i.getStringExtra("url");
        try {
            NotificationManager nm = (NotificationManager) getSystemService(NOTIFICATION_SERVICE);
            if (Build.VERSION.SDK_INT >= 26 && nm.getNotificationChannel("audio") == null) {
                nm.createNotificationChannel(new NotificationChannel("audio", "Audio", NotificationManager.IMPORTANCE_LOW));
            }
            int ic = getResources().getIdentifier("ic_stat_bippy", "drawable", getPackageName());
            if (ic == 0) ic = getApplicationInfo().icon;
            Notification n = new NotificationCompat.Builder(this, "audio")
                .setSmallIcon(ic)
                .setContentTitle("Bippy")
                .setContentText("Tocando mensagem de voz")
                .setOngoing(true)
                .build();
            if (Build.VERSION.SDK_INT >= 29) {
                startForeground(7001, n, android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK);
            } else {
                startForeground(7001, n);
            }
        } catch (Exception e) {}
        if (url == null || url.length() == 0) {
            stopSelf();
            return START_NOT_STICKY;
        }
        new Thread(new Runnable() {
            public void run() {
                play(url);
            }
        }).start();
        return START_NOT_STICKY;
    }

    private void fail() {
        try {
            new android.os.Handler(getMainLooper()).post(new Runnable() {
                public void run() {
                    android.widget.Toast.makeText(BippyAudioService.this, "Nao consegui tocar. Abra o Bippy para ouvir.", android.widget.Toast.LENGTH_LONG).show();
                }
            });
        } catch (Exception e) {}
        stopSelf();
    }

    private void play(String url) {
        try {
            File f = new File(getCacheDir(), "aud_notif");
            HttpURLConnection h = (HttpURLConnection) new URL(url).openConnection();
            h.setConnectTimeout(10000);
            h.setReadTimeout(20000);
            if (h.getResponseCode() != 200) {
                fail();
                return;
            }
            InputStream in = h.getInputStream();
            FileOutputStream out = new FileOutputStream(f);
            byte[] buf = new byte[8192];
            int r;
            while ((r = in.read(buf)) > 0) out.write(buf, 0, r);
            out.close();
            in.close();
            h.disconnect();
            mp = new MediaPlayer();
            mp.setAudioAttributes(new AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_MEDIA)
                .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                .build());
            mp.setDataSource(f.getPath());
            mp.setOnCompletionListener(new MediaPlayer.OnCompletionListener() {
                public void onCompletion(MediaPlayer m) {
                    stopSelf();
                }
            });
            mp.setOnErrorListener(new MediaPlayer.OnErrorListener() {
                public boolean onError(MediaPlayer m, int what, int extra) {
                    fail();
                    return true;
                }
            });
            mp.prepare();
            mp.start();
        } catch (Exception e) {
            fail();
        }
    }

    @Override
    public void onDestroy() {
        try {
            if (mp != null) {
                mp.release();
                mp = null;
            }
            stopForeground(true);
        } catch (Exception e) {}
        super.onDestroy();
    }
}
JAVA2
  cat > $PD/BippyReplyReceiver.java <<'JAVA2'
package PKGNAME;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.os.Bundle;
import androidx.core.app.RemoteInput;

public class BippyReplyReceiver extends BroadcastReceiver {
    @Override
    public void onReceive(final Context c, final Intent i) {
        try {
            final String act = i.getStringExtra("act");
            if (act != null) {
                final String c0 = i.getStringExtra("cid");
                if (c0 == null) return;
                BippyNotif.clear(c, c0);
                final PendingResult pr0 = goAsync();
                new Thread(new Runnable() {
                    public void run() {
                        try {
                            if ("read".equals(act)) BippyNotif.markRead(c, c0);
                            else if ("mute".equals(act)) BippyNotif.mute(c, c0, 8);
                        } catch (Exception e) {}
                        pr0.finish();
                    }
                }).start();
                return;
            }
            Bundle r = RemoteInput.getResultsFromIntent(i);
            if (r == null) return;
            CharSequence t = r.getCharSequence("reply");
            final String cid = i.getStringExtra("cid");
            final String title = i.getStringExtra("title");
            if (t == null || cid == null) return;
            final String txt = t.toString().trim();
            if (txt.length() == 0) return;
            final String mid = java.util.UUID.randomUUID().toString();
            // 1) atualiza a notificacao na hora (senao o Android deixa o "girando")
            BippyNotif.replied(c, cid, title, txt);
            // 2) guarda a resposta antes de enviar: se o celular congelar o app, ela e enviada ao abrir (sem repetir)
            BippyNotif.queue(c, cid, txt, mid);
            final PendingResult pr = goAsync();
            new Thread(new Runnable() {
                public void run() {
                    try {
                        boolean ok = BippyNotif.send(c, cid, txt, mid);
                        if (ok) {
                            BippyNotif.dequeue(c, mid);
                        } else {
                            BippyNotif.show(c, cid, title, "Resposta nao enviada. Toque para abrir o Bippy e enviar.");
                        }
                    } catch (Exception e) {}
                    pr.finish();
                }
            }).start();
        } catch (Exception e) {}
    }
}
JAVA2
  sed -i "s/PKGNAME/$PKG/" $PD/BippyNotif.java $PD/BippyMsgService.java $PD/BippyReplyReceiver.java $PD/BippyAudioService.java
  # manifesto: servico e receptor (e tira o servico padrao do plugin, para o nosso ser o unico)
  grep -q 'xmlns:tools' android/app/src/main/AndroidManifest.xml || sed -i 's#<manifest #<manifest xmlns:tools="http://schemas.android.com/tools" #' android/app/src/main/AndroidManifest.xml
  grep -q BippyMsgService android/app/src/main/AndroidManifest.xml || sed -i "s#</application>#<service android:name=\"$PKG.BippyMsgService\" android:exported=\"false\"><intent-filter android:priority=\"100\"><action android:name=\"com.google.firebase.MESSAGING_EVENT\"/></intent-filter></service><service android:name=\"com.capacitorjs.plugins.pushnotifications.MessagingService\" tools:node=\"remove\"/><receiver android:name=\"$PKG.BippyReplyReceiver\" android:exported=\"false\"/></application>#" android/app/src/main/AndroidManifest.xml
  grep -q FOREGROUND_SERVICE_MEDIA_PLAYBACK android/app/src/main/AndroidManifest.xml || sed -i 's#<application #<uses-permission android:name="android.permission.FOREGROUND_SERVICE"/><uses-permission android:name="android.permission.FOREGROUND_SERVICE_MEDIA_PLAYBACK"/><application #' android/app/src/main/AndroidManifest.xml
  grep -q BippyAudioService android/app/src/main/AndroidManifest.xml || sed -i "s#</application>#<service android:name=\"$PKG.BippyAudioService\" android:exported=\"false\" android:foregroundServiceType=\"mediaPlayback\"/></application>#" android/app/src/main/AndroidManifest.xml
  # dependencias do app (o plugin nao expoe o firebase-messaging para o app)
  cat >> android/app/build.gradle <<'EOF'

dependencies {
    implementation platform('com.google.firebase:firebase-bom:32.7.0')
    implementation 'com.google.firebase:firebase-messaging'
    implementation 'androidx.core:core:1.12.0'
}
EOF
  # MainActivity: saber se o app esta aberto, limpar a notificacao ao abrir, guardar login para responder
  python3 - <<'PY'
import glob
j=glob.glob('android/app/src/main/java/**/MainActivity.java',recursive=True)[0]
t=open(j,encoding='utf-8').read()
if 'volatile boolean visible' not in t:
    t=t.replace('public class MainActivity extends BridgeActivity {','public class MainActivity extends BridgeActivity {\n    static volatile boolean visible = false;',1)
    cb='''grab(getIntent());
        try {
            getApplication().registerActivityLifecycleCallbacks(new android.app.Application.ActivityLifecycleCallbacks() {
                public void onActivityResumed(android.app.Activity a) { visible = true; }
                public void onActivityPaused(android.app.Activity a) { visible = false; }
                public void onActivityCreated(android.app.Activity a, Bundle b) {}
                public void onActivityStarted(android.app.Activity a) {}
                public void onActivityStopped(android.app.Activity a) {}
                public void onActivitySaveInstanceState(android.app.Activity a, Bundle b) {}
                public void onActivityDestroyed(android.app.Activity a) {}
            });
        } catch (Exception e) {}'''
    assert t.count('grab(getIntent());')==1
    t=t.replace('grab(getIntent());',cb,1)
    a='try { String pc = i.getStringExtra("cid"); if (pc != null && pc.length() > 0) pcid = pc; } catch (Exception e) {}'
    assert a in t
    t=t.replace(a,'try { String pc = i.getStringExtra("cid"); if (pc != null && pc.length() > 0) { pcid = pc; BippyNotif.clear(this, pc); } } catch (Exception e) {}',1)
    b='        @JavascriptInterface\n        public String pushCid()'
    assert b in t
    t=t.replace(b,'''        @JavascriptInterface
        public void saveAuth(String url, String key, String tok, String uid) {
            try {
                MainActivity.this.getSharedPreferences("bippy_auth", 0).edit()
                    .putString("url", url).putString("key", key).putString("tok", tok).putString("uid", uid).apply();
            } catch (Exception e) {}
        }

        @JavascriptInterface
        public void savePhoto(String cid, String dataUrl) {
            try {
                int k = dataUrl.indexOf(',');
                byte[] by = android.util.Base64.decode(dataUrl.substring(k + 1), android.util.Base64.DEFAULT);
                java.io.File f = new java.io.File(MainActivity.this.getFilesDir(), "ph_" + Math.abs(cid.hashCode()) + ".jpg");
                java.io.FileOutputStream o = new java.io.FileOutputStream(f);
                o.write(by);
                o.close();
            } catch (Exception e) {}
        }

        @JavascriptInterface
        public void clearAuth() {
            try { MainActivity.this.getSharedPreferences("bippy_auth", 0).edit().clear().apply(); } catch (Exception e) {}
        }

        @JavascriptInterface
        public String takeReplies() {
            try {
                android.content.SharedPreferences sp = MainActivity.this.getSharedPreferences("bippy_push", 0);
                String q = sp.getString("q", "[]");
                sp.edit().remove("q").apply();
                return q;
            } catch (Exception e) { return "[]"; }
        }

'''+b,1)
    open(j,'w',encoding='utf-8').write(t)
    print('mainactivity push ok')
PY
  # nao deixa o login (token) do app ir para o backup do Google
  mkdir -p android/app/src/main/res/xml
  cat > android/app/src/main/res/xml/bippy_backup.xml <<'XML'
<?xml version="1.0" encoding="utf-8"?>
<full-backup-content>
    <exclude domain="sharedpref" path="bippy_auth.xml"/>
    <exclude domain="sharedpref" path="bippy_push.xml"/>
</full-backup-content>
XML
  cat > android/app/src/main/res/xml/bippy_extract.xml <<'XML'
<?xml version="1.0" encoding="utf-8"?>
<data-extraction-rules>
    <cloud-backup>
        <exclude domain="sharedpref" path="bippy_auth.xml"/>
        <exclude domain="sharedpref" path="bippy_push.xml"/>
    </cloud-backup>
    <device-transfer>
        <exclude domain="sharedpref" path="bippy_auth.xml"/>
        <exclude domain="sharedpref" path="bippy_push.xml"/>
    </device-transfer>
</data-extraction-rules>
XML
  grep -q fullBackupContent android/app/src/main/AndroidManifest.xml || sed -i 's#<application #<application android:fullBackupContent="@xml/bippy_backup" android:dataExtractionRules="@xml/bippy_extract" #' android/app/src/main/AndroidManifest.xml
  echo "firebase ok"; grep -n "google-services" android/build.gradle android/app/build.gradle || true
fi

# Chave fixa do Bippy: faz o Gradle assinar sempre com o debug.keystore do repositorio
if [ -f debug.keystore ]; then
  KS="$(pwd)/debug.keystore"
  mkdir -p ~/.android && cp debug.keystore ~/.android/debug.keystore
  cat >> android/app/build.gradle <<EOF

android {
    signingConfigs {
        debug {
            storeFile file("$KS")
            storePassword "android"
            keyAlias "androiddebugkey"
            keyPassword "android"
        }
    }
}
EOF
  echo "chave fixa ok: $KS"
  keytool -list -keystore debug.keystore -storepass android 2>/dev/null | grep -i fingerprint || true
fi
