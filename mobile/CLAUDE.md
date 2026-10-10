# Spatial Bloop – project notes (read this first)

Handover notes for a new Claude session (or a teammate). It covers what the project is, where everything lives,
how the pieces fit, and what's still open. Last updated: 10 Oct 2026 (BEST Hacks 2026).

## 1. What it is

**Spatial Bloop** is an iPhone audio guide to the **Field Museum's Main Level (Chicago)**:
1. You put on AirPods and pick an exhibit.
2. You follow 3D "bloop" sounds placed a few metres ahead of you along the route.
3. When you arrive, the guide tells you the exhibit's story.

The app has two modes:
- **Map mode** (default) looks like Duolingo: friendly, rounded, chunky buttons, and a mascot called *Bloop*.
  The map is 3D by default, Apple-Maps style, with a first-person "Look" view and a 2D floor plan.
- **Listening mode** is for blind or low-vision users: no map, big spoken buttons, VoiceOver-friendly.

Design rules the owner asked for:
- Simple, Duolingo-like look.
- The app guides you step by step and never shows too many options at once.
- 3D is the default map, with a first-person view.
- Models are simpler than the original detailed ones but nicer than the plain "clay" version, in Apple Maps 3D style.

## 2. Folder layout (`~/BEST hacks 2026/mobile/`)

```
mobile/
├── CLAUDE.md                 ← this file
├── resources.zip             backup of the OLD resources (detailed textured models + old generator). Keep.
├── resources/                3D models + generator (see §5)
│   ├── MuseumMap.usdz        building (used for the 3D map AND first-person view)
│   ├── Artifacts/*.usdz      8 exhibit models
│   ├── Thumbnails/<key>.png  exhibit pictures (also in the app's asset catalog)
│   ├── FieldMuseum_MainLevel_info.json   floor plan + exhibits data (same as the app copy)
│   ├── previews/*.png        renders for a quick look
│   ├── tools/                Python generator (numpy; Playwright+Chromium for pictures)
│   └── README.md
└── BestHackMobile/           the Xcode project (git repo; only "Initial Commit" so far, all newer work is uncommitted)
    ├── BestHackMobile.xcodeproj
    │   └── xcshareddata/xcschemes/BestHackMobile.xcscheme   shared scheme, Metal API Validation OFF (see §7)
    ├── Secrets.example.plist
    ├── README.md             user-facing README (features, setup, route API)
    └── BestHackMobile/       sources (Xcode "synchronized folder": new files are picked up automatically)
```

## 3. Build settings that matter

- **Xcode 27 / iOS 27 SDK.** `IPHONEOS_DEPLOYMENT_TARGET = 27.0`.
- **Multiplatform target:** iPhone, iPad, Mac and Vision (`SUPPORTED_PLATFORMS` includes macosx and xros).
  Wrap iOS-only APIs in `#if os(iOS)`, and use `UIColor`/`NSColor` via `#if canImport(UIKit)`.
- **Swift 5 language mode,** `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, `SWIFT_APPROACHABLE_CONCURRENCY = YES`.
  Everything is MainActor by default. Pure data and maths types are marked `nonisolated` (e.g. `MuseumInfo`, `MuseumGeometry`, the Shapes).
- **Synchronized root group** (`PBXFileSystemSynchronizedRootGroup`): any file added under `BestHackMobile/BestHackMobile/` is in the target. You never need to edit `project.pbxproj` to add files.
- **iPhone is portrait-only** (`INFOPLIST_KEY_UISupportedInterfaceOrientations_iPhone = UIInterfaceOrientationPortrait`).
- **Info.plist keys** are generated: location ("when in use") and motion (AirPods head tracking).
- **Secrets:** `BestHackMobile/Config/Secrets.plist` (git-ignored) holds
  - `ELEVENLABS_API_KEY`
  - `ROUTE_API_URL`
  - `ROUTE_Y_AXIS`

  Never print or commit it.

## 4. Source map (`BestHackMobile/BestHackMobile/`)

| Path | What it does |
|---|---|
| `App/BestHackMobileApp.swift` | `@main`, shows `RootView`. |
| `App/RootView.swift` | Owns `GuideModel` + `VisitLog`. First launch → `WelcomeView` (intro), afterwards → `MapScreen`. Sets `.fontDesign(.rounded)`. |
| `Design/Theme.swift` | **Design system:** colours (light/dark), `Theme.title(.title)` fonts (Dynamic Type), `ChunkyButtonStyle` (kinds: primary, blue, orange, danger, secondary, secondaryDanger, quiet), `RoundIconButtonStyle`, `ChunkyCardButtonStyle`, `.chunkyCard()`, `.floatingPanel()`, `ChunkyProgressBar`, `Chip`, `ExhibitThumbnail` (shows `Image("Exhibit-<key>")`). |
| `Design/Mascot.swift` | `Mascot` (Bloop: moods happy/talking/thinking/cheering, blinks, bobs), `MascotSays` (speech bubble), `ConfettiView`. |
| `Features/Welcome/WelcomeView.swift` | 4-step intro with a progress bar: hello → mode (`ChoiceCard`) → headphone left/right test → location permission. |
| `Features/Map/MapScreen.swift` | Main screen: map layer, `TopBar` (place chip, DEMO tag, ★ seen/total, settings), `MapStylePicker` (3D / Look / 2D), locate button, `WalkPad` (demo arrows in Look view), `NoticeBanner`, sheets (exhibits, settings, detail), `ArrivalView` overlay, haptics. Measures the top bar and card heights (`covered` insets) so the maps centre on the visible area. |
| `Features/Map/GuidePanel.swift` | The single bottom card. `ExploreCard` ("Next up" = nearest unvisited exhibit + Let's go + 2 small buttons + All exhibits), `PreviewCard`, `WalkingCard` (turn arrow, meters to go, progress, Repeat, Walk me there (demo), ✕ with confirmation), `StoryButton` (Hear its story ↔ Stop), `ArrivalView` (confetti, +1 ★, "Next: …"), `ListenModeView` + `BigButton`, helpers `nextExhibits()` and `turnInstruction()`. |
| `Features/Map/Map3DView.swift` | 3D map (RealityKit `RealityView`, `content.camera = .virtual`). Overview ↔ eye-level blend, gestures (pan, pinch 25–450 m, rotate; drag to look in eye level; tap the floor to move in demo), SwiftUI pin overlay (`ExhibitPin`) + gallery labels. `MuseumMapScene` = the RealityKit side (lights + shadows, building, exhibits, user marker, route band, highlight disc). It squashes the building groups `Walls/Hall/Blocks/Entrances` to 42 % height in the overview. |
| `Features/Map/MapCamera.swift` | `MapStyle` enum, `CameraGoal`, `MapCameraRig` (smoothing per frame, pose, `project()` world→screen, `floorPoint()` screen→floor). FOV 60° vertical. |
| `Features/Map/Map2DView.swift` | Canvas floor plan (north up), tap pins / tap the floor to move (demo). |
| `Features/Map/MapPalette.swift` | 2D map colours (floor tints match the 3D model). |
| `Features/Artifacts/` | `ArtifactListView` (grid of all exhibits + progress), `ArtifactDetailView` (turning 3D model, story, pinned Let's go / Hear its story, optional Close), `ArtifactModelView` (turntable RealityView, falls back to the thumbnail). |
| `Features/Settings/SettingsView.swift` | Short settings (mode, guide toggles, bloop volume, headphones, demo, intro again, reset visits) + `AdvancedSettingsView` ("Voice and advanced": voice engine, ElevenLabs key, location source, route service, credits). |
| `Models/GuideModel.swift` | **The guide (core logic, `@Observable`)**, see §6. |
| `Models/VisitLog.swift` | Visited exhibits (★), persisted in UserDefaults `visits.exhibits`. |
| `Models/UserMode.swift` | `.standard` ("With the map") / `.blind` ("Just listening"). |
| `Models/VoiceSettings.swift` | Apple vs ElevenLabs voice, key in Keychain. |
| `Models/Museum/MuseumInfo.swift` | Decodes the info JSON; `MuseumGeometry` (yaw maths, point-in-polygon). |
| `Audio/` | `SpatialAudioEngine` (AVAudioEnvironmentNode HRTF: bloop + spoken voice placed in 3D), `Bloop`, `SpeechOutput`, `AppleSpeech`. |
| `Services/Location/` | `LocationService` (GPS + compass → model coords; falls back to a **simulated** position when not at the museum), `GeoReference`. |
| `Services/Routing/` | `RouteProvider` (straight line or your `ROUTE_API_URL`), `RouteMath`, `RouteDecoder`. |
| `Services/` | `HeadTracker` (AirPods `CMHeadphoneMotionManager`), `KeychainStore`, `MuseumAssets` (finds `.usdz`/JSON in the bundle; `map()` loads **MuseumMap.usdz**), `ElevenLabs/`. |
| `Resources/Museum/` | `MuseumMap.usdz`, `Artifacts/*.usdz`, `FieldMuseum_MainLevel_info.json`. |
| `Resources/Assets.xcassets` | `Exhibits/Exhibit-<key>` pictures, AccentColor (#1EA5F2). |

**UserDefaults / AppStorage keys:**
- App state: `userMode`, `onboarding.done`, `map.style`, `visits.exhibits`
- Guide settings: `guide.autoAnnounce`, `guide.selectByLooking`, `audio.bloopVolume`, `location.source`
- Voice: `voice.engine.v2`, `voice.elevenLabs.voiceID`, `voice.elevenLabs.model`

## 5. Museum data and coordinates

- **Units and axes:** metres, **+x east, −z north, +y up**, floor at y = 0. The origin is the centre of the building, rotated 1.03° so the walls are axis-aligned. A 2D floor point is `(x, z)`.
- **Yaw:** 0 = facing north (−z), positive = turned left. `MuseumGeometry.forward(yaw:)` / `yaw(from:to:)`.
- **The JSON** (`FieldMuseum_MainLevel_info.json`) contains:
  - `rooms[]`: outline, theme, status open/closed/staff_only
  - `exhibits[]`: key, title, gallery, text, position, yaw_degrees, footprint_m, detail_model
  - `displays[]`: vitrines and dioramas
  - `doors[]`, `points_of_interest[]`
  - `meta.nave`: Stanley Field Hall rectangle
  - `building_outline`
  - `georeference`: GPS → model coordinates
- **Exhibit keys:**
  - `maximo` (Máximo the Titanosaur, hall)
  - `elephants` (Fighting African Elephants, hall)
  - `totems` (Totem Poles, hall)
  - `tsavo_lions` (Mammals of Africa)
  - `seabirds` (Birds)
  - `mask` (Greenstone Mask, Ancient Americas)
  - `pawnee_lodge` (Ancient Americas)
  - `mastaba` (Inside Ancient Egypt)
- **Simulated start:** (0.2, 56), just inside the South Entrance.
- **Data licence:** © 2020 Field Museum, CC BY 4.0. The credit must stay in the app (it's in Settings → Voice and advanced → About).

## 6. GuideModel API (what the UI uses)

- **State:**
  - Where you are: `position`, `facingYaw?`, `placeName`, `nearby` (3 closest)
  - Choosing by looking: `faced?`, `dwellProgress`
  - Selection and guidance: `preview?` (settable), `target?`, `route`, `routeVersion`, `remaining?`, `progress` (0…1), `turn` (.ahead/.left/.right/.around/.unknown), `arrived?`
  - Messages: `statusMessage?`, `loadError?`
  - Sub-objects: `info`, `audio` (`isSpeaking`, `speechNotice`, `bloopVolume`), `voice`, `location`, `head`
  - Settings: `selectByLooking`, `autoAnnounce`, `demoWalk`, `mode`
- **Haptic counters:** `facedEvent`, `selectionEvent`, `waypointEvent`, `arrivalEvent`, `onTrackEvent`, `offRouteEvent`.
- **Actions:**
  - Lifecycle: `start(mode:)`, `stop()`
  - Guidance: `navigate(to:)`, `stopGuidance()`, `follow(route:to:)`, `follow(routeJSON:)`
  - Speech: `tellStory(of:)`, `announceNearby()`, `announceLocation()`, `announceDirection()` (added this session: "Turn left. 24 meters to …"), `stopSpeaking()`
  - Directions text: `directions(to:)` ("12 m ahead"), `spokenDirections(to:)`, `distance(to:)`
  - Setup and demo: `playTestBloop(onLeft:)`, `requestLocationPermission()`, `alignHeadphones()`, `moveSimulated(to:)`, `walkSimulated(by:)`, `turnSimulated(by:)`
- **Behaviour:**
  - It ticks 20×/s.
  - Arrival is when you're within 2 m of the route end or footprint + 2 m.
  - Off-route is more than 8 m away; it then re-routes.
  - Facing an exhibit for 1.5 s chooses it.
- **Route service:** `POST ROUTE_API_URL {"from":{x,y},"to":{id,name,x,y}}` → list of points (y = model z). The full format is in the app README.

## 7. Gotchas (learned the hard way)

1. **`RealityView` on iOS shows the AR camera by default.** Always set `content.camera = .virtual` in the make closure. Both `Map3DView` and `ArtifactModelView` do. The old 3D map didn't, which (together with a missing `MuseumMap.usdz`) is why it looked broken.
2. **Simulator crash:** "MTLDebugRenderCommandEncoder … Draw Errors Validation … fsRealityPbr" → killed. Fix: Metal API Validation off. The shared scheme sets `enableGPUValidationMode = "1"`. If the scheme is ever regenerated: Edit Scheme → Run → Diagnostics → uncheck Metal API Validation.
3. **Background:** the `RealityView` background is transparent with `.backgroundStyle(...)` / `.background(...)`, so the sky is a SwiftUI gradient. The 3D map always uses a light sky, even in dark mode.
4. **Building group names:** they come from USD prim names (`findEntity(named: "Walls")`). Keep them stable in the generator: `Outside`, `Floors`, `Walls`, `Blocks`, `Hall`, `Entrances`, `Furniture`, `Displays`.
5. **Pins and labels are SwiftUI overlays,** projected with `MapCameraRig.project()` using the same pose as the RealityKit camera (FOV set with `fieldOfViewOrientation = .vertical`). If you change the FOV, change `MapCameraRig.fieldOfView` only.
6. **Camera loop:** `MapCameraRig` is deliberately *not* observable. It's advanced inside a `TimelineView` and pauses when settled (via `settleTick`).
7. **Throwaway instances:** `@State var x = SomeClass()` creates a throwaway instance on every view init, so `MuseumMapScene.init()` is empty and the meshes are built in `build()`.
8. **Text contrast:** button faces (`Theme.green`, `blue`, `red`) are darkened for white text (≥3:1). Use `blueText`, `greenShade`, `redText` and `inkSoft` for text on cards. `Theme.orange` and `greenBright` are for progress and stars only (no text on them).
9. **Thumbnails** are `Image("Exhibit-<key>")` from the asset catalog. A new exhibit needs a new imageset (the generator renders it into `resources/Thumbnails/`).

## 8. 3D models: how to rebuild

Run this on any machine with python3 + numpy (the Mac's Linux shell works):

```sh
cd resources
python3 tools/build_all.py FieldMuseum_MainLevel_info.json .               # models + thumbnails + previews
python3 tools/build_all.py FieldMuseum_MainLevel_info.json . --no-pictures  # models only
```

The output is deterministic: a rebuild gives byte-identical `MuseumMap.usdz`. After rebuilding:
1. Copy `MuseumMap.usdz` and `Artifacts/` into `BestHackMobile/BestHackMobile/Resources/Museum/`.
2. Copy the thumbnails into `Assets.xcassets/Exhibits/Exhibit-<key>.imageset/<key>.png`, cropped square at 480 px.

The generator files:
- `meshkit.py`: shapes (box, prism, tube along a spline, dome, sphere…), `Scene`
- `usdz.py`: USDA + UsdPreviewSurface, 64-byte-aligned zip
- `palette.py`: all colours
- `build_building.py`: building from the JSON
  - closed rooms become solid blocks
  - walkable rooms get painted walls with door openings
  - the hall gets columns, arches and a balcony
  - no ceilings
- `build_exhibits.py`: the 8 exhibits (front faces +z, footprint centred, y = 0 floor)
- `preview.py`: headless WebGL renderer
- `build_all.py`: thumbnail camera per exhibit in `THUMBS`

Sizes: building ~44k triangles / 2.4 MB, exhibits 0.4k–19k triangles each, ~4.4 MB total.

## 9. Status (end of 10 Oct session)

**Done:**
- Full UI redesign: Duolingo style, guided one-card flow, intro, listening mode.
- 3D default map, first-person Look view, restyled 2D.
- New Apple-Maps-style models and cleaned-up resources.
- An independent UI/UX review; its main findings were fixed:
  - card height
  - framing
  - demo stuck
  - stop speech
  - contrast
  - Dynamic Type
  - tap targets
  - portrait lock
  - Metal validation

**Verification:**
- The first UI version compiled and ran on the owner's Mac.
- The second round (review fixes + `GuideModel.announceDirection()`) was only syntax-checked. **Build it first (⌘B) and fix any compile errors** before anything else.

**Open ideas / not done yet:**
- Dark-mode lighting for the 3D scene (currently it stays daytime on purpose).
- Short pin titles in the overview: titles only show when zoomed in (< 90 m).
- Pins can overlap the map controls on very small screens.
- "Cheering" mascot when close to the target; a tap-Bloop-to-stop hint.
- Real walking routes need the `ROUTE_API_URL` service; without it guidance is a straight line through walls.
- Nothing has been committed to git since "Initial Commit". Commit when the build is green.

## 10. Working on this from a cloud Claude session

- The Mac is reachable through the device tools when the desktop app is linked. The connected folder is
  `/Users/stanislawsikora/BEST hacks 2026/mobile` (mounted as `$HOME/mnt/mobile` in the device shell, a Linux VM: no Xcode there).
- **Moving files:**
  - To bring a few files over: `device_stage_files`, one file at a time works best.
  - To send files back: make a tarball, `SendUserFile` it, then `device_commit_files`, then untar in the device shell.
- **Compiling:** Swift can't be compiled in the cloud. A syntax check is possible with tree-sitter-swift
  (GitHub `alex-pinkus/tree-sitter-swift`, branch `with-generated-files`, plus the tree-sitter CLI from GitHub releases).
  The real check is Xcode on the Mac. Xcode can only be granted "click" access through computer use, and it is usually full-screen on another Space, so ask the owner to press ⌘B / ⌘R.
