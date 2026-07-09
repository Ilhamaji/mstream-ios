#!/usr/bin/env bash
set -e

BASE_DIR="$(cd "$(dirname "$0")" && pwd)"
TARGET_DIR=""
for candidate in "$BASE_DIR/ios/App/App" "$BASE_DIR/ios/App"; do
  if [ -d "$candidate" ]; then
    TARGET_DIR="$candidate"
    break
  fi
done

if [ -z "$TARGET_DIR" ]; then
  echo "Error: iOS App target directory not found."
  echo "Checked: $BASE_DIR/ios/App/App and $BASE_DIR/ios/App"
  exit 1
fi

INFO_PLIST="$TARGET_DIR/Info.plist"
if [ -f "$INFO_PLIST" ]; then
  python3 <<PY
import plistlib
from pathlib import Path
p = Path(r"$INFO_PLIST")
data = plistlib.loads(p.read_bytes())
changed = False
screen_orient = ["UIInterfaceOrientationPortrait", "UIInterfaceOrientationLandscapeLeft", "UIInterfaceOrientationLandscapeRight"]
if data.get("UISupportedInterfaceOrientations") != screen_orient:
    data["UISupportedInterfaceOrientations"] = screen_orient
    changed = True
if data.get("UISupportedInterfaceOrientations~ipad") != screen_orient:
    data["UISupportedInterfaceOrientations~ipad"] = screen_orient
    changed = True
if data.get("UIRequiresFullScreen") is not True:
    data["UIRequiresFullScreen"] = True
    changed = True
if data.get("UIViewControllerBasedStatusBarAppearance") is not True:
    data["UIViewControllerBasedStatusBarAppearance"] = True
    changed = True
for key in ["UIMainStoryboardFile", "NSMainStoryboardFile", "UIMainStoryboardFile~ipad"]:
    if key in data:
        del data[key]
        changed = True
if changed:
    p.write_bytes(plistlib.dumps(data))
PY
fi

if [ ! -f "$TARGET_DIR/SceneDelegate.swift" ] && [ ! -f "$TARGET_DIR/AppDelegate.swift" ]; then
  echo "Warning: No SceneDelegate.swift or AppDelegate.swift found in $TARGET_DIR"
fi

if [ -f "$TARGET_DIR/SceneDelegate.swift" ]; then
  cat > "$TARGET_DIR/SceneDelegate.swift" <<'EOF'
import UIKit
import WebKit

class SceneDelegate: UIResponder, UIWindowSceneDelegate {

    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = (scene as? UIWindowScene) else { return }
        let window = UIWindow(windowScene: windowScene)
        let navigationController = UINavigationController(rootViewController: WebViewController())
        window.rootViewController = navigationController
        self.window = window
        window.makeKeyAndVisible()
    }
}

class WebViewController: UIViewController, WKScriptMessageHandler, WKNavigationDelegate, WKUIDelegate {
    var webView: WKWebView!
    private var nativeRotateButton: UIButton!

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        title = "Cineby"

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

                        function postFullscreen() {
                            var fs = !!(document.fullscreenElement || document.webkitFullscreenElement || document.webkitIsFullScreen);
                            try { window.webkit.messageHandlers.fullscreenState.postMessage(fs); } catch(e){}
                        }

                        var observer = new MutationObserver(update);
                        observer.observe(document.body, { childList: true, subtree: true, attributes: true, attributeFilter: ['style', 'class'] });
                        window.addEventListener('resize', update);
                        window.addEventListener('scroll', update);
                        document.addEventListener('fullscreenchange', function(){ update(); postFullscreen(); });
                        document.addEventListener('webkitfullscreenchange', function(){ update(); postFullscreen(); });
                        update(); postFullscreen();
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

        loadWebApp()
    }

    @objc func nativeRotateTapped() {
        let device = UIDevice.current
        let isPortrait = device.orientation.isPortrait || device.orientation == .unknown
        if isPortrait {
            UIDevice.current.setValue(UIInterfaceOrientation.landscapeRight.rawValue, forKey: "orientation")
        } else {
            UIDevice.current.setValue(UIInterfaceOrientation.portrait.rawValue, forKey: "orientation")
        }
        UIViewController.attemptRotationToDeviceOrientation()
    }

    private func loadWebApp() {
        if let url = URL(string: "https://cineby.at") {
            webView.load(URLRequest(url: url))
        }
    }

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        return .all
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        if message.name == "videoVisibility" {
            if let visible = message.body as? Bool {
                DispatchQueue.main.async {
                    self.nativeRotateButton.isHidden = !visible
                }
            }
        }
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if navigationAction.targetFrame == nil {
            webView.load(navigationAction.request)
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }

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
EOF
fi

if [ -f "$TARGET_DIR/AppDelegate.swift" ] && [ ! -f "$TARGET_DIR/SceneDelegate.swift" ]; then
  cat > "$TARGET_DIR/AppDelegate.swift" <<'EOF'
import UIKit
import WebKit

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {

    var window: UIWindow?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        if window == nil {
            window = UIWindow(frame: UIScreen.main.bounds)
        }
        window?.rootViewController = UINavigationController(rootViewController: WebViewController())
        window?.makeKeyAndVisible()
        return true
    }
}

class WebViewController: UIViewController, WKScriptMessageHandler, WKNavigationDelegate, WKUIDelegate {
    var webView: WKWebView!
    private var nativeRotateButton: UIButton!

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        title = "Cineby"

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

                        function postFullscreen() {
                            var fs = !!(document.fullscreenElement || document.webkitFullscreenElement || document.webkitIsFullScreen);
                            try { window.webkit.messageHandlers.fullscreenState.postMessage(fs); } catch(e){}
                        }

                        var observer = new MutationObserver(update);
                        observer.observe(document.body, { childList: true, subtree: true, attributes: true, attributeFilter: ['style', 'class'] });
                        window.addEventListener('resize', update);
                        window.addEventListener('scroll', update);
                        document.addEventListener('fullscreenchange', function(){ update(); postFullscreen(); });
                        document.addEventListener('webkitfullscreenchange', function(){ update(); postFullscreen(); });
                        update(); postFullscreen();
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

        loadWebApp()
    }

    @objc func nativeRotateTapped() {
        let device = UIDevice.current
        let isPortrait = device.orientation.isPortrait || device.orientation == .unknown
        if isPortrait {
            UIDevice.current.setValue(UIInterfaceOrientation.landscapeRight.rawValue, forKey: "orientation")
        } else {
            UIDevice.current.setValue(UIInterfaceOrientation.portrait.rawValue, forKey: "orientation")
        }
        UIViewController.attemptRotationToDeviceOrientation()
    }

    private func loadWebApp() {
        if let url = URL(string: "https://cineby.at") {
            webView.load(URLRequest(url: url))
        }
    }

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        return .all
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        if message.name == "videoVisibility" {
            if let visible = message.body as? Bool {
                DispatchQueue.main.async {
                    self.nativeRotateButton.isHidden = !visible
                }
            }
        }
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if navigationAction.targetFrame == nil {
            webView.load(navigationAction.request)
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }

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
EOF
fi

chmod +x "$BASE_DIR/patch_ios.sh"
