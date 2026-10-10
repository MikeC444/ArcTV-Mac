import ArcTVCore
import SwiftUI

/// Settings > Recommendations (Arc TV Plus): what has been liked or marked Not for me, what shapes the Picked for you row, and a reset.
struct RecommendationsPane: View {
    @EnvironmentObject private var model: AppModel
    @State private var tab: Rating = .like
    @State private var confirmingReset = false

    var body: some View {
        Group {
            if model.plus.active { content } else { locked }
        }
        .task {
            await model.loadPlus()
            if model.plus.active { await model.loadRatings() }
        }
    }

    private var locked: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Recommendations are only for Arc TV Plus.").font(.system(size: 16, weight: .bold)).foregroundStyle(Theme.textPrimary)
            Text("With Plus, Arc TV learns what you like and fills a Picked for you row on Home.")
                .font(.system(size: 13))
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(Theme.elevated))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.divider, lineWidth: 1))
    }

    private var summary: RecommendationSummary {
        summarizeRecommendations(ratings: model.ratings.compactMapValues(\.rating), list: model.myList ?? [])
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("See what shapes your Picked for you row, and fine-tune what you see.")
                .font(.system(size: 13))
                .foregroundStyle(Theme.textSecondary)

            ratedSection
            shapesSection
            howItWorks
            resetSection
        }
    }

    // MARK: Liked / Not for me

    private var shown: [FeedbackItem] {
        model.ratings.values.filter { $0.rating == tab }.sorted { $0.updatedAt > $1.updatedAt }
    }

    private var ratedSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                ChoicePill(label: "Liked (\(summary.likes))", selected: tab == .like) { tab = .like }
                ChoicePill(label: "Not for me (\(summary.dislikes))", selected: tab == .dislike) { tab = .dislike }
            }
            if shown.isEmpty {
                Text(tab == .like
                     ? "Nothing liked yet. Choose Like on any movie or show and it shows up here."
                     : "Nothing marked Not for me yet. Those titles, and ones like them, are left out of your picks.")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textTertiary)
            } else {
                VStack(spacing: 8) {
                    ForEach(shown) { item in RatedRow(item: item) }
                }
            }
        }
    }

    // MARK: What shapes your picks

    private var shapesSection: some View {
        let s = summary
        return card("What shapes your picks") {
            pointsRow("Titles you like (\(s.likes))", pointsLabel(s.likePoints))
            pointsRow("Titles marked Not for me (\(s.dislikes))", pointsLabel(s.dislikePoints))
            pointsRow("Your My List and finished titles (\(s.finished) finished, \(s.saved) saved)", pointsLabel(s.listPoints))
            Text("Movies count as finished when you watch them to the end; mark a show as watched yourself. Points are how much each title counts toward your taste. They are not a score.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.textTertiary)
            if s.overLimit {
                Text("Only your \(RecommendConfig.interactionDetailFetchLimit) strongest ratings and saves are used for your picks right now.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textTertiary)
            }
            if !s.ready {
                Text("Not enough yet: your picks start once you have at least \(RecommendConfig.minInteractionsForPersonalisation) titles you like, finished, saved or marked Not for me, and at least one of them liked, finished or saved. Until then Home shows popular titles.")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.accent)
            }
        }
    }

    private var howItWorks: some View {
        card("How it works") {
            step("1", "It learns your taste.", "Every movie or show you like, finish or save adds points toward the genres, directors and cast you enjoy. A Like counts most, and Not for me counts against.")
            step("2", "It scores what is on offer.", "Titles from your Home rows are compared with your taste, mostly on genre, then on director and cast. Titles you have already finished, rated or are watching are left out.")
            step("3", "It shows a spread.", "Your strongest matches stay, and the rest of the row follows your mix of tastes, so a smaller taste still gets its share.")
            step("4", "It changes when you refresh.", "Most of the row is different next time, and no single title of yours can explain too many picks.")
            step("5", "It explains itself.", "The line under most picks names the title behind it. A few say \"More from directors you enjoy\" instead, and with no real match no reason is shown.")
        }
    }

    private var resetSection: some View {
        card("Reset preferences") {
            Text("Clears every Like and Not for me (\(model.ratings.count) now). Your picks still use your My List and finished titles, and a title you removed from the row stays out for \(RecommendConfig.pickedDismissDays) days.")
                .font(.system(size: 13))
                .foregroundStyle(Theme.textSecondary)
            Button { confirmingReset = true } label: { Label("Reset preferences", systemImage: "arrow.counterclockwise") }
                .buttonStyle(GlassButtonStyle())
                .disabled(model.ratings.isEmpty)
        }
        .alert("Reset your preferences?", isPresented: $confirmingReset) {
            Button("Reset", role: .destructive) { Task { await model.resetRatings() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Every Like and Not for me is cleared, on every device.")
        }
    }

    // MARK: Pieces

    private func card<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.system(size: 16, weight: .bold)).foregroundStyle(Theme.textPrimary)
            content()
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(Theme.elevated))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.divider, lineWidth: 1))
    }

    private func pointsRow(_ label: String, _ points: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).font(.system(size: 14)).foregroundStyle(Theme.textSecondary)
            Spacer(minLength: 12)
            Text(points).font(.system(size: 14, weight: .bold)).foregroundStyle(Theme.textPrimary)
        }
    }

    private func step(_ number: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(number)
                .font(.system(size: 12, weight: .heavy))
                .foregroundStyle(Color(hex: 0x04161A))
                .frame(width: 22, height: 22)
                .background(Circle().fill(Theme.brandGradient))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.textPrimary)
                Text(detail).font(.system(size: 13)).foregroundStyle(Theme.textSecondary)
            }
        }
    }
}

/// One rated title: its poster, its name, and a way to take the rating off.
private struct RatedRow: View {
    @EnvironmentObject private var model: AppModel
    let item: FeedbackItem

    private var preview: MetaPreview {
        MetaPreview(id: item.contentId, type: item.contentType == "MOVIE" ? "movie" : "series", name: item.title, poster: model.ratingPosters[item.contentId])
    }

    var body: some View {
        HStack(spacing: 12) {
            Color.clear
                .frame(width: 40, height: 60)
                .overlay {
                    if let poster = preview.poster, let url = URL(string: poster) {
                        AsyncImage(url: url) { phase in
                            if case let .success(image) = phase { image.resizable().aspectRatio(contentMode: .fill) }
                        }
                    } else {
                        Text(String(item.title.prefix(1))).font(.system(size: 18, weight: .bold)).foregroundStyle(Theme.textTertiary)
                    }
                }
                .background(Theme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title).font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.textPrimary).lineLimit(1)
                Text(item.contentType == "MOVIE" ? "Movie" : "TV show").font(.system(size: 12)).foregroundStyle(Theme.textTertiary)
            }
            Spacer(minLength: 0)
            Button { model.openDetail(preview) } label: { Text("View") }
                .buttonStyle(GlassButtonStyle())
            Button {
                if let rating = item.rating { Task { await model.rate(preview, rating) } }
            } label: { Label("Remove", systemImage: "xmark") }
                .buttonStyle(GlassButtonStyle())
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.elevated))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.divider, lineWidth: 1))
    }
}
