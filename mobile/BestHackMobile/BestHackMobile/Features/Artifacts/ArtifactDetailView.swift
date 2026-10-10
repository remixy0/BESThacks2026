import SwiftUI

/// One exhibit: turn the 3D model with your finger, read or hear about it, and go there.
struct ArtifactDetailView: View {
    let guide: GuideModel
    let visits: VisitLog
    let exhibit: MuseumInfo.Exhibit
    /// Shows a Close button (when the page is its own sheet rather than pushed from the list).
    var showsClose = false
    /// Called after "Let's go" (and Close).
    var onStartWalking: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                ZStack(alignment: .bottomLeading) {
                    ArtifactModelView(exhibit: exhibit, interactive: true)
                        .frame(height: 280)
                        .frame(maxWidth: .infinity)
                        .background(
                            RadialGradient(colors: [Theme.accent.opacity(0.14), Theme.cardSunken],
                                           center: .center, startRadius: 10, endRadius: 220)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: Theme.corner, style: .continuous))
                    Label(tr("Swipe sideways to turn it", "Przesuń w bok, żeby obrócić"), systemImage: "hand.draw.fill")
                        .font(Theme.small)
                        .foregroundStyle(Theme.inkSoft)
                        .padding(12)
                        .accessibilityHidden(true)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text(exhibit.name)
                        .font(Theme.title(.title))
                        .foregroundStyle(Theme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                    HStack(spacing: 8) {
                        Chip(text: exhibit.galleryName, systemImage: "building.columns.fill", tint: Theme.ink)
                        Chip(text: guide.directions(to: exhibit), systemImage: "figure.walk", tint: Theme.ink)
                    }
                    if visits.contains(exhibit.key) {
                        Chip(text: tr("You've been here", "Odwiedzony"), systemImage: "checkmark", tint: Theme.mintText)
                    }
                }

                Text(exhibit.story)
                    .font(Theme.body)
                    .foregroundStyle(Theme.ink)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.page)
        .soundScreen(.exhibitDetail, guide: guide)
        // The main action always sits at the bottom of the screen.
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 10) {
                StoryButton(guide: guide, exhibit: exhibit)
                Button {
                    guide.navigate(to: exhibit)
                    onStartWalking()
                } label: {
                    Text(tr("Let's go", "Ruszamy"))
                }
                .buttonStyle(AppButtonStyle(kind: .primary))
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 6)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
            .background(Theme.page.opacity(0.96).ignoresSafeArea())
        }
        .navigationTitle(exhibit.name)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            if showsClose {
                ToolbarItem(placement: .cancellationAction) {
                    Button(tr("Close", "Zamknij"), action: onStartWalking)
                        .font(Theme.bodyBold)
                }
            }
        }
    }
}
