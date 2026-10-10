import simd
import SwiftUI

/// A simple top-down floor plan (north up) that keeps you in the middle: galleries, exhibits, the route, and you.
/// Drag to look around, pinch to zoom, tap an exhibit to see it; the location button brings you back to the middle.
/// Always in the dark palette, like the 3D map, so it isn't glaring white.
struct Map2DView: View {
    let guide: GuideModel
    var visited: Set<String> = []
    /// How much of the screen the top bar and the bottom card cover (from the screen edges).
    var covered = EdgeInsets()
    var onSelect: (MuseumInfo.Exhibit) -> Void = { _ in }

    @State private var scale: CGFloat = 4        // points per metre
    @State private var zoomStart: CGFloat?
    /// How far you've dragged the plan away from yourself (metres). The plan keeps following you, offset by this.
    @State private var offset = SIMD2<Float>.zero
    @State private var dragStart: SIMD2<Float>?

    var body: some View {
        GeometryReader { geo in
            let visibleTop = min(covered.top, geo.size.height * 0.4)
            let visibleBottom = geo.size.height - min(covered.bottom, geo.size.height * 0.6)
            let anchor = CGPoint(x: geo.size.width / 2, y: (visibleTop + visibleBottom) / 2)
            let projection = Projection(anchor: anchor, center: guide.position + offset, scale: scale)
            Canvas { context, _ in
                draw(in: &context, projection: projection)
            }
            .contentShape(Rectangle())
            .gesture(SimultaneousGesture(panGesture, zoomGesture))
            .onTapGesture { location in
                handleTap(at: location, projection: projection)
            }
        }
        .background(MapPalette.outside(dark: true))
        .overlay(alignment: .bottomTrailing) {
            if simd_length(offset) > 0.5 {
                RecenterButton {
                    withAnimation(.easeOut(duration: 0.25)) { offset = .zero }
                }
                .padding(.trailing, 14)
                .padding(.bottom, covered.bottom + 12)
                .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.2), value: simd_length(offset) > 0.5)
        .onChange(of: guide.target?.key) { _, key in
            if key != nil { offset = .zero }
        }
        .environment(\.colorScheme, .dark)
        .accessibilityElement()
        .accessibilityLabel(tr("Floor plan", "Plan piętra"))
        .accessibilityValue(accessibilitySummary)
        .accessibilityActions {
            ForEach(guide.info?.exhibits ?? []) { exhibit in
                Button(tr("Show ", "Pokaż: ") + exhibit.name) { onSelect(exhibit) }
            }
        }
    }

    // MARK: - Drawing

    private func draw(in context: inout GraphicsContext, projection: Projection) {
        guard let info = guide.info else { return }
        let dark = true

        // Building and Stanley Field Hall.
        let building = polygonPath(info.outline, projection)
        context.fill(building, with: .color(MapPalette.building(dark: dark)))
        let hall = info.hallRect
        let hallPath = polygonPath([hall.min, SIMD2(hall.max.x, hall.min.y), hall.max, SIMD2(hall.min.x, hall.max.y)], projection)
        context.fill(hallPath, with: .color(MapPalette.hall(dark: dark)))

        // Galleries.
        for room in info.rooms {
            let path = polygonPath(room.polygon, projection)
            let theme = room.name == nil ? "closed" : room.theme
            context.fill(path, with: .color(MapPalette.floor(theme: theme, dark: dark)))
            context.stroke(path, with: .color(MapPalette.wall(dark: dark)), lineWidth: 1)
        }
        context.stroke(building, with: .color(MapPalette.wall(dark: dark)), lineWidth: 2)

        // Gallery names once zoomed in enough.
        if scale > 2.2 {
            var seen = Set<String>()
            for room in info.rooms {
                guard let name = room.name, !seen.contains(name), room.polygon.count >= 3 else { continue }
                seen.insert(name)
                context.draw(Text(placeText(name)).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary),
                             at: projection.point(room.center))
            }
            context.draw(Text(placeText(info.hallName)).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary),
                         at: projection.point(SIMD2((hall.min.x + hall.max.x) / 2, hall.min.y + 6)))
        }

        // Route.
        if guide.route.count >= 2 {
            var line = Path()
            line.addLines(guide.route.map { projection.point($0) })
            context.stroke(line, with: .color(.white), style: StrokeStyle(lineWidth: 9, lineCap: .round, lineJoin: .round))
            context.stroke(line, with: .color(MapPalette.route), style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
        }

        // Exhibits: a white-ringed dot (accent when selected), a mint dot once visited.
        let highlighted = guide.target?.key ?? guide.preview?.key
        for exhibit in info.exhibits {
            let p = projection.point(exhibit.floorPoint)
            let isOn = exhibit.key == highlighted || exhibit.key == guide.faced?.key
            let r: CGFloat = isOn ? 12 : 9
            context.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)), with: .color(.white))
            let inner = Path(ellipseIn: CGRect(x: p.x - r + 2.5, y: p.y - r + 2.5, width: (r - 2.5) * 2, height: (r - 2.5) * 2))
            context.fill(inner, with: .color(isOn ? MapPalette.selected : MapPalette.exhibit))
            if visited.contains(exhibit.key) {
                context.fill(Path(ellipseIn: CGRect(x: p.x + r * 0.35, y: p.y - r * 1.2, width: 11, height: 11)), with: .color(MapPalette.visited))
            }
            if scale > 1.6 || isOn {
                context.draw(Text(exhibit.name).font(.system(size: 12, weight: .semibold)).foregroundStyle(.primary),
                             at: CGPoint(x: p.x, y: p.y + r + 10))
            }
        }

        // You: heading beam (from AirPods), accuracy circle (from the beacons), dot.
        let me = projection.point(guide.position)
        if let yaw = guide.facingYaw {
            var beam = Path()
            beam.move(to: me)
            let spread: Float = 0.45
            for step in 0...8 {
                let a = yaw - spread + 2 * spread * Float(step) / 8
                let tip = guide.position + MuseumGeometry.forward(yaw: a) * Float(42 / scale)
                beam.addLine(to: projection.point(tip))
            }
            beam.closeSubpath()
            context.fill(beam, with: .color(MapPalette.user.opacity(0.22)))
        }
        if let accuracy = guide.positioning.accuracy, guide.positioning.source == .beacons {
            let r = CGFloat(accuracy) * scale
            context.fill(Path(ellipseIn: CGRect(x: me.x - r, y: me.y - r, width: r * 2, height: r * 2)),
                         with: .color(MapPalette.user.opacity(0.1)))
        }
        context.fill(Path(ellipseIn: CGRect(x: me.x - 9, y: me.y - 9, width: 18, height: 18)), with: .color(.white))
        context.fill(Path(ellipseIn: CGRect(x: me.x - 6.5, y: me.y - 6.5, width: 13, height: 13)), with: .color(MapPalette.user))
    }

    private func polygonPath(_ points: [SIMD2<Float>], _ projection: Projection) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: projection.point(first))
        for point in points.dropFirst() { path.addLine(to: projection.point(point)) }
        path.closeSubpath()
        return path
    }

    // MARK: - Gestures

    /// Drag the plan under your finger.
    private var panGesture: some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                if dragStart == nil { dragStart = offset }
                let moved = SIMD2(Float(value.translation.width / scale), Float(value.translation.height / scale))
                let wanted = (dragStart ?? .zero) - moved
                // Keep the middle of the screen over the building.
                let focus = simd_clamp(guide.position + wanted, SIMD2(-110, -72), SIMD2(110, 72))
                offset = focus - guide.position
            }
            .onEnded { _ in dragStart = nil }
    }

    private var zoomGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                if zoomStart == nil { zoomStart = scale }
                scale = min(max((zoomStart ?? scale) * value.magnification, 0.9), 14)
            }
            .onEnded { _ in zoomStart = nil }
    }

    private func handleTap(at location: CGPoint, projection: Projection) {
        guard let info = guide.info else { return }
        let hit = info.exhibits.min {
            projection.distance(location, to: $0.floorPoint) < projection.distance(location, to: $1.floorPoint)
        }
        if let hit, projection.distance(location, to: hit.floorPoint) < 28 {
            onSelect(hit)
        }
    }

    private var accessibilitySummary: String {
        var parts = [guide.placeName.isEmpty ? "" : tr("You are in: ", "Jesteś tutaj: ") + guide.placeName + "."]
        if let nearest = guide.nearby.first {
            parts.append(tr("Nearest exhibit: ", "Najbliższy eksponat: ") + "\(nearest.name), \(guide.directions(to: nearest)).")
        }
        return parts.joined(separator: " ")
    }

    /// Floor metres <-> screen points, north up.
    private struct Projection {
        /// Where `center` appears on screen (the middle of the visible area).
        let anchor: CGPoint
        let center: SIMD2<Float>
        let scale: CGFloat

        func point(_ p: SIMD2<Float>) -> CGPoint {
            CGPoint(x: anchor.x + CGFloat(p.x - center.x) * scale,
                    y: anchor.y + CGFloat(p.y - center.y) * scale)
        }

        func distance(_ location: CGPoint, to p: SIMD2<Float>) -> CGFloat {
            let q = point(p)
            return hypot(q.x - location.x, q.y - location.y)
        }
    }
}
