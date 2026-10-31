<p align="center">
  <img src="Preferences/Resources/Pineora@3x.png" alt="Pineora icon" width="80" height="80">
</p>

<h1 align="center">Pineora</h1>

<p align="center">Home Screen icon theming for jailbroken iOS</p>

<p align="center">English · <a href="README.zh-CN.md">简体中文</a></p>

## Features

- Enable, disable, and reorder themes to combine them by priority.
- Read common `.theme` icon layouts, including `IconBundles` and `Bundles`.
- Support for icon masks, badge styling, and clock and calendar theme resources.
- iOS 26 folder preview icon adaptations; settings in Simplified Chinese, English, Japanese, and Korean.

## Usage & Compatibility

After installation, open **Settings → Pineora**, select and reorder themes, then tap **Apply Changes**. Theme search directories are shown in settings. No theme packs are included in this repository.

Requires `mobilesubstrate` and `preferenceloader`. The deployment target is iOS 16.0+, with rootless and roothide build configurations. The current development device runs iOS 26.0.1; compatibility paths for iOS 16/17/18 still need testing on devices running those versions.

## Building & Layout

Build with [Apelin](https://github.com/owngoal-dev/Apelin) using [apelin-project.json](apelin-project.json). Bind the project to a compatible toolchain and SDK registered on your own device; the current development configuration uses CLT 15.3 / the iOS 17.4 SDK. Build rootless and roothide packages separately.

- `Sources/`: theme parsing, rendering, and SpringBoard hooks.
- `Preferences/`, `PreferenceLoader/`: settings pane and its entry.
- `Research/`: research notes, compatibility investigations, probes, and regression test sources.
- `Tools/`: settings icon generator.

## License

Original project code is licensed under the [MIT License](LICENSE). Third-party material referenced in `Research/` and Apple SF Symbols used in the icon are not relicensed by this license and remain subject to their respective rights and license terms. Pineora is not affiliated with SnowBoard and does not represent its authors.
