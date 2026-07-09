import UIKit
import WebKit

class WebViewController: UIViewController, WKNavigationDelegate, WKUIDelegate {
    var webView: WKWebView!
    private var containerView: UIView!
    private var nativeRotateButton: UIButton!
    private var nativeLockButton: UIButton!
    private var isFullscreen = false
    private var isLandscapeRotated = false
    private var isPlaybackLocked = false

    private var webViewConstraints: [NSLayoutConstraint] = []
    private var rotateButtonConstraints: [NSLayoutConstraint] = []
    private var lockButtonConstraints: [NSLayoutConstraint] = []

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        title = "Cineby"

        setupWebView()
        setupNativeRotateButton()
        setupNativeLockButton()
        setupNavigationBarRotateButton()
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
            webView.topAnchor.constraint(equalTo: containerView.topAnchor),
            webView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
            webView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor)
        ]
        NSLayoutConstraint.activate(webViewConstraints)
    }

    func setupNativeRotateButton() {
        nativeRotateButton = UIButton(type: .system)
        nativeRotateButton.setTitle("Portrait ↻", for: .normal)
        nativeRotateButton.setTitleColor(.white, for: .normal)
        nativeRotateButton.backgroundColor = UIColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 0.8)
        nativeRotateButton.layer.borderColor = UIColor.white.cgColor
        nativeRotateButton.layer.borderWidth = 1
        nativeRotateButton.layer.cornerRadius = 10
        nativeRotateButton.titleLabel?.font = UIFont.boldSystemFont(ofSize: 14)
        nativeRotateButton.translatesAutoresizingMaskIntoConstraints = false
        nativeRotateButton.isHidden = true
        nativeRotateButton.addTarget(self, action: #selector(nativeRotateTapped), for: .touchUpInside)
        
        view.addSubview(nativeRotateButton)
        view.bringSubviewToFront(nativeRotateButton)
        
        updateRotateButtonConstraints(landscape: false)
    }

    func setupNativeLockButton() {
        nativeLockButton = UIButton(type: .system)
        nativeLockButton.setTitle("Lock 🔓", for: .normal)
        nativeLockButton.setTitleColor(.white, for: .normal)
        nativeLockButton.backgroundColor = UIColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 0.8)
        nativeLockButton.layer.borderColor = UIColor.white.cgColor
        nativeLockButton.layer.borderWidth = 1
        nativeLockButton.layer.cornerRadius = 10
        nativeLockButton.titleLabel?.font = UIFont.boldSystemFont(ofSize: 14)
        nativeLockButton.translatesAutoresizingMaskIntoConstraints = false
        nativeLockButton.isHidden = true
        nativeLockButton.addTarget(self, action: #selector(nativeLockTapped), for: .touchUpInside)
        
        view.addSubview(nativeLockButton)
        view.bringSubviewToFront(nativeLockButton)
        
        updateLockButtonConstraints(landscape: false)
    }

    func setupNavigationBarRotateButton() {
        let rotateButton = UIBarButtonItem(title: "Rotate ↻", style: .plain, target: self, action: #selector(navigationRotateTapped))
        rotateButton.tintColor = .systemBlue
        self.navigationItem.rightBarButtonItem = rotateButton
    }

    private func updateRotateButtonConstraints(landscape: Bool) {
        NSLayoutConstraint.deactivate(rotateButtonConstraints)
        
        if landscape {
            // Physical bottom-left of screen acts as visual bottom-right in landscape mode
            rotateButtonConstraints = [
                nativeRotateButton.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 20),
                nativeRotateButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -20),
                nativeRotateButton.widthAnchor.constraint(equalToConstant: 100),
                nativeRotateButton.heightAnchor.constraint(equalToConstant: 40)
            ]
        } else {
            // Normal bottom-right safe area in portrait
            rotateButtonConstraints = [
                nativeRotateButton.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -20),
                nativeRotateButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -20),
                nativeRotateButton.widthAnchor.constraint(equalToConstant: 100),
                nativeRotateButton.heightAnchor.constraint(equalToConstant: 40)
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
                nativeLockButton.widthAnchor.constraint(equalToConstant: 100),
                nativeLockButton.heightAnchor.constraint(equalToConstant: 40)
            ]
        } else {
            // Normal bottom-left safe area in portrait (though hidden)
            lockButtonConstraints = [
                nativeLockButton.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 20),
                nativeLockButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -20),
                nativeLockButton.widthAnchor.constraint(equalToConstant: 100),
                nativeLockButton.heightAnchor.constraint(equalToConstant: 40)
            ]
        }
        NSLayoutConstraint.activate(lockButtonConstraints)
    }

    func loadWebApp() {
        if let url = URL(string: "https://cineby.at") {
            webView.load(URLRequest(url: url))
        }
    }

    @objc func nativeRotateTapped() {
        NSLog("nativeRotateTapped called")
        setOrientationVisual(false)
    }

    @objc func navigationRotateTapped() {
        NSLog("navigationRotateTapped called")
        setOrientationVisual(true)
    }

    @objc func nativeLockTapped() {
        NSLog("nativeLockTapped called")
        isPlaybackLocked.toggle()
        
        if isPlaybackLocked {
            nativeLockButton.setTitle("Unlock 🔒", for: .normal)
            nativeLockButton.backgroundColor = UIColor(red: 0.8, green: 0.2, blue: 0.2, alpha: 0.9)
            nativeLockButton.layer.borderColor = UIColor.red.cgColor
            nativeRotateButton.isHidden = true
            webView.isUserInteractionEnabled = false
        } else {
            nativeLockButton.setTitle("Lock 🔓", for: .normal)
            nativeLockButton.backgroundColor = UIColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 0.8)
            nativeLockButton.layer.borderColor = UIColor.white.cgColor
            nativeRotateButton.isHidden = false
            webView.isUserInteractionEnabled = true
        }
    }

    func setOrientationVisual(_ landscape: Bool) {
        self.isLandscapeRotated = landscape
        
        // Reset lock when exiting landscape
        if !landscape {
            isPlaybackLocked = false
            webView.isUserInteractionEnabled = true
            nativeLockButton.setTitle("Lock 🔓", for: .normal)
            nativeLockButton.backgroundColor = UIColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 0.8)
            nativeLockButton.layer.borderColor = UIColor.white.cgColor
            nativeLockButton.isHidden = true
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
                
                self.nativeRotateButton.transform = CGAffineTransform(rotationAngle: .pi / 2)
                self.nativeRotateButton.isHidden = false
                
                self.nativeLockButton.transform = CGAffineTransform(rotationAngle: .pi / 2)
                self.nativeLockButton.isHidden = false
            } else {
                self.webView.transform = .identity
                self.nativeRotateButton.transform = .identity
                self.nativeRotateButton.isHidden = true
                
                self.nativeLockButton.transform = .identity
                self.nativeLockButton.isHidden = true
                
                self.webView.translatesAutoresizingMaskIntoConstraints = false
                NSLayoutConstraint.activate(self.webViewConstraints)
            }
            
            self.navigationController?.setNavigationBarHidden(landscape, animated: true)
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
