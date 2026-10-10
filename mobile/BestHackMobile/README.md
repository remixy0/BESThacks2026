# Spatial Bloop (BestHackMobile)

An audio guide to the Field Museum's Main Level. Put on AirPods, pick an exhibit, and follow the 3D "bloops": they
come from the direction you should walk. Bloop, the little blue guide, walks you through it one step at a time.

## How it works

1. **Intro (first launch only):** four quick screens with a progress bar: hello → *With the map* or *Just listening*
   → test the left/right bloop on your headphones → allow location. (Settings → *Show the intro again* replays it.)
2. **The map:** the museum in 3D like Apple Maps (**3D**, default), a first-person eye-level view (**Look**), or the
   2D floor plan (**2D**) – the three round buttons on the right. Exhibits are pins with their picture; tap one.
3. **One card at a time** at the bottom:
   - *Next up* – the nearest exhibit you haven't seen with a big **Let's go** (one tap), two more, and *All exhibits*.
   - *Exhibit* – picture, distance, **Let's go**, *Hear its story* (turns into *Stop*), *Look closer* (turn the 3D model).
   - *Walking* – a big arrow (straight on / turn left / turn right / turn around), meters to go, a progress bar,
     *Repeat*, and ✕ to stop (asks first).
   - *You made it!* – confetti, +1 ★ (the ★ 3/8 in the top bar), and a button straight to the next exhibit.
4. **Choose by looking:** face an exhibit for 1.5 s and the guide picks it (Settings can turn this off).
5. **Bloop navigation:** a bloop plays 3 m ahead of you along the route. Higher-pitched with a light tap when you
   face the right way, muffled when it's behind you, faster as you get closer.
6. **Listening mode** (blind or low vision): no map, big spoken buttons – *What's near me?*, *Where am I?*, nearby
   exhibits, *Stop guidance*. VoiceOver two-finger double tap = *What's near me?*.

Haptics: facing an exhibit (tick), choosing one (success), passing a route waypoint (tap), on-course bloops (light
tap), going off route (warning), arriving (success).

## Setup

1. Copy `Secrets.example.plist` to `BestHackMobile/Config/Secrets.plist` (git-ignored) and fill in:
   - `ELEVENLABS_API_KEY`: voice (needs Text to Speech + Voices Read). Optional; without it the Apple voice is used.
   - `ROUTE_API_URL`: your route service (see below). Optional; without it guidance goes in a straight line.
   - `ROUTE_Y_AXIS`: `model_z` (default) or `north`.
2. Open `BestHackMobile.xcodeproj`, run on an iPhone with AirPods.

**Location.** At the museum the app uses GPS + compass (converted to the model's coordinates; indoor GPS is only
accurate to roughly 10–30 m). Anywhere else it uses a **simulated position** (a purple DEMO tag in the top bar): tap the
3D or 2D map to move yourself, or in Look view hold the arrow buttons to walk and turn. While walking somewhere,
**Walk me there** (or *Settings → Walk the route by itself*) walks you along the route for demos.

**Simulator:** the shared scheme turns off Metal API Validation, which otherwise stops RealityKit apps in the
Simulator with a "Draw Errors Validation" assertion. iPhone is portrait-only.

## Route API

The app sends one request when guidance to an exhibit starts (and again if you wander more than 8 m off the route):

```http
POST <ROUTE_API_URL>
Content-Type: application/json

{"from": {"x": 0.2, "y": 56.0},
 "to":   {"id": "totems", "name": "Totem Poles", "x": -0.6, "y": 22.5}}
```

Reply with a list of (x, y) points from the start to the exhibit. Any of these shapes works (numbers or numeric strings):

```json
{"route": [[0.2, 56.0], [0.0, 40.0], [-0.6, 22.5]]}
[[0.2, 56.0], [0.0, 40.0], [-0.6, 22.5]]
[{"x": 0.2, "y": 56.0}, {"x": 0.0, "y": 40.0}, {"x": -0.6, "y": 22.5}]
```

(`"points"`, `"path"`, `"coordinates"` and `"waypoints"` are accepted in place of `"route"`.)

**Coordinates:** metres, origin = centre of the building, **x = east**, **y = the model's z = south** (exactly
`position[0]` and `position[2]` in `FieldMuseum_MainLevel_info.json`). If your service uses +y = north, set
`ROUTE_Y_AXIS` to `north`. Exhibit ids are the `key`s in that JSON (`maximo`, `elephants`, `totems`, `tsavo_lions`,
`seabirds`, `mask`, `pawnee_lodge`, `mastaba`). The JSON also has `building_outline`, `rooms[].outline`, `doors`, and
a `georeference` block for converting GPS.

To push a route from somewhere else (e.g. a socket), call `guide.follow(routeJSON: data)` or
`guide.follow(route: points, to: exhibit)`. To plug in a different planner, implement `RouteProvider`
(`Services/Routing/RouteProvider.swift`).

## Project structure

```
BestHackMobile/
├── App/                  Entry point, RootView (intro → map)
├── Design/               Theme (colours, rounded type, chunky buttons, cards, progress bar), Mascot (Bloop, confetti)
├── Features/
│   ├── Welcome/          The 4-step intro
│   ├── Map/              MapScreen (top bar, map buttons), GuidePanel (the one bottom card, arrival, listening mode),
│   │                     Map3DView (3D + eye level, pins), MapCamera (smooth camera), Map2DView, MapPalette
│   ├── Artifacts/        Exhibit grid, exhibit page, turning 3D model
│   └── Settings/         Short settings + "Voice and services"
├── Models/               GuideModel (the guide), VisitLog (★ visited), UserMode, VoiceSettings, Museum/MuseumInfo
├── Audio/                SpatialAudioEngine (3D bloop + voice), Bloop, SpeechOutput, AppleSpeech
├── Services/
│   ├── Location/         LocationService (GPS, compass, simulated), GeoReference
│   ├── Routing/          RouteProvider (straight line / your API), RouteMath, RouteDecoder
│   ├── ElevenLabs/       Text-to-speech client + errors
│   └── HeadTracker, KeychainStore, MuseumAssets
├── Config/               Secrets.swift + Secrets.plist (git-ignored)
└── Resources/
    ├── Assets.xcassets   Exhibits/Exhibit-<key> pictures, accent colour
    └── Museum/           MuseumMap.usdz (building), Artifacts/*.usdz (exhibits), info JSON
```

The 3D models and exhibit pictures are generated by `../resources/tools/` (see `../resources/README.md`).

## Credits

Floor-plan data © 2020 Field Museum of Natural History, CC BY 4.0 (https://github.com/arcataroger/openlayers_indoor_map).
The building and exhibit models are simplified reconstructions, not scans.
