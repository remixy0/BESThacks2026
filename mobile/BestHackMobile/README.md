# Spatial Bloop (BestHackMobile)

An audio guide to the Field Museum's Main Level. Put on AirPods, pick an exhibit, and follow the 3D "bloops": they
come from the direction you should walk. Bluetooth beacons tell the app where you are; your AirPods tell it which
way you face.

## How it works

1. **Log in** with your account, or **Try the demo** (signs in as `test@test.test` / `test`; the login is still sent
   to the server, and the app continues even if the server doesn't answer).
2. **Intro (first time only):** hello → *With the map* or *Just listening* → test the left/right bloop on your
   AirPods → allow location (iPhone only lets apps hear beacons with location access; GPS isn't used).
   *Settings → Back to the welcome screen* shows it again.
3. **Calibrate (every visit):** stand on the calibration spot, face its front, tap **Calibrate** and hold still for
   3 seconds. That sets your position, zeroes the AirPods heading, and corrects each beacon's signal strength.
4. **The map:** 3D (like Apple Maps), **Look** (first person) or 2D, chosen with the sliding switch at the top. The map
   follows you and turns only with your AirPods (no dragging, no phone compass). Pinch to zoom. Tap a pin to see it.
5. **One card at a time** at the bottom: *Next up* + **Let's go** → *Walking* (arrow, metres to go, progress,
   Repeat, ✕). Arriving is announced and ticks the exhibit off; there are no pop-ups.
6. **Listening mode** (blind or low vision): the screen is four big coloured corners (yellow, blue, pink, green), each
   one of the four nearest exhibits. The guide reads them out ("Top left, yellow: Máximo, 20 meters ahead…") with
   three hard knocks. Tap a corner: a long buzz and "…tap again to go there". Tap it again: long-short-long buzz and
   guidance starts. Hold anywhere to hear the options again. While walking: top half = which way, bottom half = stop
   (tap twice).
7. **Voice:** Settings → Voice: the Apple voice (offline) or any ElevenLabs voice, each with a ▶︎ to hear it first,
   and the speaking speed (a bit slower than normal by default). Until you pick one, the app uses the first voice in
   your ElevenLabs account whose name contains "Makłowicz".
8. **Language:** Polish (default) or English: the switch is on the login screen, the first intro screen and in Settings.
   It changes everything: screens, the guide's voice, exhibit stories and the speech recognizer.
9. **Talking:** in listening mode, after the four options are read out (or tap *Mów* at the bottom), say a colour,
   a corner, a number or the exhibit's name ("żółty", "lewy górny", "słonie"), then "tak". At an exhibit, or with the
   *Mów* button on the map card: "opowiedz", "dalej", "powtórz", "gdzie jestem", "którędy", "stop". Speech is recognized
   by ElevenLabs Scribe; the API key needs the *Speech to Text* permission.
   **Wake phrase:** say "Hej Bloop" (or your own phrase, Settings → Guide → Wake phrase) and then the command,
   without touching the phone. The phrase is spotted by Apple's speech recognizer on the iPhone.
10. **Finding the way by ear:** facing the wrong way, bloops come fast and get higher as you turn toward the route;
    when you face it there's a bright chime and a firm tap, then only a soft bloop every few seconds while you keep
    going the right way. Turn away and the quick, loud bloops come straight back.

## Walking through the museum in any room (your own beacons)

Settings → **Beacon layout and steps**:
1. Hang 4 beacons (one per corner works best). Stand in one corner facing into the room: **x** = metres to your right,
   **y** = metres ahead. Tap *Add the beacons I hear*, then open each one, pick the right beacon (hold the phone next
   to it: it's the strongest), type its x/y, and tap *Measure* standing 1 m away.
2. Set the **calibration point** in the room and which way you face there. Calibrating there puts you at the museum's
   calibration spot (South Entrance), facing into the hall. **Walk scale** stretches the room (3× = 1 m walked is 3 m).
3. Turn on *Use my beacon layout*, calibrate (hold the phone in front of you, pointing forward), and walk.

**Steps:** the phone counts your steps and measures how you turn (gyroscope, no compass). Every step moves you
straight away; the beacons keep the steps from drifting. Walking direction: the phone while you hold it in front of
you, otherwise your AirPods. If you move too little or too far, change *Step length*. The live plan on that screen
shows the beacons, the distance each one measures, and you.

## Setup

1. Copy `Secrets.example.plist` to `BestHackMobile/Config/Secrets.plist` (git-ignored) and fill in:
   - `BACKEND_URL`: your backend. Empty = `http://172.20.10.6` (built in). Plain http works. Can also be set in the app
     (login screen → server, or Settings → Server, beacons and keys).
   - `ELEVENLABS_API_KEY`: voice and voice commands (needs Text to Speech, Speech to Text and Voices Read).
     Optional; without it the Apple voice is used and voice commands are off.
   - `ROUTE_API_URL`: your route service (see below). Optional; without it guidance goes in a straight line.
   - `ROUTE_Y_AXIS`: `model_z` (default) or `north`; applies to routes, beacon positions and the calibration spot.
   - `CALIBRATION_POINT`: `x, y, facingDegrees` of the calibration spot (default `0.2, 56, 0`: just inside the South
     Entrance, facing into the hall). The backend can also send it (see below).
2. Open `BestHackMobile.xcodeproj`, run on an iPhone with AirPods. Beacons need a real iPhone (not the Simulator).

## Backend API

The app expects two endpoints. If one answers 404 it tries the next usual path, so most simple backends just work.

### Login

```http
POST <BACKEND_URL>/auth/login        (then /login, /api/login, /api/auth/login)
Content-Type: application/json

{"email": "test@test.test", "password": "test"}
```

Any 2xx = logged in. A token is optional; the app picks it up from `token`, `access_token`, `accessToken`, `jwt`
(top level or one level down) and sends it as `Authorization: Bearer <token>` afterwards. 401/403 = wrong password.

### Beacon positions

```http
GET <BACKEND_URL>/beacons            (then /api/beacons)
```

```json
{
  "beacons": [
    {"major": 1, "minor": 1, "x": 0.0,  "y": 40.0, "tx_power": -59},
    {"major": 1, "minor": 2, "x": 10.0, "y": 50.0},
    {"id": "1:3", "position": [-10.0, 2.5, 50.0]}
  ],
  "calibration": {"x": 0.2, "y": 56, "facing_degrees": 0, "name": "the start marker"}
}
```

- A bare list (`[...]`) works too, and so do `items` / `data` instead of `beacons`.
- Each beacon needs an identity and a position. Identity: `major` + `minor`, or `id` as `"major:minor"`, or a plain
  number `id` (= the minor). Position: `x` + `y` (or `z`), or `position` as `[x, z]` / `[x, height, z]`.
- Coordinates are museum metres: x = east, y = the model's z (south), origin = centre of the building (the same
  numbers as `position[0]` and `position[2]` in `FieldMuseum_MainLevel_info.json`), unless `ROUTE_Y_AXIS` is `north`.
- `tx_power` (also `txPower`, `measured_power`, `rssi_1m`) is the RSSI 1 m from the beacon; default −59 dBm.
- `calibration` is optional: where to stand to calibrate (`facing_degrees`: 0 = north, 90 = west).

The beacons themselves are iBeacons with UUID `DFB76639-2B31-46CB-AAD1-63470563632E` (the `BEACON_UUID` in the
firmware); the app tells them apart by major/minor. *Settings → Server, beacons and keys → What the phone hears*
lists every beacon with its signal and estimated distance, which helps when placing them.

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

(`"points"`, `"path"`, `"coordinates"` and `"waypoints"` are accepted in place of `"route"`.) Exhibit ids are the
`key`s in the info JSON (`maximo`, `elephants`, `totems`, `tsavo_lions`, `seabirds`, `mask`, `pawnee_lodge`,
`mastaba`). To push a route from somewhere else, call `guide.follow(routeJSON: data)`.

## Project structure

```
BestHackMobile/
├── App/                  Entry point; RootView + AppModel (login → intro → calibration → museum)
├── Design/               Theme (colours, buttons, cards, progress line), BloopOrb (the app's mark)
├── Features/
│   ├── Login/            Log in or demo
│   ├── Welcome/          The 4-step intro
│   ├── Calibration/      Stand on the spot, face front, calibrate
│   ├── Map/              MapScreen (sliding style switch), GuidePanel (the one bottom card),
│   │                     Map3DView (3D + eye level, Canvas pins), MapCamera, Map2DView, MapPalette
│   ├── Listen/           Listening mode: the four-corner chooser
│   ├── Artifacts/        Exhibit grid, exhibit page, turning 3D model
│   └── Settings/         Settings, voice picker, server/beacons/keys, beacon debug list
├── Models/               GuideModel (the guide), AccountStore, CalibrationSpot, VisitLog, UserMode, VoiceSettings,
│                         Museum/MuseumInfo
├── Audio/                SpatialAudioEngine (3D bloop + voice), Bloop, SpeechOutput, AppleSpeech
├── Services/
│   ├── Beacons/          BeaconScanner (Core Location ranging), BeaconPositioner (RSSI → position),
│   │                     BeaconDirectory (the server's beacon list), BeaconLayout (your own layout + room ↔ museum)
│   ├── Location/         PositionService (beacons + steps → position, calibration, demo walk), PositionFilter (Kalman)
│   ├── Motion/           MotionTracker (steps + turning from the phone's motion sensors)
│   ├── Backend/          BackendClient (login, beacons)
│   ├── Routing/          RouteProvider (straight line / your API), RouteMath, RouteDecoder
│   ├── ElevenLabs/       Text-to-speech client + errors
│   └── Haptics, HeadTracker, KeychainStore, MuseumAssets
├── Config/               Secrets.swift + Secrets.plist (git-ignored)
└── Resources/            Assets (exhibit pictures), Museum (MuseumMap.usdz, Artifacts/*.usdz, info JSON)
```

`AppInfo.plist` (next to the project, outside the synchronized folder) adds the plain-http exception for a local
backend; everything else in Info.plist is generated from build settings.

The 3D models and exhibit pictures are generated by `../resources/tools/` (see `../resources/README.md`).

## Credits

Floor-plan data © 2020 Field Museum of Natural History, CC BY 4.0 (https://github.com/arcataroger/openlayers_indoor_map).
The building and exhibit models are simplified reconstructions, not scans.
