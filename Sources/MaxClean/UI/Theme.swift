import SwiftUI
import AppKit

enum Theme {
    static let bgTop = Color(red: 0.20, green: 0.08, blue: 0.36)
    static let bgMid = Color(red: 0.11, green: 0.05, blue: 0.24)
    static let bgBottom = Color(red: 0.05, green: 0.03, blue: 0.12)
    static let sidebar = Color(red: 0.10, green: 0.06, blue: 0.17)
    static let accent = Color(red: 0.69, green: 0.42, blue: 1.0)
    static let accent2 = Color(red: 0.98, green: 0.38, blue: 0.82)
    static let green = Color(red: 0.32, green: 0.90, blue: 0.62)
    static let orange = Color(red: 1.0, green: 0.66, blue: 0.30)
    static let red = Color(red: 1.0, green: 0.38, blue: 0.42)
    static let card = Color.white.opacity(0.06)
    static let cardHover = Color.white.opacity(0.10)
    static let stroke = Color.white.opacity(0.10)

    static var background: some View {
        ZStack {
            LinearGradient(colors: [bgTop, bgMid, bgBottom], startPoint: .topLeading, endPoint: .bottomTrailing)
            RadialGradient(colors: [accent.opacity(0.25), .clear], center: .topTrailing, startRadius: 10, endRadius: 600)
            RadialGradient(colors: [accent2.opacity(0.12), .clear], center: .bottomLeading, startRadius: 10, endRadius: 500)
        }
    }

    static var accentGradient: LinearGradient {
        LinearGradient(colors: [accent, accent2], startPoint: .leading, endPoint: .trailing)
    }
}

struct Card<Content: View>: View {
    let content: Content
    var padding: CGFloat = 16
    init(padding: CGFloat = 16, @ViewBuilder _ content: () -> Content) {
        self.padding = padding
        self.content = content()
    }
    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.card))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Theme.stroke, lineWidth: 1))
    }
}

struct GlowButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .foregroundColor(.white)
            .padding(.horizontal, 22)
            .padding(.vertical, 10)
            .background(Capsule().fill(Theme.accentGradient))
            .shadow(color: Theme.accent.opacity(enabled ? 0.55 : 0), radius: configuration.isPressed ? 4 : 14)
            .opacity(enabled ? 1 : 0.4)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct GhostButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundColor(.white.opacity(0.92))
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(Capsule().fill(Color.white.opacity(configuration.isPressed ? 0.18 : 0.08)))
            .overlay(Capsule().stroke(Theme.stroke, lineWidth: 1))
    }
}

struct PageHeader<Trailing: View>: View {
    let icon: String
    let title: String
    let subtitle: String
    let trailing: Trailing

    init(icon: String, title: String, subtitle: String, @ViewBuilder trailing: () -> Trailing) {
        self.icon = icon; self.title = title; self.subtitle = subtitle; self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.accentGradient).frame(width: 46, height: 46)
                Image(systemName: icon).font(.system(size: 20, weight: .semibold)).foregroundColor(.white)
            }
            .shadow(color: Theme.accent.opacity(0.5), radius: 10)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 24, weight: .bold, design: .rounded))
                Text(subtitle).font(.system(size: 13)).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer()
            trailing
        }
        .padding(.bottom, 6)
    }
}

extension PageHeader where Trailing == EmptyView {
    init(icon: String, title: String, subtitle: String) {
        self.init(icon: icon, title: title, subtitle: subtitle) { EmptyView() }
    }
}

struct Ring: View {
    var progress: Double
    var title: String
    var value: String
    var size: CGFloat = 140
    var lineWidth: CGFloat = 12
    var warn: Bool = false

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle().stroke(Color.white.opacity(0.08), lineWidth: lineWidth)
                Circle()
                    .trim(from: 0, to: max(0.001, min(progress, 1)))
                    .stroke(warn
                            ? AngularGradient(colors: [Theme.orange, Theme.red, Theme.orange], center: .center)
                            : AngularGradient(colors: [Theme.accent, Theme.accent2, Theme.accent], center: .center),
                            style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.6), value: progress)
                VStack(spacing: 2) {
                    Text(value).font(.system(size: size * 0.13, weight: .bold, design: .rounded))
                        .lineLimit(1).minimumScaleFactor(0.6)
                    Text("\(Int((progress * 100).rounded()))%").font(.caption).foregroundStyle(.secondary)
                }
                .padding(.horizontal, lineWidth + 6)
            }
            .frame(width: size, height: size)
            Text(title).font(.subheadline).foregroundStyle(.secondary)
        }
    }
}

/// CleanMyMac uslubidagi katta dumaloq tugma.
struct BigScanButton: View {
    let title: String
    let busy: Bool
    let action: () -> Void
    @State private var pulse = false
    @State private var hover = false
    @State private var spin = false

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .trim(from: 0, to: 0.75)
                    .stroke(AngularGradient(colors: [.clear, Theme.accent, Theme.accent2], center: .center),
                            style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .frame(width: 188, height: 188)
                    .rotationEffect(.degrees(spin ? 360 : 0))
                Circle()
                    .stroke(Theme.accentGradient, lineWidth: 2)
                    .frame(width: 196, height: 196)
                    .scaleEffect(pulse ? 1.10 : 0.96)
                    .opacity(pulse ? 0 : 0.6)
                Circle()
                    .stroke(Color.white.opacity(0.18), lineWidth: 2)
                    .frame(width: 176, height: 176)
                Circle()
                    .fill(Theme.accentGradient)
                    .frame(width: 152, height: 152)
                    .overlay(Circle().fill(LinearGradient(colors: [.white.opacity(0.35), .clear],
                                                          startPoint: .top, endPoint: .center)).padding(6))
                    .shadow(color: Theme.accent.opacity(hover ? 0.9 : 0.6), radius: hover ? 36 : 22)
                if busy {
                    ProgressView().controlSize(.large).tint(.white)
                } else {
                    Text(title).font(.system(size: 21, weight: .bold, design: .rounded)).foregroundColor(.white)
                }
            }
            .scaleEffect(hover ? 1.03 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: hover)
        }
        .buttonStyle(.plain)
        .disabled(busy)
        .onHover { h in
            hover = h
            // Halqa va "puls" faqat sichqoncha ustida turganda aylanadi — bo'sh turganda CPU 0%
            if h {
                withAnimation(.easeOut(duration: 1.8).repeatForever(autoreverses: false)) { pulse = true }
                withAnimation(.linear(duration: 6).repeatForever(autoreverses: false)) { spin = true }
            } else {
                var t = Transaction()
                t.disablesAnimations = true
                withTransaction(t) { spin = false }
                withAnimation(.easeOut(duration: 0.4)) { pulse = false }
            }
        }
    }
}

/// Skanerlash jarayoni — foizli halqa.
struct ScanProgressRing: View {
    let progress: Double
    @State private var spin = false
    var body: some View {
        ZStack {
            Circle().stroke(Color.white.opacity(0.08), lineWidth: 10)
            Circle()
                .trim(from: 0, to: max(0.02, progress))
                .stroke(Theme.accentGradient, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.3), value: progress)
            Circle()
                .trim(from: 0, to: 0.12)
                .stroke(Color.white.opacity(0.5), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .frame(width: 196, height: 196)
                .rotationEffect(.degrees(spin ? 360 : 0))
            Text("\(Int(progress * 100))%")
                .font(.system(size: 34, weight: .bold, design: .rounded))
        }
        .frame(width: 170, height: 170)
        .onAppear { withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) { spin = true } }
    }
}

struct SizeBar: View {
    let fraction: Double
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.07))
                Capsule().fill(Theme.accentGradient).frame(width: max(4, g.size.width * min(max(fraction, 0), 1)))
            }
        }
        .frame(height: 6)
    }
}

struct EmptyState: View {
    let icon: String
    let text: String
    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle().fill(Theme.accent.opacity(0.12)).frame(width: 96, height: 96)
                Image(systemName: icon).font(.system(size: 40)).foregroundStyle(Theme.accentGradient)
            }
            Text(text).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }
}

/// Fayl qatori: belgi, nom, yo'l, hajm, "Finder'da ko'rsatish".
struct FileRow: View {
    let entry: FileEntry
    let toggle: () -> Void
    var showDate = true
    @State private var hover = false

    var body: some View {
        HStack(spacing: 10) {
            Toggle("", isOn: Binding(get: { entry.selected }, set: { _ in toggle() }))
                .toggleStyle(.checkbox).labelsHidden()
            Image(nsImage: IconCache.icon(entry.url.path))
                .resizable().frame(width: 22, height: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.name).lineLimit(1).truncationMode(.middle)
                Text(entry.note ?? entry.url.deletingLastPathComponent().path)
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }
            Spacer()
            if let hint = entry.hint {
                Label(hint, systemImage: "lightbulb")
                    .font(.caption2)
                    .lineLimit(1)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Capsule().fill(Theme.accent.opacity(0.15)))
                    .foregroundColor(Theme.accent)
                    .help(hint)
            }
            if showDate, entry.modified != nil {
                Text(Format.relative(entry.modified)).font(.caption).foregroundStyle(.secondary)
            }
            Text(Format.bytes(entry.size)).font(.system(.body, design: .rounded).weight(.medium))
                .monospacedDigit().frame(width: 90, alignment: .trailing)
            Button { QuickLook.preview(entry.url) } label: { Image(systemName: "eye") }
                .buttonStyle(.borderless)
                .opacity(hover ? 1 : 0.35)
                .help(T("Ko'rib chiqish (Quick Look)", "Preview (Quick Look)", "Просмотр (Quick Look)"))
            Button { FS.reveal(entry.url) } label: { Image(systemName: "magnifyingglass") }
                .buttonStyle(.borderless)
                .opacity(hover ? 1 : 0.35)
                .help(T("Finder'da ko'rsatish", "Show in Finder", "Показать в Finder"))
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .background(RoundedRectangle(cornerRadius: 8).fill(hover ? Color.white.opacity(0.05) : .clear))
        .onHover { hover = $0 }
    }
}

/// Belgilar keshi — NSWorkspace.icon har safar diskka murojaat qilmasligi uchun.
enum IconCache {
    private static let cache = NSCache<NSString, NSImage>()
    static func icon(_ path: String) -> NSImage {
        if let i = cache.object(forKey: path as NSString) { return i }
        let i = NSWorkspace.shared.icon(forFile: path)
        i.size = NSSize(width: 32, height: 32)
        cache.setObject(i, forKey: path as NSString)
        return i
    }
}

struct BottomBar<Content: View>: View {
    let content: Content
    init(@ViewBuilder _ content: () -> Content) { self.content = content() }
    var body: some View {
        HStack { content }
            .padding(.horizontal, 18).padding(.vertical, 12)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Theme.stroke, lineWidth: 1))
            .shadow(color: .black.opacity(0.3), radius: 16, y: 6)
    }
}

/// Hover'da ko'tariladigan karta-tugma (bosh sahifa plitkalari).
struct HoverTile<Content: View>: View {
    let action: () -> Void
    let content: Content
    @State private var hover = false
    init(action: @escaping () -> Void, @ViewBuilder _ content: () -> Content) {
        self.action = action; self.content = content()
    }
    var body: some View {
        Button(action: action) {
            content
                .frame(maxWidth: .infinity, minHeight: 80)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(hover ? Theme.cardHover : Theme.card))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(hover ? Theme.accent.opacity(0.6) : Theme.stroke, lineWidth: 1))
                .scaleEffect(hover ? 1.02 : 1)
                .animation(.easeOut(duration: 0.15), value: hover)
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}


// MARK: - Animatsiyalar

/// Sekin suzib yuradigan rangli "nur" fon (CleanMyMac uslubida). Blur bir marta chiziladi,
/// faqat siljish animatsiya qilinadi — GPU uchun yengil.
struct AnimatedBackground: View {
    var compact = false
    @State private var move = false
    @AppStorage("animatedBackground") private var animated = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private func glow(_ c: Color, _ d: CGFloat) -> some View {
        let k: CGFloat = compact ? 0.5 : 1
        return Circle()
            .fill(RadialGradient(colors: [c, c.opacity(0)], center: .center, startRadius: 0, endRadius: d * k / 2))
            .frame(width: d * k, height: d * k)
    }

    var body: some View {
        let k: CGFloat = compact ? 0.5 : 1
        let o1 = CGSize(width: (move ? 170 : 300) * k, height: (move ? -200 : -60) * k)
        let o2 = CGSize(width: (move ? -260 : -110) * k, height: (move ? 240 : 110) * k)
        let o3 = CGSize(width: (move ? 60 : -90) * k, height: (move ? 80 : 220) * k)
        return ZStack {
            LinearGradient(colors: [Theme.bgTop, Theme.bgMid, Theme.bgBottom], startPoint: .topLeading, endPoint: .bottomTrailing)
            // Blur o'rniga radial gradient — ko'rinishi bir xil, chizish deyarli bepul
            glow(Theme.accent.opacity(0.38), 760).offset(o1)
            glow(Theme.accent2.opacity(0.24), 680).offset(o2)
            glow(Color(red: 0.30, green: 0.42, blue: 1.0).opacity(0.15), 560).offset(o3)
        }
        .clipped()
        .ignoresSafeArea()
        .onAppear { updateMotion() }
        .onChange(of: animated) { _ in updateMotion() }
    }

    private func updateMotion() {
        // To'xtovsiz animatsiya faqat sozlamada yoqilsa (standart: o'chiq — CPU tejaladi)
        if animated && !reduceMotion {
            withAnimation(.easeInOut(duration: 14).repeatForever(autoreverses: true)) { move = true }
        } else {
            withAnimation(.easeInOut(duration: 0.6)) { move = false }
        }
    }
}

/// Paydo bo'lish: pastdan yengil ko'tarilib, ko'rinadi.
struct FadeIn: ViewModifier {
    let delay: Double
    @State private var shown = false
    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 14)
            .scaleEffect(shown ? 1 : 0.98)
            .onAppear {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.85).delay(delay)) { shown = true }
            }
    }
}

extension View {
    func fadeIn(_ delay: Double = 0) -> some View { modifier(FadeIn(delay: delay)) }

    /// Raqamlar o'zgarganda silliq aylanish (macOS 14+).
    @ViewBuilder func numericTransition() -> some View {
        if #available(macOS 14.0, *) {
            self.contentTransition(.numericText())
        } else {
            self
        }
    }
}

/// Tozalashdan keyingi "muvaffaqiyat" portlashi.
struct SuccessBurst: View {
    @State private var go = false
    var body: some View {
        ZStack {
            ForEach(0..<16, id: \.self) { i in
                Circle()
                    .fill(i % 2 == 0 ? Theme.accent : Theme.accent2)
                    .frame(width: i % 3 == 0 ? 10 : 7, height: i % 3 == 0 ? 10 : 7)
                    .offset(y: go ? -(100 + CGFloat(i % 4) * 14) : 0)
                    .rotationEffect(.degrees(Double(i) / 16 * 360))
                    .opacity(go ? 0 : 1)
            }
            Circle().fill(Theme.green.opacity(0.16)).frame(width: 152, height: 152)
                .scaleEffect(go ? 1 : 0.3)
            Circle().stroke(Theme.green.opacity(0.6), lineWidth: 3).frame(width: 152, height: 152)
                .scaleEffect(go ? 1 : 0.3)
            Image(systemName: "checkmark")
                .font(.system(size: 60, weight: .bold))
                .foregroundColor(Theme.green)
                .scaleEffect(go ? 1 : 0.2)
                .rotationEffect(.degrees(go ? 0 : -30))
        }
        .frame(width: 200, height: 200)
        .onAppear {
            withAnimation(.spring(response: 0.7, dampingFraction: 0.55)) { go = true }
        }
    }
}


/// Quick Look oynasida ko'rsatish (o'chirishdan oldin faylni ko'rib olish uchun).
enum QuickLook {
    static func preview(_ url: URL) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/qlmanage")
        p.arguments = ["-p", url.path]
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try? p.run()
    }
}
