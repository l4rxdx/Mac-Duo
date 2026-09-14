<div align="center">

# Mac Duo · l4rxx 修改版

**简体中文、自适应角度、60 fps 与锁屏开盖动画增强版**

本仓库是 [sumimakito/Mac-Duo](https://github.com/sumimakito/Mac-Duo) 的
l4rxx 修改版，保留原作者 Makito 的署名并遵循 Apache License 2.0。

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
- **Adaptive trigger:** Learns the resting lid angle and supports a configurable 0° to 30° accidental-trigger buffer.
- **Lock-screen opening effect:** After a real clamshell sleep, the same depth effect follows the physical lid angle while the Mac opens on the lock screen. It can be turned off independently in settings.
- **Warm first frame:** The Metal pipeline and a privacy-safe wallpaper texture are prepared before the trigger, avoiding capture and compilation work during wake.


> [!NOTE]
> Mac Duo is completely **free** to use. Whether you use the app or reuse its code in your projects, please consider [sponsoring me](https://github.com/sponsors/sumimakito) if you find it helpful.
>
> Special thanks to our team at [Moeru AI](https://github.com/moeru-ai) for sponsoring the Apple Developer Program membership used to sign and notarize the prebuilt app here.

## Download

[下载 DMG](https://github.com/l4rxdx/Mac-Duo/releases/latest/download/Mac-Duo-l4rxx-v0.1.0.dmg) | [下载 ZIP](https://github.com/l4rxdx/Mac-Duo/releases/latest/download/Mac-Duo-l4rxx-v0.1.0.zip)

以上是 l4rxx 修改版的公开构建，支持 Apple Silicon 与 Intel Mac。
首次打开时请在 Finder 中右键应用并选择“打开”，再按提示授予屏幕录制权限。
公开安装包使用 ad-hoc 签名，不包含维护者的个人开发证书。

Requires macOS 14 or later and a MacBook with a compatible lid angle sensor.
Grant Screen Recording permission when prompted to enable the effect.

## l4rxx 修改内容

- 简体中文、English 与跟随系统三种界面语言，可在应用内即时切换。
- 自适应学习常用屏幕角度，并可设置学习时间。
- 0°–30° 防误触角度，避免轻微调整屏幕时触发动画。
- 60 fps 实时渲染与首帧预热，减少动画割裂和首次顿帧。
- 真实合盖休眠后，在锁屏页面随开盖角度显示动画。
- 固定本地安装身份，后续本机更新尽量保留屏幕录制权限。

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
- The desktop capture stops when macOS sleeps. On the next real lid wake, a preloaded wallpaper (or neutral gradient fallback) drives the opening effect without capturing lock-screen or desktop contents.
- Clicks pass through the effect to the apps underneath.

## Acknowledgements

This project is built with AI assistance.

Modified by [l4rxx](https://github.com/l4rxdx). Originally developed by
[Makito](https://github.com/sumimakito).

## License

Licensed under the [Apache License 2.0](LICENSE). Copyright 2026 Makito.

See [NOTICE](NOTICE) for attribution.
