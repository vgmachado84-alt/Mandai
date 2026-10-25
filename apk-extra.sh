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
