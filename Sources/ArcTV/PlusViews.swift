import ArcTVCore
import SwiftUI

/// Shown in a Plus-only settings tab when the account does not have Plus.
private struct PlusLockedNote: View {
    @EnvironmentObject private var model: AppModel
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: "lock.fill").font(.system(size: 22)).foregroundStyle(Theme.textTertiary)
            Text(title).font(.system(size: 16, weight: .bold)).foregroundStyle(Theme.textPrimary)
            Text(detail).font(.system(size: 13)).foregroundStyle(Theme.textSecondary)
            Button { model.settingsTab = .plus } label: { Label("See Arc TV Plus", systemImage: "rosette") }.buttonStyle(GlassButtonStyle())
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(Theme.elevated))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.divider, lineWidth: 1))
    }
}

private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
    VStack(alignment: .leading, spacing: 12) { content() }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(Theme.elevated))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.divider, lineWidth: 1))
}

// MARK: Settings > Arc TV Plus

/// What Plus adds, whether you have it, and how to subscribe. Nothing here changes what the free app does.
struct PlusPane: View {
    @EnvironmentObject private var model: AppModel
    @State private var busy: String?
    @State private var waiting = false
    @State private var error: String?
    @State private var confirmingCancel = false
    @State private var cancelling = false
    @State private var cancelError: String?

    private var plus: PlusStatus { model.plus }
    private var owned: Bool { plus.paywall && plus.active }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            status
            subscription
            Text(PlusCopy.freeNote).font(.system(size: 14)).foregroundStyle(Theme.textSecondary)
            proceeds

            Text("What Plus adds").font(.system(size: 18, weight: .bold)).foregroundStyle(Theme.textPrimary).padding(.top, 8)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 14, alignment: .top), GridItem(.flexible(), spacing: 14, alignment: .top)], spacing: 14) {
                ForEach(PlusCopy.perks) { perk in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 10) {
                            Text(perk.title).font(.system(size: 15, weight: .bold)).foregroundStyle(Theme.textPrimary)
                            tag(perk.soon ? "Coming soon" : (plus.paywall ? "Plus" : "Included in early access"), soon: perk.soon)
                            if let extra = perk.tag { tag(extra, soon: true) }
                        }
                        Text(perk.detail).font(.system(size: 13)).foregroundStyle(Theme.textSecondary)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, minHeight: 150, maxHeight: 150, alignment: .topLeading)
                    .background(RoundedRectangle(cornerRadius: 14).fill(Theme.surface))
                }
            }

            if plus.paywall, !plus.active { subscribe }
        }
        .task { await model.loadPlus() }
    }

    private func tag(_ text: String, soon: Bool) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(soon ? Color(hex: 0xC9B5FF) : Theme.cyan)
            .padding(.horizontal, 10)
            .padding(.vertical, 2)
            .overlay(Capsule().stroke(soon ? Theme.violet.opacity(0.7) : Theme.cyan.opacity(0.5), lineWidth: 1))
    }

    private var status: some View {
        HStack(alignment: .center, spacing: 12) {
            if !plus.paywall {
                badge("Early access")
                Text("Arc TV Plus is in early access: its features are free for now and will need a Plus subscription once it launches.").font(.system(size: 13)).foregroundStyle(Theme.textSecondary)
            } else if plus.active {
                badge("Arc TV Plus")
                Text("You have Arc TV Plus\(PlusPlan.label(for: plus.plan).map { " (\($0))" } ?? "")\(validText) Thank you for supporting Arc TV.")
                    .font(.system(size: 13)).foregroundStyle(Theme.textSecondary)
            } else {
                badge("Free plan")
                Text("You're on the free plan. Everything below is included with Plus.").font(.system(size: 13)).foregroundStyle(Theme.textSecondary)
            }
        }
    }

    private var validText: String {
        if let until = plus.validUntil.flatMap(ISODate.date(from:)) { return ". Your current period runs to \(until.formatted(date: .abbreviated, time: .omitted))." }
        return ", for life."
    }

    private func badge(_ text: String) -> some View {
        Text(text).font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.textPrimary).padding(.horizontal, 12).padding(.vertical, 4).background(Capsule().fill(Theme.surfaceHigh))
    }

    private var proceeds: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "heart.fill").foregroundStyle(Theme.accent)
            Text(PlusCopy.proceedsNote).font(.system(size: 13)).foregroundStyle(Theme.textPrimary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(Theme.accent.opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.accent.opacity(0.25), lineWidth: 1))
    }

    // MARK: Subscription (monthly or yearly): when it renews, and cancelling

    @ViewBuilder
    private var subscription: some View {
        if owned, plus.plan == "monthly" || plus.plan == "yearly" {
            let label = PlusPlan.label(for: plus.plan) ?? ""
            let until = plus.validUntil.flatMap(ISODate.date(from:))?.formatted(date: .abbreviated, time: .omitted)
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Arc TV Plus · \(label)").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.textTertiary)
                    Text(plus.cancelAtPeriodEnd ? "Your subscription won't renew.\(until.map { " You keep Plus until \($0)." } ?? "")" : (until.map { "Renews on \($0)." } ?? "Active."))
                        .font(.system(size: 14)).foregroundStyle(Theme.textPrimary)
                }
                Spacer()
                if !plus.cancelAtPeriodEnd {
                    Button { cancelError = nil; confirmingCancel = true } label: { Label("Cancel subscription", systemImage: "xmark.circle") }.buttonStyle(GlassButtonStyle())
                }
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 14).fill(Theme.elevated))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.divider, lineWidth: 1))
            .alert("Cancel your \(label.lowercased()) subscription?", isPresented: $confirmingCancel) {
                Button("Cancel subscription", role: .destructive) { cancel() }
                Button("Keep Plus", role: .cancel) {}
            } message: {
                Text(until.map { "You keep Arc TV Plus until \($0). After that it won't renew and you won't be charged again." } ?? "You keep Arc TV Plus until the end of the period you've paid for. After that it won't renew and you won't be charged again.")
            }
            if let cancelError { Text(cancelError).font(.system(size: 13)).foregroundStyle(Theme.coralText) }
        }
    }

    private func cancel() {
        cancelling = true
        Task {
            do { try await model.cancelSubscription() } catch let APIError.server(status, message) {
                cancelError = status == 409 ? "Lifetime Plus has no subscription to cancel."
                    : status == 404 ? "We couldn't find a subscription to cancel on this account."
                    : status == 429 ? (message ?? "Too many tries. Try again in a moment.") : "Couldn't cancel your subscription. Try again in a moment."
            } catch {
                cancelError = "Couldn't cancel your subscription. Try again in a moment."
            }
            cancelling = false
        }
    }

    // MARK: How to subscribe

    private var subscribe: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("How to subscribe").font(.system(size: 18, weight: .bold)).foregroundStyle(Theme.textPrimary).padding(.top, 8)
            VStack(alignment: .leading, spacing: 6) {
                Text("1. Pick a plan below: monthly, yearly, or a one-time Lifetime payment.\(plus.trialDays > 0 ? " Yearly starts with \(plus.trialDays) days free." : "")")
                Text("2. Pay on Stripe's secure page, which opens in your browser.")
                Text("3. Come back to this tab: Plus switches on by itself within a minute.")
            }
            .font(.system(size: 13)).foregroundStyle(Theme.textSecondary)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 190), spacing: 14, alignment: .top)], spacing: 16) {
                ForEach(PlusPlan.all) { plan in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(plan.label).font(.system(size: 17, weight: .bold)).foregroundStyle(Theme.textPrimary)
                        Text("Price at checkout").font(.system(size: 20, weight: .heavy)).foregroundStyle(Theme.textPrimary)
                        Text(plan.per).font(.system(size: 12)).foregroundStyle(Theme.textTertiary)
                        Text(plan.blurb).font(.system(size: 13)).foregroundStyle(Theme.textSecondary).fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 4)
                        Button { choose(plan.id) } label: {
                            Text(busy == plan.id ? "Opening…" : buttonText(plan)).frame(maxWidth: .infinity)
                        }
                        .buttonStyle(BrandButtonStyle())
                        .disabled(busy != nil)
                    }
                    .padding(18)
                    .frame(maxWidth: .infinity, minHeight: 190, alignment: .topLeading)
                    .background(RoundedRectangle(cornerRadius: 14).fill(Theme.surface))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(plan.note != nil ? Theme.accent : Color.white.opacity(0.08), lineWidth: 1))
                    .overlay(alignment: .topTrailing) {
                        if let note = noteText(plan) {
                            Text(note).font(.system(size: 12, weight: .bold)).foregroundStyle(Color(hex: 0x07101A)).padding(.horizontal, 10).padding(.vertical, 2)
                                .background(Capsule().fill(Theme.accent)).offset(x: -12, y: -10)
                        }
                    }
                }
            }
            .padding(.top, 8)
            if waiting { Text("Waiting for your payment… this switches on by itself when it goes through.").font(.system(size: 13)).foregroundStyle(Theme.textSecondary) }
            if let error { Text(error).font(.system(size: 13)).foregroundStyle(Theme.coralText) }
            if plus.trialDays > 0 {
                Text("Your card is taken at checkout, but nothing is charged for the first \(plus.trialDays) days. Cancel before then and you pay nothing. The free trial is for the yearly plan, once per account.")
                    .font(.system(size: 12)).foregroundStyle(Theme.textTertiary)
            }
            Text("Payments are handled by Stripe's secure checkout page; we never see your card.").font(.system(size: 12)).foregroundStyle(Theme.textTertiary)
        }
    }

    private func buttonText(_ plan: PlusPlan) -> String {
        plan.id == "lifetime" ? "Get Lifetime" : (plan.id == "yearly" && plus.trialDays > 0 ? "Start \(plus.trialDays)-day free trial" : "Choose \(plan.label)")
    }

    private func noteText(_ plan: PlusPlan) -> String? {
        plan.id == "yearly" && plus.trialDays > 0 ? "\(plus.trialDays) days free" : plan.note
    }

    private func choose(_ plan: String) {
        busy = plan
        error = nil
        Task {
            do {
                try await model.startCheckout(plan)
                waiting = true
            } catch let APIError.server(status, _) {
                error = status == 409 ? "You already have Plus for life." : status == 503 ? "Plus checkout isn't available yet." : "Couldn't start checkout. Try again in a moment."
            } catch {
                self.error = "Couldn't start checkout. Try again in a moment."
            }
            busy = nil
        }
    }
}

// MARK: Settings > Plus settings

struct PlusSettingsPane: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        if !model.plus.active {
            PlusLockedNote(title: "Plus settings are only for Arc TV Plus.", detail: "Switch Smart source picking and your other Plus features on and off here.")
        } else {
            card {
                Toggle(isOn: $model.smartPicking) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Smart source picking").font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.textPrimary)
                        Text("Skip the source list and start the best source this Mac can play. If none surely plays, you still get the list.")
                            .font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
                    }
                }
                .toggleStyle(.switch)
                .tint(Theme.accent)
            }
        }
    }
}

// MARK: Settings > Your stats

struct StatsPane: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Group {
            if !model.plus.active {
                PlusLockedNote(title: "Your stats are only for Arc TV Plus.", detail: "See how much you watch, how this week compares, your streak, a map of your last 13 weeks and your busiest day.")
            } else if let stats = model.stats {
                StatsBody(stats: stats, truncated: model.statsTruncated)
            } else if model.statsFailed {
                Text("Couldn't read your watch history right now. Try again in a moment.").font(.system(size: 13)).foregroundStyle(Theme.textSecondary)
            } else {
                StatsSkeleton()
            }
        }
        .task { if model.plus.active { await model.loadStats() } }
    }
}

private struct StatsBody: View {
    let stats: WatchStats
    let truncated: Bool

    var body: some View {
        if stats.isEmpty {
            Text("Nothing here yet. Watch something and your stats will appear.").font(.system(size: 13)).foregroundStyle(Theme.textSecondary)
        } else {
            VStack(alignment: .leading, spacing: 16) {
                hero
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 10, alignment: .top)], spacing: 10) {
                    tile("calendar", "Last 7 days", WatchStats.duration(stats.last7DaysMs))
                    tile("calendar.badge.clock", "Last 30 days", WatchStats.duration(stats.last30DaysMs))
                    tile("flame.fill", "Day streak", plural(stats.streakDays, "day"),
                         note: stats.longestStreakDays > stats.streakDays ? "best \(stats.longestStreakDays)" : (stats.streakDays > 0 && stats.streakDays == stats.longestStreakDays ? "your best" : nil), hot: stats.streakDays >= 3)
                    tile("timer", "Per day you watch", WatchStats.duration(stats.avgPerActiveDayMs), note: "\(plural(stats.activeDays, "day")) in all")
                    tile("film", "Movies finished", String(stats.moviesFinished))
                    tile("tv", "Episodes watched", String(stats.episodesWatched), note: stats.showsWatched > 0 ? "across \(plural(stats.showsWatched, "show"))" : nil)
                }
                split
                heat
                weekdays
                Text("Counted from your watch history\(truncated ? " (the most recent part of it)" : ""). A title you watch again counts once, on the day you last watched it.")
                    .font(.system(size: 12)).foregroundStyle(Theme.textTertiary)
            }
        }
    }

    private func plural(_ n: Int, _ word: String) -> String { "\(n) \(word)\(n == 1 ? "" : "s")" }

    private var hero: some View {
        let change = WatchStats.weekChange(last7: stats.last7DaysMs, prev7: stats.prev7DaysMs)
        return VStack(alignment: .leading, spacing: 6) {
            Text("You've watched").font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.textTertiary)
            Text(WatchStats.duration(stats.totalMs)).font(.system(size: 44, weight: .heavy)).foregroundStyle(Theme.brandGradient)
            HStack(spacing: 12) {
                if let first = stats.firstWatchedAt {
                    Text("since \(first.formatted(.dateTime.month(.wide).year()))").font(.system(size: 13)).foregroundStyle(Theme.textSecondary)
                }
                if let change {
                    let text = change.direction == "same" ? "Same as last week" : "\(change.percent)% \(change.direction == "up" ? "more" : "less") than last week"
                    Text(text)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(change.direction == "up" ? Theme.cyan : (change.direction == "down" ? Color(hex: 0xFFB86B) : Theme.textSecondary))
                        .padding(.horizontal, 10).padding(.vertical, 3)
                        .background(Capsule().fill(Theme.surfaceHigh))
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(Theme.elevated))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.blue.opacity(0.35), lineWidth: 1))
    }

    private func tile(_ icon: String, _ label: String, _ value: String, note: String? = nil, hot: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: icon).foregroundStyle(hot ? Color(hex: 0xFF9F43) : Theme.accent)
                Text(label).foregroundStyle(Theme.textTertiary)
            }
            .font(.system(size: 12))
            Text(value).font(.system(size: 19, weight: .bold)).foregroundStyle(Theme.textPrimary)
            if let note { Text(note).font(.system(size: 12)).foregroundStyle(Theme.textTertiary) }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.surface))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(hot ? Color(hex: 0xFF9F43).opacity(0.55) : .clear, lineWidth: 1))
    }

    @ViewBuilder
    private var split: some View {
        let total = stats.movieMs + stats.showMs
        if total > 0 {
            let moviePercent = Int((Double(stats.movieMs) / Double(total) * 100).rounded())
            VStack(alignment: .leading, spacing: 8) {
                Text("Movies or shows").font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.textPrimary)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Theme.violet)
                        Capsule().fill(Theme.cyan).frame(width: geo.size.width * CGFloat(moviePercent) / 100)
                    }
                }
                .frame(height: 10)
                HStack {
                    legend(Theme.cyan, "Movies \(WatchStats.duration(stats.movieMs)) · \(moviePercent)%")
                    Spacer()
                    legend(Theme.violet, "Shows \(WatchStats.duration(stats.showMs)) · \(100 - moviePercent)%")
                }
            }
        }
    }

    private func legend(_ color: Color, _ text: String) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 9, height: 9)
            Text(text).font(.system(size: 13)).foregroundStyle(Theme.textSecondary)
        }
    }

    private var heat: some View {
        let cells = WatchStats.heatCells(stats.dailyMs)
        return VStack(alignment: .leading, spacing: 8) {
            Text("Last 13 weeks").font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.textPrimary)
            HStack(alignment: .top, spacing: 8) {
                VStack(spacing: 4) {
                    ForEach(0..<7, id: \.self) { row in
                        Text(["Mon", "", "Wed", "", "Fri", "", "Sun"][row]).font(.system(size: 10)).foregroundStyle(Theme.textTertiary).frame(height: 18, alignment: .center)
                    }
                }
                // Column by column (a week each), Monday first.
                HStack(spacing: 4) {
                    ForEach(0..<((cells.count + 6) / 7), id: \.self) { week in
                        VStack(spacing: 4) {
                            ForEach(0..<7, id: \.self) { day in
                                let index = week * 7 + day
                                if index < cells.count, let cell = cells[safe: index] {
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(cell.ms == nil ? .clear : color(level: cell.level))
                                        .frame(width: 18, height: 18)
                                        .help(cell.ms.map { "\(cell.label): \($0 > 0 ? WatchStats.duration($0) : "nothing watched")" } ?? "")
                                } else {
                                    Color.clear.frame(width: 18, height: 18)
                                }
                            }
                        }
                    }
                }
            }
            HStack(spacing: 4) {
                Spacer()
                Text("Less").font(.system(size: 11)).foregroundStyle(Theme.textTertiary)
                ForEach(0..<5, id: \.self) { level in RoundedRectangle(cornerRadius: 3).fill(color(level: level)).frame(width: 12, height: 12) }
                Text("More").font(.system(size: 11)).foregroundStyle(Theme.textTertiary)
            }
        }
    }

    private func color(level: Int) -> Color {
        switch level {
        case 0: return Theme.surfaceHigh
        case 1: return Theme.cyan.opacity(0.28)
        case 2: return Theme.cyan.opacity(0.52)
        default: return Theme.cyan
        }
    }

    private var weekdays: some View {
        let peak = max(stats.byWeekdayMs.max() ?? 1, 1)
        return VStack(alignment: .leading, spacing: 10) {
            Text("Busiest day\(stats.busiestWeekday.map { ": \(WatchStats.weekdays[$0])" } ?? "")").font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.textPrimary)
            HStack(alignment: .bottom, spacing: 8) {
                ForEach(0..<7, id: \.self) { index in
                    VStack(spacing: 4) {
                        Text(WatchStats.short(stats.byWeekdayMs[index])).font(.system(size: 11, weight: index == stats.busiestWeekday ? .bold : .regular)).foregroundStyle(Theme.cyan).frame(height: 14)
                        ZStack(alignment: .bottom) {
                            Color.clear.frame(height: 100)
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Theme.brandGradient)
                                .opacity(0.85)
                                .frame(width: 34, height: max(4, 100 * CGFloat(stats.byWeekdayMs[index]) / CGFloat(peak)))
                        }
                        Text(String(WatchStats.weekdays[index].prefix(3))).font(.system(size: 11)).foregroundStyle(Theme.textSecondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}

// MARK: The Plus popups

/// "Everything in Arc TV Plus" (members, once ever) or the invitation (everyone else, once Plus is paid).
struct PlusPopupView: View {
    @EnvironmentObject private var model: AppModel
    let popup: AppModel.PlusPopup

    private struct Benefit: Identifiable {
        var icon: String
        var title: String
        var detail: String
        var id: String { title }
    }

    private var title: String {
        switch popup {
        case .welcome: return "Everything in Arc TV Plus."
        case .download: return "Downloads come with Arc TV Plus."
        case .invitation: return "Get more from every movie night."
        }
    }
    private var subtitle: String {
        switch popup {
        case .welcome: return "Here is what your Plus membership gives you."
        case .download: return "Save movies and episodes to your Mac. Everything you use today stays free."
        case .invitation: return "Everything you use today stays free. Arc TV Plus adds extras on top."
        }
    }
    private var goLabel: String { popup == .welcome ? "See my Plus settings" : "Take me there" }
    private var hint: String { popup == .welcome ? "Parental controls are on the way" : "Explore plans in Settings > Arc TV Plus" }

    private var benefits: [Benefit] {
        if popup == .welcome {
            return [
                Benefit(icon: "heart.fill", title: "Picked for you", detail: "A Home row chosen from the movies and shows you like, with the reason under each poster. Tune it in Settings > Recommendations."),
                Benefit(icon: "person.2.fill", title: "Up to 5 profiles", detail: "Their own My List, Continue Watching and recommendations. Add kids profiles and PIN locks."),
                Benefit(icon: "bolt.fill", title: "Smart source picking", detail: "Skips the source list and starts the best source your Mac can play."),
                Benefit(icon: "chart.bar.fill", title: "Your stats", detail: "How much you watch, your streak and a map of your last 13 weeks."),
                Benefit(icon: "arrow.down.circle.fill", title: "Downloads (web and Mac)", detail: "Save movies and episodes to your Mac from the Download button on a title's page.")
            ]
        }
        let picked = Benefit(icon: "heart.fill", title: "Picked for you", detail: "A Home row chosen from the movies and shows you like, with the reason under each poster.")
        let profiles = Benefit(icon: "person.2.fill", title: "Up to 5 profiles", detail: "Their own My List, Continue Watching and recommendations. Add kids profiles and PIN locks.")
        let downloads = Benefit(icon: "arrow.down.circle.fill", title: "Downloads on the web and Mac", detail: "Save movies and episodes to your Mac, best quality at the smallest size first.")
        let more = Benefit(icon: "rosette", title: "And more", detail: "Smart source picking and your watch stats, with parental controls on the way.")
        // From a Download button the list leads with Downloads.
        return popup == .download ? [downloads, picked, profiles, more] : [picked, profiles, downloads, more]
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.65).ignoresSafeArea().onTapGesture { model.closePlusPopup() }
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 8) {
                    LogoView(height: 26)
                    Text("PLUS").font(.system(size: 12, weight: .heavy)).tracking(1.5).foregroundStyle(Theme.cyan)
                    Spacer()
                    Button { model.closePlusPopup() } label: {
                        Image(systemName: "xmark").font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.textPrimary).frame(width: 32, height: 32).background(Circle().fill(Color.white.opacity(0.12)))
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.cancelAction)
                }
                Text(title).font(.system(size: 28, weight: .heavy)).foregroundStyle(Theme.textPrimary)
                Text(subtitle).font(.system(size: 15)).foregroundStyle(Theme.textSecondary)
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(benefits) { benefit in
                        HStack(alignment: .top, spacing: 14) {
                            Image(systemName: benefit.icon).font(.system(size: 16)).foregroundStyle(Theme.cyan)
                                .frame(width: 38, height: 38).background(Circle().fill(Theme.cyan.opacity(0.12)))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(benefit.title).font(.system(size: 15, weight: .bold)).foregroundStyle(Theme.textPrimary)
                                Text(benefit.detail).font(.system(size: 13)).foregroundStyle(Theme.textSecondary).fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
                HStack(spacing: 12) {
                    Button { model.closePlusPopup(openSettings: popup == .welcome ? .plusSettings : .plus) } label: {
                        HStack { Text(goLabel); Image(systemName: "arrow.right") }.frame(maxWidth: .infinity)
                    }
                    .buttonStyle(BrandButtonStyle())
                    Button("Close") { model.closePlusPopup() }.buttonStyle(GlassButtonStyle())
                }
                .padding(.top, 6)
                Text(hint).font(.system(size: 12)).foregroundStyle(Theme.textTertiary).frame(maxWidth: .infinity)
                if popup == .invitation {
                    Button("Don't show me again") { model.dismissInvitationForever() }
                        .buttonStyle(.plain)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textTertiary)
                        .underline()
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(28)
            .frame(width: 520)
            .background(RoundedRectangle(cornerRadius: 24).fill(Theme.elevated))
            .overlay(RoundedRectangle(cornerRadius: 24).stroke(Theme.divider, lineWidth: 1))
            .overlay(alignment: .top) { Capsule().fill(Theme.brandGradient).frame(width: 80, height: 3).padding(.top, 10) }
            .shadow(color: .black.opacity(0.6), radius: 40, y: 20)
        }
    }
}
