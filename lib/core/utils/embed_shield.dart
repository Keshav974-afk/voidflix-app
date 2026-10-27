import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

/// EmbedShield provides bulletproof anti-popup and silent redirect absorption
/// for third-party streaming embeds (SPHub, streamed.st, DaddyLive, NetMirror, etc.).
class EmbedShield {
  EmbedShield._();

  static const String userAgent =
      'Mozilla/5.0 (Linux; Android 14; Mobile) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36';

  /// JavaScript payload injected on page start and finish.
  /// Fakes window.open with a mock Window proxy, intercepts popunder links,
  /// neutralizes ad redirects, and prevents click-jackers without breaking media players.
  static const String antiPopupScript = '''
(function() {
  if (window.__voidflixShieldActive) return;
  window.__voidflixShieldActive = true;

  function FakeWindow(u, t) {
    this.closed = false;
    this.name = t || '_blank';
    this.opener = window;
    this.parent = window;
    this.top = window;
    this.location = {
      href: u || 'about:blank',
      assign: function() {},
      replace: function() {},
      reload: function() {},
      toString: function() { return u || 'about:blank'; }
    };
    this.document = {
      write: function() {},
      writeln: function() {},
      open: function() {},
      close: function() {},
      title: 'Media'
    };
    this.focus = function() {};
    this.blur = function() {};
    this.close = function() { this.closed = true; };
    this.postMessage = function() {};
    this.addEventListener = function() {};
    this.removeEventListener = function() {};
    this.dispatchEvent = function() { return true; };
  }

  try {
    window.open = function(u, t, f) {
      console.log('[Voidflix] Silently absorbed popup request:', u);
      return new FakeWindow(u, t);
    };
    Object.defineProperty(window, 'open', {
      value: window.open,
      writable: false,
      configurable: false
    });
    window.alert = function() {};
    window.confirm = function() { return false; };
    window.prompt = function() { return null; };
  } catch(e) {}

  var blockedDomains = [
    'adsterra', 'popads', 'propellerads', 'exoclick', 'bet365', '1xbet',
    'betway', 'casino', 'adcash', 'trafficjunky', 'onclickmega', 'doubleclick',
    'adnxs', 'popcash', 'hilltopads', 'monetag', 'asiafilm', 'capitalhospitals',
    'czernik', 'tinyurl', 'sphub.net', 'quge5', 'diskbecause', 'optimserve'
  ];

  function isAdUrl(u) {
    if (!u) return false;
    var low = ('' + u).toLowerCase();
    for (var i = 0; i < blockedDomains.length; i++) {
      if (low.indexOf(blockedDomains[i]) !== -1) return true;
    }
    return false;
  }

  // Trap location.assign & location.replace so redirect attempts are absorbed silently
  try {
    var origAssign = window.location.assign;
    window.location.assign = function(u) {
      if (isAdUrl(u)) {
        console.log('[Voidflix] Silently absorbed location.assign:', u);
        return;
      }
      try { origAssign.call(window.location, u); } catch(err) {}
    };
    var origReplace = window.location.replace;
    window.location.replace = function(u) {
      if (isAdUrl(u)) {
        console.log('[Voidflix] Silently absorbed location.replace:', u);
        return;
      }
      try { origReplace.call(window.location, u); } catch(err) {}
    };
  } catch(e) {}

  // Intercept click on links targeting new windows or ad domains
  document.addEventListener('click', function(e) {
    var t = e.target;
    while (t && t.tagName !== 'A') {
      t = t.parentElement;
    }
    if (t && t.tagName === 'A') {
      var href = t.getAttribute('href') || '';
      var target = t.getAttribute('target') || '';
      if (target === '_blank' || target === '_new' || isAdUrl(href)) {
        e.preventDefault();
        e.stopPropagation();
        e.stopImmediatePropagation();
        console.log('[Voidflix] Silently absorbed anchor click:', href);
        return false;
      }
    }
  }, true);

  // Safely neutralize click-jackers WITHOUT removing legitimate video player containers
  function cleanOverlays() {
    try {
      var all = document.querySelectorAll('div, a, section, p, span');
      for (var i = 0; i < all.length; i++) {
        var el = all[i];

        // Never touch or remove player containers or media stages
        var idOrClass = ((el.id || '') + ' ' + (el.className || '')).toLowerCase();
        if (idOrClass.includes('player') || idOrClass.includes('video') || idOrClass.includes('media') || idOrClass.includes('shaka') || idOrClass.includes('container') || idOrClass.includes('voidflix')) {
          continue;
        }

        // Kill transparent / invisible overlay elements that block taps to video
        var style = window.getComputedStyle(el);
        if (style.position === 'fixed' || style.position === 'absolute') {
          var z = parseInt(style.zIndex, 10);
          var isTransparent = style.opacity === '0' || style.backgroundColor === 'transparent' || style.backgroundColor === 'rgba(0, 0, 0, 0)';
          if (z >= 999999 && isTransparent && !el.querySelector('video') && !el.querySelector('iframe')) {
            el.style.pointerEvents = 'none';
          }
        }
      }
    } catch(e) {}
  }

  cleanOverlays();
  setInterval(cleanOverlays, 800);

  function notifyTap() {
    try { if (window.VoidflixBridge) { window.VoidflixBridge.postMessage('screen_tapped'); } } catch(e) {}
  }
  window.addEventListener('click', notifyTap, true);
  window.addEventListener('touchend', notifyTap, true);

  function hookVideo() {
    try {
      var vids = document.querySelectorAll('video');
      for (var i = 0; i < vids.length; i++) {
        var v = vids[i];
        if (!v._vfHooked) {
          v._vfHooked = true;
          v.addEventListener('ended', function() {
            if (window.VoidflixBridge) { window.VoidflixBridge.postMessage('video_ended'); }
          });
          v.addEventListener('timeupdate', function() {
            if (v.duration && v.duration > 15 && v.currentTime >= v.duration - 2) {
              if (!v._vfEndedPosted) {
                v._vfEndedPosted = true;
                if (window.VoidflixBridge) { window.VoidflixBridge.postMessage('video_ended'); }
              }
            }
          });
        }
      }
    } catch(e) {}
  }
  hookVideo();
  setInterval(hookVideo, 3000);
})();
''';

  /// Evaluates whether a pending navigation request should be blocked.
  static bool shouldBlockNavigation(String url) {
    final lower = url.toLowerCase();

    // 1. App store / intent / system schemes
    if (lower.startsWith('intent:') ||
        lower.startsWith('market:') ||
        lower.startsWith('vnd:') ||
        lower.startsWith('whatsapp:') ||
        lower.startsWith('tg:') ||
        lower.startsWith('mailto:') ||
        lower.startsWith('tel:') ||
        lower.startsWith('sms:') ||
        lower.endsWith('.apk') ||
        lower.endsWith('.exe')) {
      return true;
    }

    // 2. Ad networks and popunders
    const blocked = [
      'adsterra', 'popads', 'propellerads', 'exoclick', 'bet365', '1xbet',
      'betway', 'casino', 'adcash', 'trafficjunky', 'onclickmega', 'doubleclick',
      'adnxs', 'popcash', 'hilltopads', 'monetag', 'asiafilm', 'capitalhospitals',
      'czernik', 'tinyurl.com', 'sphub.net', 'quge5.com', 'diskbecause',
      '/ad.html', 'optimserve', 'syndication', 'popunder', 'clickadu',
      'revenuehits', 'yllix', 'adtrue', 'bidvertiser',
    ];

    for (final b in blocked) {
      if (lower.contains(b)) return true;
    }

    return false;
  }

  /// Configures an Android WebView for smooth inline media playback.
  static void configureAndroid(WebViewController controller) {
    if (controller.platform is AndroidWebViewController) {
      final android = controller.platform as AndroidWebViewController;
      android.setMediaPlaybackRequiresUserGesture(false);
      android.setMixedContentMode(MixedContentMode.alwaysAllow);
      android.setAllowContentAccess(true);
      android.setAllowFileAccess(true);
    }
  }
}
