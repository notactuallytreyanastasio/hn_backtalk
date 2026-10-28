import UIKit

/// Newsprint: warm paper, near-black ink, one orange taken from Hacker News's
/// header, and New York (the system serif) for anything meant to be read.
enum Theme {
    static let paper = UIColor { $0.userInterfaceStyle == .dark ? UIColor(red: 0.09, green: 0.085, blue: 0.08, alpha: 1)
                                                              : UIColor(red: 0.965, green: 0.945, blue: 0.905, alpha: 1) }
    static let card = UIColor { $0.userInterfaceStyle == .dark ? UIColor(red: 0.13, green: 0.12, blue: 0.11, alpha: 1)
                                                             : UIColor(red: 0.995, green: 0.985, blue: 0.96, alpha: 1) }
    static let ink = UIColor { $0.userInterfaceStyle == .dark ? UIColor(red: 0.93, green: 0.91, blue: 0.87, alpha: 1)
                                                            : UIColor(red: 0.09, green: 0.08, blue: 0.07, alpha: 1) }
    static let muted = UIColor { $0.userInterfaceStyle == .dark ? UIColor(white: 0.62, alpha: 1)
                                                              : UIColor(red: 0.42, green: 0.40, blue: 0.37, alpha: 1) }
    static let rule = UIColor { $0.userInterfaceStyle == .dark ? UIColor(white: 1, alpha: 0.12) : UIColor(white: 0, alpha: 0.12) }
    static let orange = UIColor(red: 0.93, green: 0.36, blue: 0.06, alpha: 1)

    /// Thread depth bars, so you can tell which reply answers which.
    static let depth: [UIColor] = [
        orange,
        UIColor(red: 0.20, green: 0.45, blue: 0.70, alpha: 1),
        UIColor(red: 0.30, green: 0.58, blue: 0.36, alpha: 1),
        UIColor(red: 0.62, green: 0.36, blue: 0.66, alpha: 1),
        UIColor(red: 0.78, green: 0.62, blue: 0.16, alpha: 1),
        UIColor(red: 0.45, green: 0.45, blue: 0.45, alpha: 1),
    ]

    static func serif(_ size: CGFloat, _ weight: UIFont.Weight = .regular, italic: Bool = false) -> UIFont {
        var d = UIFont.systemFont(ofSize: size, weight: weight).fontDescriptor
        d = d.withDesign(.serif) ?? d
        if italic, let i = d.withSymbolicTraits(d.symbolicTraits.union(.traitItalic)) { d = i }
        return UIFont(descriptor: d, size: size)
    }

    static func sans(_ size: CGFloat, _ weight: UIFont.Weight = .regular) -> UIFont {
        .systemFont(ofSize: size, weight: weight)
    }

    /// Letter-spaced small caps for kickers like WEBSHIT WEEKLY.
    static func kicker(_ text: String, size: CGFloat = 11, color: UIColor = orange) -> NSAttributedString {
        NSAttributedString(string: text.uppercased(), attributes: [
            .font: UIFont.systemFont(ofSize: size, weight: .heavy),
            .kern: size * 0.18,
            .foregroundColor: color,
        ])
    }

    static func ago(_ seconds: Int?) -> String {
        guard let seconds else { return "" }
        let d = Int(Date().timeIntervalSince1970) - seconds
        switch d {
        case ..<60: return "now"
        case ..<3600: return "\(d / 60)m"
        case ..<86400: return "\(d / 3600)h"
        default: return "\(d / 86400)d"
        }
    }
}
