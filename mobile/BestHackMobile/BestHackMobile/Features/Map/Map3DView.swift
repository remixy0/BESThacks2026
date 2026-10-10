import RealityKit
import SwiftUI

#if canImport(UIKit)
import UIKit
private typealias PlatformColor = UIColor
#else
import AppKit
private typealias PlatformColor = NSColor
#endif

/// The 3D map, in two styles that blend into each other:
/// - `.overview`: the museum from above at an angle, like Apple Maps' 3D. It follows you and turns with your AirPods.
/// - `.eyeLevel`: first person, standing where you are and looking where your AirPods face.
///
/// Only you move it: no dragging, no phone compass. Pinch zooms the overview.
///
/// Pins and gallery names are drawn in one Canvas over the 3D scene: SwiftUI renders each pin once as a symbol,
/// and every frame just places those pictures. That's far cheaper than dozens of views moving every frame.
struct Map3DView: View {
    let guide: GuideModel
    let style: MapStyle
    var visited: Set<String> = []
    /// How much of the screen the top bar and the bottom card cover (from the screen edges).
    var covered = EdgeInsets()
    var onSelect: (MuseumInfo.Exhibit) -> Void = { _ in }

    @State private var scene = MuseumMapScene()
    @State private var rig = MapCameraRig(CameraGoal(focus: SIMD2(0, 40), distance: 160, pitch: 1.0, bearing: 0, eyeLevel: 0))
    @State private var isLoaded = false
    @State private var buildingMissing = false
    @State private var pinHeights: [String: Float] = [:]
    @State private var labels: [RoomLabel] = []
    /// Bumped when the camera comes to rest, so the frame loop can pause.
    @State private var settleTick = 0
    /// Overview zoom: metres from the camera to you.
    @State private var distance: Float = 90
    @State private var zoomStart: Float?

    /// A dark dusk sky: easy on the eyes, and the lit museum stands out against it.
    private static let sky = LinearGradient(colors: [Color(hex: 0x1C2029), Color(hex: 0x353C49)], startPoint: .top, endPoint: .bottom)

    var body: some View {
        let _ = settleTick
        GeometryReader { geo in
            let goal = cameraGoal(size: geo.size)
            let settled = rig.isSettled(at: goal)
            TimelineView(.animation(minimumInterval: 1.0 / 60, paused: settled)) { timeline in
                let _ = advance(toward: goal, at: timeline.date)
                ZStack {
                    RealityView { content in
                        content.camera = .virtual
                        let loaded = await scene.build(in: &content, info: guide.info) { heights in
                            pinHeights = heights
                        }
                        if let info = guide.info { labels = Self.roomLabels(info) }
                        buildingMissing = !loaded
                        isLoaded = true
                    } update: { _ in
                        scene.apply(frame)
                    }
                    .backgroundStyle(Self.sky)

                    if isLoaded {
                        overlay(size: geo.size)
                    }
                }
            }
            .contentShape(Rectangle())
            .gesture(zoomGesture)
            .onTapGesture(coordinateSpace: .local) { location in
                selectPin(at: location, size: geo.size)
            }
        }
        .background(Self.sky)
        .overlay {
            if !isLoaded {
                VStack(spacing: 12) {
                    ProgressView()
                        .tint(.white)
                    Text(tr("Building the museum…", "Buduję muzeum…"))
                        .font(Theme.caption)
                        .foregroundStyle(Color.white.opacity(0.8))
                }
            } else if buildingMissing {
                Text(tr("The 3D building is missing from the app (MuseumMap.usdz). Try the 2D map.", "Brakuje modelu budynku (MuseumMap.usdz). Użyj mapy 2D."))
                    .font(Theme.caption)
                    .foregroundStyle(Color(hex: 0x3C3C3C))
                    .multilineTextAlignment(.center)
                    .padding(14)
                    .background(RoundedRectangle(cornerRadius: 14).fill(.white))
                    .padding(40)
            }
        }
        .onChange(of: guide.target?.key) { _, key in
            if key != nil { distance = min(distance, 70) }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(style == .eyeLevel ? tr("Eye level view", "Widok z oczu") : tr("3D map", "Mapa 3D"))
        .accessibilityValue(accessibilitySummary)
        .accessibilityActions {
            ForEach(guide.info?.exhibits ?? []) { exhibit in
                Button(tr("Show ", "Pokaż: ") + exhibit.name) { onSelect(exhibit) }
            }
        }
    }

    /// Moves the camera one frame; when it comes to rest, asks SwiftUI to re-check so the frame loop can pause.
    private func advance(toward goal: CameraGoal, at date: Date) -> Bool {
        let wasSettled = rig.isSettled(at: goal)
        rig.advance(toward: goal, at: date)
        if !wasSettled, rig.isSettled(at: goal) {
            Task { @MainActor in settleTick &+= 1 }
        }
        return true
    }

    // MARK: - Camera goal

    /// Points (in screen points) that the visible middle sits above the screen's middle.
    private func visibleLift(_ size: CGSize) -> CGFloat {
        let top = min(covered.top, size.height * 0.4)
        let bottom = min(covered.bottom, size.height * 0.6)
        return (bottom - top) / 2
    }

    /// The camera focus that puts `point` in the middle of the visible part of the map.
    private func centered(_ point: SIMD2<Float>, bearing: Float, distance: Float, size: CGSize) -> SIMD2<Float> {
        let pitch = overviewPitch(distance)
        let metresPerPoint = 2 * distance * tan(MapCameraRig.fieldOfView / 2) / Float(max(size.height, 1))
        let ahead = Float(visibleLift(size)) * metresPerPoint / max(sin(pitch), 0.3)
        return point - MuseumGeometry.forward(yaw: bearing) * ahead
    }

    private func overviewPitch(_ distance: Float) -> Float {
        0.8 + 0.32 * min(max((distance - 30) / 300, 0), 1)
    }

    private func cameraGoal(size: CGSize) -> CameraGoal {
        if style == .eyeLevel {
            // Your AirPods steer the view, left-right and up-down. Without them: along the route, or north.
            let facing = guide.facingYaw ?? routeYaw ?? 0
            // Tilt down a little so the horizon sits in the upper part of the visible area: you see the floor,
            // the route and the exhibits ahead above the card.
            let half = Float(max(size.height, 1)) / 2
            let horizonFromMiddle = Float(visibleLift(size)) + Float(max(size.height - covered.top - covered.bottom, 100)) * 0.18
            let pitch = atan(horizonFromMiddle / half * tan(MapCameraRig.fieldOfView / 2))
            // Looking up tilts the camera up (pitch here is "below the horizon", so it goes down).
            return CameraGoal(focus: guide.position, distance: 2, pitch: min(max(pitch - guide.headPitch, -0.9), 1.1),
                              bearing: facing, eyeLevel: 1)
        }
        // The map turns with your head (with a small deadband); north up without calibrated AirPods.
        let heading = guide.mapHeading ?? 0
        let center = centered(guide.position, bearing: heading, distance: distance, size: size)
        return CameraGoal(focus: center, distance: distance, pitch: overviewPitch(distance), bearing: heading, eyeLevel: 0)
    }

    /// Direction of the route just ahead of you.
    private var routeYaw: Float? {
        guard guide.route.count >= 2 else { return nil }
        let progress = RouteMath.progress(of: guide.position, along: guide.route, from: 0)
        let ahead = RouteMath.point(on: guide.route, from: progress, ahead: 4)
        guard simd_distance(ahead, guide.position) > 0.5 else { return nil }
        return MuseumGeometry.yaw(from: guide.position, to: ahead)
    }

    private var frame: MuseumMapScene.Frame {
        let pose = rig.pose
        return MuseumMapScene.Frame(
            eye: pose.eye,
            target: pose.target,
            eyeLevel: rig.current.eyeLevel,
            distance: rig.current.distance,
            user: guide.position,
            facing: guide.facingYaw,
            route: guide.route,
            routeVersion: guide.routeVersion,
            highlighted: guide.target?.key ?? guide.preview?.key ?? guide.faced?.key
        )
    }

    // MARK: - Overlay: pins and gallery names

    private struct PlacedPin {
        let key: String
        let point: CGPoint
        let scale: CGFloat
        let depth: Float
    }

    private func overlay(size: CGSize) -> some View {
        let project = rig.projector(in: size)
        let blend = rig.current.eyeLevel
        let zoomedIn = rig.current.distance < 90
        let highlighted = guide.target?.key ?? guide.preview?.key
        let shownLabels = blend < 0.3 && rig.current.distance < 220 ? labels : []
        let pins = placedPins(project: project, size: size, blend: blend, highlighted: highlighted)

        return Canvas { context, _ in
            for label in shownLabels {
                guard let projected = project(SIMD3(label.point.x, 0.2, label.point.y)),
                      isOnScreen(projected.point, size: size, margin: -20),
                      let symbol = context.resolveSymbol(id: label.id) else { continue }
                context.draw(symbol, at: projected.point)
            }
            for pin in pins {
                guard let symbol = context.resolveSymbol(id: pin.key) else { continue }
                var pinContext = context
                pinContext.translateBy(x: pin.point.x, y: pin.point.y)
                pinContext.scaleBy(x: pin.scale, y: pin.scale)
                // The pin's tip sits on the exhibit.
                pinContext.draw(symbol, at: CGPoint(x: 0, y: -symbol.size.height / 2))
            }
        } symbols: {
            ForEach(shownLabels) { label in
                RoomLabelView(name: label.name)
                    .tag(label.id)
            }
            ForEach(guide.info?.exhibits ?? []) { exhibit in
                ExhibitPin(
                    exhibit: exhibit,
                    isSelected: exhibit.key == highlighted,
                    isVisited: visited.contains(exhibit.key),
                    caption: blend > 0.5 ? "\(Int(guide.distance(to: exhibit).rounded())) m" : (zoomedIn || exhibit.key == highlighted ? exhibit.name : nil)
                )
                .tag(exhibit.key)
            }
        }
        .allowsHitTesting(false)
    }

    private func placedPins(project: MapCameraRig.Projector, size: CGSize, blend: Float, highlighted: String?) -> [PlacedPin] {
        var result: [PlacedPin] = []
        for exhibit in guide.info?.exhibits ?? [] {
            let height = pinHeights[exhibit.key] ?? 4
            guard let projected = project(SIMD3(exhibit.position[0], height + 0.6, exhibit.position[2])),
                  isOnScreen(projected.point, size: size, margin: 40) else { continue }
            result.append(PlacedPin(key: exhibit.key, point: projected.point,
                                    scale: pinScale(depth: projected.depth, blend: blend), depth: projected.depth))
        }
        // Far pins first, near ones on top, the selected one on top of everything.
        result.sort { a, b in
            if a.key == highlighted { return false }
            if b.key == highlighted { return true }
            return a.depth > b.depth
        }
        return result
    }

    private func pinScale(depth: Float, blend: Float) -> CGFloat {
        let overview = CGFloat(min(max(160 / max(rig.current.distance, 1), 0.7), 1.0))
        let eye = CGFloat(min(max(16 / max(depth, 1), 0.5), 1.0))
        return overview + (eye - overview) * CGFloat(blend)
    }

    private func isOnScreen(_ point: CGPoint, size: CGSize, margin: CGFloat) -> Bool {
        point.x > -margin && point.x < size.width + margin && point.y > -margin && point.y < size.height + margin
    }

    /// Taps select a pin (the top-most one under your finger).
    private func selectPin(at location: CGPoint, size: CGSize) {
        guard isLoaded, let info = guide.info else { return }
        let pins = placedPins(project: rig.projector(in: size), size: size, blend: rig.current.eyeLevel,
                              highlighted: guide.target?.key ?? guide.preview?.key)
        for pin in pins.reversed() {
            let badge = CGPoint(x: pin.point.x, y: pin.point.y - 32 * pin.scale)
            if hypot(location.x - badge.x, location.y - badge.y) < 32 * pin.scale,
               let exhibit = info.exhibits.first(where: { $0.key == pin.key }) {
                onSelect(exhibit)
                return
            }
        }
    }

    struct RoomLabel: Identifiable {
        let name: String
        let point: SIMD2<Float>
        var id: String { "room-\(name)" }
    }

    private static func roomLabels(_ info: MuseumInfo) -> [RoomLabel] {
        var seen = Set<String>()
        var labels: [RoomLabel] = []
        for room in info.rooms {
            guard let name = room.name, room.status == "open", !seen.contains(name), room.polygon.count >= 3 else { continue }
            seen.insert(name)
            labels.append(RoomLabel(name: name, point: room.center))
        }
        let hall = info.hallRect
        labels.append(RoomLabel(name: info.hallName, point: SIMD2((hall.min.x + hall.max.x) / 2, hall.max.y - 6)))
        return labels
    }

    // MARK: - Zoom (the only gesture)

    private var zoomGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                guard style == .overview else { return }
                if zoomStart == nil { zoomStart = distance }
                distance = min(max((zoomStart ?? distance) / Float(value.magnification), 25), 300)
            }
            .onEnded { _ in zoomStart = nil }
    }

    private var accessibilitySummary: String {
        var parts: [String] = []
        if !guide.placeName.isEmpty { parts.append(tr("You are in: ", "Jesteś tutaj: ") + guide.placeName + ".") }
        if let nearest = guide.nearby.first {
            parts.append(tr("Nearest exhibit: ", "Najbliższy eksponat: ") + "\(nearest.name), \(guide.directions(to: nearest)).")
        }
        return parts.joined(separator: " ")
    }
}

// MARK: - Labels and pins (rendered once as Canvas symbols)

private struct RoomLabelView: View {
    let name: String

    var body: some View {
        Text(placeText(name))
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Color.white.opacity(0.92))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(Color.black.opacity(0.45)))
            .fixedSize()
    }
}

/// A round badge with the exhibit's picture and a little pointer, standing on the exhibit, with an optional caption.
struct ExhibitPin: View {
    let exhibit: MuseumInfo.Exhibit
    var isSelected = false
    var isVisited = false
    var caption: String?

    private var ring: Color { isSelected ? Theme.accent : Theme.coral }

    var body: some View {
        VStack(spacing: 4) {
            Text(caption ?? exhibit.name)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(isSelected ? Color.white : Color(hex: 0x17191E))
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Capsule().fill(isSelected ? Theme.accent : Color.white))
                .overlay(Capsule().strokeBorder(Color.black.opacity(isSelected ? 0 : 0.12), lineWidth: 1))
                .opacity(caption != nil || isSelected ? 1 : 0)
            VStack(spacing: 0) {
                ZStack(alignment: .topTrailing) {
                    ExhibitThumbnail(key: exhibit.key, size: 40, background: .white)
                        .clipShape(Circle())
                        .padding(3)
                        .background(Circle().fill(ring))
                    if isVisited {
                        Image(systemName: "checkmark")
                            .font(.system(size: 9, weight: .black))
                            .foregroundStyle(.white)
                            .frame(width: 18, height: 18)
                            .background(Circle().fill(Theme.mint))
                            .overlay(Circle().strokeBorder(.white, lineWidth: 1.5))
                            .offset(x: 4, y: -4)
                    }
                }
                PinPointer()
                    .fill(ring)
                    .frame(width: 12, height: 8)
                    .offset(y: -1)
            }
        }
        .fixedSize()
    }
}

nonisolated struct PinPointer: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

// MARK: - RealityKit scene

/// The RealityKit side of the 3D map. Lives as long as the view.
final class MuseumMapScene {
    /// Everything the scene needs for one frame.
    struct Frame {
        var eye: SIMD3<Float>
        var target: SIMD3<Float>
        /// 0 = overview, 1 = eye level.
        var eyeLevel: Float
        var distance: Float
        var user: SIMD2<Float>
        var facing: Float?
        var route: [SIMD2<Float>]
        var routeVersion: Int
        var highlighted: String?
    }

    /// Parts of the building that shrink in the overview so you can see into the galleries.
    private static let squashedGroups = ["Walls", "Hall", "Blocks", "Entrances"]
    private static let overviewWallScale: Float = 0.42

    private let root = Entity()
    private let camera = PerspectiveCamera()
    private let user = Entity()
    private var beam = Entity()
    private let routeLayer = Entity()
    private var highlight = Entity()
    private var squashed: [Entity] = []
    private var exhibits: [String: MuseumInfo.Exhibit] = [:]
    private var builtRouteVersion = -1
    private var lastSquash: Float = -1
    private var lastHighlight: String?
    private var lastUserScale: Float = -1

    /// Cheap on purpose: SwiftUI may create (and throw away) a scene each time the view is rebuilt.
    /// The meshes are made in `build`, once.
    init() {}

    private func makeMarkers() {
        let beamModel = ModelEntity(mesh: Self.beamMesh(), materials: [UnlitMaterial(color: Self.color(0.55, 0.60, 0.95))])
        beam = beamModel
        let disc = ModelEntity(mesh: .generateCylinder(height: 0.05, radius: 1),
                               materials: [UnlitMaterial(color: Self.color(0.85, 0.87, 0.98))])
        disc.isEnabled = false
        highlight = disc

        // You: indigo dot in a white ring on a pale halo, with a beam showing where you face.
        let halo = ModelEntity(mesh: .generateCylinder(height: 0.04, radius: 2.2), materials: [UnlitMaterial(color: Self.color(0.82, 0.85, 0.98))])
        let ring = ModelEntity(mesh: .generateCylinder(height: 0.08, radius: 1.1), materials: [UnlitMaterial(color: Self.color(1, 1, 1))])
        let dot = ModelEntity(mesh: .generateCylinder(height: 0.12, radius: 0.8), materials: [UnlitMaterial(color: Self.color(0.23, 0.30, 0.79))])
        halo.position.y = 0.2
        beam.position.y = 0.22
        ring.position.y = 0.26
        dot.position.y = 0.3
        user.addChild(halo)
        user.addChild(beam)
        user.addChild(ring)
        user.addChild(dot)
    }

    // MARK: Build

    /// Adds everything to the view. Returns false if the building model couldn't be loaded.
    func build(in content: inout RealityViewCameraContent, info: MuseumInfo?, onPinHeights: @escaping ([String: Float]) -> Void) async -> Bool {
        makeMarkers()
        camera.camera.fieldOfViewInDegrees = MapCameraRig.fieldOfView * 180 / .pi
        camera.camera.fieldOfViewOrientation = .vertical
        camera.camera.near = 0.05
        camera.camera.far = 1200
        content.add(camera)

        // A warm, dimmed key light and a cool fill from the other side: a darker "evening" museum that isn't
        // glaring white. No real-time shadows: they were the most expensive part of every frame.
        let sun = DirectionalLight()
        sun.light.intensity = 1450
        sun.light.color = Self.color(1.0, 0.94, 0.86)
        sun.look(at: .zero, from: [45, 90, 70], relativeTo: nil)
        content.add(sun)
        let fill = DirectionalLight()
        fill.light.intensity = 620
        fill.light.color = Self.color(0.78, 0.85, 1.0)
        fill.look(at: .zero, from: [-60, 70, -50], relativeTo: nil)
        content.add(fill)

        content.add(root)
        var loaded = false
        do {
            let building = try await MuseumAssets.map()
            root.addChild(building)
            squashed = Self.squashedGroups.compactMap { building.findEntity(named: $0) }
            loaded = true
        } catch {
            print("[Map3D] couldn't load MuseumMap.usdz: \(error)")
        }
        root.addChild(routeLayer)
        root.addChild(highlight)
        root.addChild(user)

        guard let info else { return loaded }
        var heights: [String: Float] = [:]
        for exhibit in info.exhibits {
            exhibits[exhibit.key] = exhibit
            let anchor = Entity()
            anchor.name = "exhibit:\(exhibit.key)"
            anchor.position = [exhibit.position[0], 0, exhibit.position[2]]
            anchor.orientation = simd_quatf(angle: exhibit.yawDegrees * .pi / 180, axis: [0, 1, 0])
            root.addChild(anchor)
            if let model = try? await MuseumAssets.artifact(exhibit) {
                anchor.addChild(model)
                heights[exhibit.key] = model.visualBounds(relativeTo: nil).max.y
            }
        }
        onPinHeights(heights)
        return loaded
    }

    // MARK: Update

    func apply(_ frame: Frame) {
        camera.look(at: frame.target, from: frame.eye, relativeTo: nil)

        // Walls: low in the overview (see into the rooms), full height at eye level.
        let t = min(max(frame.eyeLevel, 0), 1)
        let squash = Self.overviewWallScale + (1 - Self.overviewWallScale) * (t * t * (3 - 2 * t))
        if abs(squash - lastSquash) > 0.002 {
            lastSquash = squash
            for entity in squashed {
                entity.scale = [1, squash, 1]
            }
        }

        // You. The marker grows when zoomed out so it stays easy to see, and hides at eye level.
        user.isEnabled = frame.eyeLevel < 0.6
        user.position = [frame.user.x, 0, frame.user.y]
        let userScale = min(max(frame.distance / 70, 0.8), 3.2)
        if abs(userScale - lastUserScale) > 0.01 {
            lastUserScale = userScale
            user.scale = SIMD3(repeating: userScale)
        }
        beam.isEnabled = frame.facing != nil
        beam.orientation = simd_quatf(angle: frame.facing ?? 0, axis: [0, 1, 0])

        // Selected exhibit: a pale disc under it.
        if frame.highlighted != lastHighlight {
            lastHighlight = frame.highlighted
            if let key = frame.highlighted, let exhibit = exhibits[key] {
                let radius = max(exhibit.halfExtents.x, exhibit.halfExtents.y) + 1.6
                highlight.position = [exhibit.position[0], 0.13, exhibit.position[2]]
                highlight.scale = [radius, 1, radius]
                highlight.isEnabled = true
            } else {
                highlight.isEnabled = false
            }
        }

        if frame.routeVersion != builtRouteVersion {
            builtRouteVersion = frame.routeVersion
            rebuildRoute(frame.route)
        }
    }

    /// The route as a coral band on the floor with a white edge, like a walking route in Maps.
    private func rebuildRoute(_ route: [SIMD2<Float>]) {
        routeLayer.children.removeAll()
        guard route.count >= 2 else { return }
        let edge = UnlitMaterial(color: Self.color(1, 1, 1))
        let fill = UnlitMaterial(color: Self.color(0.94, 0.36, 0.21))
        for (width, height, material) in [(Float(1.25), Float(0.16), edge), (Float(0.85), Float(0.18), fill)] {
            for i in 0..<(route.count - 1) {
                let a = route[i], b = route[i + 1]
                let length = simd_distance(a, b)
                guard length > 0.05 else { continue }
                let segment = ModelEntity(mesh: .generateBox(width: width, height: 0.02, depth: length), materials: [material])
                let middle = (a + b) / 2
                segment.position = [middle.x, height, middle.y]
                segment.orientation = simd_quatf(angle: MuseumGeometry.yaw(from: a, to: b), axis: [0, 1, 0])
                routeLayer.addChild(segment)
            }
            for point in route {
                let joint = ModelEntity(mesh: .generateCylinder(height: 0.02, radius: width / 2), materials: [material])
                joint.position = [point.x, height, point.y]
                routeLayer.addChild(joint)
            }
        }
        // A ring where the route ends.
        if let last = route.last {
            let ring = ModelEntity(mesh: .generateCylinder(height: 0.03, radius: 1.4), materials: [UnlitMaterial(color: Self.color(0.12, 0.62, 0.47))])
            ring.position = [last.x, 0.2, last.y]
            routeLayer.addChild(ring)
        }
    }

    // MARK: Pieces

    /// A flat wedge on the floor pointing forward (-z), 7 m long.
    private static func beamMesh() -> MeshResource {
        let length: Float = 7
        let spread: Float = 0.45
        var descriptor = MeshDescriptor(name: "beam")
        descriptor.positions = MeshBuffers.Positions([
            SIMD3<Float>(0, 0, 0),
            SIMD3<Float>(-sin(spread) * length, 0, -cos(spread) * length),
            SIMD3<Float>(0, 0, -length),
            SIMD3<Float>(sin(spread) * length, 0, -cos(spread) * length),
        ])
        // Both windings, so it shows from above whichever side RealityKit treats as the front.
        descriptor.primitives = .triangles([0, 2, 1, 0, 3, 2, 0, 1, 2, 0, 2, 3])
        return (try? MeshResource.generate(from: [descriptor])) ?? .generatePlane(width: 0.1, depth: 0.1)
    }

    private static func color(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat) -> PlatformColor {
        PlatformColor(red: red, green: green, blue: blue, alpha: 1)
    }
}
