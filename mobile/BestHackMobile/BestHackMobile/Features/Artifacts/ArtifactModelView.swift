import RealityKit
import SwiftUI

/// An exhibit's 3D model, slowly turning. With `interactive`, drag sideways to turn it yourself.
/// Turning stops when Reduce Motion is on.
///
/// The turning happens in RealityKit's own frame loop (not a SwiftUI timeline), so SwiftUI doesn't redraw
/// this view 30 times a second.
struct ArtifactModelView: View {
    let exhibit: MuseumInfo.Exhibit
    var interactive = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var turntable = Entity()
    @State private var spin = Spin()
    @State private var isLoaded = false
    @State private var failed = false
    @State private var dragStartAngle: Float?

    /// Shared with the frame loop.
    private final class Spin {
        var automatic: Float = 0.5
        var manual: Float = 0
        var isPaused = false
        var subscription: EventSubscription?
    }

    var body: some View {
        RealityView { content in
            content.camera = .virtual
            let camera = PerspectiveCamera()
            camera.camera.fieldOfViewInDegrees = 30
            camera.look(at: [0, 0.02, 0], from: [0, 0.55, 2.4], relativeTo: nil)
            content.add(camera)

            let key = DirectionalLight()
            key.light.intensity = 3200
            key.look(at: .zero, from: [1.5, 2.5, 2.5], relativeTo: nil)
            content.add(key)
            let fill = DirectionalLight()
            fill.light.intensity = 1400
            fill.look(at: .zero, from: [-2, 1, -1.5], relativeTo: nil)
            content.add(fill)

            content.add(turntable)
            let spin = spin
            let turntable = turntable
            spin.subscription = content.subscribe(to: SceneEvents.Update.self) { [weak spin, weak turntable] event in
                guard let spin, let turntable else { return }
                if !spin.isPaused { spin.automatic += Float(event.deltaTime) * 0.45 }
                turntable.orientation = simd_quatf(angle: spin.automatic + spin.manual, axis: [0, 1, 0])
            }

            guard let model = try? await MuseumAssets.artifact(exhibit) else {
                failed = true
                return
            }
            // Fit any size (a 37 m dinosaur or a 40 cm mask) into a 1 m box, centred.
            let bounds = model.visualBounds(relativeTo: nil)
            let size = max(bounds.extents.x, bounds.extents.y, bounds.extents.z)
            let scale: Float = size > 0 ? 1 / size : 1
            model.scale = SIMD3(repeating: scale)
            model.position = -bounds.center * scale
            turntable.addChild(model)
            isLoaded = true
        }
        .onAppear { spin.isPaused = reduceMotion }
        .onChange(of: reduceMotion) { _, reduce in spin.isPaused = reduce }
        .overlay {
            if failed {
                // No 3D model: show the picture instead.
                ExhibitThumbnail(key: exhibit.key, size: 200, background: .clear)
            } else if !isLoaded {
                ProgressView()
            }
        }
        // Sideways swipes turn the model; vertical ones still scroll the page.
        .simultaneousGesture(turnGesture, including: interactive ? .all : .none)
        .accessibilityElement()
        .accessibilityLabel(tr("3D model of ", "Model 3D: ") + exhibit.name)
        .accessibilityAddTraits(.isImage)
    }

    private var turnGesture: some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                guard abs(value.translation.width) > abs(value.translation.height) || dragStartAngle != nil else { return }
                if dragStartAngle == nil { dragStartAngle = spin.manual }
                spin.manual = (dragStartAngle ?? 0) + Float(value.translation.width) * 0.012
            }
            .onEnded { _ in dragStartAngle = nil }
    }
}
