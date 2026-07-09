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

            // Listen for messages from child frames to mark active iframe player
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
                    .art-control, .art-controls, .art-mask, .art-state, .art-state-play, .art-play, .art-poster, .art-bottom, .art-progress,
                    [class*="control" i], 
                    [class*="toolbar" i], 
                    [class*="play-button" i], 
                    [class*="play-icon" i], 
                    [class*="play-btn" i], 
                    [class*="playbutton" i], 
                    [class*="playButton" i], 
                    [class*="big-play" i], 
                    [class*="display-icon" i],
                    [class*="display-btn" i],
                    [class*="overlay" i], 
                    [class*="mask" i], 
                    [class*="poster" i], 
                    [class*="preview" i],
                    [class*="spinner" i],
                    [class*="loading" i],
                    [class*="player-controls" i],
                    [class*="video-controls" i],
                    [class*="button" i],
                    [class*="btn" i],
                    [class*="progress" i],
                    [class*="volume" i],
                    [class*="time" i],
                    [class*="title" i],
                    [class*="logo" i],
                    [class*="menu" i],
                    [class*="settings" i],
                    [class*="setting" i],
                    [class*="bottom-bar" i],
                    [class*="control-bar" i],
                    [class*="controls-bar" i],
                    [class*="player-bar" i],
                    [class*="bottom-controls" i],
                    [class*="controller" i],
                    [class*="dplayer" i],
                    [class*="shaka" i] {
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
        }
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        NSLog("didStartProvisionalNavigation - resetting rotate button until video is found")
        updateRotateButtonVisibility(hasVideo: false)
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
