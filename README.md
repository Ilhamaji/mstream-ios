# Cineby iOS Wrapper

A minimalist native iOS wrapper for the movie streaming website [Cineby](https://cineby.at) featuring **Bypass Portrait Orientation Lock** and **Netflix-Style Playback Lock**.

---

## 📱 Key Features

1. **Bypass Orientation Lock**: Instantly watch movies in fullscreen landscape even when the system *Portrait Orientation Lock* is active on your iPhone.
2. **Reddit-Style Floating Controls**: Floating circular control buttons (50x50) styled using native Apple **SF Symbols** in both portrait and landscape modes (replacing navigation headers completely).
3. **Netflix-Style Playback Lock**:
   * Instant screen lock that disables all touch interactions on the video player/WebView (blocking ads, pop-ups, and accidental pause/seeking).
   * **Auto-Hide**: The red lock button automatically fades out after 3 seconds of inactivity.
   * **Tap-to-Toggle**: Simply tap anywhere on the screen to show or instantly hide the lock button.
4. **Edge-to-Edge Fullscreen (No Margins)**: Automatically overrides HTML viewport scales and safe area margins in landscape to fill the physical screen completely.

---

## 📸 Screenshots

| Main View (Portrait) | Player View (Landscape) |
| --- | --- |
| ![Portrait View](screenshots/media__1783615340513.png) | ![Landscape View](screenshots/media__1783615340286.png) |

---

## ⚙️ How to Install (Sideloadly)

1. Download the `unsigned-App.ipa` build file from the **Actions** tab in your GitHub repository.
2. Connect your iPhone to your computer (Windows/Mac).
3. Open **Sideloadly**, enter your Apple ID, and drag the `.ipa` file into the app.
4. Click **Start** to install.
5. On your iPhone, go to **Settings → General → VPN & Device Management**, tap your Apple ID, and select **Trust**.

---

## 🚀 How to Use

1. Open the **Cineby** app and select the movie you want to watch.
2. Once the movie starts playing, tap the circular rotation icon `arrow.triangle.2.circlepath` floating in the top-right corner of the screen to enter landscape mode.
3. **Locking the Screen**: Tap the unlocked padlock icon `lock.open.fill` at the bottom-left of the landscape screen. The button will turn red, lock touch gestures, and fade out in 3 seconds.
4. **Unlocking the Screen**: Tap anywhere on the blank screen to show the red padlock button, then tap the padlock button itself to unlock.
5. Tap the circular rotation button in the bottom-right of the landscape screen to return to portrait mode.
