# CoolBun 🥟

A tiny (well under 1 MB) dylib that adds a floating button to any sideloaded iOS app.
Tap the button to see live stats and turn on heat-saving options.

Made for iPhone 7 Plus (arm64, iOS 12 - 15.8), works on newer devices too.

## Features

- Floating draggable button, always on top, in every app
- Live readout: UI FPS, CPU %, RAM, heat level (Cool / Warm / HOT / CRITICAL), battery %
- FPS cap: Auto / 60 / 45 / 30 (lower FPS = less heat, longer battery)
- Render scale: 100% / 75% / 50% / 35% (smaller graphics = much less GPU load)

## Honest limits

- Heat cannot be reduced by 100%. Lower FPS + lower render scale can reduce it a lot in many games and apps, but results depend on the app.
- iPhone 7 Plus has a 60 Hz screen. It cannot do 120 Hz. This dylib can only lower FPS, not raise it.
- The render scale works on apps that use Metal / OpenGL views (most games). Apps drawn another way may not change.
- Apps with anti-tamper or their own custom engine may ignore the settings.
- A worn-out battery is a common reason for random shutdowns and slowness. Check Settings > Battery > Battery Health. A new battery at a repair shop can fix more than any dylib.

## Build

1. Create a new GitHub repo, for example `CoolBun`.
2. Upload these files: `CoolBun.m`, `Makefile`, `.github/workflows/build.yml`, `README.md`.
3. Open the **Actions** tab, run **Build CoolBun dylib** (or just push).
4. Download the `CoolBun-dylib` artifact. Inside is `CoolBun.dylib`.

## Use

Inject `CoolBun.dylib` into the decrypted `.ipa` of your own app with your usual sideload tool (for example Sideloadly's "Inject dylibs" option), then install it.

Use it only on apps you own or are allowed to modify. Do not use it in online games where tampering is against the rules.
