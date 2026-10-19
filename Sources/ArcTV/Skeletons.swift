import SwiftUI

/// A grey block with a light sweep across it, shown where something is still loading (the web app's shimmer).
struct Shimmer: View {
    var cornerRadius: CGFloat = 10
    @State private var phase: CGFloat = -1

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(Theme.surface)
            .overlay(
                GeometryReader { geo in
                    LinearGradient(colors: [.clear, Color.white.opacity(0.07), .clear], startPoint: .leading, endPoint: .trailing)
                        .frame(width: geo.size.width * 0.6)
                        .offset(x: phase * geo.size.width * 1.6)
                }
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            )
            .onAppear {
                withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) { phase = 1 }
            }
    }
}

/// Home while its rows load: a banner and three rows of posters.
struct HomeSkeleton: View {
    var body: some View {
        GeometryReader { geo in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Shimmer(cornerRadius: 0).frame(height: min(520, geo.size.height * 0.62))
                    Spacer().frame(height: 32)
                    ForEach(0..<3, id: \.self) { _ in
                        VStack(alignment: .leading, spacing: 14) {
                            Shimmer(cornerRadius: 6).frame(width: 180, height: 20).padding(.horizontal, 44)
                            HStack(spacing: 16) {
                                ForEach(0..<10, id: \.self) { _ in Shimmer().frame(width: PosterSize.row, height: PosterSize.row * 1.5) }
                            }
                            .padding(.horizontal, 44)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .clipped()
                        }
                        .padding(.bottom, 32)
                    }
                }
            }
            .disabled(true)
        }
    }
}

/// Movies / TV Shows / My List while the first page loads: a grid of grey posters.
struct GridSkeleton: View {
    var body: some View {
        LazyVGrid(columns: PosterSize.gridColumns, alignment: .leading, spacing: 24) {
            ForEach(0..<14, id: \.self) { _ in Shimmer().aspectRatio(2.0 / 3.0, contentMode: .fit) }
        }
        .padding(.horizontal, 44)
    }
}

/// Select a source while the addons answer: the quality pills and sort button, and source cards, each the size and shape of the real ones.
struct SourcesSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                ForEach([104, 50, 72, 66, 64], id: \.self) { width in Shimmer(cornerRadius: 17).frame(width: CGFloat(width), height: 34) }
                Spacer(minLength: 12)
                Shimmer(cornerRadius: 17).frame(width: 150, height: 34)
            }
            VStack(spacing: 10) {
                ForEach(0..<8, id: \.self) { _ in SourceCardSkeleton() }
            }
        }
    }
}

/// One source card: the quality badge, three lines of text, the size and addon, and the play button.
struct SourceCardSkeleton: View {
    var body: some View {
        HStack(spacing: 16) {
            Shimmer().frame(width: 70, height: 46)
            VStack(alignment: .leading, spacing: 7) {
                Shimmer(cornerRadius: 4).frame(maxWidth: 420, minHeight: 14, maxHeight: 14)
                Shimmer(cornerRadius: 4).frame(width: 150, height: 11)
                Shimmer(cornerRadius: 4).frame(width: 210, height: 10)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 7) {
                Shimmer(cornerRadius: 4).frame(width: 60, height: 13)
                Shimmer(cornerRadius: 4).frame(width: 74, height: 10)
            }
            Shimmer(cornerRadius: 15).frame(width: 30, height: 30)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(height: 78)
        .background(RoundedRectangle(cornerRadius: 14).fill(Theme.surfaceHigh.opacity(0.85)))
    }
}

/// The cast row of a title's page while it loads: round photos with a name under each.
struct CastSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Shimmer(cornerRadius: 6).frame(width: 70, height: 22)
            HStack(spacing: 20) {
                ForEach(0..<4, id: \.self) { _ in
                    VStack(spacing: 8) {
                        Shimmer(cornerRadius: 58).frame(width: 116, height: 116)
                        Shimmer(cornerRadius: 4).frame(width: 90, height: 13)
                        Shimmer(cornerRadius: 4).frame(width: 60, height: 10)
                    }
                }
            }
        }
    }
}

/// A show's seasons and episodes while they load.
struct SeasonsSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Shimmer(cornerRadius: 6).frame(width: 110, height: 22)
            HStack(spacing: 12) { ForEach(0..<5, id: \.self) { _ in Shimmer(cornerRadius: 26).frame(width: 52, height: 52) } }
            HStack(spacing: 16) {
                ForEach(0..<4, id: \.self) { _ in
                    VStack(alignment: .leading, spacing: 8) {
                        Shimmer().frame(width: 270, height: 152)
                        Shimmer(cornerRadius: 4).frame(width: 200, height: 14)
                        Shimmer(cornerRadius: 4).frame(width: 250, height: 11)
                    }
                }
            }
        }
    }
}

/// Your stats while the history is read.
struct StatsSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) { ForEach(0..<3, id: \.self) { _ in Shimmer(cornerRadius: 14).frame(maxWidth: .infinity).frame(height: 96) } }
            Shimmer(cornerRadius: 14).frame(maxWidth: .infinity).frame(height: 150)
            Shimmer(cornerRadius: 14).frame(maxWidth: .infinity).frame(height: 110)
        }
    }
}

/// Shown at the bottom of the window while the Mac has no network.
struct OfflineBanner: View {
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "wifi.slash")
            Text("You're offline. Titles load again, and changes you make go through, once you're back online.")
        }
        .font(.system(size: 13))
        .foregroundStyle(Theme.textSecondary)
        .padding(.horizontal, 44)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(hex: 0x26262B).opacity(0.96))
    }
}
