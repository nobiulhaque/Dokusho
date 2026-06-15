<p align="center">
 <img width=200px height=200px src="assets/app_icons/icon-red.png"/>
</p>

<h1 align="center"> Dokusho </h1>

<div align="center">

Dokusho is a customized, lightweight open-source Android app for reading manga and manhwa, built with Flutter. Inspired by Mangayomi, Tachiyomi, and Mihon, it has been streamlined for mobile manga reading with a unified explore feed.
</div>

## Features

- **Unified Explore Feed**: Browse trending/popular manga from all your downloaded extensions on a single dashboard row-by-row.
- **Android Optimized**: Focused exclusively on the Android platform.
- **Chapter Progress Overlay**: Displays total chapters and your read progress directly on grid covers and detail lists.
- **Local & Online Reading**: Read downloaded chapters offline or stream online.
- **Configurable Reader**: Supports multiple reading directions, webtoon modes, and layout adjustments.

## How to Build

Dokusho uses `flutter_rust_bridge` for Rust-based library components.

1. Ensure you have the **Flutter SDK** and **Rust toolchain** installed.
2. Install the code generator:
   ```bash
   cargo install 'flutter_rust_bridge_codegen'
   ```
3. Generate the bindings:
   ```bash
   flutter_rust_bridge_codegen generate
   ```
4. Run or build the app:
   ```bash
   flutter run
   ```

## License

Dokusho is a derivative work based on Mangayomi and is licensed under the Apache License 2.0. See the LICENSE file for details.

Copyright 2026 Nobiul Haque (https://github.com/nobiulhaque/Dokusho)
Copyright 2023 Moustapha Kodjo Amadou