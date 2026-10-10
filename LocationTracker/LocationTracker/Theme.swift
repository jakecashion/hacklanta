import SwiftUI

// Neobrutalism theme. Source of truth: DESIGN.md at the repo root.
// White page, white surfaces, 2 pt ink borders, hard offset shadows (no blur), pastel accents.

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }

    // Rubik's brand colours, read from rubiks.com (CSS tokens --_color---primary--*).
    static let page = Color.white                   // cube white: page background
    static let surface = Color.white                // cards
    static let ink = Color(hex: 0x010101)           // cube body black: borders, shadows, text
    static let inkSecondary = Color(hex: 0x555555)
    static let cubeRed = Color(hex: 0xEC2236)       // primary / CTA
    static let cubeBlue = Color(hex: 0x28B1E6)      // secondary
    static let cubeGreen = Color(hex: 0x52B44D)
    static let cubeYellow = Color(hex: 0xFCE000)    // tags, stars
    static let cubeOrange = Color(hex: 0xF28820)
    static let lightBlue = Color(hex: 0xB9E5FB)     // soft fills, placeholders
}

enum Brut {
    static let border: CGFloat = 2
    static let radius: CGFloat = 10
    static let radiusLarge: CGFloat = 14
    static let radiusInput: CGFloat = 6
    static let shadowSmall: CGFloat = 3
    static let shadowMedium: CGFloat = 4
    static let shadowLarge: CGFloat = 6
}

// MARK: - Surfaces

private struct BrutSurface: ViewModifier {
    var fill: Color
    var radius: CGFloat
    var shadow: CGFloat
    var borderColor: Color

    func body(content: Content) -> some View {
        content
            .background(RoundedRectangle(cornerRadius: radius).fill(fill))
            .overlay(RoundedRectangle(cornerRadius: radius).stroke(borderColor, lineWidth: Brut.border))
            .background(
                RoundedRectangle(cornerRadius: radius)
                    .fill(Color.ink)
                    .offset(x: shadow, y: shadow)
                    .opacity(shadow > 0 ? 1 : 0)
            )
    }
}

extension View {
    /// Card with a 2 pt border and a hard offset shadow. Use `shadow: 0` for a flat card.
    func brutCard(fill: Color = .surface, radius: CGFloat = Brut.radius,
                  shadow: CGFloat = Brut.shadowMedium, border: Color = .ink) -> some View {
        modifier(BrutSurface(fill: fill, radius: radius, shadow: shadow, borderColor: border))
    }

    /// Text field look: white, 6 pt radius, small shadow. Focus turns border and shadow coral.
    func brutInput(focused: Bool = false) -> some View {
        self
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: Brut.radiusInput).fill(Color.surface))
            .overlay(RoundedRectangle(cornerRadius: Brut.radiusInput)
                .stroke(focused ? Color.cubeRed : Color.ink, lineWidth: Brut.border))
            .background(
                RoundedRectangle(cornerRadius: Brut.radiusInput)
                    .fill(focused ? Color.cubeRed : Color.ink)
                    .offset(x: Brut.shadowSmall, y: Brut.shadowSmall)
            )
            .offset(x: focused ? -1 : 0, y: focused ? -1 : 0)
            .animation(.easeOut(duration: 0.12), value: focused)
    }

    /// Fonts, tint and colour scheme for a root screen, sheet or cover.
    func brutScreen() -> some View {
        self
            .fontDesign(.rounded)
            .tint(Color.ink)
            .foregroundStyle(Color.ink)
            .preferredColorScheme(.light)
    }

    /// Page background that fills the safe area.
    func pageBackground() -> some View {
        background(Color.page.ignoresSafeArea())
    }
}

// MARK: - Buttons

/// Press-down button: the face slides onto its shadow.
struct BrutButtonStyle: ButtonStyle {
    var fill: Color = .cubeRed
    var textColor: Color = .white
    var pill = false
    var fullWidth = true
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        let shadow = pressed ? 0 : Brut.shadowMedium
        let shift = pressed ? Brut.shadowMedium : 0
        let shape = pill ? AnyShape(Capsule()) : AnyShape(RoundedRectangle(cornerRadius: Brut.radius))
        configuration.label
            .font(.body.weight(.bold))
            .foregroundStyle(textColor)
            .padding(.horizontal, 20)
            .frame(maxWidth: fullWidth ? .infinity : nil, minHeight: 52)
            .background(shape.fill(fill))
            .overlay(shape.stroke(Color.ink, lineWidth: Brut.border))
            .background(shape.fill(Color.ink).offset(x: Brut.shadowMedium, y: Brut.shadowMedium).opacity(shadow > 0 ? 1 : 0))
            .offset(x: shift, y: shift)
            .opacity(isEnabled ? 1 : 0.4)
            .animation(.easeOut(duration: 0.08), value: pressed)
    }
}

extension ButtonStyle where Self == BrutButtonStyle {
    static var brutPrimary: BrutButtonStyle { BrutButtonStyle() }
    static var brutSecondary: BrutButtonStyle { BrutButtonStyle(fill: .cubeBlue, textColor: .ink) }
    static var brutGhost: BrutButtonStyle { BrutButtonStyle(fill: .surface, textColor: .ink) }
    static var brutPill: BrutButtonStyle { BrutButtonStyle(fill: .cubeRed, pill: true) }
}

/// Plain text button with an underline-free look, for "not now" and "cancel".
struct BrutLinkStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Color.inkSecondary)
            .padding(.vertical, 8)
            .opacity(configuration.isPressed ? 0.5 : 1)
    }
}

// MARK: - Small components

/// Outlined or filled pill tag.
struct GenreChip: View {
    let text: String
    var fill: Color = .cubeYellow

    var body: some View {
        Text(text)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(Color.ink)
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(Capsule().fill(fill))
            .overlay(Capsule().stroke(Color.ink, lineWidth: Brut.border))
    }
}

/// Line icon in a pastel circle with a small hard shadow.
struct IconBox: View {
    let systemName: String
    var fill: Color = .cubeGreen
    var size: CGFloat = 48

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: size * 0.42, weight: .semibold))
            .foregroundStyle(Color.ink)
            .frame(width: size, height: size)
            .background(Circle().fill(fill))
            .overlay(Circle().stroke(Color.ink, lineWidth: Brut.border))
            .background(Circle().fill(Color.ink).offset(x: Brut.shadowSmall, y: Brut.shadowSmall))
    }
}

struct CoverArt: View {
    let url: URL?
    var size: CGFloat = 72

    var body: some View {
        let radius = max(Brut.radius, size / 8)
        AsyncImage(url: url) { image in
            image.resizable().scaledToFill()
        } placeholder: {
            ZStack {
                Color.lightBlue
                Image(systemName: "music.note").foregroundStyle(Color.ink)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: radius))
        .overlay(RoundedRectangle(cornerRadius: radius).stroke(Color.ink, lineWidth: Brut.border))
    }
}

struct EqualizerView: View {
    private let barCount = 4
    var color: Color = .ink

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.15)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(alignment: .bottom, spacing: 3) {
                ForEach(0..<barCount, id: \.self) { i in
                    let h = 6 + 14 * abs(sin(t * 3 + Double(i) * 1.3))
                    Capsule()
                        .fill(color)
                        .frame(width: 4, height: h)
                }
            }
            .frame(height: 20, alignment: .bottom)
        }
    }
}

// MARK: - Decoration

struct FourPointStar: Shape {
    func path(in rect: CGRect) -> Path {
        // Same shape as the 32 x 32 SVG star in the design skill.
        let pts: [(CGFloat, CGFloat)] = [
            (16, 2), (17.5, 14.5), (30, 16), (17.5, 17.5),
            (16, 30), (14.5, 17.5), (2, 16), (14.5, 14.5),
        ]
        var p = Path()
        for (i, pt) in pts.enumerated() {
            let point = CGPoint(x: rect.minX + pt.0 / 32 * rect.width, y: rect.minY + pt.1 / 32 * rect.height)
            i == 0 ? p.move(to: point) : p.addLine(to: point)
        }
        p.closeSubpath()
        return p
    }
}

struct DecorStar: View {
    var color: Color = .cubeYellow
    var size: CGFloat = 28
    var rotation: Double = 0

    var body: some View {
        FourPointStar()
            .fill(color)
            .overlay(FourPointStar().stroke(Color.ink, lineWidth: 1.5))
            .frame(width: size, height: size)
            .rotationEffect(.degrees(rotation))
            .accessibilityHidden(true)
    }
}

struct DecorBlob: View {
    var color: Color = .cubeOrange
    var size: CGFloat = 56

    var body: some View {
        Ellipse()
            .fill(color)
            .frame(width: size, height: size * 0.86)
            .rotationEffect(.degrees(-12))
            .accessibilityHidden(true)
    }
}

extension Font {
    /// Handwritten callout. Use sparingly.
    static func scribble(_ size: CGFloat = 20) -> Font {
        .custom("BradleyHandITCTT-Bold", size: size)
    }
}

func tapHaptic() {
    UIImpactFeedbackGenerator(style: .light).impactOccurred()
}

/// White nav bar with an ink line, ink titles, rounded type. Call once at launch.
func configureBrutAppearance() {
    let ink = UIColor(Color.ink)
    func rounded(_ size: CGFloat) -> UIFont {
        let base = UIFont.systemFont(ofSize: size, weight: .bold)
        return base.fontDescriptor.withDesign(.rounded).map { UIFont(descriptor: $0, size: size) } ?? base
    }

    let nav = UINavigationBarAppearance()
    nav.configureWithOpaqueBackground()
    nav.backgroundColor = UIColor(Color.page)
    nav.shadowColor = ink
    nav.titleTextAttributes = [.foregroundColor: ink, .font: rounded(17)]
    nav.largeTitleTextAttributes = [.foregroundColor: ink, .font: rounded(34)]
    UINavigationBar.appearance().standardAppearance = nav
    UINavigationBar.appearance().scrollEdgeAppearance = nav
    UINavigationBar.appearance().compactAppearance = nav
}
