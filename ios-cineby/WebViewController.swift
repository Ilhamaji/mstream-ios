import UIKit
import WebKit

class WebViewController: UIViewController, WKNavigationDelegate, WKUIDelegate {
    var webView: WKWebView!
    private var containerView: UIView!
    private var portraitRotateButton: UIButton!
    private var landscapeRotateButton: UIButton!
    private var nativeLockButton: UIButton!
    private var isFullscreen = false
    private var isLandscapeRotated = false
    private var isPlaybackLocked = false
    
    private var unlockAutoHideTimer: Timer?
    private var screenTapGesture: UITapGestureRecognizer!

    private var webViewConstraints: [NSLayoutConstraint] = []
    private var rotateButtonConstraints: [NSLayoutConstraint] = []
    private var lockButtonConstraints: [NSLayoutConstraint] = []

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        self.navigationController?.setNavigationBarHidden(true, animated: false)

        setupWebView()
        setupPortraitRotateButton()
        setupLandscapeRotateButton()
        setupNativeLockButton()
        setupTapGesture()
        loadWebApp()
    }

    func setupWebView() {
        let contentController = WKUserContentController()
        
        let js = """
        (function() {
          try {
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

            // Listen for playback lock messages and forward recursively
            window.addEventListener('message', function(event) {
              if (event.data && event.data.type === 'playbackLock') {
                var locked = event.data.locked;
                
                // 1. Apply style override in this frame
                var style = document.getElementById('playback-lock-style-override');
                if (locked) {
                  if (!style) {
                    style = document.createElement('style');
                    style.id = 'playback-lock-style-override';
                    document.head.appendChild(style);
                  }
                  style.innerHTML = `
                    .jw-controls, .jw-controlbar, .jw-title, .jw-logo, .jw-nextup-container, .jw-display, .jw-display-icon, .jw-display-icon-container,
                    .vjs-control-bar, .vjs-big-play-button, .vjs-loading-spinner, .vjs-poster,
                    .plyr__controls, 
                    .art-control, .art-controls, .art-mask, .art-state, .art-state-play, .art-play, .art-poster,
                    div[class*="control" i], 
                    div[class*="toolbar" i], 
                    [class*="play-button" i], 
                    [class*="play-icon" i], 
                    [class*="play-btn" i], 
                    [class*="playbutton" i], 
                    [class*="playButton" i], 
                    [class*="big-play" i], 
                    [class*="display-icon" i],
                    [class*="display-btn" i],
                    div[class*="overlay" i], 
                    div[class*="mask" i], 
                    div[class*="poster" i], 
                    div[class*="preview" i],
                    div[class*="spinner" i],
                    div[class*="loading" i],
                    [class*="player-controls" i],
                    [class*="video-controls" i] {
                        display: none !important;
                        opacity: 0 !important;
                        visibility: hidden !important;
                        pointer-events: none !important;
                    }
                  `;
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

        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
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
        portraitRotateButton.isHidden = false
        portraitRotateButton.addTarget(self, action: #selector(portraitRotateTapped), for: .touchUpInside)
        
        view.addSubview(portraitRotateButton)
        view.bringSubviewToFront(portraitRotateButton)
        
        NSLayoutConstraint.activate([
            portraitRotateButton.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -20),
            portraitRotateButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 20),
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
        if let url = URL(string: "https://cineby.at") {
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
            // Send to current window
            window.postMessage({ type: 'playbackLock', locked: locked }, '*');
            // Send to all child iframes
            var iframes = document.querySelectorAll('iframe');
            for (var i = 0; i < iframes.length; i++) {
                try {
                    iframes[i].contentWindow.postMessage({ type: 'playbackLock', locked: locked }, '*');
                } catch (e) {}
            }
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
            } else {
                self.webView.transform = .identity
                self.landscapeRotateButton.transform = .identity
                self.landscapeRotateButton.isHidden = true
                
                self.nativeLockButton.transform = .identity
                self.nativeLockButton.isHidden = true
                
                self.portraitRotateButton.isHidden = false
                
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
                
                // Force HTML and Body to be full screen
                var style = document.getElementById('fullscreen-override-style');
                if (!style) {
                    style = document.createElement('style');
                    style.id = 'fullscreen-override-style';
                    document.head.appendChild(style);
                }
                style.innerHTML = 'html, body { width: 100% !important; height: 100% !important; margin: 0 !important; padding: 0 !important; overflow: hidden !important; } video { object-fit: contain !important; }';
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
        return host.lowercased().contains("cineby")
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
