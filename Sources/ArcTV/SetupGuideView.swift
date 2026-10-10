import SwiftUI

/// "How to set up your sources": a beginner's guide (debrid service, Torrentio, then Arc TV), the same as the web app's, opened from the page that
/// says no sources were found.
struct SetupGuideView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ZStack(alignment: .topLeading) {
            Theme.background.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Text("How to set up your sources")
                        .font(.system(size: 34, weight: .heavy))
                        .foregroundStyle(Theme.brandGradient)
                        .padding(.top, 70)
                    Text("Arc TV is a player. It shows you movies and shows, but it needs somewhere to get the video from. This guide shows you how to connect that, one small step at a time. You don't need to be good with computers.")
                        .font(.system(size: 16))
                        .foregroundStyle(Theme.textSecondary)

                    box("The short version") {
                        numbered("Debrid service:", "a small subscription that gives you fast, ready-to-play links.", 1)
                        numbered("Torrentio:", "a free addon that finds those links. You connect it to your debrid service.", 2)
                        numbered("Arc TV:", "you paste one link into the app, and you're done.", 3)
                        paragraph("A plan is very cheap. Plans usually cost only a few dollars a month, and you can stop any time. You only need one service. The price is on the service's own website, so check there for today's plans.")
                    }

                    part("Part 1 of 3", "Get a debrid service",
                         "A debrid service is a website you pay a small amount to each month. It does the heavy lifting and gives Arc TV a link that plays straight away. The two most popular are Real-Debrid and TorBox. Pick one. You don't need both.") {
                        step(1, "Make an account") {
                            paragraph("Go to the website of the one you chose and sign up with your email.")
                            HStack(spacing: 6) { site("real-debrid.com", "https://real-debrid.com"); Text("or").foregroundStyle(Theme.textSecondary); site("torbox.app", "https://torbox.app") }
                        }
                        step(2, "Buy a plan") { paragraph("Pick the cheapest plan to start. It's very cheap, and the lowest one is all you need. The website will walk you through paying.") }
                        step(3, "Find your API key") {
                            paragraph("An API key is just a long password made of letters and numbers. It lets Torrentio use the plan you paid for. You will copy it in a moment.")
                            bullet("Real-Debrid: while signed in, open real-debrid.com/apitoken and copy the long code you see.")
                            bullet("TorBox: sign in, open Settings, and copy your API key.")
                        }
                        step(4, "Keep it safe") { paragraph("Leave the page open, or paste the key into a note for the next part.") }
                        warning("Never share your API key. Anyone with it can use the plan you paid for. If it ever leaks, make a new one on the service's website.")
                    }

                    part("Part 2 of 3", "Connect it to Torrentio",
                         "Torrentio is a free addon that searches for your movies and shows. Here you tell it about your debrid service. At the end it gives you one special link, which you will use in Part 3.") {
                        step(1, "Open the Torrentio setup page") { site("torrentio.strem.fun/configure", "https://torrentio.strem.fun/configure") }
                        step(2, "Choose your debrid service") { paragraph("Scroll down to the box that says Debrid provider. Click it and choose the service you signed up for (RealDebrid or TorBox).") }
                        step(3, "Paste your API key") {
                            paragraph("A new box appears. Paste the API key from Part 1 into it. With Real-Debrid there may also be a Continue to Real-Debrid button. You can use it to sign in and it will fill the key in for you.")
                        }
                        step(4, "Leave everything else alone") { paragraph("The other settings are optional and the defaults work well. If you're not sure, skip it.") }
                        step(5, "Copy your link") {
                            paragraph("Scroll to the very bottom of the page. You'll see a button called Install. Don't click Install. It's built for a different app. Copy the link instead: right-click the Install button and choose Copy Link.")
                            paragraph("The link looks something like https://torrentio.strem.fun/realdebrid=…/manifest.json. It may start with stremio://, and Arc TV accepts that too.")
                        }
                        warning("This link has your API key inside it. Only paste it into Arc TV. Don't post it or send it to anyone.")
                    }

                    part("Part 3 of 3", "Add Torrentio to Arc TV", "Last part. You paste the link you copied and Arc TV does the rest.") {
                        step(1, "Open the Addons page") {
                            Button("Go to Settings > Addons") { model.openSettings(.addons) }.buttonStyle(GlassButtonStyle())
                        }
                        step(2, "Paste your link") { paragraph("Click the box under Add an addon, paste the link from Part 2, and press Add.") }
                        step(3, "Wait for the confirmation") { paragraph("After a moment you'll see that Torrentio was added. It now shows in your addon list.") }
                        step(4, "Play something") { paragraph("Open any movie or show and press Play. To pick a source yourself, use Choose source in the title's right-click menu.") }
                        Text("That's it, you're done. Your addons are saved to your account, so they also show up on your other devices once you sign in to Arc TV.")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)
                    }

                    VStack(alignment: .leading, spacing: 14) {
                        Text("Something went wrong?").font(.system(size: 24, weight: .bold)).foregroundStyle(Theme.textPrimary)
                        faq("It says \"Couldn't install that addon\"", "The link was probably cut short. It must end in /manifest.json. Go back to the Torrentio page and copy it again.")
                        faq("There are no sources, or a source won't play", "Check that your debrid plan is still active and you used the right API key. If you made a new key, repeat Part 2 to get a new link and replace the old addon.")
                        faq("I want to change my debrid service or key", "In Settings > Addons, remove Torrentio. Then do Part 2 and Part 3 again with the new details.")
                        faq("One title has no sources", "Not every title is available everywhere. Try a different source in the list, or a different title.")
                    }
                }
                .frame(maxWidth: 760, alignment: .leading)
                .padding(.horizontal, 44)
                .padding(.bottom, 60)
                .frame(maxWidth: .infinity)
            }
            BackButton { model.guideOpen = false }
                .padding(.leading, 28)
                .padding(.top, 22)
        }
    }

    // MARK: Pieces

    private func box<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.system(size: 20, weight: .bold)).foregroundStyle(Theme.textPrimary)
            content()
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(Theme.elevated))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.divider, lineWidth: 1))
    }

    private func part<Content: View>(_ label: String, _ title: String, _ intro: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(label.uppercased()).font(.system(size: 12, weight: .bold)).tracking(1.2).foregroundStyle(Theme.accent)
            Text(title).font(.system(size: 26, weight: .heavy)).foregroundStyle(Theme.textPrimary)
            paragraph(intro)
            content()
        }
    }

    private func step<Content: View>(_ number: Int, _ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Text("\(number)")
                .font(.system(size: 16, weight: .heavy))
                .foregroundStyle(Color(hex: 0x04161A))
                .frame(width: 34, height: 34)
                .background(Circle().fill(Theme.brandGradient))
            VStack(alignment: .leading, spacing: 8) {
                Text(title).font(.system(size: 17, weight: .bold)).foregroundStyle(Theme.textPrimary)
                content()
            }
        }
    }

    private func numbered(_ lead: String, _ text: String, _ number: Int) -> some View {
        (Text("\(number). ").foregroundColor(Theme.accent) + Text(lead + " ").bold().foregroundColor(Theme.textPrimary) + Text(text).foregroundColor(Theme.textSecondary))
            .font(.system(size: 15))
    }

    private func paragraph(_ text: String) -> some View {
        Text(text).font(.system(size: 15)).foregroundStyle(Theme.textSecondary).fixedSize(horizontal: false, vertical: true)
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("•").foregroundStyle(Theme.textTertiary)
            paragraph(text)
        }
    }

    private func site(_ label: String, _ address: String) -> some View {
        Group {
            if let url = URL(string: address) { Link(label, destination: url) } else { Text(label) }
        }
        .font(.system(size: 15, weight: .semibold))
    }

    private func warning(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 14))
            .foregroundStyle(Theme.textPrimary)
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color(hex: 0xFFB020).opacity(0.12)))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(hex: 0xFFB020).opacity(0.5), lineWidth: 1))
    }

    private func faq(_ question: String, _ answer: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(question).font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.textPrimary)
            paragraph(answer)
        }
    }
}
