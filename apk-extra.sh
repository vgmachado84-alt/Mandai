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
  mkdir -p android/app/src/main/res/drawable
  cat > android/app/src/main/res/drawable/ic_stat_bippy.xml <<'XML'
<vector xmlns:android="http://schemas.android.com/apk/res/android" android:width="24dp" android:height="24dp" android:viewportWidth="24" android:viewportHeight="24">
    <path android:fillColor="#FFFFFFFF" android:pathData="M20,2H4C2.9,2 2,2.9 2,4v18l4,-4h14c1.1,0 2,-0.9 2,-2V4C22,2.9 21.1,2 20,2z"/>
</vector>
XML
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

    static void show(Context c, String cid, String title, String body) {
        try {
            if (cid == null || cid.length() == 0) return;
            if (title == null || title.length() == 0) title = "Bippy";
            if (body == null) body = "";
            body = body.replace("\n", " ");
            NotificationManager nm = (NotificationManager) c.getSystemService(Context.NOTIFICATION_SERVICE);
            if (Build.VERSION.SDK_INT >= 26 && nm.getNotificationChannel(CH) == null) {
                NotificationChannel ch = new NotificationChannel(CH, "Mensagens", NotificationManager.IMPORTANCE_HIGH);
                ch.setDescription("Novas mensagens");
                nm.createNotificationChannel(ch);
            }
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
                .setColor(0xFF7C4DFF);
            android.graphics.Bitmap lb = photo(c, cid);
            if (lb != null) b.setLargeIcon(lb);
            nm.notify(cid, 1, b.build());
        } catch (Exception e) {}
    }

    static android.graphics.Bitmap logoBmp = null;

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
            BippyNotif.show(this, d.get("cid"), d.get("t"), d.get("b"));
        } catch (Exception e) {}
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
            Bundle r = RemoteInput.getResultsFromIntent(i);
            if (r == null) return;
            CharSequence t = r.getCharSequence("reply");
            final String cid = i.getStringExtra("cid");
            final String title = i.getStringExtra("title");
            if (t == null || cid == null) return;
            final String txt = t.toString().trim();
            if (txt.length() == 0) return;
            final String mid = java.util.UUID.randomUUID().toString();
            // 1) fecha a notificacao na hora (senao o Android deixa o "girando")
            BippyNotif.clear(c, cid);
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
  sed -i "s/PKGNAME/$PKG/" $PD/BippyNotif.java $PD/BippyMsgService.java $PD/BippyReplyReceiver.java
  # manifesto: servico e receptor (e tira o servico padrao do plugin, para o nosso ser o unico)
  grep -q 'xmlns:tools' android/app/src/main/AndroidManifest.xml || sed -i 's#<manifest #<manifest xmlns:tools="http://schemas.android.com/tools" #' android/app/src/main/AndroidManifest.xml
  grep -q BippyMsgService android/app/src/main/AndroidManifest.xml || sed -i "s#</application>#<service android:name=\"$PKG.BippyMsgService\" android:exported=\"false\"><intent-filter android:priority=\"100\"><action android:name=\"com.google.firebase.MESSAGING_EVENT\"/></intent-filter></service><service android:name=\"com.capacitorjs.plugins.pushnotifications.MessagingService\" tools:node=\"remove\"/><receiver android:name=\"$PKG.BippyReplyReceiver\" android:exported=\"false\"/></application>#" android/app/src/main/AndroidManifest.xml
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
