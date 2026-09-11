<div align="center">

# Mac Duo

**Wish you could bring the iPhone Duo effect to your MacBook?**

https://github.com/user-attachments/assets/3ea3b098-c6d2-4398-8f3a-e9087bbb33f2

Close the lid and watch your screen content tilt, blur, and fade as it moves.  
Mac Duo adds this effect to your MacBook, with controls in the menu bar.

<img src="./assets/menu.png" width="400" alt="Mac Duo menu">

</div>

<hr>

With the default settings, it's recommended to view the effect in front of your MacBook.

- **Metal rendering:** Uses GPU rendering to apply perspective, blur, and dimming as the lid closes.
- **Live screen content:** Uses ScreenCaptureKit to capture and render screen content in real time.
- **Adjustable perspective:** Tweak the perspective to suit your viewing position and make the effect look more natural.


> [!NOTE]
> Mac Duo is completely **free** to use. Whether you use the app or reuse its code in your projects, please consider [sponsoring me](https://github.com/sponsors/sumimakito) if you find it helpful.
>
> Special thanks to our team at [Moeru AI](https://github.com/moeru-ai) for sponsoring the Apple Developer Program membership used to sign and notarize the prebuilt app here.

## Download

[Download DMG](https://github.com/sumimakito/Mac-Duo/releases/download/dev/Mac-Duo-dev.dmg) | [Download ZIP](https://github.com/sumimakito/Mac-Duo/releases/download/dev/Mac-Duo-dev.zip)

These downloads contain the latest [development build](https://github.com/sumimakito/Mac-Duo/releases/tag/dev) for Apple Silicon and Intel Macs.

Requires macOS 14 or later and a MacBook with a compatible lid angle sensor.
Grant Screen Recording permission when prompted to enable the effect.

## Build

Requires Xcode with Swift 6.0 or later. Run from the project directory:

```sh
./build.sh
```

The script creates `build/Mac Duo.app` with an ad-hoc signature. Open it from Finder, or build and launch with:

```sh
./build.sh --run
```

macOS may require Screen Recording permission again after rebuilding with ad-hoc signing.

### Simplified Chinese local install and updates

For the Simplified Chinese build on a Mac with one Apple Development or
Developer ID Application signing identity, run:

```sh
./install-zh-cn.sh
```

The script always installs the same app identity at
`/Applications/Mac Duo 中文版.app`, signs it with the same Apple-issued
identity, and keeps the previous build under `build/install-backups/`. This
allows macOS to recognize later builds as updates and retain Screen Recording
permission. Migrating from an ad-hoc build requires granting the permission one
final time; subsequent updates made with the same signing identity should keep
it.

Use **Language** at the bottom of the settings panel to switch between Follow
System, Simplified Chinese, and English without reinstalling the app.

## Known limitations

- Only MacBooks with a compatible lid angle sensor can use the effect. The app reports when no sensor is available.
- The effect applies only to the built-in display.
- The effect stops when macOS sleeps as the lid closes.
- Clicks pass through the effect to the apps underneath.

## Acknowledgements

This project is built with AI assistance.

## License

Licensed under the [Apache License 2.0](LICENSE). Copyright 2026 Makito.

See [NOTICE](NOTICE) for attribution.
