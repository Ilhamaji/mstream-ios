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

SRC_DIR="$BASE_DIR/../ios-cineby"
if [ ! -d "$SRC_DIR" ]; then
  echo "Error: Source directory $SRC_DIR not found."
  exit 1
fi

echo "Copying source files from $SRC_DIR to $TARGET_DIR..."
cp "$SRC_DIR/WebViewController.swift" "$TARGET_DIR/WebViewController.swift"
cp "$SRC_DIR/OrientationNavigationController.swift" "$TARGET_DIR/OrientationNavigationController.swift"

if [ -f "$TARGET_DIR/SceneDelegate.swift" ]; then
  echo "Target project uses SceneDelegate. Copying SceneDelegate.swift..."
  cp "$SRC_DIR/SceneDelegate.swift" "$TARGET_DIR/SceneDelegate.swift"
  cp "$SRC_DIR/AppDelegate.swift" "$TARGET_DIR/AppDelegate.swift"
else
  echo "Target project uses AppDelegate-only. Modifying AppDelegate.swift..."
  cat > "$TARGET_DIR/AppDelegate.swift" <<'EOF'
import UIKit

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {

    var window: UIWindow?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        if window == nil {
            window = UIWindow(frame: UIScreen.main.bounds)
        }
        window?.rootViewController = OrientationNavigationController(rootViewController: WebViewController())
        window?.makeKeyAndVisible()
        return true
    }

    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        return window?.rootViewController?.supportedInterfaceOrientations ?? .all
    }
}
EOF
fi

echo "Successfully patched iOS project."
