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
                                ForEach(0..<10, id: \.self) { _ in Shimmer().frame(width: 156, height: 234) }
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
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150, maximum: 210), spacing: 16, alignment: .top)], alignment: .leading, spacing: 22) {
            ForEach(0..<14, id: \.self) { _ in Shimmer().aspectRatio(2.0 / 3.0, contentMode: .fit) }
        }
        .padding(.horizontal, 44)
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
