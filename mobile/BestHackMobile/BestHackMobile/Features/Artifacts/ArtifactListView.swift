import SwiftUI

/// Every exhibit as a picture card, with your progress on top. Tap one to see it in 3D and go there.
struct ArtifactListView: View {
    let guide: GuideModel
    let visits: VisitLog
    /// Called after "Let's go" so the sheet can close and the walk can start.
    var onStartWalking: () -> Void

    @Environment(\.dismiss) private var dismiss

    private var exhibits: [MuseumInfo.Exhibit] {
        (guide.info?.exhibits ?? []).sorted { guide.distance(to: $0) < guide.distance(to: $1) }
    }

    private let columns = [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    progress
                    LazyVGrid(columns: columns, spacing: 14) {
                        ForEach(exhibits) { exhibit in
                            NavigationLink {
                                ArtifactDetailView(guide: guide, visits: visits, exhibit: exhibit, onStartWalking: onStartWalking)
                            } label: {
                                ExhibitGridCard(exhibit: exhibit,
                                                directions: guide.directions(to: exhibit),
                                                isVisited: visits.contains(exhibit.key))
                            }
                            .buttonStyle(CardButtonStyle(padding: 12))
                        }
                    }
                }
                .padding(16)
                .frame(maxWidth: 720)
                .frame(maxWidth: .infinity)
            }
            .background(Theme.page)
            .navigationTitle(tr("Exhibits", "Eksponaty"))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(tr("Done", "Gotowe")) { dismiss() }
                        .font(Theme.bodyBold)
                }
            }
        }
    }

    private var progress: some View {
        let total = max(exhibits.count, 1)
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(visits.visited.isEmpty ? tr("Start your collection", "Zacznij kolekcję") : tr("\(visits.visited.count) of \(total) seen", "Odwiedzone: \(visits.visited.count) z \(total)"))
                    .font(Theme.headline)
                    .foregroundStyle(Theme.ink)
                Spacer(minLength: 0)
                Image(systemName: "star.fill")
                    .foregroundStyle(Theme.amber)
            }
            ProgressLine(value: Double(visits.visited.count) / Double(total), tint: Theme.amber, height: 8)
        }
        .card()
        .accessibilityElement(children: .combine)
    }
}

/// A big picture card for the grid.
struct ExhibitGridCard: View {
    let exhibit: MuseumInfo.Exhibit
    var directions: String
    var isVisited: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ExhibitThumbnail(key: exhibit.key, size: 140)
                .frame(maxWidth: .infinity)
                .overlay(alignment: .topTrailing) {
                    if isVisited {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 24))
                            .foregroundStyle(.white, Theme.mint)
                            .padding(4)
                    }
                }
            Text(exhibit.name)
                .font(Theme.bodyBold)
                .foregroundStyle(Theme.ink)
                .lineLimit(2, reservesSpace: true)
                .multilineTextAlignment(.leading)
            Text(exhibit.galleryName)
                .font(Theme.small)
                .foregroundStyle(Theme.inkSoft)
                .lineLimit(1)
            Label(directions, systemImage: "figure.walk")
                .font(Theme.small)
                .foregroundStyle(Theme.inkSoft)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(exhibit.name), \(exhibit.galleryName), \(directions)" + (isVisited ? tr(", visited", ", odwiedzony") : ""))
    }
}
