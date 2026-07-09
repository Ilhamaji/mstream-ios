import UIKit
import WebKit

enum ActiveSite {
    case none
    case cineby
    case nimegami
}

class LeakAvoider: NSObject, WKScriptMessageHandler {
    weak var delegate: WKScriptMessageHandler?
    init(delegate: WKScriptMessageHandler) {
        self.delegate = delegate
    }
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        self.delegate?.userContentController(userContentController, didReceive: message)
    }
}

class WebViewController: UIViewController, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
    var webView: WKWebView!
    private var containerView: UIView!
    private var landingView: UIView!
    private var portraitRotateButton: UIButton!
    private var switchWebButton: UIButton!
    private var landscapeRotateButton: UIButton!
    private var nativeLockButton: UIButton!
    
    private var activeSite: ActiveSite = .none
    private var isFullscreen = false
    private var isLandscapeRotated = false
    private var isPlaybackLocked = false
    private var hasActiveVideo = false
    
    private var unlockAutoHideTimer: Timer?
    private var screenTapGesture: UITapGestureRecognizer!

    private var webViewConstraints: [NSLayoutConstraint] = []
    private var rotateButtonConstraints: [NSLayoutConstraint] = []
    private var lockButtonConstraints: [NSLayoutConstraint] = []
    private var switchButtonTopConstraint: NSLayoutConstraint!

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(red: 0.05, green: 0.05, blue: 0.07, alpha: 1.0)
        self.navigationController?.setNavigationBarHidden(true, animated: false)

        setupWebView()
        setupSwitchWebButton()
        setupPortraitRotateButton()
        setupLandscapeRotateButton()
        setupNativeLockButton()
        setupTapGesture()
        setupLandingView()
    }

    func setupWebView() {
        let contentController = WKUserContentController()
        
        // === EARLY SCRIPT: injected at document START, runs in ALL frames ===
        // Locks video.controls at prototype level BEFORE any player script runs.
        let earlyJS = """
        (function() {
          try {
            // Block 'controls' attribute via prototype descriptor — runs before player code
            if (typeof HTMLVideoElement !== 'undefined') {
              try {
                Object.defineProperty(HTMLVideoElement.prototype, 'controls', {
                  get: function() { return false; },
                  set: function() {},
                  configurable: true,
                  enumerable: true
                });
              } catch(e) {}

              // Block setAttribute('controls', ...) at prototype level
              var _origSetAttr = HTMLVideoElement.prototype.setAttribute;
              HTMLVideoElement.prototype.setAttribute = function(name, val) {
                if (name === 'controls' || name === 'Controls') return;
                return _origSetAttr.apply(this, arguments);
              };
            }

            // Inject webkit media controls hiding CSS immediately
            var earlyStyle = document.getElementById('mstream-early-hide');
            if (!earlyStyle) {
              earlyStyle = document.createElement('style');
              earlyStyle.id = 'mstream-early-hide';
              (document.head || document.documentElement).appendChild(earlyStyle);
            }
            earlyStyle.innerHTML = [
              'video::-webkit-media-controls { display: none !important; opacity: 0 !important; }',
              'video::-webkit-media-controls-enclosure { display: none !important; opacity: 0 !important; }',
              'video::-webkit-media-controls-panel { display: none !important; opacity: 0 !important; }',
              'video::-webkit-media-controls-play-button { display: none !important; opacity: 0 !important; }',
              'video::-webkit-media-controls-start-playback-button { display: none !important; opacity: 0 !important; }',
              'video::-webkit-media-controls-overlay-play-button { display: none !important; opacity: 0 !important; }',
              'video::-webkit-media-controls-volume-slider { display: none !important; opacity: 0 !important; }',
              'video::-webkit-media-controls-timeline { display: none !important; opacity: 0 !important; }',
              'video::-webkit-media-controls-current-time-display { display: none !important; opacity: 0 !important; }',
              'video::-webkit-media-controls-time-remaining-display { display: none !important; opacity: 0 !important; }',
              'video::-webkit-media-controls-mute-button { display: none !important; opacity: 0 !important; }',
              'video::-webkit-media-controls-fullscreen-button { display: none !important; opacity: 0 !important; }',
              /* Broad catch-all untuk semua shadow DOM media controls */
              '*::-webkit-media-controls { display: none !important; }',
              '*::-webkit-media-controls-overlay-play-button { display: none !important; }',
              '*::-webkit-media-controls-start-playback-button { display: none !important; }',
              /* Sembunyikan container volume/timeline native */
              'video { -webkit-media-controls-display: none; }',
              '* { -webkit-touch-callout: none !important; }'
            ].join(' ');

            // Langsung set properti disableRemotePlayback dan disablePictureInPicture
            // pada semua video yang sudah ada — ini paling efektif menekan overlay play button WebKit
            function stripNativeVideoUI(v) {
              try {
                if ('disableRemotePlayback' in v) v.disableRemotePlayback = true;
                if ('disablePictureInPicture' in v) v.disablePictureInPicture = true;
                v.controls = false;
                v.removeAttribute('controls');
              } catch(e) {}
            }
            document.querySelectorAll('video').forEach(stripNativeVideoUI);
            // MutationObserver untuk video baru yang ditambahkan
            var videoStripper = new MutationObserver(function(muts) {
              muts.forEach(function(m) {
                m.addedNodes.forEach(function(node) {
                  if (node.nodeName === 'VIDEO') stripNativeVideoUI(node);
                  if (node.querySelectorAll) node.querySelectorAll('video').forEach(stripNativeVideoUI);
                });
              });
            });
            videoStripper.observe(document.documentElement, { childList: true, subtree: true });

            // MutationObserver: strip 'controls' attribute the moment it appears on any video
            var controlsGuard = new MutationObserver(function(mutations) {
              mutations.forEach(function(m) {
                if (m.type === 'attributes' && m.attributeName === 'controls') {
                  m.target.removeAttribute('controls');
                }
                if (m.type === 'childList') {
                  m.addedNodes.forEach(function(node) {
                    if (node.nodeName === 'VIDEO') {
                      node.removeAttribute('controls');
                    }
                    if (node.querySelectorAll) {
                      node.querySelectorAll('video').forEach(function(v) {
                        v.removeAttribute('controls');
                      });
                    }
                  });
                }
              });
            });
            controlsGuard.observe(document.documentElement, {
              attributes: true,
              attributeFilter: ['controls'],
              childList: true,
              subtree: true
            });
          } catch(e) {}
        })();
        """
        let earlyScript = WKUserScript(source: earlyJS, injectionTime: .atDocumentStart, forMainFrameOnly: false)
        contentController.addUserScript(earlyScript)

        let js = """
        (function() {
          try {
            // Auto playsinline logic
            function forcePlaysInline() {
              var videos = Array.from(document.querySelectorAll('video'));
              videos.forEach(function(video) {
                if (!video.hasAttribute('playsinline')) {
                  video.setAttribute('playsinline', 'true');
                  video.setAttribute('webkit-playsinline', 'true');
                }
              });
            }
            var observer = new MutationObserver(forcePlaysInline);
            observer.observe(document.body, { childList: true, subtree: true });
            setInterval(forcePlaysInline, 1000);
            forcePlaysInline();

            // Enable iframe fullscreen attributes
            function enableIframeFullscreen() {
              var iframes = document.querySelectorAll('iframe');
              iframes.forEach(function(iframe) {
                if (!iframe.hasAttribute('allowfullscreen')) {
                  iframe.setAttribute('allowfullscreen', 'true');
                }
                if (!iframe.hasAttribute('allow')) {
                  iframe.setAttribute('allow', 'autoplay; fullscreen');
                } else {
                  var allowVal = iframe.getAttribute('allow');
                  if (!allowVal.includes('fullscreen')) {
                    iframe.setAttribute('allow', allowVal + '; fullscreen');
                  }
                }
              });
            }
            var iframeObserver = new MutationObserver(enableIframeFullscreen);
            iframeObserver.observe(document.body, { childList: true, subtree: true });
            setInterval(enableIframeFullscreen, 1000);
            enableIframeFullscreen();

            // Intercept Element requestFullscreen API and notify native Swift side
            try {
              var triggerNativeRotation = function() {
                try {
                  window.webkit.messageHandlers.videoDetector.postMessage({ triggerRotation: true });
                } catch (e) {}
              };
              if (Element.prototype.requestFullscreen) {
                var origRequest = Element.prototype.requestFullscreen;
                Element.prototype.requestFullscreen = function() {
                  triggerNativeRotation();
                  return Promise.resolve();
                };
              }
              if (Element.prototype.webkitRequestFullscreen) {
                Element.prototype.webkitRequestFullscreen = function() {
                  triggerNativeRotation();
                  return Promise.resolve();
                };
              }
              if (typeof HTMLVideoElement !== 'undefined') {
                if (HTMLVideoElement.prototype.webkitEnterFullscreen) {
                  HTMLVideoElement.prototype.webkitEnterFullscreen = function() {
                    triggerNativeRotation();
                  };
                }
                if (HTMLVideoElement.prototype.webkitEnterFullScreen) {
                  HTMLVideoElement.prototype.webkitEnterFullScreen = function() {
                    triggerNativeRotation();
                  };
                }
              }
            } catch(e) {}

            // Video presence detection (only post on state change)
            var lastHasVideo = false;
            function checkVideoPresence() {
              var hasVideo = document.querySelector('video') !== null;
              if (hasVideo !== lastHasVideo) {
                lastHasVideo = hasVideo;
                try {
                  window.webkit.messageHandlers.videoDetector.postMessage({ hasVideo: hasVideo });
                } catch (e) {}
                // If we have video inside this frame/iframe, broadcast to parent window
                if (hasVideo && window.parent !== window) {
                  window.parent.postMessage({ type: 'iAmVideoPlayer' }, '*');
                }
              }
            }
            setInterval(checkVideoPresence, 1000);
            checkVideoPresence();

            // Broadcast active site info from main frame to all subframes recursively
            function broadcastActiveSite() {
              var site = window.location.hostname.includes('nimegami') ? 'nimegami' : 'cineby';
              function sendSite(win) {
                try {
                  win.postMessage({ type: 'mstreamActiveSite', site: site }, '*');
                } catch (e) {}
                for (var i = 0; i < win.frames.length; i++) {
                  sendSite(win.frames[i]);
                }
              }
              sendSite(window);
            }
            setInterval(broadcastActiveSite, 1000);
            broadcastActiveSite();

            // Inject custom Mstream dedicated playback controls
            // Overlay is placed on document.body with position:fixed to guarantee it
            // is always on top of any player library's own touch-intercept layers.
            function injectMstreamControls() {
              var video = document.querySelector('video');
              if (!video) return;

              var existing = document.getElementById('mstream-controls-overlay');
              if (existing) {
                // Overlay exists — ensure it's still attached to body and has our ref
                if (existing.parentNode !== document.body) {
                  document.body.appendChild(existing);
                }
                return;
              }

              var overlay = document.createElement('div');
              overlay.id = 'mstream-controls-overlay';
              // Fixed positioning on body — always above everything
              overlay.style.cssText = [
                'position: fixed',
                'top: 50%',
                'left: 50%',
                'transform: translate(-50%, -50%)',
                'display: flex',
                'align-items: center',
                'justify-content: center',
                'gap: 24px',
                'z-index: 2147483647',
                'pointer-events: auto',
                'opacity: 0',
                'transition: opacity 0.3s ease-in-out',
                'background: rgba(0,0,0,0.45)',
                'padding: 12px 24px',
                'border-radius: 30px',
                '-webkit-transform: translate(-50%, -50%)'
              ].join('; ');

              overlay.innerHTML = `
                <button id="mstream-btn-back" style="width:50px;height:50px;border-radius:25px;border:1px solid rgba(255,255,255,0.4);background:rgba(20,20,20,0.85);color:white;font-size:14px;font-weight:bold;cursor:pointer;display:flex;align-items:center;justify-content:center;outline:none;-webkit-tap-highlight-color:transparent;touch-action:manipulation;">↺ 5s</button>
                <button id="mstream-btn-play" style="width:60px;height:60px;border-radius:30px;border:1px solid rgba(255,255,255,0.4);background:rgba(20,20,20,0.85);color:white;font-size:20px;font-weight:bold;cursor:pointer;display:flex;align-items:center;justify-content:center;outline:none;-webkit-tap-highlight-color:transparent;touch-action:manipulation;">▶</button>
                <button id="mstream-btn-forward" style="width:50px;height:50px;border-radius:25px;border:1px solid rgba(255,255,255,0.4);background:rgba(20,20,20,0.85);color:white;font-size:14px;font-weight:bold;cursor:pointer;display:flex;align-items:center;justify-content:center;outline:none;-webkit-tap-highlight-color:transparent;touch-action:manipulation;">5s ↻</button>
              `;

              // Append directly to body for guaranteed top z-index stacking
              document.body.appendChild(overlay);

              var backBtn = document.getElementById('mstream-btn-back');
              var playBtn = document.getElementById('mstream-btn-play');
              var forwardBtn = document.getElementById('mstream-btn-forward');

              var timer = null;
              function showControls() {
                if (document.body.classList.contains('playback-locked')) {
                  hideControls();
                  return;
                }
                overlay.style.opacity = '1';
                overlay.style.pointerEvents = 'auto';
                resetTimer();
              }
              function hideControls() {
                overlay.style.opacity = '0';
                overlay.style.pointerEvents = 'none';
              }
              function resetTimer() {
                clearTimeout(timer);
                timer = setTimeout(hideControls, 3000);
              }

              // Temporarily freeze any player intercept layer during button press
              // so our touchstart fires cleanly without the player stealing the event
              function freezePlayerInterceptors() {
                try {
                  var v = document.querySelector('video');
                  if (!v) return;
                  var el = v.parentNode;
                  var depth = 0;
                  while (el && el !== document.body && depth < 6) {
                    var pe = getComputedStyle(el).pointerEvents;
                    if (pe !== 'none') {
                      el.dataset.mstreamFrozenPE = pe;
                      el.style.setProperty('pointer-events', 'none', 'important');
                    }
                    el = el.parentNode;
                    depth++;
                  }
                } catch(e) {}
              }
              function unfreezePlayerInterceptors() {
                try {
                  var v = document.querySelector('video');
                  if (!v) return;
                  var el = v.parentNode;
                  var depth = 0;
                  while (el && el !== document.body && depth < 6) {
                    if (el.dataset.mstreamFrozenPE !== undefined) {
                      el.style.removeProperty('pointer-events');
                      delete el.dataset.mstreamFrozenPE;
                    }
                    el = el.parentNode;
                    depth++;
                  }
                } catch(e) {}
              }

              function makeButtonHandler(action) {
                var lastTouch = 0;
                return {
                  touchstart: function(e) {
                    e.stopPropagation();
                    lastTouch = Date.now();
                    action(e);
                    showControls();
                  },
                  click: function(e) {
                    e.stopPropagation();
                    if (Date.now() - lastTouch < 600) return; // dedupe
                    action(e);
                    showControls();
                  },
                  touchend: function(e) {
                    e.stopPropagation();
                    unfreezePlayerInterceptors();
                  }
                };
              }

              var backHandler = makeButtonHandler(function(e) {
                e.preventDefault();
                var v = document.querySelector('video');
                if (v) v.currentTime = Math.max(0, v.currentTime - 5);
              });
              backBtn.addEventListener('touchstart', backHandler.touchstart, {passive: false});
              backBtn.addEventListener('touchend', backHandler.touchend, {passive: false});
              backBtn.addEventListener('click', backHandler.click);

              var playHandler = makeButtonHandler(function(e) {
                e.preventDefault();
                var v = document.querySelector('video');
                if (!v) return;
                if (v.paused) { v.play(); } else { v.pause(); }
              });
              playBtn.addEventListener('touchstart', playHandler.touchstart, {passive: false});
              playBtn.addEventListener('touchend', playHandler.touchend, {passive: false});
              playBtn.addEventListener('click', playHandler.click);

              var forwardHandler = makeButtonHandler(function(e) {
                e.preventDefault();
                var v = document.querySelector('video');
                if (v) v.currentTime = Math.min(v.duration, v.currentTime + 5);
              });
              forwardBtn.addEventListener('touchstart', forwardHandler.touchstart, {passive: false});
              forwardBtn.addEventListener('touchend', forwardHandler.touchend, {passive: false});
              forwardBtn.addEventListener('click', forwardHandler.click);

              // Track play/pause state
              function syncPlayBtn() {
                var v = document.querySelector('video');
                if (!v) return;
                playBtn.innerText = v.paused ? '▶' : '❚❚';
              }
              setInterval(syncPlayBtn, 500);
              syncPlayBtn();

              // Expose showControls for global touch handler
              overlay.showMstreamControls = showControls;

              showControls();
            }
            setInterval(injectMstreamControls, 1000);
            injectMstreamControls();

            // Set up global touch/click capture listener to show controls on screen tap
            // Since overlay is now fixed on body, any tap anywhere should show it
            if (!window.hasMstreamTouchListeners) {
              window.hasMstreamTouchListeners = true;
              var handleGlobalTouch = function(e) {
                // Skip taps on our own buttons
                var tid = e.target && e.target.id;
                if (tid === 'mstream-btn-play' || tid === 'mstream-btn-back' || tid === 'mstream-btn-forward') {
                  return;
                }
                // Skip taps on the overlay container itself (between buttons)
                if (e.target && e.target.id === 'mstream-controls-overlay') return;

                var video = document.querySelector('video');
                if (!video) return;
                var overlay = document.getElementById('mstream-controls-overlay');
                if (!overlay || typeof overlay.showMstreamControls !== 'function') return;
                overlay.showMstreamControls();
              };
              document.addEventListener('touchstart', handleGlobalTouch, {passive: true, capture: true});
              document.addEventListener('click', handleGlobalTouch, {capture: true});
            }

            // Persistently hide default player controls, timelines, and timestamps.
            // Covers all major player libraries and common class patterns.
            var HIDE_CONTROLS_CSS = [
              /* WebKit native video controls (most important!) */
              'video::-webkit-media-controls { display:none!important; }',
              'video::-webkit-media-controls-enclosure { display:none!important; }',
              'video::-webkit-media-controls-panel { display:none!important; }',
              'video::-webkit-media-controls-play-button { display:none!important; }',
              'video::-webkit-media-controls-start-playback-button { display:none!important; }',
              'video::-webkit-media-controls-overlay-play-button { display:none!important; }',
              'video::-webkit-media-controls-volume-slider { display:none!important; }',
              'video::-webkit-media-controls-timeline { display:none!important; }',
              'video::-webkit-media-controls-current-time-display { display:none!important; }',
              'video::-webkit-media-controls-time-remaining-display { display:none!important; }',
              'video::-webkit-media-controls-mute-button { display:none!important; }',
              'video::-webkit-media-controls-fullscreen-button { display:none!important; }',
              /* JW Player */
              '.jw-controls,.jw-controlbar,.jw-title,.jw-logo,',
              '.jw-nextup-container,.jw-display-icon-container,',
              '.jw-settings-menu,.jw-settings-submenu,.jw-settings-content,',
              '.jw-submenu,.jw-icon-inline,.jw-slider-container,.jw-time-tip,',
              /* Video.js */
              '.vjs-control-bar,.vjs-big-play-button,.vjs-loading-spinner,.vjs-poster,',
              /* Plyr */
              '.plyr__controls,.plyr__play-large,.plyr__control--overlaid,',
              /* Artplayer */
              '.art-control,.art-controls,.art-bottom,.art-progress,',
              '.art-state,.art-state-play,.art-play,.art-poster,',
              '.art-layer-mask,.art-layer,.art-layers,.art-notice,',
              /* DPlayer */
              '.dplayer-controller,.dplayer-bar-wrap,.dplayer-menu,.dplayer-setting-box,',
              /* Shaka Player */
              '.shaka-bottom-controls,.shaka-settings-menu,.shaka-overflow-menu,',
              /* HLS.js / Flowplayer */
              '.fp-controls,.fp-ui,.fp-elapsed,.fp-duration,',
              /* Cineby / Generic */
              '.cb-controlbar,.cb-control,.cb-controls,',
              '.player-controlbar,.player-bottom,.player-ui,.player-controls,',
              '.video-controlbar,.video-bottombar,.video-controls,',
              /* Wide attribute-based selectors — catch-all for unknown players */
              '[class*=controlbar]:not(#mstream-controls-overlay),',
              '[class*=control-bar]:not(#mstream-controls-overlay),',
              '[class*=playerbar]:not(#mstream-controls-overlay),',
              '[class*=player-control]:not(#mstream-controls-overlay),',
              '[class*=video-control]:not(#mstream-controls-overlay)',
              '{ display:none!important; opacity:0!important; visibility:hidden!important; pointer-events:none!important; }',
              /* Always keep our dedicated overlay visible */
              '#mstream-controls-overlay { display:flex!important; visibility:visible!important; pointer-events:auto!important; }',
              '#mstream-controls-overlay * { display:flex!important; visibility:visible!important; pointer-events:auto!important; }',
              '#mstream-controls-overlay[style*="opacity: 0"],',
              '#mstream-controls-overlay[style*="opacity:0"]',
              '{ opacity:0!important; pointer-events:none!important; }'
            ].join(' ');

            function hideDefaultControls() {
              // Inject persistent CSS
              var style = document.getElementById('mstream-default-controls-hide-override');
              if (!style) {
                style = document.createElement('style');
                style.id = 'mstream-default-controls-hide-override';
                (document.head || document.documentElement).appendChild(style);
              }
              style.innerHTML = HIDE_CONTROLS_CSS;

              // Remove controls attribute and property from all videos
              try {
                var videos = document.querySelectorAll('video');
                for (var i = 0; i < videos.length; i++) {
                  var v = videos[i];
                  v.controls = false;
                  v.removeAttribute('controls');
                  // Nonaktifkan remote playback & PiP — ini yang paling efektif
                  // menekan tombol overlay play button bawaan WebKit di WKWebView
                  try { if ('disableRemotePlayback' in v) v.disableRemotePlayback = true; } catch(e) {}
                  try { if ('disablePictureInPicture' in v) v.disablePictureInPicture = true; } catch(e) {}

                  // Override setAttribute to block future re-adds of 'controls'
                  if (!v.__mstreamOverridden) {
                    v.__mstreamOverridden = true;
                    var origSetAttr = v.setAttribute.bind(v);
                    v.setAttribute = function(name, value) {
                      if (name === 'controls') return;
                      origSetAttr(name, value);
                    };
                    Object.defineProperty(v, 'controls', {
                      get: function() { return false; },
                      set: function() {},
                      configurable: true
                    });
                  }
                }
              } catch (e) {}

              // Also inject the same CSS into all accessible iframes
              try {
                var iframes = document.querySelectorAll('iframe');
                for (var fi = 0; fi < iframes.length; fi++) {
                  try {
                    var iDoc = iframes[fi].contentDocument || iframes[fi].contentWindow.document;
                    if (!iDoc) continue;
                    var iStyle = iDoc.getElementById('mstream-default-controls-hide-override');
                    if (!iStyle) {
                      iStyle = iDoc.createElement('style');
                      iStyle.id = 'mstream-default-controls-hide-override';
                      (iDoc.head || iDoc.documentElement).appendChild(iStyle);
                    }
                    iStyle.innerHTML = HIDE_CONTROLS_CSS;
                    var iVideos = iDoc.querySelectorAll('video');
                    for (var vi = 0; vi < iVideos.length; vi++) {
                      var iv = iVideos[vi];
                      iv.controls = false;
                      iv.removeAttribute('controls');
                      if (!iv.__mstreamOverridden) {
                        iv.__mstreamOverridden = true;
                        var origSetAttrI = iv.setAttribute.bind(iv);
                        iv.setAttribute = function(name, value) {
                          if (name === 'controls') return;
                          origSetAttrI(name, value);
                        };
                        Object.defineProperty(iv, 'controls', {
                          get: function() { return false; },
                          set: function() {},
                          configurable: true
                        });
                      }
                    }
                  } catch (iframeErr) {}
                }
              } catch (e) {}
            }
            setInterval(hideDefaultControls, 300);
            hideDefaultControls();

            // Notify native side of frame loading to check/enforce lock state
            try {
              window.webkit.messageHandlers.videoDetector.postMessage({ frameLoaded: true });
            } catch (e) {}

            // Listen for messages from child frames
            window.addEventListener('message', function(event) {
              if (event.data && event.data.type === 'iAmVideoPlayer') {
                var iframes = document.querySelectorAll('iframe');
                for (var i = 0; i < iframes.length; i++) {
                  if (iframes[i].contentWindow === event.source) {
                    iframes[i].classList.add('active-video-player');
                    break;
                  }
                }
              }

              if (event.data && event.data.type === 'playbackLock') {
                var locked = event.data.locked;
                if (locked) {
                  document.body.classList.add('playback-locked');
                  var overlay = document.getElementById('mstream-controls-overlay');
                  if (overlay) {
                    overlay.style.opacity = '0';
                    overlay.style.pointerEvents = 'none';
                  }
                  
                  // Setup recursive/continuous JS enforcement
                  if (window.mstreamLockInterval) clearInterval(window.mstreamLockInterval);
                  
                  var enforceHiding = function() {
                    if (!document.body.classList.contains('playback-locked')) {
                      if (window.mstreamLockInterval) clearInterval(window.mstreamLockInterval);
                      return;
                    }
                    var selectors = [
                      /* JW Player */
                      '.jw-controls', '.jw-controlbar', '.jw-title', '.jw-logo',
                      '.jw-nextup-container', '.jw-display-icon-container',
                      '.jw-settings-menu', '.jw-settings-submenu', '.jw-settings-content',
                      '.jw-submenu', '.jw-icon-inline', '.jw-slider-container', '.jw-time-tip',
                      /* Video.js */
                      '.vjs-control-bar', '.vjs-big-play-button', '.vjs-loading-spinner', '.vjs-poster',
                      /* Plyr */
                      '.plyr__controls',
                      /* Artplayer */
                      '.art-control', '.art-controls', '.art-bottom', '.art-progress',
                      '.art-state', '.art-state-play', '.art-play', '.art-poster',
                      /* DPlayer */
                      '.dplayer-controller', '.dplayer-bar-wrap', '.dplayer-menu', '.dplayer-setting-box',
                      /* Shaka Player */
                      '.shaka-bottom-controls', '.shaka-settings-menu', '.shaka-overflow-menu',
                      /* Cineby-specific */
                      '.cb-controlbar', '.cb-control', '.cb-controls',
                      '.player-controlbar', '.player-bottom', '.player-ui',
                      '.video-controlbar', '.video-bottombar'
                    ];
                    selectors.forEach(function(sel) {
                      try {
                        var elements = document.querySelectorAll(sel);
                        for (var i = 0; i < elements.length; i++) {
                          // Never hide our own dedicated overlay
                          if (elements[i].id === 'mstream-controls-overlay') continue;
                          elements[i].style.setProperty('display', 'none', 'important');
                          elements[i].style.setProperty('opacity', '0', 'important');
                          elements[i].style.setProperty('visibility', 'hidden', 'important');
                          elements[i].style.setProperty('pointer-events', 'none', 'important');
                        }
                      } catch(e) {}
                    });
                    
                    try {
                      var videos = document.querySelectorAll('video');
                      for (var i = 0; i < videos.length; i++) {
                        videos[i].controls = false;
                        videos[i].removeAttribute('controls');
                      }
                    } catch(e) {}
                  };
                  
                  enforceHiding();
                  window.mstreamLockInterval = setInterval(enforceHiding, 250);
                } else {
                  document.body.classList.remove('playback-locked');
                  if (window.mstreamLockInterval) {
                    clearInterval(window.mstreamLockInterval);
                    window.mstreamLockInterval = null;
                  }
                  
                  // Restore elements by clearing the inline properties
                  var selectors = [
                    '.jw-controls', '.jw-controlbar', '.jw-settings-menu', '.jw-settings-submenu',
                    '.art-controls', '.art-bottom', '[class*="control" i]', '[class*="bottom-bar" i]'
                  ];
                  selectors.forEach(function(sel) {
                    try {
                      var elements = document.querySelectorAll(sel);
                      for (var i = 0; i < elements.length; i++) {
                        elements[i].style.removeProperty('display');
                        elements[i].style.removeProperty('opacity');
                        elements[i].style.removeProperty('visibility');
                        elements[i].style.removeProperty('pointer-events');
                      }
                    } catch(e) {}
                  });
                }
                
                // 1. Apply style override in this frame
                var style = document.getElementById('playback-lock-style-override');
                if (locked) {
                  if (!style) {
                    style = document.createElement('style');
                    style.id = 'playback-lock-style-override';
                    document.head.appendChild(style);
                  }
                  style.innerHTML = `
                    /* JW Player */
                    .jw-controls, .jw-controlbar, .jw-title, .jw-logo,
                    .jw-nextup-container, .jw-display-icon-container,
                    .jw-settings-menu, .jw-settings-submenu, .jw-settings-content,
                    .jw-submenu, .jw-icon-inline, .jw-slider-container, .jw-time-tip,
                    /* Video.js */
                    .vjs-control-bar, .vjs-big-play-button, .vjs-loading-spinner, .vjs-poster,
                    /* Plyr */
                    .plyr__controls,
                    /* Artplayer */
                    .art-control, .art-controls, .art-bottom, .art-progress,
                    .art-state, .art-state-play, .art-play, .art-poster,
                    /* DPlayer */
                    .dplayer-controller, .dplayer-bar-wrap, .dplayer-menu, .dplayer-setting-box,
                    /* Shaka Player */
                    .shaka-bottom-controls, .shaka-settings-menu, .shaka-overflow-menu,
                    /* Cineby-specific */
                    .cb-controlbar, .cb-control, .cb-controls,
                    .player-controlbar, .player-bottom, .player-ui,
                    .video-controlbar, .video-bottombar {
                        display: none !important;
                        opacity: 0 !important;
                        visibility: hidden !important;
                        pointer-events: none !important;
                    }
                  `;
                  
                  // Disable HTML5 native controls programmatically
                  try {
                    var videos = document.querySelectorAll('video');
                    videos.forEach(function(v) {
                      v.controls = false;
                      v.removeAttribute('controls');
                    });
                  } catch (e) {}
                } else {
                  if (style) {
                    style.remove();
                  }
                }
                
                // 2. Forward recursively to all child iframes in this frame
                try {
                  var childIframes = document.querySelectorAll('iframe');
                  for (var i = 0; i < childIframes.length; i++) {
                    childIframes[i].contentWindow.postMessage({ type: 'playbackLock', locked: locked }, '*');
                  }
                } catch (e) {}
              }
            });
          } catch (e) {}
        })();
        """
        let userScript = WKUserScript(source: js, injectionTime: .atDocumentEnd, forMainFrameOnly: false)
        contentController.addUserScript(userScript)

        // Memory-safe LeakAvoider message handler setup
        contentController.add(LeakAvoider(delegate: self), name: "videoDetector")

        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.allowsPictureInPictureMediaPlayback = false
        config.allowsAirPlayForMediaPlayback = false
        if #available(iOS 10.0, *) {
            config.mediaTypesRequiringUserActionForPlayback = []
        }
        config.preferences.javaScriptCanOpenWindowsAutomatically = true
        config.userContentController = contentController

        containerView = UIView()
        containerView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(containerView)

        NSLayoutConstraint.activate([
            containerView.topAnchor.constraint(equalTo: view.topAnchor),
            containerView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            containerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            containerView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])

        webView = WKWebView(frame: .zero, configuration: config)
        webView.translatesAutoresizingMaskIntoConstraints = false
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        webView.scrollView.contentInsetAdjustmentBehavior = .always
        webView.backgroundColor = .systemBackground
        containerView.addSubview(webView)

        webViewConstraints = [
            webView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            webView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ]
        NSLayoutConstraint.activate(webViewConstraints)
    }

    func setupLandingView() {
        landingView = UIView()
        landingView.backgroundColor = UIColor(red: 0.05, green: 0.05, blue: 0.07, alpha: 1.0)
        landingView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(landingView)
        view.bringSubviewToFront(landingView)
        
        NSLayoutConstraint.activate([
            landingView.topAnchor.constraint(equalTo: view.topAnchor),
            landingView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            landingView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            landingView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
        
        let stackView = UIStackView()
        stackView.axis = .vertical
        stackView.alignment = .center
        stackView.spacing = 24
        stackView.translatesAutoresizingMaskIntoConstraints = false
        landingView.addSubview(stackView)
        
        NSLayoutConstraint.activate([
            stackView.centerYAnchor.constraint(equalTo: landingView.centerYAnchor),
            stackView.leadingAnchor.constraint(equalTo: landingView.leadingAnchor, constant: 40),
            stackView.trailingAnchor.constraint(equalTo: landingView.trailingAnchor, constant: -40)
        ])
        
        let titleLabel = UILabel()
        titleLabel.text = "SELECT PORTAL"
        titleLabel.textColor = .white
        titleLabel.font = UIFont.systemFont(ofSize: 26, weight: .black)
        titleLabel.textAlignment = .center
        stackView.addArrangedSubview(titleLabel)
        
        let subtitleLabel = UILabel()
        subtitleLabel.text = "Choose a streaming portal to begin"
        subtitleLabel.textColor = .lightGray
        subtitleLabel.font = UIFont.systemFont(ofSize: 14, weight: .medium)
        subtitleLabel.textAlignment = .center
        stackView.addArrangedSubview(subtitleLabel)
        
        let spacer = UIView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        spacer.heightAnchor.constraint(equalToConstant: 10).isActive = true
        stackView.addArrangedSubview(spacer)
        
        let cinebyButton = createCardButton(
            title: "Cineby",
            subtitle: "Movies & TV Shows",
            accentColor: UIColor.systemRed,
            iconName: "play.fill",
            action: #selector(cinebyCardTapped)
        )
        stackView.addArrangedSubview(cinebyButton)
        
        let nimegamiButton = createCardButton(
            title: "Nimegami",
            subtitle: "Anime Streaming",
            accentColor: UIColor.systemGreen,
            iconName: "globe",
            action: #selector(nimegamiCardTapped)
        )
        stackView.addArrangedSubview(nimegamiButton)
        
        NSLayoutConstraint.activate([
            cinebyButton.widthAnchor.constraint(equalTo: stackView.widthAnchor),
            cinebyButton.heightAnchor.constraint(equalToConstant: 90),
            nimegamiButton.widthAnchor.constraint(equalTo: stackView.widthAnchor),
            nimegamiButton.heightAnchor.constraint(equalToConstant: 90)
        ])
    }
    
    private func createCardButton(title: String, subtitle: String, accentColor: UIColor, iconName: String, action: Selector) -> UIButton {
        let button = UIButton(type: .custom)
        button.backgroundColor = UIColor(white: 0.12, alpha: 0.8)
        button.layer.borderColor = accentColor.cgColor
        button.layer.borderWidth = 1.5
        button.layer.cornerRadius = 16
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: action, for: .touchUpInside)
        
        button.addTarget(self, action: #selector(cardTouchDown(_:)), for: .touchDown)
        button.addTarget(self, action: #selector(cardTouchUp(_:)), for: [.touchUpInside, .touchUpOutside, .touchCancel])
        
        let container = UIStackView()
        container.axis = .horizontal
        container.alignment = .center
        container.spacing = 16
        container.isUserInteractionEnabled = false
        container.translatesAutoresizingMaskIntoConstraints = false
        button.addSubview(container)
        
        NSLayoutConstraint.activate([
            container.leadingAnchor.constraint(equalTo: button.leadingAnchor, constant: 20),
            container.trailingAnchor.constraint(equalTo: button.trailingAnchor, constant: -20),
            container.topAnchor.constraint(equalTo: button.topAnchor, constant: 15),
            container.bottomAnchor.constraint(equalTo: button.bottomAnchor, constant: -15)
        ])
        
        let iconCircle = UIView()
        iconCircle.backgroundColor = accentColor.withAlphaComponent(0.2)
        iconCircle.layer.cornerRadius = 24
        iconCircle.translatesAutoresizingMaskIntoConstraints = false
        iconCircle.widthAnchor.constraint(equalToConstant: 48).isActive = true
        iconCircle.heightAnchor.constraint(equalToConstant: 48).isActive = true
        container.addArrangedSubview(iconCircle)
        
        let iconView = UIImageView()
        let config = UIImage.SymbolConfiguration(pointSize: 18, weight: .bold)
        iconView.image = UIImage(systemName: iconName, withConfiguration: config)
        iconView.tintColor = accentColor
        iconView.contentMode = .scaleAspectFit
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconCircle.addSubview(iconView)
        
        NSLayoutConstraint.activate([
            iconView.centerXAnchor.constraint(equalTo: iconCircle.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: iconCircle.centerYAnchor)
        ])
        
        let textStack = UIStackView()
        textStack.axis = .vertical
        textStack.alignment = .leading
        textStack.spacing = 4
        textStack.translatesAutoresizingMaskIntoConstraints = false
        container.addArrangedSubview(textStack)
        
        let label = UILabel()
        label.text = title
        label.textColor = .white
        label.font = UIFont.systemFont(ofSize: 20, weight: .bold)
        textStack.addArrangedSubview(label)
        
        let sublabel = UILabel()
        sublabel.text = subtitle
        sublabel.textColor = .lightGray
        sublabel.font = UIFont.systemFont(ofSize: 12, weight: .medium)
        textStack.addArrangedSubview(sublabel)
        
        return button
    }

    @objc private func cardTouchDown(_ sender: UIButton) {
        UIView.animate(withDuration: 0.1) {
            sender.transform = CGAffineTransform(scaleX: 0.95, y: 0.95)
        }
    }
    
    @objc private func cardTouchUp(_ sender: UIButton) {
        UIView.animate(withDuration: 0.1) {
            sender.transform = .identity
        }
    }
    
    @objc private func cinebyCardTapped() {
        activeSite = .cineby
        adjustButtonConstraintsForActiveSite()
        loadWebApp()
        animateLandingOut()
    }
    
    @objc private func nimegamiCardTapped() {
        activeSite = .nimegami
        adjustButtonConstraintsForActiveSite()
        loadWebApp()
        animateLandingOut()
    }
    
    private func animateLandingOut() {
        UIView.animate(withDuration: 0.4, animations: {
            self.landingView.alpha = 0
        }) { _ in
            self.landingView.isHidden = true
            self.switchWebButton.isHidden = false
            // Keep portraitRotateButton hidden until a video is detected!
            self.portraitRotateButton.isHidden = true
        }
    }

    func setupSwitchWebButton() {
        switchWebButton = UIButton(type: .system)
        let config = UIImage.SymbolConfiguration(pointSize: 18, weight: .bold, scale: .medium)
        let icon = UIImage(systemName: "arrow.left.arrow.right", withConfiguration: config)
        switchWebButton.setImage(icon, for: .normal)
        switchWebButton.tintColor = .white
        
        switchWebButton.backgroundColor = UIColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 0.8)
        switchWebButton.layer.borderColor = UIColor.white.cgColor
        switchWebButton.layer.borderWidth = 1
        switchWebButton.layer.cornerRadius = 25
        switchWebButton.clipsToBounds = true
        switchWebButton.translatesAutoresizingMaskIntoConstraints = false
        switchWebButton.isHidden = true // hidden initially
        switchWebButton.addTarget(self, action: #selector(switchWebTapped), for: .touchUpInside)
        
        view.addSubview(switchWebButton)
        view.bringSubviewToFront(switchWebButton)
        
        switchButtonTopConstraint = switchWebButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 20)
        NSLayoutConstraint.activate([
            switchWebButton.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -20),
            switchButtonTopConstraint,
            switchWebButton.widthAnchor.constraint(equalToConstant: 50),
            switchWebButton.heightAnchor.constraint(equalToConstant: 50)
        ])
    }

    func setupPortraitRotateButton() {
        portraitRotateButton = UIButton(type: .system)
        let config = UIImage.SymbolConfiguration(pointSize: 18, weight: .bold, scale: .medium)
        let icon = UIImage(systemName: "arrow.triangle.2.circlepath", withConfiguration: config)
        portraitRotateButton.setImage(icon, for: .normal)
        portraitRotateButton.tintColor = .white
        
        portraitRotateButton.backgroundColor = UIColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 0.8)
        portraitRotateButton.layer.borderColor = UIColor.white.cgColor
        portraitRotateButton.layer.borderWidth = 1
        portraitRotateButton.layer.cornerRadius = 25
        portraitRotateButton.clipsToBounds = true
        portraitRotateButton.translatesAutoresizingMaskIntoConstraints = false
        portraitRotateButton.isHidden = true // hidden initially (shown when video is found)
        portraitRotateButton.addTarget(self, action: #selector(portraitRotateTapped), for: .touchUpInside)
        
        view.addSubview(portraitRotateButton)
        view.bringSubviewToFront(portraitRotateButton)
        
        NSLayoutConstraint.activate([
            portraitRotateButton.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -20),
            portraitRotateButton.topAnchor.constraint(equalTo: switchWebButton.bottomAnchor, constant: 15),
            portraitRotateButton.widthAnchor.constraint(equalToConstant: 50),
            portraitRotateButton.heightAnchor.constraint(equalToConstant: 50)
        ])
    }

    func setupLandscapeRotateButton() {
        landscapeRotateButton = UIButton(type: .system)
        let config = UIImage.SymbolConfiguration(pointSize: 18, weight: .bold, scale: .medium)
        let icon = UIImage(systemName: "arrow.triangle.2.circlepath", withConfiguration: config)
        landscapeRotateButton.setImage(icon, for: .normal)
        landscapeRotateButton.tintColor = .white
        
        landscapeRotateButton.backgroundColor = UIColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 0.8)
        landscapeRotateButton.layer.borderColor = UIColor.white.cgColor
        landscapeRotateButton.layer.borderWidth = 1
        landscapeRotateButton.layer.cornerRadius = 25
        landscapeRotateButton.clipsToBounds = true
        landscapeRotateButton.translatesAutoresizingMaskIntoConstraints = false
        landscapeRotateButton.isHidden = true
        landscapeRotateButton.addTarget(self, action: #selector(landscapeRotateTapped), for: .touchUpInside)
        
        view.addSubview(landscapeRotateButton)
        view.bringSubviewToFront(landscapeRotateButton)
        
        updateRotateButtonConstraints(landscape: false)
    }

    func setupNativeLockButton() {
        nativeLockButton = UIButton(type: .system)
        let config = UIImage.SymbolConfiguration(pointSize: 18, weight: .bold, scale: .medium)
        let icon = UIImage(systemName: "lock.open.fill", withConfiguration: config)
        nativeLockButton.setImage(icon, for: .normal)
        nativeLockButton.tintColor = .white
        
        nativeLockButton.backgroundColor = UIColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 0.8)
        nativeLockButton.layer.borderColor = UIColor.white.cgColor
        nativeLockButton.layer.borderWidth = 1
        nativeLockButton.layer.cornerRadius = 25
        nativeLockButton.clipsToBounds = true
        nativeLockButton.translatesAutoresizingMaskIntoConstraints = false
        nativeLockButton.isHidden = true
        nativeLockButton.addTarget(self, action: #selector(nativeLockTapped), for: .touchUpInside)
        
        view.addSubview(nativeLockButton)
        view.bringSubviewToFront(nativeLockButton)
        
        updateLockButtonConstraints(landscape: false)
    }

    func setupTapGesture() {
        screenTapGesture = UITapGestureRecognizer(target: self, action: #selector(handleScreenTap))
        screenTapGesture.isEnabled = false
        view.addGestureRecognizer(screenTapGesture)
    }

    private func updateRotateButtonConstraints(landscape: Bool) {
        NSLayoutConstraint.deactivate(rotateButtonConstraints)
        
        if landscape {
            // Physical bottom-left of screen acts as visual bottom-right in landscape mode
            rotateButtonConstraints = [
                landscapeRotateButton.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 20),
                landscapeRotateButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -20),
                landscapeRotateButton.widthAnchor.constraint(equalToConstant: 50),
                landscapeRotateButton.heightAnchor.constraint(equalToConstant: 50)
            ]
        } else {
            // Normal bottom-right safe area in portrait
            rotateButtonConstraints = [
                landscapeRotateButton.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -20),
                landscapeRotateButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -20),
                landscapeRotateButton.widthAnchor.constraint(equalToConstant: 50),
                landscapeRotateButton.heightAnchor.constraint(equalToConstant: 50)
            ]
        }
        NSLayoutConstraint.activate(rotateButtonConstraints)
    }

    private func updateLockButtonConstraints(landscape: Bool) {
        NSLayoutConstraint.deactivate(lockButtonConstraints)
        
        if landscape {
            // Physical top-left of screen acts as visual bottom-left in landscape mode
            lockButtonConstraints = [
                nativeLockButton.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 20),
                nativeLockButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 20),
                nativeLockButton.widthAnchor.constraint(equalToConstant: 50),
                nativeLockButton.heightAnchor.constraint(equalToConstant: 50)
            ]
        } else {
            // Normal bottom-left safe area in portrait (though hidden)
            lockButtonConstraints = [
                nativeLockButton.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 20),
                nativeLockButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -20),
                nativeLockButton.widthAnchor.constraint(equalToConstant: 50),
                nativeLockButton.heightAnchor.constraint(equalToConstant: 50)
            ]
        }
        NSLayoutConstraint.activate(lockButtonConstraints)
    }

    func loadWebApp() {
        var urlString = ""
        switch activeSite {
        case .cineby:
            urlString = "https://cineby.at"
        case .nimegami:
            urlString = "https://nimegami.id/"
        case .none:
            return
        }
        
        if let url = URL(string: urlString) {
            webView.load(URLRequest(url: url))
        }
    }

    @objc func portraitRotateTapped() {
        NSLog("portraitRotateTapped called")
        setOrientationVisual(true)
    }

    @objc func landscapeRotateTapped() {
        NSLog("landscapeRotateTapped called")
        setOrientationVisual(false)
    }

    @objc func switchWebTapped() {
        NSLog("switchWebTapped called")
        
        UIView.transition(with: self.webView, duration: 0.4, options: .transitionCrossDissolve, animations: {
            if self.activeSite == .cineby {
                self.activeSite = .nimegami
            } else {
                self.activeSite = .cineby
            }
            self.adjustButtonConstraintsForActiveSite()
            self.loadWebApp()
        }, completion: nil)
    }

    private func adjustButtonConstraintsForActiveSite() {
        let targetConstant: CGFloat = (activeSite == .nimegami) ? 80 : 20
        UIView.animate(withDuration: 0.3) {
            self.switchButtonTopConstraint.constant = targetConstant
            self.view.layoutIfNeeded()
        }
    }

    @objc func nativeLockTapped() {
        NSLog("nativeLockTapped called")
        isPlaybackLocked.toggle()
        
        let config = UIImage.SymbolConfiguration(pointSize: 18, weight: .bold, scale: .medium)
        
        if isPlaybackLocked {
            let lockIcon = UIImage(systemName: "lock.fill", withConfiguration: config)
            nativeLockButton.setImage(lockIcon, for: .normal)
            nativeLockButton.backgroundColor = UIColor(red: 0.8, green: 0.2, blue: 0.2, alpha: 0.9)
            nativeLockButton.layer.borderColor = UIColor.red.cgColor
            nativeLockButton.alpha = 1.0
            nativeLockButton.isUserInteractionEnabled = true
            
            landscapeRotateButton.isHidden = true
            webView.isUserInteractionEnabled = false
            screenTapGesture.isEnabled = true
            
            resetUnlockAutoHideTimer()
        } else {
            let unlockIcon = UIImage(systemName: "lock.open.fill", withConfiguration: config)
            nativeLockButton.setImage(unlockIcon, for: .normal)
            nativeLockButton.backgroundColor = UIColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 0.8)
            nativeLockButton.layer.borderColor = UIColor.white.cgColor
            nativeLockButton.alpha = 1.0
            nativeLockButton.isUserInteractionEnabled = true
            
            landscapeRotateButton.isHidden = false
            webView.isUserInteractionEnabled = true
            screenTapGesture.isEnabled = false
            
            stopUnlockAutoHideTimer()
        }
        
        // Broadcast the lock message to all frames instantly
        broadcastPlaybackLockState(isPlaybackLocked)
    }

    private func broadcastPlaybackLockState(_ locked: Bool) {
        let js = """
        (function() {
            var locked = \(locked);
            function broadcastLock(win, locked) {
                try {
                    win.postMessage({ type: 'playbackLock', locked: locked }, '*');
                } catch (e) {}
                try {
                    var length = win.frames.length;
                    for (var i = 0; i < length; i++) {
                        try {
                            broadcastLock(win.frames[i], locked);
                        } catch (e) {}
                    }
                } catch (e) {}
            }
            broadcastLock(window, locked);
        })();
        """
        webView.evaluateJavaScript(js, completionHandler: nil)
    }

    private func resetUnlockAutoHideTimer() {
        stopUnlockAutoHideTimer()
        unlockAutoHideTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            UIView.animate(withDuration: 0.3) {
                self.nativeLockButton.alpha = 0
            } completion: { _ in
                self.nativeLockButton.isUserInteractionEnabled = false
            }
        }
    }

    private func stopUnlockAutoHideTimer() {
        unlockAutoHideTimer?.invalidate()
        unlockAutoHideTimer = nil
    }

    @objc func handleScreenTap() {
        NSLog("handleScreenTap called")
        
        let newAlpha: CGFloat = nativeLockButton.alpha == 0 ? 1.0 : 0.0
        
        UIView.animate(withDuration: 0.3) {
            self.nativeLockButton.alpha = newAlpha
        } completion: { _ in
            self.nativeLockButton.isUserInteractionEnabled = (newAlpha > 0)
        }
        
        if newAlpha > 0 {
            resetUnlockAutoHideTimer()
        } else {
            stopUnlockAutoHideTimer()
        }
    }

    func updateRotateButtonVisibility(hasVideo: Bool) {
        self.hasActiveVideo = hasVideo
        
        // Only toggle visibility in portrait mode.
        // In landscape, we let setOrientationVisual layout determine button visibility.
        if !isLandscapeRotated {
            UIView.animate(withDuration: 0.3) {
                self.portraitRotateButton.isHidden = !hasVideo
            }
        }
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        if message.name == "videoDetector" {
            guard let body = message.body as? [String: Any] else { return }
            
            if let hasVideo = body["hasVideo"] as? Bool {
                NSLog("videoDetector received hasVideo: \(hasVideo)")
                updateRotateButtonVisibility(hasVideo: hasVideo)
            }
            
            if let triggerRotation = body["triggerRotation"] as? Bool, triggerRotation {
                NSLog("videoDetector received triggerRotation request")
                if !isLandscapeRotated {
                    setOrientationVisual(true)
                }
            }
            
            if let frameLoaded = body["frameLoaded"] as? Bool, frameLoaded {
                NSLog("videoDetector received frameLoaded. isPlaybackLocked = \(isPlaybackLocked)")
                if isPlaybackLocked {
                    broadcastPlaybackLockState(true)
                }
            }
        }
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        NSLog("didStartProvisionalNavigation - resetting rotate button until video is found")
        updateRotateButtonVisibility(hasVideo: false)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        NSLog("didFinishNavigation - re-injecting controls hide CSS")
        reinjectControlsHide()
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        NSLog("didCommit - re-injecting controls hide CSS early")
        reinjectControlsHide()
    }

    private func reinjectControlsHide() {
        let js = """
        (function() {
          try {
            var css = [
              'video::-webkit-media-controls{display:none!important}',
              'video::-webkit-media-controls-enclosure{display:none!important}',
              'video::-webkit-media-controls-panel{display:none!important}',
              'video::-webkit-media-controls-play-button{display:none!important}',
              'video::-webkit-media-controls-overlay-play-button{display:none!important}',
              'video::-webkit-media-controls-start-playback-button{display:none!important}',
              'video::-webkit-media-controls-timeline{display:none!important}',
              'video::-webkit-media-controls-volume-slider{display:none!important}',
              'video::-webkit-media-controls-fullscreen-button{display:none!important}',
              '.jw-controls,.jw-controlbar,.vjs-control-bar,.vjs-big-play-button',
              ',.plyr__controls,.plyr__play-large,.plyr__control--overlaid',
              ',.art-control,.art-controls,.art-bottom,.art-progress,.art-state,.art-play,.art-poster,.art-layer,.art-layers',
              ',.dplayer-controller,.dplayer-bar-wrap',
              ',.shaka-bottom-controls,.shaka-settings-menu',
              ',.fp-controls,.fp-ui',
              ',.player-controls,.player-controlbar,.player-bottom,.player-ui',
              ',.video-controls,.video-controlbar,.video-bottombar',
              ',[class*=controlbar]:not(#mstream-controls-overlay)',
              ',[class*=control-bar]:not(#mstream-controls-overlay)',
              ',[class*=player-control]:not(#mstream-controls-overlay)',
              ',[class*=video-control]:not(#mstream-controls-overlay)',
              '{display:none!important;opacity:0!important;visibility:hidden!important;pointer-events:none!important}',
              '#mstream-controls-overlay{display:flex!important;visibility:visible!important;pointer-events:auto!important}',
              '#mstream-controls-overlay *{display:flex!important;visibility:visible!important;pointer-events:auto!important}',
              '#mstream-controls-overlay[style*="opacity: 0"],#mstream-controls-overlay[style*="opacity:0"]{opacity:0!important;pointer-events:none!important}'
            ].join('');

            var s = document.getElementById('mstream-reinject-hide');
            if (!s) {
              s = document.createElement('style');
              s.id = 'mstream-reinject-hide';
              (document.head || document.documentElement).appendChild(s);
            }
            s.textContent = css;

            document.querySelectorAll('video').forEach(function(v) {
              v.removeAttribute('controls');
            });
          } catch(e) {}
        })();
        """
        webView.evaluateJavaScript(js, completionHandler: nil)
    }

    func setOrientationVisual(_ landscape: Bool) {
        self.isLandscapeRotated = landscape
        
        // Reset lock when exiting landscape
        if !landscape {
            isPlaybackLocked = false
            webView.isUserInteractionEnabled = true
            screenTapGesture.isEnabled = false
            stopUnlockAutoHideTimer()
            
            let config = UIImage.SymbolConfiguration(pointSize: 18, weight: .bold, scale: .medium)
            let unlockIcon = UIImage(systemName: "lock.open.fill", withConfiguration: config)
            nativeLockButton.setImage(unlockIcon, for: .normal)
            nativeLockButton.backgroundColor = UIColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 0.8)
            nativeLockButton.layer.borderColor = UIColor.white.cgColor
            nativeLockButton.alpha = 1.0
            nativeLockButton.isUserInteractionEnabled = true
            nativeLockButton.isHidden = true
            
            // Broadcast unlock state to clear styles
            broadcastPlaybackLockState(false)
        }
        
        // Update content inset adjustment behavior
        webView.scrollView.contentInsetAdjustmentBehavior = landscape ? .never : .always
        if landscape {
            webView.scrollView.contentInset = .zero
            webView.scrollView.scrollIndicatorInsets = .zero
        }
        
        UIView.animate(withDuration: 0.3) {
            if landscape {
                NSLayoutConstraint.deactivate(self.webViewConstraints)
                self.webView.translatesAutoresizingMaskIntoConstraints = true
                
                self.webView.transform = CGAffineTransform(rotationAngle: .pi / 2)
                
                let containerSize = self.containerView.bounds.size
                self.webView.bounds = CGRect(x: 0, y: 0, width: containerSize.height, height: containerSize.width)
                self.webView.center = CGPoint(x: containerSize.width / 2, y: containerSize.height / 2)
                
                self.landscapeRotateButton.transform = CGAffineTransform(rotationAngle: .pi / 2)
                self.landscapeRotateButton.isHidden = false
                
                self.nativeLockButton.transform = CGAffineTransform(rotationAngle: .pi / 2)
                self.nativeLockButton.alpha = 1.0
                self.nativeLockButton.isUserInteractionEnabled = true
                self.nativeLockButton.isHidden = false
                
                self.portraitRotateButton.isHidden = true
                self.switchWebButton.isHidden = true
            } else {
                self.webView.transform = .identity
                self.landscapeRotateButton.transform = .identity
                self.landscapeRotateButton.isHidden = true
                
                self.nativeLockButton.transform = .identity
                self.nativeLockButton.isHidden = true
                
                // Restore portrait state: Switch button is visible,
                // Rotate button is only visible if a video was actively detected.
                self.portraitRotateButton.isHidden = !self.hasActiveVideo
                self.switchWebButton.isHidden = false
                
                self.webView.translatesAutoresizingMaskIntoConstraints = false
                NSLayoutConstraint.activate(self.webViewConstraints)
            }
            
            self.navigationController?.setNavigationBarHidden(true, animated: false)
            self.isFullscreen = landscape
            self.setNeedsStatusBarAppearanceUpdate()
            
            self.updateRotateButtonConstraints(landscape: landscape)
            self.updateLockButtonConstraints(landscape: landscape)
            
            self.view.layoutIfNeeded()
        }
        
        // Inject JS to update the viewport meta tag and force full size
        let width = landscape ? max(view.bounds.width, view.bounds.height) : min(view.bounds.width, view.bounds.height)
        let height = landscape ? min(view.bounds.width, view.bounds.height) : max(view.bounds.width, view.bounds.height)
        
        let js = """
        (function() {
            var meta = document.querySelector('meta[name="viewport"]');
            if (!meta) {
                meta = document.createElement('meta');
                meta.name = 'viewport';
                document.getElementsByTagName('head')[0].appendChild(meta);
            }
            if (\(landscape)) {
                meta.setAttribute('content', 'width=\(width), height=\(height), initial-scale=1.0, maximum-scale=1.0, user-scalable=no, viewport-fit=cover');
                
                // Force HTML, Body, and active video frame to be full screen
                var style = document.getElementById('fullscreen-override-style');
                if (!style) {
                    style = document.createElement('style');
                    style.id = 'fullscreen-override-style';
                    document.head.appendChild(style);
                }
                style.innerHTML = 'html, body { width: 100% !important; height: 100% !important; margin: 0 !important; padding: 0 !important; overflow: hidden !important; background: #000 !important; } iframe.active-video-player { position: fixed !important; top: 0 !important; left: 0 !important; width: 100% !important; height: 100% !important; z-index: 999999 !important; background: #000 !important; border: none !important; } video { position: fixed !important; top: 0 !important; left: 0 !important; width: 100% !important; height: 100% !important; z-index: 999999 !important; background: #000 !important; object-fit: contain !important; }';
            } else {
                meta.setAttribute('content', 'width=device-width, initial-scale=1.0, viewport-fit=cover');
                var style = document.getElementById('fullscreen-override-style');
                if (style) {
                    style.remove();
                }
            }
            // Trigger a resize event so the web player adjusts
            window.dispatchEvent(new Event('resize'));
        })();
        """
        webView.evaluateJavaScript(js, completionHandler: nil)
    }

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        return .portrait
    }

    override var shouldAutorotate: Bool {
        return false
    }

    override var prefersStatusBarHidden: Bool {
        return isFullscreen
    }

    private func isTrustedURL(_ url: URL) -> Bool {
        guard let host = url.host else { return false }
        let h = host.lowercased()
        return h.contains("cineby") || h.contains("nimegami")
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if navigationAction.targetFrame == nil {
            if let url = navigationAction.request.url {
                if isTrustedURL(url) {
                    webView.load(navigationAction.request)
                }
            }
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if navigationAction.targetFrame == nil {
            if let url = navigationAction.request.url {
                if isTrustedURL(url) {
                    webView.load(navigationAction.request)
                }
            }
        }
        return nil
    }
}
