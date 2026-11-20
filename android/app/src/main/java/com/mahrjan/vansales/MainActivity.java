package com.mahrjan.vansales;

import android.app.Activity;
import android.app.DownloadManager;
import android.content.Intent;
import android.net.Uri;
import android.os.Bundle;
import android.os.Environment;
import android.webkit.CookieManager;
import android.webkit.URLUtil;
import android.webkit.ValueCallback;
import android.webkit.WebChromeClient;
import android.webkit.WebResourceRequest;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;

/** Mahrjan van sales app: opens the web app full screen. All screens and logic come from the website. */
public class MainActivity extends Activity {
    private static final String HOME = "https://inventory-mahrjan.github.io/mahrjan-system/index-app.html";
    private static final String HOST = "inventory-mahrjan.github.io";
    private static final int PICK = 7;
    private WebView web;
    private ValueCallback<Uri[]> pending;

    @Override protected void onCreate(Bundle saved) {
        super.onCreate(saved);
        web = new WebView(this);
        setContentView(web);
        WebSettings s = web.getSettings();
        s.setJavaScriptEnabled(true);
        s.setDomStorageEnabled(true);
        s.setDatabaseEnabled(true);
        s.setCacheMode(WebSettings.LOAD_DEFAULT);
        s.setMediaPlaybackRequiresUserGesture(false);
        s.setUserAgentString(s.getUserAgentString() + " MahrjanApp");
        CookieManager.getInstance().setAcceptCookie(true);
        web.setWebViewClient(new WebViewClient() {
            @Override public boolean shouldOverrideUrlLoading(WebView v, WebResourceRequest r) {
                Uri u = r.getUrl();
                if (HOST.equals(u.getHost())) return false;            // our pages stay in the app
                try { startActivity(new Intent(Intent.ACTION_VIEW, u)); } catch (Exception e) { }
                return true;                                             // WhatsApp, maps, other sites open outside
            }
        });
        web.setWebChromeClient(new WebChromeClient() {
            @Override public boolean onShowFileChooser(WebView v, ValueCallback<Uri[]> cb, FileChooserParams p) {
                if (pending != null) pending.onReceiveValue(null);
                pending = cb;
                try { startActivityForResult(p.createIntent(), PICK); } catch (Exception e) { pending = null; return false; }
                return true;
            }
        });
        web.setDownloadListener((url, ua, cd, mime, len) -> {
            if (!url.startsWith("http")) return;
            try {
                DownloadManager.Request q = new DownloadManager.Request(Uri.parse(url));
                String name = URLUtil.guessFileName(url, cd, mime);
                q.setMimeType(mime);
                q.setNotificationVisibility(DownloadManager.Request.VISIBILITY_VISIBLE_NOTIFY_COMPLETED);
                q.setDestinationInExternalPublicDir(Environment.DIRECTORY_DOWNLOADS, name);
                ((DownloadManager) getSystemService(DOWNLOAD_SERVICE)).enqueue(q);
            } catch (Exception e) { }
        });
        if (saved != null) web.restoreState(saved); else web.loadUrl(HOME);
    }

    @Override protected void onActivityResult(int req, int res, Intent data) {
        if (req == PICK && pending != null) { pending.onReceiveValue(WebChromeClient.FileChooserParams.parseResult(res, data)); pending = null; return; }
        super.onActivityResult(req, res, data);
    }
    @Override protected void onSaveInstanceState(Bundle out) { super.onSaveInstanceState(out); web.saveState(out); }
    @Override public void onBackPressed() { if (web.canGoBack()) web.goBack(); else super.onBackPressed(); }
}
