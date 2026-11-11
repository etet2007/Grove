# macOS alternate Dock icon implementations

Research date: 2026-11-05. Scope: source-level examples relevant to Grove's loss of the Tahoe rim after assigning a raster `NSApplication.applicationIconImage`. No Grove application code changed for this research.

## Findings

**No inspected open-source implementation establishes that loading a named alternate icon from `Assets.car` retains the system's live Tahoe icon treatment.** The concrete examples below either draw ordinary images or deliberately return to the bundle's default icon. This is a limit of the inspected evidence, not proof that every possible approach fails.

### Ghostty: raster alternates, default icon restored separately

Inspected repository snapshot `e95bed63330cc921f3cf2fe3d14e024396b09d43`. The relevant files last changed in commit [`c7a73076e9c3ebb395faa51d5f92f49327a62df5`](https://github.com/ghostty-org/ghostty/commit/c7a73076e9c3ebb395faa51d5f92f49327a62df5), dated 2026-04-20.

- [`AppIcon.image(in:)`](https://github.com/ghostty-org/ghostty/blob/e95bed63330cc921f3cf2fe3d14e024396b09d43/macos/Sources/Features/Custom%20App%20Icon/AppIcon.swift) uses `bundle.image(forResource: "BlueprintImage")` and corresponding names for supplied alternates, `NSImage(data:)` for a custom file, and a custom renderer for colorized icons. Its official choice returns `nil`. `AppIconUpdater` saves the selection, sends a distributed notification, and calls `NSWorkspace.shared.setIcon` for the app path.
- The [`BlueprintImage` asset manifest](https://github.com/ghostty-org/ghostty/blob/e95bed63330cc921f3cf2fe3d14e024396b09d43/macos/Assets.xcassets/Alternate%20Icons/BlueprintImage.imageset/Contents.json) identifies an ordinary `macOS-AppIcon-1024px.png` in an `.imageset`; this is not evidence of a layered alternate app-icon rendition.
- [`DockTilePlugin`](https://github.com/ghostty-org/ghostty/blob/e95bed63330cc921f3cf2fe3d14e024396b09d43/macos/Sources/Features/Custom%20App%20Icon/DockTilePlugin.swift) installs an `NSImageView` as `dockTile.contentView` for alternates. On macOS 26, the official release choice instead passes `nil`, clears `contentView`, and calls `display()`; its comment explicitly says this resets to `Ghostty.icon`. Pre-Tahoe uses `AppIconImage` instead.

**Implication:** Ghostty demonstrates persistence and custom Dock rendering, but does not demonstrate preserving live system edge highlights for alternate artwork. Copying its Dock plugin alone would not answer Grove's visual requirement. Its explicit Tahoe default reset supports keeping Grove's default path separate from raster alternates. These implications are inferences from code; no Ghostty Dock screenshot was verified here.

### iTerm2: custom Dock view draws its base image itself

[`iTermSuiteDockTileView.swift`](https://github.com/gnachman/iTerm2/blob/5ff63dade30865fe9faf2ac7003971dd55c46c88/sources/AppKit/iTermSuiteDockTileView.swift), introduced in commit [`5ff63dade30865fe9faf2ac7003971dd55c46c88`](https://github.com/gnachman/iTerm2/commit/5ff63dade30865fe9faf2ac7003971dd55c46c88), dated 2026-08-30, installs a custom Dock content view for isolated `-suite` instances. It draws `NSApp.applicationIconImage` and overlays the suite name. Its source comment says replacing the Dock's default drawing requires rendering the base icon itself.

**Implication:** This is a concrete custom-rendering example, not an alternate Icon Composer selection API or evidence of preserved Tahoe highlights. CotEditor and Zed source-tree inspection did not yield a relevant implementation; no claim about their whole codebase follows from that limited search.

### Unread developer: export rendered alternates

John Brayton's first-party [Icon Composer Notes](https://www.virtualsanity.com/202507/icon-composer-notes/) was published 2025-07-10 and updated 2026-03-19. It records that `NSImage(named:)` could load an Icon Composer icon in Tahoe beta 1 but failed in beta 3, and that including multiple `.icon` files appeared to retain only the default. Those are dated beta observations, not a current OS guarantee. For Unread, he planned generated alternate `.icon` files plus exported PNGs with fixed palettes. He also gives an `ictool --export-preview macOS Light …` example, updated for Xcode 26.4 RC. This establishes a developer-used rendered-image workflow; it does not establish live system effects on a runtime alternate.

## Actionable conclusion for Grove

Keep `applicationIconImage = nil` as the default restoration path. For alternate artwork requiring a Tahoe-like rim, investigate **Apple-rendered exported artwork**, and verify the actual running Dock result before delivery. The parent investigation successfully exported a temporary Grove `.icon` through installed `ictool` and visually observed a rim in the PNG; that observation proves an export result only, not Dock rendering or automatic light/dark/tinted behavior.

Do not describe named `NSImage` assets, `.icon` resources, or a Dock plugin as a confirmed live-rim fix on the strength of these sources. Compare with only the current `dist/Grove.app` running: the parent investigation found simultaneous `/Applications/Grove.app` and `dist/Grove.app` processes sharing the bundle identifier, which can confound observations and preference notifications. That local condition is independent of the public-source findings.


## User-named examples: installed Orca and Codex (direct local evidence)

Read-only inspection on 2026-11-05; installed application resources and JavaScript were inspected without changing preferences, launching previews, or executing the applications' icon setters. These are observations of the installed versions, not general claims about all releases.

### Orca

- `/Applications/Orca.app/Contents/Resources/app.asar.unpacked/resources/app-icons/orca-blue.png` visibly contains its outer highlight, darker edge and rounded tile. The effects are present in the PNG independently of the Dock.
- The packaged `out/main/index.js` in `app.asar` maps watercolor/blue selections to the corresponding PNG files; `pce` calls `nativeImage.createFromPath`, and `Sce` passes the result to `app.dock.setIcon`.
- Its additional persistence path calls public `NSWorkspace.setIcon(_:forFile:options:)` via AppleScript. That changes the application's Finder custom icon; it is separate from adding highlights. Grove's current requirement leaves the Finder icon at its default, so this persistence behavior should not be copied without changing that requirement.
- `resources/icon-source/generate.sh` contains an Icon Composer `.icon` → `actool` → ICNS → PNG generation workflow for its default assets. This is evidence of its default pipeline; it does not prove how every alternate PNG was authored.

### Codex (installed as ChatGPT.app)

- `/Applications/ChatGPT.app/Contents/Info.plist` identifies `com.openai.codex` and provides `CFBundleIconName=Icon` for the primary icon.
- The resource `/Applications/ChatGPT.app/Contents/Resources/icon-codex-light.png` visibly contains rendered shadows/highlights and rounded tile edges.
- Its packaged `.vite/build/early-bootstrap-45-628adb74a9c47df1.js` selects alternate resource names based on system light/dark appearance, loads with `nativeImage.createFromPath`, and uses `app.dock.setIcon`. The alternate path crops a small margin (rounded width/128) before assignment. The default branch clears the Dock override.
- A native `set-app-icon` helper is also invoked for persistence. Its internal behavior was not investigated, so this note makes no claim about its implementation.

### Corrected inference

The named examples demonstrate that static images can preserve a convincing dimensional appearance after replacement: the highlights can already be present in the supplied resource. They do not establish a public switch that automatically adds the primary icon's material to any assigned bitmap. Earlier statements that flattening necessarily prevents the desired visual appearance were too broad.

## Local tool probe and next verification

- Installed Xcode: 27.2 (27B52), Icon Composer `ictool` 27.2 / bundle version 143. Tool syntax was checked locally with `--help`.
- A temporary Grove `.icon` under `/tmp/grove-icon-composer-research/` used the existing source artwork as an opaque layer. `ictool --export-image --platform macOS --rendition Default --width 256 --height 256 --scale 1 --design-generation 26` successfully produced a PNG whose outer rim was visually inspected. Only the export was verified; no Dock claim follows.
- Next implementation experiment: use an Icon Composer export for one alternate and compare its actual Dock display to the primary icon, with only one Grove process running and matched canvas padding. Compare at normal Dock size, not only a large preview. If confirmed, extend to other alternates. Appearance-dependent exports are a separate decision; a baked image is not an automatically adaptive layered system icon.
- The previous `NSWorkspace` carrier-app rasterization remains an unconfirmed attempt. It should not be described as a proven solution or expanded before that comparison.
