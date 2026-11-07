# Snake Clash

A fullscreen native iPad snake arena built with SpriteKit and SwiftUI. An earlier Canvas web version is also included in `public/` as a separate preview.

## Run the iPad app in Xcode

1. Open `ios/SnakeClash.xcodeproj` in Xcode.
2. Select the **SnakeClash** scheme and an iPad simulator, then press **Run** (⌘R).
3. To run on your own iPad, connect it to your Mac, choose the iPad as the destination, and select your Apple ID's development team under **Signing & Capabilities**. Enable Developer Mode on the iPad if Xcode requests it. You can use a Personal Team for local testing. If the bundle identifier is already taken, change it to a unique value.

The app supports iPadOS 17+, portrait and landscape, and runs fully offline. The arena, snake rendering, floating touch joystick, food, and burst effects use SpriteKit. SwiftUI provides native menus, HUD, pause, help, and a six-color snake picker. Your chosen color, mute preference, and personal best save on the device. Status and home indicator overlays hide during play; controls respect safe areas.

The iPad app no longer uses WKWebView, HTML, or JavaScript. Edit `ios/SnakeClash/GameWorld.swift` for gameplay and `ios/SnakeClash/SnakeClashApp.swift` for rendering and interface. The legacy `ios:sync` command only updates the old web bundle and is not part of the native build.

## Native controls

Drag anywhere in the arena to steer. Hold BOOST with another finger to dash. The pause button freezes the game; switching away pauses automatically. Pick Lavender, Mint, Coral, Sky, Gold, or Lime before a round. Eat smaller snakes to release yellow balls, collect the balls to grow, and avoid bigger snakes. Your tail is safe and arena edges wrap.

## Native audio

A gentle synthesized pad and bell melody loop during play. Collecting yellow balls plays a short chime; eating a rival plays a rising reward chime with a rounded pop. When your snake dies, a descending cue plays as the round ends. Dot sounds are rate-limited during large food showers. All audio is synthesized locally and works offline. The speaker button on the start menu and in the arena mutes both ambience and effects. Audio pauses with gameplay and when the app leaves the foreground, respects iPad Silent Mode, and mixes with other apps' music.

`GameAudio.swift` handles native AVFoundation playback and audio interruptions; `SoundSynthesis.swift` creates the original PCM sounds.

## Verify the native game

```sh
npm run test:native
```

The checks exercise the Swift simulation, player-only collection signals, and generated audio: WAV format, duration, signal level, smooth looping, and sound tails. The iPad Simulator build has also been checked. Running on a physical iPad requires signing with your Apple account.

## Play the web preview locally

Requires Node.js 20 or newer.

```sh
npm start
```

Open http://localhost:5173 on your computer. To play on an iPad connected to the same Wi-Fi, open `http://YOUR-MAC-LOCAL-IP:5173` in Safari. Your Mac's local IP is listed in System Settings → Wi-Fi → Details → TCP/IP. Allow incoming connections if macOS asks. Keep the server running.

In Safari, tap Share → Add to Home Screen to create an app icon. This is a Home Screen web app, not an App Store binary. For access away from your Mac and offline installation, host the `public` directory on an HTTPS static host. The service worker caches the game on HTTPS (or localhost); it is unavailable over a plain HTTP LAN address.

## Web preview controls

- **iPad:** Drag anywhere in the arena to steer using the floating joystick. Hold BOOST with another finger to dash.
- **Desktop:** Move the mouse over the arena, or use WASD / arrow keys. Hold Space to boost.
- **Pause:** Use the pause button, P, or Escape. Switching away from the app pauses automatically.
- Touch smaller snakes to turn them into yellow balls. Collect the balls to grow. Bigger snakes can eat you. Similar-sized snakes pass safely. Your tail is safe, and arena edges wrap around.
- Your best score saves on this device. Sound is optional and starts muted.

## Verify the web preview

```sh
npm test
```

Tests cover snake collisions, yellow ball drops, collecting food, boost energy, wrapping, and a 100-second simulated round. The Xcode simulator build has also been checked. Physical iPad signing and App Store distribution require your Apple account.


## Saved rounds and performance

The native app saves an active round every ten seconds and whenever it pauses or leaves the foreground. Relaunching restores it paused; tap Keep on snacking to continue. Score, size, position, rivals, food, energy, and pending rival respawns are preserved. A completed round clears the resumable save.

Xcode updates using the same bundle identifier preserve these local saves, best score, color, and mute preference. Deleting the app or changing its bundle identifier does not carry that data over. A force quit can lose up to ten seconds of active play.

Rendering uses a shared dot/glow texture for food and bursts, fewer snake path segments, and skips rebuilding a stationary arena. Collision comparisons avoid repeated square roots; HUD values only publish when changed. Physical-device frame-rate measurements are still needed to quantify the improvement.
