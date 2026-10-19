import ArcTVCore
import SwiftUI

/// Netflix's page, laid out like the web app's: a "Top 10 Today" row (a big outlined number behind each poster, the red N on its corner), then the
/// service's titles as wide pictures close together, with each title's logo at its bottom left and no captions.

/// The service's red N, drawn as three bars (the web app's `NetflixN`), for a corner of a picture.
struct NetflixN: View {
    var width: CGFloat = 11

    var body: some View {
        Canvas { context, size in
            let w = size.width
            let h = size.height
            let red = Color(hex: 0xE50914)
            context.fill(Path(CGRect(x: 0, y: 0, width: w / 3, height: h)), with: .color(red))
            context.fill(Path(CGRect(x: w * 2 / 3, y: 0, width: w / 3, height: h)), with: .color(red))
            var diagonal = Path()
            diagonal.move(to: CGPoint(x: 0, y: 0))
            diagonal.addLine(to: CGPoint(x: w / 3, y: 0))
            diagonal.addLine(to: CGPoint(x: w, y: h))
            diagonal.addLine(to: CGPoint(x: w * 2 / 3, y: h))
            diagonal.closeSubpath()
            context.fill(diagonal, with: .color(Color(hex: 0xB1060F)))
        }
        .frame(width: width, height: width * 40 / 24)
        .shadow(color: .black.opacity(0.6), radius: 1.5, y: 1)
    }
}

/// A title's logo at the bottom left of a wide picture, on a soft shade. It looks the logo up on Metahub (Cinemeta's own logos live there, by IMDb id);
/// nothing is drawn, shade included, when there is none.
private struct WideLogo: View {
    let item: MetaPreview
    @State private var image: NSImage?

    private var url: URL? {
        if let logo = item.logo, let url = URL(string: logo) { return url }
        let digits = item.id.dropFirst(2)
        guard item.id.hasPrefix("tt"), !digits.isEmpty, digits.allSatisfy(\.isNumber) else { return nil }
        return URL(string: "https://images.metahub.space/logo/medium/\(item.id)/img")
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            if let image {
                LinearGradient(colors: [.clear, Color.black.opacity(0.7)], startPoint: .center, endPoint: .bottom)
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: 110, maxHeight: 40, alignment: .bottomLeading)
                    .padding(.leading, 8)
                    .padding(.bottom, 6)
                    .shadow(color: .black.opacity(0.5), radius: 3, y: 1)
            }
        }
        .task(id: url) {
            guard let url else { return }
            image = await ImageCache.load(url)
        }
        .allowsHitTesting(false)
    }
}

/// One title on Netflix's page: a tall poster (the Top 10) or a wide picture (the rest), with the red N at its top left, the watched tick at its top
/// right and no caption. A click opens the title; a right-click opens its menu, as everywhere else.
struct ServiceCard: View {
    @EnvironmentObject private var model: AppModel
    let item: MetaPreview
    var wide = true
    @State private var hovering = false

    var body: some View {
        Color.clear
            .aspectRatio(wide ? 16.0 / 9.0 : 2.0 / 3.0, contentMode: .fit)
            .overlay { artwork }
            .overlay { if wide { WideLogo(item: item) } }
            .background(RoundedRectangle(cornerRadius: 4).fill(Theme.surface))
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .overlay(alignment: .topLeading) { NetflixN(width: wide ? 11 : 13).padding(.top, 5).padding(.leading, 6) }
            .overlay(alignment: .topTrailing) {
                if model.isWatched(item.id) { WatchedTick().padding(5) }
            }
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.white.opacity(hovering ? 0.9 : 0.1), lineWidth: hovering ? 2 : 1))
            .shadow(color: .black.opacity(hovering ? 0.55 : 0), radius: 12, y: 5)
            .scaleEffect(hovering ? 1.04 : 1)
            .animation(.easeOut(duration: 0.15), value: hovering)
            .onHover { inside in
                hovering = inside
                CardHover.update(CardMenuTarget(item: item), hovering: inside)
            }
            .contentShape(Rectangle())
            .onTapGesture { model.openDetail(item) }
            .help(item.name)
    }

    @ViewBuilder
    private var artwork: some View {
        let picture = wide ? (item.background ?? item.poster) : item.poster
        if let picture, let url = URL(string: picture) {
            CachedImage(url: url, contentMode: .fill)
        }
    }
}

/// The big outlined rank behind a Top 10 poster: a thin light-grey outline with the page's own colour inside, the digits as wide as their own shape (a 1 is
/// narrow), the poster over its right-hand part.
private struct RankNumber: View {
    let rank: Int
    let posterWidth: CGFloat

    private static let outline: [CGSize] = [
        CGSize(width: -1.1, height: 0), CGSize(width: 1.1, height: 0), CGSize(width: 0, height: -1.1), CGSize(width: 0, height: 1.1),
        CGSize(width: -0.8, height: -0.8), CGSize(width: 0.8, height: -0.8), CGSize(width: -0.8, height: 0.8), CGSize(width: 0.8, height: 0.8)
    ]

    var body: some View {
        let digits = Array(String(rank))
        let widths = digits.map { $0 == "1" ? posterWidth * 0.52 : posterWidth * 0.84 }
        let size = posterWidth * 1.5
        HStack(spacing: 0) {
            ForEach(digits.indices, id: \.self) { index in
                digit(String(digits[index]), size: size).frame(width: widths[index], alignment: .center)
            }
        }
        .frame(width: widths.reduce(0, +) - posterWidth * 0.2, height: posterWidth * 1.2, alignment: .bottomLeading)
        .accessibilityHidden(true)
    }

    private func digit(_ text: String, size: CGFloat) -> some View {
        ZStack {
            ForEach(Self.outline.indices, id: \.self) { index in
                Text(text).foregroundStyle(Color(hex: 0x6F6F7A)).offset(Self.outline[index])
            }
            Text(text).foregroundStyle(Theme.background)
        }
        .font(.system(size: size, weight: .black))
        .fixedSize()
        .offset(y: size * 0.14)
        .frame(height: posterWidth * 1.2, alignment: .bottom)
    }
}

/// What the Top 10 row shows: grey posters while the list is on its way, the ten titles, or nothing (no list for this service).
enum TopTenState: Equatable {
    case loading
    case ready([MetaPreview])
    case none
}

struct TopTenSection: View {
    let state: TopTenState
    private let posterWidth: CGFloat = PosterSize.topTen

    var body: some View {
        switch state {
        case .none:
            EmptyView()
        case .loading:
            section {
                ForEach(0..<TopTen.count, id: \.self) { index in
                    HStack(alignment: .bottom, spacing: 0) {
                        RankNumber(rank: index + 1, posterWidth: posterWidth)
                        Shimmer(cornerRadius: 4).frame(width: posterWidth, height: posterWidth * 1.5)
                    }
                }
            }
        case let .ready(items):
            section {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    HStack(alignment: .bottom, spacing: 0) {
                        RankNumber(rank: index + 1, posterWidth: posterWidth)
                        ServiceCard(item: item, wide: false).frame(width: posterWidth).zIndex(1)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Number \(index + 1)")
                }
            }
        }
    }

    private func section<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Top 10 Today")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
                .padding(.horizontal, 44)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .bottom, spacing: 6) { content() }
                    .padding(.horizontal, 44)
                    .padding(.vertical, 12)
            }
        }
        .padding(.bottom, 14)
    }
}

/// The titles under the Top 10: wide pictures close together (small gaps and corners, no captions, the red N on each), more as the page is scrolled,
/// and grey wide shapes after the last one while more are still to come.
struct WideGrid: View {
    let items: [MetaPreview]
    var placeholders = false
    var onLastAppear: (() -> Void)? = nil

    private let columns = [GridItem(.adaptive(minimum: 230, maximum: 380), spacing: 9, alignment: .top)]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 9) {
            ForEach(items) { item in
                ServiceCard(item: item, wide: true)
                    .onAppear { if item.id == items.last?.id { onLastAppear?() } }
            }
            if placeholders {
                ForEach(items.count..<(items.count + 10), id: \.self) { index in
                    Shimmer(cornerRadius: 4).aspectRatio(16.0 / 9.0, contentMode: .fit)
                        .onAppear { if index == items.count { onLastAppear?() } }
                }
            }
        }
        .padding(.horizontal, 44)
    }
}

/// The wide grid made only of grey cells, for while the titles load.
struct WideGridSkeleton: View {
    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 230, maximum: 380), spacing: 9, alignment: .top)], alignment: .leading, spacing: 9) {
            ForEach(0..<20, id: \.self) { _ in Shimmer(cornerRadius: 4).aspectRatio(16.0 / 9.0, contentMode: .fit) }
        }
        .padding(.horizontal, 44)
    }
}
