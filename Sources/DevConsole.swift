import Foundation
import Combine
import WebKit

/// Captures console output from pages via a WKScriptMessageHandler, and holds
/// the JS snippets used by the dev console + God-mode "Run JS".
final class ConsoleLog: NSObject, ObservableObject, WKScriptMessageHandler {
    @Published var entries: [String] = []

    func userContentController(_ userContentController: WKUserContentController,
                              didReceive message: WKScriptMessage) {
        guard message.name == "j3nsConsole", let s = message.body as? String else { return }
        DispatchQueue.main.async {
            self.entries.append(s)
            if self.entries.count > 500 { self.entries.removeFirst(self.entries.count - 500) }
        }
    }

    func clear() { entries.removeAll() }
}

enum DevConsole {
    /// Injected at document-start on every page: mirrors console.* to the native
    /// side and forwards uncaught errors.
    static let consoleHookJS = """
    (function(){
      if (window.__j3nsHooked) return; window.__j3nsHooked = true;
      function send(level, args){
        try {
          var parts = Array.prototype.map.call(args, function(a){
            try { return (typeof a === 'object') ? JSON.stringify(a) : String(a); }
            catch(e){ return String(a); }
          });
          window.webkit.messageHandlers.j3nsConsole.postMessage('['+level+'] '+parts.join(' '));
        } catch(e){}
      }
      ['log','info','warn','error','debug'].forEach(function(l){
        var orig = console[l];
        console[l] = function(){ send(l, arguments); if (orig) return orig.apply(console, arguments); };
      });
      window.addEventListener('error', function(e){
        send('error', [ (e.message||'error') + ' @ ' + (e.filename||'') + ':' + (e.lineno||0) ]);
      });
      window.addEventListener('unhandledrejection', function(e){
        send('error', [ 'Unhandled promise rejection: ' + (e.reason && e.reason.message ? e.reason.message : e.reason) ]);
      });
    })();
    """

    /// Returns a JSON string describing the current page (Info tab).
    static let pageInfoJS = """
    (function(){
      try {
        var vp = document.querySelector('meta[name=viewport]');
        return JSON.stringify({
          title: document.title,
          url: location.href,
          host: location.host,
          nodes: document.getElementsByTagName('*').length,
          scripts: document.scripts.length,
          images: document.images.length,
          links: document.links.length,
          charset: document.characterSet,
          viewport: vp ? vp.getAttribute('content') : '(none)',
          dpr: window.devicePixelRatio,
          size: window.innerWidth + 'x' + window.innerHeight,
          ua: navigator.userAgent,
          cookies: (document.cookie||'').split(';').filter(function(s){return s.trim();}).length
        }, null, 2);
      } catch(e){ return '{"error":"'+e+'"}'; }
    })();
    """
}
