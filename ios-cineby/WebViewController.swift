import UIKit
import WebKit

class WebViewController: UIViewController, WKScriptMessageHandler, WKNavigationDelegate, WKUIDelegate {
    var webView: WKWebView!
    private var nativeRotateButton: UIButton!
    private var isFullscreen = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        title = "Cineby"

        setupWebView()
        setupNativeRotateButton()
        loadWebApp()
    }

    func setupWebView() {
        let contentController = WKUserContentController()
        contentController.add(self, name: "videoVisibility")
        contentController.add(self, name: "fullscreenState")

        let js = """
        (function() {
          try {
            function hasVisibleVideo() {
              var videos = Array.from(document.querySelectorAll('video'));
              return videos.some(function(video) {
                var rect = video.getBoundingClientRect();
                var style = window.getComputedStyle(video);
                return rect.width > 100 && rect.height > 50 &&
                  rect.bottom > 0 && rect.right > 0 &&
                  rect.top < window.innerHeight && rect.left < window.innerWidth &&
                  style.visibility !== 'hidden' && style.display !== 'none';
              });
            }

                        var last = null;
                        function update() {
                            var v = hasVisibleVideo();
                            if (v !== last) {
                                try { window.webkit.messageHandlers.videoVisibility.postMessage(v); } catch(e){}
                                last = v;
                            }
                        }

            var observer = new MutationObserver(update);
            observer.observe(document.body, { childList: true, subtree: true, attributes: true, attributeFilter: ['style', 'class'] });
            window.addEventListener('resize', update);
            window.addEventListener('scroll', update);
                        function postFullscreen() {
                            var fs = !!(document.fullscreenElement || document.webkitFullscreenElement || document.webkitIsFullScreen);
                            try { window.webkit.messageHandlers.fullscreenState.postMessage(fs); } catch(e){}
                        }
                        document.addEventListener('fullscreenchange', function(){ update(); postFullscreen(); });
                        document.addEventListener('webkitfullscreenchange', function(){ update(); postFullscreen(); });
            update();
          } catch (e) { }
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

        webView = WKWebView(frame: .zero, configuration: config)
        webView.translatesAutoresizingMaskIntoConstraints = false
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        webView.scrollView.contentInsetAdjustmentBehavior = .always
        webView.backgroundColor = .systemBackground
        view.addSubview(webView)

        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            webView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            webView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor)
        ])
    }

    func setupNativeRotateButton() {
        nativeRotateButton = UIButton(type: .system)
        nativeRotateButton.setTitle("Rotate", for: .normal)
        nativeRotateButton.setTitleColor(.white, for: .normal)
        nativeRotateButton.backgroundColor = UIColor(white: 0, alpha: 0.6)
        nativeRotateButton.layer.cornerRadius = 8
        nativeRotateButton.translatesAutoresizingMaskIntoConstraints = false
        nativeRotateButton.isHidden = true
        nativeRotateButton.addTarget(self, action: #selector(nativeRotateTapped), for: .touchUpInside)
        view.addSubview(nativeRotateButton)

        // Ensure button is above the web view
        view.bringSubviewToFront(nativeRotateButton)

        NSLayoutConstraint.activate([
            nativeRotateButton.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            nativeRotateButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16),
            nativeRotateButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 72),
            nativeRotateButton.heightAnchor.constraint(equalToConstant: 40)
        ])
    }

    func loadWebApp() {
        if let url = URL(string: "https://cineby.at") {
            webView.load(URLRequest(url: url))
        }
    }

    @objc func nativeRotateTapped() {
        NSLog("nativeRotateTapped called")
        toggleOrientation()
    }

    func toggleOrientation() {
        let isPortrait: Bool
        if let scene = view.window?.windowScene {
            isPortrait = scene.interfaceOrientation.isPortrait
        } else {
            let device = UIDevice.current
            isPortrait = device.orientation.isPortrait || device.orientation == .unknown
        }
        NSLog("toggleOrientation: isPortrait=\(isPortrait)")
        if isPortrait {
            setOrientation(.landscapeRight)
        } else {
            setOrientation(.portrait)
        }
    }

    func setOrientation(_ orientation: UIInterfaceOrientation) {
        UIDevice.current.setValue(orientation.rawValue, forKey: "orientation")
        UIViewController.attemptRotationToDeviceOrientation()
    }

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        return .all
    }

    override var shouldAutorotate: Bool {
        return true
    }

    // MARK: WKScriptMessageHandler
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        if message.name == "videoVisibility" {
            if let visible = message.body as? Bool {
                DispatchQueue.main.async {
                    NSLog("videoVisibility -> \(visible)")
                    self.nativeRotateButton.isHidden = !visible
                }
            }
            return
        }
        if message.name == "fullscreenState" {
            if let fs = message.body as? Bool {
                DispatchQueue.main.async {
                    NSLog("fullscreenState -> \(fs)")
                    self.isFullscreen = fs
                    self.setNeedsStatusBarAppearanceUpdate()
                }
            }
            return
        }
    }

    override var prefersStatusBarHidden: Bool {
        return isFullscreen
    }

    // MARK: WKNavigationDelegate
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if navigationAction.targetFrame == nil {
            webView.load(navigationAction.request)
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }

    // MARK: WKUIDelegate
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if navigationAction.targetFrame == nil {
            webView.load(navigationAction.request)
        }
        return nil
    }

    deinit {
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "videoVisibility")
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "fullscreenState")
    }
}
