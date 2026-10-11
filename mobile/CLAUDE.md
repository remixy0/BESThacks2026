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
  - `BACKEND_HOST`: the backend's IP (e.g. `192.168.1.20`, http + port 8081 assumed) or full URL; empty = local data only. Settings → Server wins. Old `BACKEND_URL` still read.
  - (`ROUTE_API_URL` is no longer used: routes come from the backend WebSocket or the bundled grid.)
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
| `Features/Login/LoginView.swift` | Email + password → `AccountStore.signIn` (or *Create account* → `register`); *Try the demo* → `signInDemo()`; server IP editor; language switch with flags. |
| `Features/Welcome/WelcomeView.swift` | 4-step intro: hello → mode (`ChoiceCard`) → AirPods left/right test → beacons (asks location permission). |
| `Features/Calibration/CalibrationView.swift` | Stand on the spot, face front, tap Calibrate, hold still 3 s (`guide.beginCalibration()` → `finishCalibration()`). Shows AirPods + beacon status. Listening mode: spoken instructions, bottom half is one big button. |
| `Features/Map/MapScreen.swift` | Map mode screen: map layer, top row (`MapStyleSlider` 3D/Look/2D + settings), auto-hiding `NoticeBanner`, `GuidePanel`, sheets. `GuideEvents` = tiny view that owns all haptic triggers + marks visits (so guide events don't redraw the screen). Routes to `ListenModeView` in listening mode. |
| `Features/Map/GuidePanel.swift` | The one bottom card. `ExploreCard` (place + position dot, "You're at X · Story" when at an exhibit, Next up, Let's go, all-exhibits button), `PreviewCard`, `WalkingCard` (arrow, metres, progress, Repeat, ✕ with confirmation), `StoryButton`, `nextExhibits()`, `turnInstruction()`. No arrival pop-up. |
| `Features/Map/Map3DView.swift` | 3D map (RealityKit `RealityView`, `content.camera = .virtual`). Overview ↔ eye-level blend. Camera always follows `guide.position`; overview bearing = `guide.mapHeading` (AirPods with 4° deadband, north-up without); eye level = `guide.facingYaw`. Only gesture: pinch zoom (25–300 m) + tap pins. Pins and room labels are **Canvas symbols** placed each frame (not SwiftUI views). `MuseumMapScene` = RealityKit side (2 directional lights, **no shadows**, building, exhibits, user marker, coral route band, highlight disc). |
| `Features/Map/MapCamera.swift` | `MapStyle`, `CameraGoal`, `MapCameraRig` (smoothing per frame, pose, `projector(in:)` world→screen). **FOV 75° vertical.** |
| `Features/Map/Map2DView.swift` | Canvas floor plan (north up), centred on you, pinch zoom, tap pins. Shows beacon accuracy circle. |
| `Features/Map/MapPalette.swift` | 2D map colours (floor tints match the 3D model). |
| `Features/Listen/ListenModeView.swift` | Listening mode: 2×2 grid (yellow/blue/pink/green, black text) of `MuseumInfo.nearest(to:count:4, excluding: atExhibit)`. On show: `Haptics.attention()` + spoken list (each option from its direction). Tap → `Haptics.selected()` + "…tap again to go there"; same corner within 20 s → `Haptics.confirmed()` + `navigate`. Hold → repeat. Walking: top half directions (hold = story), bottom half stop (tap twice). Choices are kept stable until guidance ends / you ask again. |
| `Features/Artifacts/` | `ArtifactListView` (grid + progress), `ArtifactDetailView`, `ArtifactModelView` (turntable driven by `SceneEvents.Update`, not a SwiftUI timeline). |
| `Features/Settings/SettingsView.swift` | Settings (mode, Voice, Calibrate again, guide toggles, position + demo walk, account: back to welcome screen, reset visits, log out), `VoicePickerView` (Apple/ElevenLabs, voice list with ▶︎ preview, quality, saved speech: count/size, download stories, delete; custom voice ID), `AdvancedSettingsView` (server, beacons, ElevenLabs key, routes, credits), `BeaconsView` (live RSSI/distance per beacon, path-loss exponent stepper). |
| `Models/GuideModel.swift` | **The guide (core logic, `@Observable`)**, see §6. |
| `Models/Language.swift` | `AppLanguage` (pl default / en), `LanguageSettings.shared`, `tr(en, pl)`, `trNow`, `metersText` (Polish plurals), `MuseumText` (Polish exhibit titles/galleries/stories + place names), `Exhibit.name/galleryName/story`, `placeText()`. |
| `Models/VoiceCommands.swift` | Pure keyword parser (pl + en): corner by position/colour/number, exhibit names, yes/no, story, next, repeat, stop, where am I, which way. Words are folded (lowercase, no accents, ł→l). |
| `Models/VoiceControl.swift` | Listen once: beep → `VoiceRecorder` (stops after ~1 s of quiet) → `ElevenLabsSTT` → `VoiceCommands.parse`. `state` idle/listening/thinking, `problem`. |
| `Audio/WakeWordListener.swift` | Wake phrase (Settings › "Mów bez dotykania"): Apple `SFSpeechRecognizer` (pl-PL/en-US, on-device when supported) on its own `AVAudioEngine` input tap, fuzzy match on folded words, restarts every 50 s. On hearing it: `heardEvent += 1` → map mode `runMapVoice`, listening mode `listenAndAct()`. `GuideModel.listen()` calls `suspend()`/`resume()` around recording; `start()`/`stop()` follow the guide. Off by default (mic stays on). |
| `Audio/VoiceRecorder.swift` | AVAudioRecorder (16 kHz AAC) with metering, adaptive speech threshold, mic permission (`AVAudioApplication`). |
| `Services/ElevenLabs/SpeechCache.swift` | **TTS cache.** `SpeechCache.shared`: every ElevenLabs sentence is saved as raw PCM16 24 kHz in Library/Caches/ElevenLabsSpeech, key = SHA-256 of voice + model + speed + text ("v1|pcm_24000|…"; bump "v1" if the request/voice settings change). Saved → played from the phone, no request; in-flight downloads are shared (`SpeechClip`, many listeners); a started download always finishes and is saved even if playback stops; LRU trim above 250 MB. `ElevenLabsTTS.stream` reads through it, `ElevenLabsTTS.download` does the actual request. GuideModel: stories are spoken as two sentences ("Name." + story) so the story recording is shared; `speakNext` prefetches the next queued sentence; `downloadStories()` / `storyDownload` / `savedStoryCount()` back Settings › Voice › "Zapamiętane nagrania". STT is never cached. |
| `Services/ElevenLabs/ElevenLabsSTT.swift` | `POST /v1/speech-to-text`, model `scribe_v2` (falls back to `scribe_v1` on 400/422), `language_code` pol/eng. Key needs Speech to Text permission. |
| `Models/AccountStore.swift` | Account (UserDefaults `account.current`: email, role, `isLocal`), email+password in Keychain (`Backend`/`login`) for automatic re-login, server override (UserDefaults `backend.url`). `signIn`: 401 → wrong password; server problems → **failsafe**: signed in locally (`isLocal`), `notice` shown on the map. `socketSession()` → `.ready(client)` / `.noServer` / `.unavailable` (re-logs in when the session expired; stops after a 401). |
| `Models/CalibrationSpot.swift` | Calibration spot (point, facing, spoken name). Default South Entrance (0.2, 56) facing north; Secrets `CALIBRATION_POINT`; backend may override. |
| `Models/VisitLog.swift` | Visited exhibits, persisted in UserDefaults `visits.exhibits`. |
| `Models/UserMode.swift` | `.standard` ("With the map") / `.blind` ("Just listening"). |
| `Models/VoiceSettings.swift` | Apple vs ElevenLabs voice, key in Keychain, `availableVoices` (account voices, else `ElevenLabsTTS.premadeVoices`), `client(voiceID:)`. |
| `Models/Museum/MuseumInfo.swift` | Decodes the info JSON (room polygons/centres/bounding boxes precomputed); `nearest(to:count:excluding:)`; `MuseumGeometry`. |
| `Audio/` | `SpatialAudioEngine` (HRTF bloop + spoken voice in 3D; `bloopStyle`, one buffer per style), `Bloop` (sounds: `buffer` guiding, `drop` calm wooden tok, `softTone` chill G4 tone, `chime`, `listenCue`), `BloopStyle` (guiding/calm/chill: `beat(degrees:onTrack:metersLeft:)` → interval/pitch/volume/muffled, `onTrackPause`, `minimumGap`, `chimeVolume`, `chimeCooldown`), `SpeechOutput`, `AppleSpeech` (voice lookup cached per language). |
| `Services/Beacons/BeaconScanner.swift` | Core Location iBeacon ranging for the UUID (iOS only; Core Bluetooth can't see iBeacons). ~1 Hz `onReadings`. |
| `Services/Beacons/BeaconPositioner.swift` | Pure maths: RSSI smoothing (EMA 0.35, stale after 4 s), log-distance model (n = 2.3, per-beacon calibration offsets), weighted Gauss–Newton trilateration (≥2 beacons), circle projection (1 beacon), calibration offsets (half shared median, half per beacon, ±15 dB). |
| `Services/Beacons/BeaconDirectory.swift` | Flexible decoder for the backend's beacon list (+ optional calibration spot). Lookup by major/minor (or minor only). |
| `Services/Location/PositionService.swift` | Beacons → filtered position (max step 1.8 m/s + 1.5 m, gain by accuracy), `source` (.beacons/.lastKnown/.demo), status text, directory cache (UserDefaults `beacons.directory`), offsets (UserDefaults `beacons.offsets`), `calibrate()`, demo walk positions. |
| `Services/Backend/BackendClient.swift` | Backend HTTP per INTEGRATION.md: session + CSRF (`/api/auth/csrf` → `/api/auth/login`, cookie JSESSIONID in `HTTPCookieStorage.shared`), `register`, `me`, `logout`, `webSocketRequest()` (copies the cookie onto the WS handshake), `isServerProblem(error)` (decides failsafe), `url(from:)` (bare IP → http://IP:8081). Beacons: tries `/api/beacons` (not in the contract). |
| `Services/Backend/PositionSocket.swift` | `/ws/position` WebSocket (`guide.server`): keeps position + destination and re-sends them after every reconnect; position ≤3/s and ≥ every 2 s; one receive loop by `type` (`navigation`, `policy`, `error`); ping heartbeat; reconnect 2→30 s; 401/403/1008 → `onSessionRejected` → re-login. `state`: off/noServer/connecting/online/offline. |
| `Services/Routing/MuseumGrid.swift` | **Local failsafe router.** Loads `Resources/Museum/field-museum-main-level.grid.json` (the backend's own map, 0.2 m cells, `1` = walkable; x = model X, y = model Z), A* (8 neighbours, no corner cutting) + string-pulling; avoids `policy.zones` (+0.3 m). `approaches[exhibitKey]` (POI `sourceId` = our key), `unreachable` (approach null; in the 11 Oct map every exhibit is reachable, only the restroom isn't), `exits`. Keep the JSON identical to `backend/java-backend/src/main/resources/maps/`. |
| `Services/Haptics.swift` | Core Haptics patterns for listening mode: `attention` (3 knocks), `selected` (long buzz), `confirmed` (long-short-long), `warning`. |
| `Services/` | `HeadTracker` (AirPods; `yaw` not observed; `session` bumps on reconnect), `KeychainStore` (generic service/account), `MuseumAssets` (**caches** loaded entities, returns clones; `preload`), `Routing/`, `ElevenLabs/`. |
| `Resources/` | `Assets.xcassets` (`Exhibits/Exhibit-<key>`), `Museum/` (`MuseumMap.usdz`, `Artifacts/*.usdz`, info JSON). |

**UserDefaults / AppStorage keys:**
- App state: `userMode`, `onboarding.done`, `map.style`, `visits.exhibits`, `account.current`, `backend.url`
- Guide settings: `guide.autoAnnounce`, `guide.selectByLooking.v2` (default off), `guide.listenOnArrival`, `audio.bloopVolume`, `audio.bloopStyle` (guiding/calm/chill, default guiding), `app.language`
- Beacons: `beacons.directory`, `beacons.offsets`
- Wake phrase: `voice.wakeWord.enabled` (default off), `voice.wakeWord.phrase` (empty = "Hej przewodniku" / "Hey guide")
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
  `facingYaw?` (AirPods + calibration offset; nil without calibrated AirPods), `mapHeading?` (facing with 4° deadband).
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
- **Screens/sync:** `screen`, `screenGeneration`, `screenAppeared(_:)`, `screenDisappeared(_:)`, `userTapped()`; `Utterance(text:toward:scope:)` with `Scope.screen/.guidance` (see gotcha 13).
- **Talking:** `voiceInput` (VoiceControl: `listen`, `finishListening` = done talking, `cancel` = throw away), `wakeWord` (WakeWordListener), `listen()` (returns nil if already listening), `perform(heard)` (story/repeat/where/which way/stop),
  `sayNotUnderstood`, `speechFinishedEvent` + `listenAfterSpeech` (map mode listens after the arrival message;
  listening mode listens after reading the four options or a choice). `listenOnArrival` setting.
- **Bloops** (`updateGuidance`): wrong way → every 0.3 s, pitch rising 0.6 → 1.45 as you turn toward the route
  (muffled when it's behind you); facing it (< 15°, released at 28°) → `onTrack = true`, chime + heavy haptic
  (`onTrackEvent`), then only a **quiet** bloop (35 % volume, pitch 1.6) every 3.5 s (2 s in the last 6 m); turning away
  (> 28°) switches straight back to the normal quick bloops. `playBloop(…, volume:)`. No AirPods → steady 0.35–0.9 s.
  Those numbers are the **Guiding** style. `audio.bloopStyle` (Settings › Guide › "Rytm dźwięków", plays a sample when changed)
  picks the rhythm + sound from `BloopStyle`: **Calm** = wooden tok, off course every 0.8–1.3 s at 75 %, on course every 6 s
  (3.5 s near the end) at 30 %, chime 60 %; **Chill** = soft tone, off course every 2–3.5 s at 55 %, on course every 12 s (6 s)
  at 22 %, chime 35 % and at most every 8 s, min 1.2 s between bloops. Direction cues (position, pitch rise, muffling) are the same.
- **Sound:** listener orientation includes head pitch and is updated from `HeadTracker.onMotion` at the AirPods' rate.
  Bloop has harmonics + a noise click (better localisation), reverb blend 0.32, environment reverb −12 dB.
  Session is `.playAndRecord` + A2DP only (AirPods stay stereo, mic = iPhone). `audio.pause()/resume()` on background.
- **Arrival also by beacon:** a beacon within ~4 m of an exhibit reading ≤ 1.5–2 m counts as being at that exhibit.
- **Behaviour:** ticks 20×/s. Arrival = within 2 m of the route end or footprint + 2.5 m **for 0.7 s**.
  Off-route > 8 m → re-route. Choose-by-facing: 1.5 s, never the exhibit you're standing at (that caused the
  "arrived" pop-up loop). Demo walk: 1.3 m/s along the route.

## 6b. Backend integration (11 Oct)

The backend contract is the backend team's INTEGRATION.md (Spring, HTTP + plain WebSocket, port 8081).

- **Host:** `BACKEND_HOST` in Secrets.plist (just the IP), or Settings → Server, beacons and keys (wins).
- **Login:** session + CSRF, no JWT (`BackendClient`).
  - Wrong password → error.
  - Server down or 5xx/403/garbage → **local mode**: you're let in and the app runs on bundled data. It logs in by itself later (credentials in Keychain) and whenever the 30-min session expires.
  - *Create account* registers (password 8–72 chars), then logs in.
- **Navigation:** `guide.server` (`PositionSocket`). `GuideModel.navigate`:
  1. Destination = `MuseumGrid.approaches[key]` (the POI approach point; the server routes to it), else `info.viewingSpot`.
  2. Straight line at once.
  3. Local A* route a moment later (`planLocalRoute`).
  4. `server.setDestination` → the server's `navigation` messages take over (`routeSource = .server`, `route = [position, nextWaypoint]`, `serverTail` = remaining after the waypoint).
- **Statuses:**
  - `arrived` → `arrive`.
  - `blocked` → no route/bloops + spoken reason (`routeBlocked`). For POSITION_* reasons, fall back to local instead (our position is probably in a wall).
  - `idle`/`cancelled` while we have a target → re-send the destination (max every 5 s, not after a DESTINATION_* error).
  - Messages about another destination (> 1 m off) are ignored.
- **Failsafe for routes (`fallBackToLocal`)** kicks in when any of these happens:
  - the socket leaves `.online`;
  - no `navigation` for 8 s while server-guided;
  - an error DESTINATION_OUTSIDE_MAP / DESTINATION_BLOCKED.

  The local route uses the bundled grid and avoids the last known zones. When the server is back, it takes over again by itself (the socket re-sends position + destination).
- **Alarm (`policy.alarmActive`):**
  - `startAlarm`: haptic (`alarmEvent`), spoken warning, guidance to the nearest exit (stand-in exhibit `GuideModel.exitKey` = "__exit", `isExit`). The server's exit choice replaces it.
  - `navigate` and `stopGuidance` refuse during the alarm.
  - `endAlarm` resumes the previous target.
  - Exits never count as visited.
- **Closed exhibits:** a grid POI with `approach: null` is refused by `navigate` with a spoken note. The map was updated on 11 Oct (commit 565284a) and now every exhibit is reachable; the app's copy was updated to match (sha256 93dab8…).
- **Settings:**
  - main screen: big mode cards (`ModeCard`), *Tempo lektora* slider (`voice.speed`, plays a sample on release), language row with flags (`AppLanguage.flag`), server status row;
  - Advanced: server IP + live connection state, "Prowadzenie teraz: z serwera / z mapy w telefonie".

- **Map gestures (11 Oct):** 3D overview and 2D plan: drag to pan + pinch to zoom.
  - The pan offset is on the floor, so the map keeps following you; the 3D overview stops turning with your head while panned (`heldBearing`).
  - `RecenterButton` (bottom right, plain style, doesn't stop speech) brings it back.
  - Pan resets when guidance starts or the style changes.
  - First person (`.eyeLevel`): pan and zoom are disabled (`.gesture(..., including: .subviews)`), only the AirPods steer; taps still pick pins.

## 7. Gotchas (learned the hard way)

1. **`RealityView` on iOS shows the AR camera by default.** Always set `content.camera = .virtual` in the make closure.
2. **Simulator crash:** "MTLDebugRenderCommandEncoder … Draw Errors Validation … fsRealityPbr" → Metal API Validation off (shared scheme sets `enableGPUValidationMode = "1"`).
3. **Background:** the `RealityView` background is transparent; the sky is a SwiftUI gradient (always daytime).
4. **Building group names** come from USD prim names (`findEntity(named: "Walls")`). Keep them stable in the generator: `Outside`, `Floors`, `Walls`, `Blocks`, `Hall`, `Entrances`, `Furniture`, `Displays`.
5. **Pins and labels are Canvas symbols** projected with `MapCameraRig.projector(in:)` (same pose as the RealityKit camera). Change the FOV only in `MapCameraRig.fieldOfView`.
6. **Camera loop:** `MapCameraRig` is deliberately *not* observable; advanced inside a `TimelineView` that pauses when settled (`settleTick`). Keep camera goals stable (deadbands) or it never pauses.
7. **Throwaway instances:** `@State var x = SomeClass()` creates a throwaway instance on every view init. App-wide objects live in `AppModel.shared`; `MuseumMapScene.init()` is empty.
8. **Performance rules:** don't read fine guide state (`position`, `facingYaw`) in cards/lists; don't put `.shadow` or materials over the live 3D view; keep event counters out of big views; RealityKit models come from the `MuseumAssets` cache.
9. **Text contrast:** white text only on `accent`/`red` faces; use `accentText`, `coralText`, `mintText`, `redText`, `inkSoft` on cards. `amber`/`coral`/`mint` fills are for dots, progress and icons.
10. **Thumbnails** are `Image("Exhibit-<key>")` from the asset catalog.
11. **iBeacons need Core Location ranging + location permission**; the Simulator can't range. CLBeacon `rssi == 0` = not heard this round.
12. **Deleting files on the Mac** from the device shell needs permission; moving them (e.g. into `mobile/backups/removed-files/`) works.
13. **Sound follows the screen (keep it that way):**
    - Every screen registers with `.soundScreen(.x, guide:)` (`App/SoundScreen.swift`), or with `guide.screenAppeared(.x)` as the first line of its own `onAppear` when it speaks there (Calibration, ListenModeView).
    - The screens are `GuideModel.Screen`: login, welcome, calibration, map, listen, plus the overlays settings, exhibits and exhibitDetail. `guide.screen` = the top overlay, else the base screen.
    - When the front screen changes, `updateFrontScreen` bumps `screenGeneration`, cancels voice input (`VoiceControl.cancel`), drops queued `.screen`-scope utterances and stops the current one, unless it is `.guidance` scope.
    - `.guidance` scope covers "guiding you to…", arrival + listening-mode story, "guidance stopped" and "calibrated". Everything else is `.screen` (the default `Utterance.scope`).
    - `guide.listen()` returns nil if the screen changed while you talked.
    - Auto-listen (`listenAfterSpeech`, `listenWhenQuiet`), wake-phrase handlers and auto-announce only act when `guide.screen` is their own screen. ListenModeView defers announcing choices (`announceWhenShown`) while Settings is on top.
    - **Taps interrupt speech:** `AppButtonStyle`, `RoundIconButtonStyle` and `CardButtonStyle` are PrimitiveButtonStyles that call `UserTap.happened()` → `guide.userTapped()` (stop talking + cancel a half-said command) *before* the button's action. So new buttons get this for free.
    - `onTapGesture` controls (listening corners/halves, calibration halves, map pins via `MapScreen.pick`) call `guide.userTapped()` themselves.
    - `.plain` buttons don't interrupt: VoiceButton, the listen Settings button (which calls `userTapped` itself).
    - `SpeechCache` cancels a download nobody listens to any more (`whenAbandoned`, not for `prepare`/`load`), so fast tapping never queues stale ElevenLabs requests. `ElevenLabsTTS.stream` retries once if it joined a just-dropped download.

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

**Verification:** round 1 built and ran on the owner's Mac. Round 2 is syntax-checked only: **build it (⌘B) first.**
If looking up moves the Look view down, flip `HeadTracker.pitchSign` to -1.

**Open ideas / not done yet:**
- Read `../backend` and `../embedded` to confirm the API paths and that the ESP32s advertise iBeacon frames
  with major/minor (the app assumes that).
- Pedestrian dead reckoning (CMPedometer steps + AirPods heading) between beacon fixes would smooth positions a lot.
- Routes: backend WebSocket when online, bundled grid A* otherwise (not compiled/tested on device yet: build ⌘B, then test with the backend running).
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
