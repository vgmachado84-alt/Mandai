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
    }
''',1)
t=t.replace('        public void set(final String top','''        public String shared() { String x = pend; pend = ""; return x; }

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
                java.io.FileInputStream in = new java.io.FileInputStream(f);
                java.io.ByteArrayOutputStream bo = new java.io.ByteArrayOutputStream();
                byte[] b = new byte[65536];
                int n;
                while ((n = in.read(b)) > 0) bo.write(b, 0, n);
                in.close();
                f.delete();
                org.json.JSONObject o = new org.json.JSONObject();
                o.put("name", it[1]);
                o.put("mime", it[2]);
                o.put("b64", android.util.Base64.encodeToString(bo.toByteArray(), android.util.Base64.NO_WRAP));
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
