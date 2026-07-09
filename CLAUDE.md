# Mstream iOS — AI Agent Guide

Native iOS WKWebView wrapper untuk Cineby (film/series) dan Nimegami (anime). Seluruh logika ada di **satu file**: `ios-cineby/WebViewController.swift` (~1300 baris).

---

## Struktur Proyek

```
ios-cineby/              ← SATU-SATUNYA folder yang perlu diedit
  WebViewController.swift  ← Seluruh logic app (Swift + JS injeksi)
  OrientationNavigationController.swift
  SceneDelegate.swift
  AppDelegate.swift
capacitor-app/
  patch_ios.sh           ← Script untuk merge source ke Xcode project
  src/                   ← Web assets (tidak dipakai untuk iOS)
```

> **Jangan sentuh** `capacitor-app/ios/` — folder itu hasil generate dari `patch_ios.sh` dan akan overwrite saat build.

---

## Arsitektur: `WebViewController.swift`

### Native Swift (UIKit)

| Komponen | Keterangan |
|---|---|
| `setupWebView()` | Konfigurasi WKWebView + injeksi JS via `WKUserScript` |
| `setupLandingView()` | Portal selection screen (Cineby / Nimegami) |
| `setupSwitchWebButton()` | Floating button top-right, toggle portal |
| `setupPortraitRotateButton()` | Muncul hanya saat video terdeteksi (portrait) |
| `setupLandscapeRotateButton()` | Muncul di landscape mode |
| `setupNativeLockButton()` | Netflix-style playback lock (landscape only) |
| `setOrientationVisual()` | Rotasi visual WebView via `CGAffineTransform` (bukan system rotation) |
| `handleScreenTap()` | Toggle lock button saat layar disentuh |
| `broadcastPlaybackLockState()` | Kirim postMessage ke semua iframe |
| `userContentController()` | Terima pesan dari JS: `hasVideo`, `triggerRotation`, `frameLoaded` |

### JavaScript yang Diinjeksikan (di dalam `setupWebView()`)

Script diinjeksikan ke **semua frame** (`forMainFrameOnly: false`), termasuk iframe player. Fungsi-fungsi utama:

| Fungsi JS | Tujuan |
|---|---|
| `forcePlaysInline()` | Set `playsinline` agar video inline, tidak fullscreen native |
| `injectMstreamControls()` | Inject overlay playback (Back 5s / Play / Forward 5s) ke `document.body` dengan `position:fixed` |
| `hideDefaultControls()` | Sembunyikan control bar bawaan player via CSS spesifik (bukan wildcard) |
| `broadcastActiveSite()` | Beritahu subframes nama site aktif |
| `handleGlobalTouch` | Listener global capture-phase: tap mana saja → tampilkan overlay |
| Pesan `playbackLock` | Lock/unlock semua kontrol bawaan player secara rekursif ke seluruh iframe |

### Overlay Dedicated (`#mstream-controls-overlay`)

- Diappend ke `document.body` dengan **`position: fixed`** — dijamin di atas semua player library
- `freezePlayerInterceptors()`: Saat button disentuh, matikan sementara `pointer-events` pada ancestor video (max 6 level) agar player tidak rebut touch
- `unfreezePlayerInterceptors()`: Restore saat `touchend`
- State play/pause di-sync setiap 500ms via `setInterval`

---

## Variabel State Swift

```swift
activeSite: ActiveSite        // .none / .cineby / .nimegami
isFullscreen: Bool            // landscape mode aktif
isLandscapeRotated: Bool      // WebView sedang dirotasi
isPlaybackLocked: Bool        // Playback lock aktif
hasActiveVideo: Bool          // Video terdeteksi di halaman
```

---

## Alur Deteksi Video

```
JS setInterval (1s) → checkVideoPresence()
  → postMessage { hasVideo: true/false }
    → Swift: userContentController()
      → updateRotateButtonVisibility()
        → portraitRotateButton.isHidden = !hasVideo
```

---

## CSS Hiding Strategy

Gunakan **class name spesifik** per player library — JANGAN wildcard `[class*="..."]` karena akan menyembunyikan layer render video dan membuat layar hitam, serta memblokir overlay kita sendiri.

Player yang di-support: JW Player, Video.js, Plyr, Artplayer, DPlayer, Shaka Player.

CSS selalu mengandung exception eksplisit:
```css
#mstream-controls-overlay, #mstream-controls-overlay * {
    display: flex !important;
    pointer-events: auto !important;
}
```

---

## Cara Deploy / Build

```bash
# Di dalam folder capacitor-app/
bash patch_ios.sh
# Lalu buka ios/App/App.xcworkspace di Xcode dan build
```

Script `patch_ios.sh` akan merge `ios-cineby/WebViewController.swift` ke dalam `AppDelegate.swift` atau `SceneDelegate.swift` tergantung struktur Xcode project.

---

## Aturan Kerja untuk AI

1. **Selalu edit `ios-cineby/WebViewController.swift`** — satu-satunya source of truth.
2. **Jangan buat file Swift baru** — cukup edit file yang sudah ada.
3. **Jangan tambah dependency** (CocoaPods/SPM) — proyek sengaja zero-dependency.
4. **Saat mengubah CSS**: Selalu gunakan class name spesifik, bukan wildcard. Selalu pertahankan exception `#mstream-controls-overlay`.
5. **Saat mengubah JS**: Script diinjeksi ke **semua frame**, efek samping bisa terjadi di iframe player third-party. Test mental di kedua site (Cineby via iframe embed, Nimegami via direct video).
6. **Nimegami**: Video langsung ada di frame utama. **Cineby**: Video ada di dalam iframe player third-party (vidsrc, dll).
7. **Jangan baca seluruh file** jika hanya perlu mengubah satu bagian — gunakan `view_file` dengan range spesifik atau `grep_search` terlebih dahulu.
