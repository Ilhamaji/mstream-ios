# Cineby — Capacitor scaffold

This scaffold helps you develop on Windows and prepare an iOS build in the cloud.

What this contains

- Minimal static web UI with `Rotate` / `Fullscreen Video` controls.
- `capacitor.config.json` pre-set to load `https://cineby.at` when used as a native app.

Quick start (Windows)

1. Run dev server to preview web UI:

```bash
cd d:/code/App/cineby/capacitor-app
npx http-server ./ -p 8080 -c-1
# open http://localhost:8080
```

2. To create a Capacitor project and connect web assets (on Windows you can prepare assets but cannot add iOS platform locally):

```bash
npm install --save @capacitor/core @capacitor/cli
npx cap init
# when asked, set webDir to './' (or keep default)
npx cap add android   # optional: you can build Android locally on Windows
```

3. iOS builds (since you are on Windows):

- Option A — Use cloud macOS CI: GitHub Actions with macOS runner or EAS Build (Expo Application Services). These can run `npx cap add ios` and build an `.ipa`.
- Option B — Rent a mac (MacStadium, MacInCloud) and run Xcode to add iOS platform and customize native code.

Notes on enabling rotate/fullscreen in native iOS:

- The web-only `screen.orientation.lock()` may not work on iOS Safari or when the WebView is loading a remote site.
- To programmatically override device orientation inside the native iOS WebView, you need a native injection (see `d:/code/App/cineby/ios-cineby/WebViewController.swift`) or install a screen-orientation plugin (`cordova-plugin-screen-orientation`) and call it from JavaScript.
- If you are working locally on macOS, run `bash patch_ios.sh` after `npx cap copy ios` to inject the native WKWebView wrapper into the generated iOS project. The GitHub Actions workflow already runs this script before building the `.ipa`.

Example: install Cordova plugin and call from JS (after adding iOS platform on macOS):

```bash
npx cap sync ios
# then in Xcode open ios/App/App.xcworkspace and add the plugin
npm install cordova-plugin-screen-orientation
```

Then call from the web code:

```js
if (window.cordova && window.screen && window.screen.orientation) {
  window.screen.orientation.lock("landscape");
}
```

If you want, I can:

- scaffold a GitHub Actions workflow to build iOS using a macOS runner, or
- scaffold an EAS Build config to produce iOS builds from your repo.

I already added a starter GitHub Actions workflow in the repo root at `.github/workflows/ios-build.yml` that runs Fastlane to build an `.ipa` and upload to TestFlight.

Required GitHub Secrets (set these in your repository Settings → Secrets):

- `MATCH_GIT_URL`: (optional) Git URL for Fastlane Match certificates repository.
- `MATCH_PASSWORD`: Password for Match repository encryption.
- `APP_STORE_CONNECT_API_KEY`: App Store Connect API key JSON (store as secret; Fastlane can use it).
- `FASTLANE_USER`: Your Apple ID email.

How to create a Match repo (quick):

1. On a Mac with Fastlane installed run:

```bash
fastlane match init
# follow prompts to create a private git repo for certs
```

2. Add your repo URL to the GitHub secret `MATCH_GIT_URL`. Use an HTTPS URL that includes a token if your repo is private and you don't want to configure SSH on the runner.

3. Ensure `MATCH_PASSWORD` is set (used to encrypt certificates in the repo).

Notes:

- In CI we run `match` in `readonly` mode; ensure the match repo already contains the certificates & provisioning profiles for your app.
- If you cannot or prefer not to use Match, you can provide signing files manually in the workflow or use App Store Connect API key with `FASTLANE_USER`.

If you prefer sideload testing instead of TestFlight, run the workflow to produce an `.ipa`, download the artifact, then install using Sideloadly from Windows.
