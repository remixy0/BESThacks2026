# Spatial Bloop – project notes (read this first)

Handover notes for a new Claude session (or a teammate). It covers what the project is, where everything lives,
how the pieces fit, and what's still open. Last updated: 10 Oct 2026, late evening (BEST Hacks 2026).

## 1. What it is

**Spatial Bloop** is an iPhone audio guide to the **Field Museum's Main Level (Chicago)**:
1. You log in (or tap *Try the demo*), calibrate on a known spot, and put on AirPods.
2. You pick an exhibit and follow 3D "bloop" sounds placed a few metres ahead of you along the route.
3. When you arrive, the guide tells you the exhibit's story.

**Where you are** comes from **BLE beacons** (iBeacons, UUID `DFB76639-2B31-46CB-AAD1-63470563632E`, positions from
the team backend). **Which way you face** comes **only from AirPods** head tracking, lined up at calibration.
There is no GPS and no phone compass any more.

**Language:** Polish by default, English switchable (login screen, intro, Settings). All UI, speech and the museum
texts (Polish exhibit titles/stories/place names in `Models/Language.swift`) follow it; use `tr("English", "Polski")`
for every user-facing string (`trNow` in nonisolated code). **Voice commands** via ElevenLabs speech-to-text (Scribe).

The app has two modes:
- **Map mode** (default): calm, flat look (indigo actions, coral for sound/route, warm off-white page). 3D map by
  default (Apple-Maps style), first-person "Look" view and 2D plan, switched with a sliding control.
- **Listening mode** for blind or low-vision users: four big bright corners = the four nearest exhibits, spoken
  positions, strong haptics, tap to choose + tap again to confirm.

Design rules the owner asked for:
- Simple UI, but **not** a Duolingo clone (no chunky 3D buttons, no cartoon mascot, no confetti/pop-ups).
- Few things on screen; the app guides you one step at a time.
- 3D is the default map, with a first-person view. The map moves only with you/your AirPods (no finger dragging,
  no phone motion); pinch-zoom is allowed.
- Models are simpler than the original detailed ones but nicer than the plain "clay" version, in Apple Maps 3D style.
- Performance matters (the previous version lagged).

## 2. Folder layout (`~/BEST hacks 2026/mobile/`)

```
mobile/
├── CLAUDE.md                 ← this file
├── backups/                  tarballs taken before big changes (BestHackMobile-before-redesign-2026-10-10.tar.gz),
│                             removed-files/ (files taken out of the target: Mascot, LocationService, GeoReference)
├── resources.zip             backup of the OLD resources (detailed textured models + old generator). Keep.
├── resources/                3D models + generator (see §8)
└── BestHackMobile/           the Xcode project (git repo; only "Initial Commit" so far, all newer work is uncommitted)
    ├── BestHackMobile.xcodeproj
    │   └── xcshareddata/xcschemes/BestHackMobile.xcscheme   shared scheme, Metal API Validation OFF (see §7)
    ├── AppInfo.plist         partial Info.plist (ATS: plain http allowed for a local backend), merged by Xcode
    ├── Secrets.example.plist
    ├── README.md             user-facing README (features, setup, backend API, route API)
    └── BestHackMobile/       sources (Xcode "synchronized folder": new files are picked up automatically)
```

Sibling folders `../backend`, `../embedded` (ESP32 beacon firmware) and `../frontendWeb` exist but haven't been
read by Claude yet (access wasn't granted). The backend contract the app expects is in README → Backend API.

## 3. Build settings that matter

- **Xcode 27 / iOS 27 SDK.** `IPHONEOS_DEPLOYMENT_TARGET = 27.0`.
- **Multiplatform target:** iPhone, iPad, Mac and Vision (`SUPPORTED_PLATFORMS` includes macosx and xros).
  Wrap iOS-only APIs in `#if os(iOS)` (beacon ranging, Core Haptics, UIApplication), and use `UIColor`/`NSColor` via `#if canImport(UIKit)`.
- **Swift 5 language mode,** `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, `SWIFT_APPROACHABLE_CONCURRENCY = YES`,
  `MEMBER_IMPORT_VISIBILITY` on (import every module you use in each file).
  Everything is MainActor by default. Pure data and maths types are marked `nonisolated` (e.g. `MuseumInfo`,
  `BeaconPositioner`, `BeaconDirectory`, `CalibrationSpot`, `BackendClient`, error enums, the Shapes). A struct created
  inside a `nonisolated` delegate callback must itself be `nonisolated` (e.g. `BeaconScanner.Reading`).
- **Synchronized root group** (`PBXFileSystemSynchronizedRootGroup`): any file added under `BestHackMobile/BestHackMobile/` is in the target. You never need to edit `project.pbxproj` to add files. Removing a file from that folder removes it from the target.
- **iPhone is portrait-only.**
- **Info.plist:** generated from build settings (location "when in use" = needed for beacon ranging, motion = AirPods,
  microphone = voice commands, speech recognition = wake phrase, local network) **plus** `AppInfo.plist` via `INFOPLIST_FILE` (only `NSAppTransportSecurity/NSAllowsArbitraryLoads`;
  don't add `NSAllowsLocalNetworking` next to it, iOS then ignores ArbitraryLoads).
- **Secrets:** `BestHackMobile/Config/Secrets.plist` (git-ignored) holds
  - `ELEVENLABS_API_KEY`
  - `BACKEND_URL` (can also be set in the app; the in-app value wins). Empty → built-in `Secrets.defaultBackendURL`
    = `http://172.20.10.6` (laptop on the iPhone's Personal Hotspot). Changing that default clears an address typed in
    the app on the next launch (`backend.defaultSeen`).
  - `ROUTE_API_URL`
  - `ROUTE_Y_AXIS` (applies to routes, beacon positions and the calibration spot)
  - `CALIBRATION_POINT` ("x, y, facingDegrees")

  Never print or commit it. (The owner's copy may not have the new keys yet; all are optional.)

## 4. Source map (`BestHackMobile/BestHackMobile/`)

| Path | What it does |
|---|---|
| `App/BestHackMobileApp.swift` | `@main`, shows `RootView`. |
| `App/RootView.swift` | `AppModel.shared` (owns `GuideModel`, `VisitLog`, `AccountStore`, `calibrationDone`; a singleton so no throwaway copies). Phases: login → welcome (first time) → calibration (every launch) → museum. Starts/stops the guide with scene phase, keeps the screen on in the museum, preloads 3D models + beacon list at launch. |
| `Design/Theme.swift` | **Design system:** colours (`accent`, `accentSoft`, `accentText`, `coral`, `coralText`, `mint`, `mintText`, `amber`, `red`, `redText`, `ink`, `inkSoft`, `page`, `card`, `cardSunken`, `line`, `lineStrong`), system fonts (`Theme.title(.title)` etc., Dynamic Type), `AppButtonStyle` (primary, secondary, danger, secondaryDanger, quiet), `RoundIconButtonStyle`, `CardButtonStyle`, `.card()`, `.floatingPanel()`, `ProgressLine`, `Chip`, `Eyebrow`, `ExhibitThumbnail`. |
| `Design/BloopOrb.swift` | The app's mark (sound source with rings; ripples only while talking). Replaced the cartoon mascot. |
| `Features/Login/LoginView.swift` | Email + password → `AccountStore.signIn`; *Try the demo* → `signInDemo()` (test@test.test / test, always continues); server URL editor. |
| `Features/Welcome/WelcomeView.swift` | 4-step intro: hello → mode (`ChoiceCard`) → AirPods left/right test → beacons (asks location permission). |
| `Features/Calibration/CalibrationView.swift` | Stand on the spot, face front, tap Calibrate, hold still 3 s (`guide.beginCalibration()` → `finishCalibration()`). Shows AirPods + beacon status. Listening mode: spoken instructions, bottom half is one big button. |
| `Features/Map/MapScreen.swift` | Map mode screen: map layer, top row (`MapStyleSlider` 3D/Look/2D + settings), auto-hiding `NoticeBanner`, `GuidePanel`, sheets. `GuideEvents` = tiny view that owns all haptic triggers + marks visits (so guide events don't redraw the screen). Routes to `ListenModeView` in listening mode. |
| `Features/Map/GuidePanel.swift` | The one bottom card. `ExploreCard` (place + position dot, "You're at X · Story" when at an exhibit, Next up, Let's go, all-exhibits button), `PreviewCard`, `WalkingCard` (arrow, metres, progress, Repeat, ✕ with confirmation), `StoryButton`, `nextExhibits()`, `turnInstruction()`. No arrival pop-up. |
| `Features/Map/Map3DView.swift` | 3D map (RealityKit `RealityView`, `content.camera = .virtual`). Overview ↔ eye-level blend. Camera always follows `guide.position`; bearing (overview and eye level) and eye-level pitch come from `guide.liveHead()` **read every frame** (AirPods, no tick delay), falling back to `facingYaw`/`mapHeading`/north. The goal is recomputed inside the `TimelineView` each frame; observed `facingYaw` (updated straight from `head.onMotion`) wakes the loop. Bearing ease 24/s eye level, 16/s overview. Only gesture: pinch zoom (25–300 m) + tap pins. Pins and room labels are **Canvas symbols** placed each frame (not SwiftUI views). `MuseumMapScene` = RealityKit side (2 directional lights, **no shadows**, building, exhibits, user marker, coral route band, highlight disc). |
| `Features/Map/MapCamera.swift` | `MapStyle`, `CameraGoal`, `MapCameraRig` (smoothing per frame, pose, `projector(in:)` world→screen). **FOV 75° vertical.** |
| `Features/Map/Map2DView.swift` | Canvas floor plan (north up), centred on you, pinch zoom, tap pins. Shows beacon accuracy circle. |
| `Features/Map/MapPalette.swift` | 2D map colours (floor tints match the 3D model). |
| `Features/Listen/ListenModeView.swift` | Listening mode: 2×2 grid (yellow/blue/pink/green, black text) of `MuseumInfo.nearest(to:count:4, excluding: atExhibit)`. On show: `Haptics.attention()` + spoken list (each option from its direction). Tap → `Haptics.selected()` + "…tap again to go there"; same corner within 20 s → `Haptics.confirmed()` + `navigate`. Hold → repeat. Walking: top half directions (hold = story), bottom half stop (tap twice). Choices are kept stable until guidance ends / you ask again. |
| `Features/Artifacts/` | `ArtifactListView` (grid + progress), `ArtifactDetailView`, `ArtifactModelView` (turntable driven by `SceneEvents.Update`, not a SwiftUI timeline). |
| `Features/Settings/SettingsView.swift` | Settings (mode, Voice, Calibrate again, guide toggles, position + demo walk, account: back to welcome screen, reset visits, log out), `VoicePickerView` (Apple/ElevenLabs, voice list with ▶︎ preview, quality, custom voice ID), `AdvancedSettingsView` (server, beacons, ElevenLabs key, routes, credits), `BeaconsView` (live RSSI/distance per beacon, path-loss exponent stepper). |
| `Models/GuideModel.swift` | **The guide (core logic, `@Observable`)**, see §6. |
| `Models/Language.swift` | `AppLanguage` (pl default / en), `LanguageSettings.shared`, `tr(en, pl)`, `trNow`, `metersText` (Polish plurals), `MuseumText` (Polish exhibit titles/galleries/stories + place names), `Exhibit.name/galleryName/story`, `placeText()`. |
| `Models/VoiceCommands.swift` | Pure keyword parser (pl + en): corner by position/colour/number, exhibit names, yes/no, story, next, repeat, stop, where am I, which way. Words are folded (lowercase, no accents, ł→l). |
| `Models/VoiceControl.swift` | Listen once: beep → `VoiceRecorder` (stops after ~1 s of quiet) → `ElevenLabsSTT` → `VoiceCommands.parse`. `state` idle/listening/thinking, `problem`. |
| `Audio/VoiceRecorder.swift` | AVAudioRecorder (16 kHz AAC) with metering, adaptive speech threshold, mic permission (`AVAudioApplication`). |
| `Services/ElevenLabs/ElevenLabsSTT.swift` | `POST /v1/speech-to-text`, model `scribe_v2` (falls back to `scribe_v1` on 400/422), `language_code` pol/eng. Key needs Speech to Text permission. |
| `Models/AccountStore.swift` | Account (UserDefaults `account.current`), server override (UserDefaults `backend.url`), `backend` client. Login = the backend's session cookie (no token any more). |
| `Models/CalibrationSpot.swift` | Calibration spot (point, facing, spoken name). Default South Entrance (0.2, 56) facing north; Secrets `CALIBRATION_POINT`; backend may override. |
| `Models/VisitLog.swift` | Visited exhibits, persisted in UserDefaults `visits.exhibits`. |
| `Models/UserMode.swift` | `.standard` ("With the map") / `.blind` ("Just listening"). |
| `Models/VoiceSettings.swift` | Apple vs ElevenLabs voice, key in Keychain, `availableVoices` (account voices, else `ElevenLabsTTS.premadeVoices`), `client(voiceID:)`. |
| `Models/Museum/MuseumInfo.swift` | Decodes the info JSON (room polygons/centres/bounding boxes precomputed); `nearest(to:count:excluding:)`; `MuseumGeometry`. |
| `Audio/` | `SpatialAudioEngine` (HRTF bloop + spoken voice in 3D), `Bloop`, `SpeechOutput`, `AppleSpeech` (voice lookup cached per language). |
| `Services/Beacons/BeaconScanner.swift` | Core Location iBeacon ranging for the UUID (iOS only; Core Bluetooth can't see iBeacons). ~1 Hz `onReadings`. |
| `Services/Beacons/BeaconPositioner.swift` | Pure maths: RSSI smoothing (EMA 0.35, stale after 4 s), log-distance model (n = 2.3, per-beacon calibration offsets), weighted Gauss–Newton trilateration (≥2 beacons), circle projection (1 beacon), calibration offsets (half shared median, half per beacon, ±15 dB). |
| `Services/Beacons/BeaconDirectory.swift` | Flexible decoder for the backend's beacon list (+ optional calibration spot). Lookup by major/minor (or minor only). |
| `Services/Location/PositionService.swift` | **Beacons + steps → position.** Works in a `FloorFrame` (museum for server beacons, your room for `layout`). Each ranging round: per-beacon range updates into `PositionFilter` (σ = 0.6 + 0.35·d, height removed with `layout.beaconHeight`), 4 rounds of all-rejected → restart from trilateration. Each step (`MotionTracker.onStep`): move along the heading (`headingSource` auto/phone/AirPods; phone heading lined up in `calibrate()`, dropped when motion restarts). `source` (.beacons/.steps/.lastKnown/.demo), layout editing helpers, `heardBeacons()`, `measurePower()`, directory cache, offsets. |
| `Services/Location/PositionFilter.swift` | Pure 2D Kalman filter: `predict` (0.02 m²/s standing, 0.25 walking, 0.8 without steps), `step` (along/across-track noise), `range` (EKF update, 3σ soft gating), `clamp`. |
| `Services/Beacons/BeaconLayout.swift` | Your own layout (UserDefaults `beacons.layout`): beacons in room metres (x right, y ahead from a corner), calibration point + facing in the room, walk scale, beacon height. `FloorFrame`: frame ↔ museum (calibration point = museum calibration spot; paper coords = (x, −z)). |
| `Services/Motion/MotionTracker.swift` | Phone `CMDeviceMotion` 50 Hz **on a background queue** (`MotionProcessor`, lock-protected; only steps hop to the main actor): steps (vertical accel, 3 Hz low-pass, peak > 0.5 m/s² and swing > 1.0, first step after a pause confirmed by the next within 1.2 s, Weinberg length 0.48·swing^¼) and heading (gyro spin about gravity, integrated; no compass). |
| `Features/Settings/BeaconLayoutView.swift` | Settings → Beacon layout and steps: toggle, live room plan (Canvas, beacons with distance rings, you + accuracy + walking direction), beacon list/editor (pick from heard beacons, measure power at 1 m), room placement, step settings. |
| `Services/Backend/BackendClient.swift` | Session login (CSRF → `JSESSIONID` cookie), register/me/logout, beacons, port 8081 added to a bare host, WebSocket request. `PositionSocket.swift` (live `/ws/position`) exists but is **not wired in** (see §9). |
| `Services/Haptics.swift` | Core Haptics patterns for listening mode: `attention` (3 knocks), `selected` (long buzz), `confirmed` (long-short-long), `warning`. |
| `Services/` | `HeadTracker` (AirPods; `yaw` not observed; `session` bumps on reconnect), `KeychainStore` (generic service/account), `MuseumAssets` (**caches** loaded entities, returns clones; `preload`), `Routing/`, `ElevenLabs/`. |
| `Resources/` | `Assets.xcassets` (`Exhibits/Exhibit-<key>`), `Museum/` (`MuseumMap.usdz`, `Artifacts/*.usdz`, info JSON). |

**UserDefaults / AppStorage keys:**
- App state: `userMode`, `onboarding.done`, `map.style`, `visits.exhibits`, `account.current`, `backend.url`, `backend.defaultSeen`
- Guide settings: `guide.autoAnnounce`, `guide.selectByLooking.v2` (default off), `guide.listenOnArrival`, `audio.bloopVolume`, `app.language`,
  `guide.wakeWord.enabled` (default on), `guide.wakeWord.phrase` (empty = "Hej Bloop" / "Hey Bloop")
- Beacons/position: `beacons.directory`, `beacons.offsets`, `beacons.layout`, `position.motion` (default on), `position.headingSource`, `position.stepFactor`
- Voice: `voice.engine.v2`, `voice.elevenLabs.voiceID`, `voice.elevenLabs.model`, `voice.speed`, `voice.elevenLabs.userPicked`
- Keychain: service `ElevenLabs`/`api-key`, service `Backend`/`token`

## 5. Museum data and coordinates

- **Units and axes:** metres, **+x east, −z north, +y up**, floor at y = 0. The origin is the centre of the building, rotated 1.03° so the walls are axis-aligned. A 2D floor point is `(x, z)`.
- **Yaw:** 0 = facing north (−z), positive = turned left. `MuseumGeometry.forward(yaw:)` / `yaw(from:to:)`.
- **The JSON** (`FieldMuseum_MainLevel_info.json`): `rooms[]`, `exhibits[]`, `displays[]`, `doors[]`,
  `points_of_interest[]`, `meta.nave` (Stanley Field Hall), `building_outline`, `georeference` (unused now).
- **Exhibit keys:** `maximo`, `elephants`, `totems` (hall), `tsavo_lions` (Mammals of Africa), `seabirds` (Birds),
  `mask`, `pawnee_lodge` (Ancient Americas), `mastaba` (Inside Ancient Egypt).
- **Default calibration spot / start:** (0.2, 56), just inside the South Entrance, facing north into the hall.
- **Beacon and route coordinates** use the same (x, z) numbers (y = model z) unless `ROUTE_Y_AXIS = north`.
- **Data licence:** © 2020 Field Museum, CC BY 4.0. The credit must stay in the app (Settings → Server, beacons and keys → About).

## 6. GuideModel API (what the UI uses)

- **Fine state (maps only; changes often):** `position` (smoothed toward `positioning.position` at 20 Hz),
  `facingYaw?` (AirPods + calibration offset, set from every AirPods sample and the tick; nil without calibrated AirPods),
  `mapHeading?` (facing with 4° deadband), `liveHead()` (not observed: the AirPods right now, for per-frame use).
- **Coarse state (text/lists; use these in cards so they don't redraw constantly):** `here` (every ~1 m),
  `heading?` (every ~10°), `placeName`, `nearby` (4 closest), `atExhibit?`. `distance(to:)` and `directions(to:)` use
  the coarse values; `spokenDirections(to:)` uses the fine ones (it's said once).
- **Calibration:** `isCalibrated`, `headingCalibrated`, `beginCalibration()`, `finishCalibration() -> CalibrationResult(beacons:airPods:)`, `skipCalibration()`.
  AirPods reconnect (`head.session` changes) → heading dropped + statusMessage asking to recalibrate.
- **Guidance:** `preview?` (settable), `target?`, `route`, `routeVersion`, `remaining?`, `progress`, `turn`, `arrived?`;
  `navigate(to:)` (says "You're already at X" if you are), `stopGuidance()`, `follow(route:to:)`, `follow(routeJSON:)`.
- **Speech:** `speak(_ [Utterance])` (replace), `speakAfterCurrent(_:)` (queue), `tellStory(of:)`, `announceNearby()`,
  `announceLocation()`, `announceDirection()`, `previewVoice(id:name:)`, `stopSpeaking()`. `Utterance(text:toward:)`.
- **Settings:** `selectByLooking` (map mode only, default off), `autoAnnounce` (map mode only, needs calibration), `demoWalk`, `mode`.
- **Haptic counters:** `facedEvent`, `selectionEvent`, `waypointEvent`, `arrivalEvent`, `onTrackEvent`, `offRouteEvent`
  (observed only by `GuideEvents`).
- **Sub-objects:** `info`, `audio`, `voice`, `positioning` (PositionService), `head`.
- **Talking:** `voiceInput` (VoiceControl), `listen()`, `perform(heard)` (story/repeat/where/which way/stop),
  `sayNotUnderstood`, `speechFinishedEvent` + `listenAfterSpeech` (map mode listens after the arrival message;
  listening mode listens after reading the four options or a choice). `listenOnArrival` setting.
- **Wake phrase:** `wakeWord` (`Audio/WakeWordListener`) listens all the time with Apple `SFSpeechRecognizer`
  (on-device when supported, own `AVAudioEngine` input tap, restarts every 50 s, fuzzy word match). When heard →
  `wakeEvent += 1`; `MapScreen.GuideEvents` (map mode) and `ListenModeView` (listening mode) then run the normal
  ElevenLabs `listen()`. `listen()` pauses the wake listener while recording. Needs an ElevenLabs key; stops in `stop()`.
- **Bloops** (`updateGuidance`): rhythm and sound come from `audio.bloopStyle` (`Audio/BloopStyle.swift`, Settings ›
  Guide › Bloop rhythm: *Guiding* quick bloops / *Calm* wooden "tok" ~1/s / *Chill* soft tone every 2–3 s; UserDefaults
  `audio.bloopStyle`). Facing the route (< 15°, released at 32°) → `onTrack`, chime (volume + cooldown per style) +
  heavy haptic, then a quiet reminder every few seconds; turning away → the style's normal bloops at once (respecting
  `minimumGap`). Picking a style plays a preview bloop.
- **Sound:** listener orientation includes head pitch and is updated from `HeadTracker.onMotion` at the AirPods' rate.
  Bloop has harmonics + a noise click (better localisation), reverb blend 0.32, environment reverb −12 dB.
  Session is `.playAndRecord` + A2DP only (AirPods stay stereo, mic = iPhone). `audio.pause()/resume()` on background.
- **Arrival also by beacon:** a beacon within ~4 m of an exhibit reading ≤ 1.5–2 m counts as being at that exhibit.
- **Behaviour:** ticks 20×/s. Arrival = within 2 m of the route end or footprint + 2.5 m **for 0.7 s**.
  Off-route > 8 m → re-route. Choose-by-facing: 1.5 s, never the exhibit you're standing at (that caused the
  "arrived" pop-up loop). Demo walk: 1.3 m/s along the route.

## 7. Gotchas (learned the hard way)

1. **`RealityView` on iOS shows the AR camera by default.** Always set `content.camera = .virtual` in the make closure.
2. **Simulator crash:** "MTLDebugRenderCommandEncoder … Draw Errors Validation … fsRealityPbr" → Metal API Validation off (shared scheme sets `enableGPUValidationMode = "1"`).
3. **Background:** the `RealityView` background is transparent; the sky is a SwiftUI gradient (always daytime).
4. **Building group names** come from USD prim names (`findEntity(named: "Walls")`). Keep them stable in the generator: `Outside`, `Floors`, `Walls`, `Blocks`, `Hall`, `Entrances`, `Furniture`, `Displays`.
5. **Pins and labels are Canvas symbols** projected with `MapCameraRig.projector(in:)` (same pose as the RealityKit camera). Change the FOV only in `MapCameraRig.fieldOfView`.
6. **Camera loop:** `MapCameraRig` is deliberately *not* observable; advanced inside a `TimelineView` that pauses when settled (`settleTick`). Keep camera goals stable (deadbands) or it never pauses.
13. **Keep the main thread free for head tracking:** AirPods motion arrives on the main queue and the map reads it per frame. Anything running many times a second (motion sensors, speech-recognizer partial results) must do its work off the main thread and only hop over for real events (a step, a wake-phrase match). That's what made the map feel laggy once.
7. **Throwaway instances:** `@State var x = SomeClass()` creates a throwaway instance on every view init. App-wide objects live in `AppModel.shared`; `MuseumMapScene.init()` is empty.
8. **Performance rules:** don't read fine guide state (`position`, `facingYaw`) in cards/lists; don't put `.shadow` or materials over the live 3D view; keep event counters out of big views; RealityKit models come from the `MuseumAssets` cache.
9. **Text contrast:** white text only on `accent`/`red` faces; use `accentText`, `coralText`, `mintText`, `redText`, `inkSoft` on cards. `amber`/`coral`/`mint` fills are for dots, progress and icons.
10. **Thumbnails** are `Image("Exhibit-<key>")` from the asset catalog.
11. **iBeacons need Core Location ranging + location permission**; the Simulator can't range. CLBeacon `rssi == 0` = not heard this round.
12. **Deleting files on the Mac** from the device shell needs permission; moving them (e.g. into `mobile/backups/removed-files/`) works.

## 8. 3D models: how to rebuild

```sh
cd resources
python3 tools/build_all.py FieldMuseum_MainLevel_info.json .               # models + thumbnails + previews
python3 tools/build_all.py FieldMuseum_MainLevel_info.json . --no-pictures  # models only
```

Deterministic output. After rebuilding: copy `MuseumMap.usdz` and `Artifacts/` into
`BestHackMobile/BestHackMobile/Resources/Museum/`, and the thumbnails into
`Assets.xcassets/Exhibits/Exhibit-<key>.imageset/<key>.png` (square, 480 px). Generator files: `meshkit.py`,
`usdz.py`, `palette.py`, `build_building.py`, `build_exhibits.py`, `preview.py`, `build_all.py`.
Sizes: building ~44k triangles / 2.4 MB, exhibits 0.4k–19k triangles each, ~4.4 MB total.

## 9. Status (end of 10 Oct, evening session)

**Done this session** (owner's list):
- New look: indigo/coral/off-white palette, flat buttons, system font, orb mark instead of mascot; no confetti.
- Simpler map screen: sliding 3D/Look/2D switch + settings on top, one card at the bottom; locate button, star chip,
  DEMO tag, WalkPad and the extra exhibit row are gone.
- Performance: Canvas pins/labels, no RealityKit shadows, no SwiftUI shadows over the 3D view, coarse vs fine guide
  state, haptic triggers isolated, model cache + preload, cached Apple voice lookup, turntable in RealityKit,
  HeadTracker no longer spams observers, room polygons precomputed, AppModel singleton.
- GPS removed → BLE beacon positioning (ranging, smoothing, trilateration, filter, debug screen).
- Calibration screen at start (position + AirPods front + beacon offsets).
- Map controlled only by you/AirPods (no drag/rotate/compass/tap-to-move); pinch zoom kept. FOV 60° → 75°.
- Arrival pop-up removed (and the arrive-again loop fixed).
- Listening mode: 4 coloured corners, spoken positions, strong haptics, tap + tap-again to confirm.
- ElevenLabs voice picker with previews (+ premade voices when listing isn't allowed).
- Login screen + demo login (test@test.test / test, sent to the backend, continues regardless).
- "Back to the welcome screen" and "Log out" in Settings.

**Round 2 (same evening):** non-scrolling calibration, AirPods pitch in Look view, more frequent / pitch-changing
bloops with a "right way" chime, darker 3D map (dusk sky, dimmed lights) and dark 2D plan, sound stops when leaving
the museum screens or backgrounding, listening-mode grid as VStack/HStack + one-sentence announcements (less lag),
slower speech (`voice.speed`, default 0.88, ElevenLabs `voice_settings.speed` + Apple rate), Polish UI/TTS + language
switch, default ElevenLabs voice = first account voice whose name contains "Makłowicz" (until the user picks one),
ElevenLabs speech-to-text commands (listening mode chooser + "Mów" strip, map mode mic button, after arrival).

**Round 3:** on the right path the bloops go quiet and sparse (see §6), bigger talk buttons (map card capsule "Mów",
listening-mode strip 120 pt), configurable wake phrase (Settings → Guide), confirm state in listening mode = black band
"Stuknij ponownie / lub powiedz „tak”" across the bottom of the chosen corner, backend default `http://172.20.10.6`.

**Round 4 (11 Oct, early morning):** own beacon layout + step tracking ("walk through the virtual museum in any room"):
Settings → Beacon layout and steps. Filter + step detector were checked with a Python simulation (5×5 m room, 4 beacons,
σ 4 dB): mean error 1.26 m beacons-only → 0.80 m fused, worst 3.2 m → 1.7 m.

**Merge note:** another Claude session had built a backend integration (session login, live `/ws/position` WebSocket,
`MuseumGrid` routing, sound-per-screen). Parts of it were overwritten by this session's syncs; the build was repaired
by porting sound-per-screen into GuideModel and unhooking `guide.server` in RootView. The full version is in
`mobile/backups/backend.tgz` if it should be merged back.

**Verification:** round 1 built and ran on the owner's Mac. Rounds 2–4 are syntax-checked only: **build it (⌘B) first.**
If looking up moves the Look view down, flip `HeadTracker.pitchSign` to -1.

**Open ideas / not done yet:**
- Read `../backend` and `../embedded` to confirm the API paths and that the ESP32s advertise iBeacon frames
  with major/minor (the app assumes that).
- Real walking routes need `ROUTE_API_URL`; without it guidance is a straight line through walls.
- Background use (screen locked) stops ranging and head tracking; the app keeps the screen on instead.
- Nothing has been committed to git since "Initial Commit". Commit when the build is green.

## 10. Working on this from a cloud Claude session

- The Mac is reachable through the device tools when the desktop app is linked. The connected folder is
  `/Users/stanislawsikora/BEST hacks 2026/mobile` (mounted as `$HOME/mnt/mobile` in the device shell, a Linux VM: no Xcode there).
- **Moving files:** tar on the device into `mobile/backups/`, `device_stage_files` the one tarball, untar in the cloud.
  Back: tar in the cloud into `/mnt/user-data/outputs/`, `device_commit_files` (stagedPath) into `mobile/backups/`,
  untar into a scratch dir in the device shell and `cp` over (cp overwrites in place; rm/unlink need permission).
- **Compiling:** Swift can't be compiled in the cloud. Syntax check: build tree-sitter (GitHub `tree-sitter/tree-sitter`
  `lib/src/lib.c`) + `alex-pinkus/tree-sitter-swift` (branch `with-generated-files`) into a tiny C checker.
  The real check is Xcode on the Mac (ask the owner to press ⌘B / ⌘R, or use computer use if granted).
