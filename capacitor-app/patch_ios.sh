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
    private var rotationLocked = false
    private var lockedOrientation: UIInterfaceOrientationMask = .all
    private var lockButton: UIBarButtonItem!

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        title = "Cineby"

        let contentController = WKUserContentController()
        contentController.add(self, name: "rotate")

        let js = """
        (function() {
          try {
            if (!document.getElementById('nativeRotateBtn')){
              var btn = document.createElement('button');
              btn.id='nativeRotateBtn';
              btn.style.position='fixed';
              btn.style.bottom='20px';
              btn.style.right='20px';
              btn.style.zIndex=2147483647;
              btn.style.padding='10px 12px';
              btn.style.background='rgba(0,0,0,0.6)';
              btn.style.color='#fff';
              btn.style.border='none';
              btn.style.borderRadius='8px';
              btn.style.fontSize='14px';
              btn.innerText='Rotate';
              btn.onclick = function(){ window.webkit.messageHandlers.rotate.postMessage('toggle'); };
              document.body.appendChild(btn);
            }
          } catch(e) { }
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
        view.addSubview(webView)

        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: view.topAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])

        setupNavigationItems()
        loadWebApp()
    }

    private func setupNavigationItems() {
        let rotateButton = UIBarButtonItem(title: "Rotate", style: .plain, target: self, action: #selector(handleRotateTap))
        lockButton = UIBarButtonItem(title: "Lock", style: .plain, target: self, action: #selector(handleLockTap))
        navigationItem.rightBarButtonItems = [lockButton, rotateButton]
    }

    private func loadWebApp() {
        if let url = URL(string: "https://cineby.at") {
            webView.load(URLRequest(url: url))
        }
    }

    @objc private func handleRotateTap() {
        toggleOrientation()
    }

    @objc private func handleLockTap() {
        rotationLocked.toggle()
        if rotationLocked {
            let current = UIDevice.current.orientation
            if current.isLandscape {
                lockedOrientation = .landscape
                setOrientation(.landscapeRight)
            } else {
                lockedOrientation = .portrait
                setOrientation(.portrait)
            }
            lockButton.title = "Locked"
        } else {
            lockedOrientation = .all
            lockButton.title = "Lock"
        }
        UIViewController.attemptRotationToDeviceOrientation()
    }

    private func toggleOrientation() {
        let device = UIDevice.current
        let isPortrait = device.orientation.isPortrait || device.orientation == .unknown
        if isPortrait {
            setOrientation(.landscapeRight)
            if rotationLocked { lockedOrientation = .landscape }
        } else {
            setOrientation(.portrait)
            if rotationLocked { lockedOrientation = .portrait }
        }
    }

    private func setOrientation(_ orientation: UIInterfaceOrientation) {
        UIDevice.current.setValue(orientation.rawValue, forKey: "orientation")
        UIViewController.attemptRotationToDeviceOrientation()
    }

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        return lockedOrientation
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        if message.name == "rotate" {
            toggleOrientation()
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
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "rotate")
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
    private var rotationLocked = false
    private var lockedOrientation: UIInterfaceOrientationMask = .all
    private var lockButton: UIBarButtonItem!

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        title = "Cineby"

        let contentController = WKUserContentController()
        contentController.add(self, name: "rotate")

        let js = """
        (function() {
          try {
            if (!document.getElementById('nativeRotateBtn')){
              var btn = document.createElement('button');
              btn.id='nativeRotateBtn';
              btn.style.position='fixed';
              btn.style.bottom='20px';
              btn.style.right='20px';
              btn.style.zIndex=2147483647;
              btn.style.padding='10px 12px';
              btn.style.background='rgba(0,0,0,0.6)';
              btn.style.color='#fff';
              btn.style.border='none';
              btn.style.borderRadius='8px';
              btn.style.fontSize='14px';
              btn.innerText='Rotate';
              btn.onclick = function(){ window.webkit.messageHandlers.rotate.postMessage('toggle'); };
              document.body.appendChild(btn);
            }
          } catch(e) { }
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
        view.addSubview(webView)

        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: view.topAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])

        setupNavigationItems()
        loadWebApp()
    }

    private func setupNavigationItems() {
        let rotateButton = UIBarButtonItem(title: "Rotate", style: .plain, target: self, action: #selector(handleRotateTap))
        lockButton = UIBarButtonItem(title: "Lock", style: .plain, target: self, action: #selector(handleLockTap))
        navigationItem.rightBarButtonItems = [lockButton, rotateButton]
    }

    private func loadWebApp() {
        if let url = URL(string: "https://cineby.at") {
            webView.load(URLRequest(url: url))
        }
    }

    @objc private func handleRotateTap() {
        toggleOrientation()
    }

    @objc private func handleLockTap() {
        rotationLocked.toggle()
        if rotationLocked {
            let current = UIDevice.current.orientation
            if current.isLandscape {
                lockedOrientation = .landscape
                setOrientation(.landscapeRight)
            } else {
                lockedOrientation = .portrait
                setOrientation(.portrait)
            }
            lockButton.title = "Locked"
        } else {
            lockedOrientation = .all
            lockButton.title = "Lock"
        }
        UIViewController.attemptRotationToDeviceOrientation()
    }

    private func toggleOrientation() {
        let device = UIDevice.current
        let isPortrait = device.orientation.isPortrait || device.orientation == .unknown
        if isPortrait {
            setOrientation(.landscapeRight)
            if rotationLocked { lockedOrientation = .landscape }
        } else {
            setOrientation(.portrait)
            if rotationLocked { lockedOrientation = .portrait }
        }
    }

    private func setOrientation(_ orientation: UIInterfaceOrientation) {
        UIDevice.current.setValue(orientation.rawValue, forKey: "orientation")
        UIViewController.attemptRotationToDeviceOrientation()
    }

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        return lockedOrientation
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        if message.name == "rotate" {
            toggleOrientation()
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
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "rotate")
    }
}
EOF
fi

chmod +x "$BASE_DIR/patch_ios.sh"
