import UIKit

/// The rear display as a magazine. Browsing the front page, it is a cover:
/// masthead and cover lines. With a thread open, it is a feature page: the
/// story's title as the headline, the roast's first sentence as the deck, and
/// the rest of the roast set as pull quotes "from" the commenters it mocks,
/// one at a time.
final class MagazineView: UIView {
    var page: Roast.Page? {
        didSet {
            guard page != oldValue else { return }
            // A new review landing on the front page keeps the rotation where
            // it is; a different kind of page starts it over.
            if Self.kind(page) != Self.kind(oldValue) { step = 0 }
            show(animated: true)
        }
    }

    private static func kind(_ p: Roast.Page?) -> String {
        switch p {
        case .cover?: "cover"
        case .front?: "front"
        case .feature(let s, _, _, _, _)?: "story \(s.id)"
        case nil: ""
        }
    }

    private var timer: Timer?
    private var step = 0
    private var content: UIView?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = Theme.paper
        clipsToBounds = true
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        timer?.invalidate()
        timer = nil
        guard window != nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 9, repeats: true) { [weak self] _ in self?.advance() }
    }

    private var builtFor: CGSize = .zero
    override func layoutSubviews() {
        super.layoutSubviews()
        if bounds.size != builtFor { rebuild() }
    }

    private var wide: Bool { bounds.width > bounds.height }

    private func rebuild() {
        builtFor = bounds.size
        step = 0
        show(animated: false)
    }

    private func advance() {
        step += 1
        show(animated: true)
    }

    private func show(animated: Bool) {
        guard bounds.width > 0, let page else { return }
        let next: UIView
        switch page {
        case .cover(let stories): next = cover(stories)
        case .front(let reviews):
            let i = step % reviews.count
            let r = reviews[i]
            // Each time round the front page, the next quote from each review.
            next = feature(story: r.story, kicker: "Front page  ·  No. \(r.rank)", deck: r.deck, quotes: r.quotes,
                           quote: step / reviews.count, commenters: r.commenters, waiting: nil,
                           folio: "\(i + 1) / \(reviews.count) reviewed")
        case let .feature(story, deck, quotes, commenters, waiting):
            let host = story.url.flatMap { URL(string: $0)?.host() }.map { $0.replacingOccurrences(of: "www.", with: "") }
            next = feature(story: story, kicker: "Webshit Weekly" + (host.map { "  ·  \($0)" } ?? ""), deck: deck, quotes: quotes,
                           quote: step, commenters: commenters, waiting: waiting,
                           folio: quotes.isEmpty ? "Backtalk" : "\(step % quotes.count + 1) / \(quotes.count)")
        }
        next.frame = bounds
        let old = content
        content = next
        addSubview(next)
        guard animated, let old else { old?.removeFromSuperview(); return }
        next.alpha = 0
        UIView.animate(withDuration: 0.8, animations: { next.alpha = 1; old.alpha = 0 }, completion: { _ in old.removeFromSuperview() })
    }

    // MARK: Cover

    private func cover(_ stories: [Story]) -> UIView {
        let v = UIView()
        let inset: CGFloat = 22
        let stack = column(spacing: 10)
        stack.addArrangedSubview(label(NSAttributedString(string: "Backtalk", attributes: [
            .font: Theme.serif(wide ? 52 : 64, .black), .foregroundColor: Theme.ink, .kern: -1.5,
        ])))
        let date = Date().formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
        stack.addArrangedSubview(label(Theme.kicker("The Hacker News Review  ·  \(date)", size: 10, color: Theme.muted)))
        stack.addArrangedSubview(doubleRule())

        guard !stories.isEmpty else {
            stack.addArrangedSubview(label(NSAttributedString(string: "Fetching the front page…", attributes: [
                .font: Theme.serif(22, italic: true), .foregroundColor: Theme.muted,
            ])))
            return place(stack, in: v, inset: inset)
        }
        let per = wide ? 4 : 5
        let groups = stride(from: 0, to: stories.count, by: per).map { Array(stories[$0..<min($0 + per, stories.count)]) }
        let group = groups[step % groups.count]
        let base = (step % groups.count) * per

        let lead = group[0]
        stack.addArrangedSubview(label(Theme.kicker("No. \(base + 1)  ·  \(lead.points ?? 0) points  ·  \(lead.num_comments ?? 0) comments")))
        let leadTitle = FitLabel(maxSize: wide ? 30 : 36, minSize: 20, lines: 4) { Theme.serif($0, .bold) }
        leadTitle.text = lead.title
        stack.addArrangedSubview(leadTitle)
        stack.setCustomSpacing(18, after: leadTitle)

        for (i, s) in group.dropFirst().enumerated() {
            let line = NSMutableAttributedString(string: "\(base + i + 2)  ", attributes: [
                .font: Theme.serif(17, .black), .foregroundColor: Theme.orange,
            ])
            line.append(NSAttributedString(string: s.title, attributes: [.font: Theme.serif(17, .medium), .foregroundColor: Theme.ink]))
            let l = label(line)
            l.numberOfLines = 2
            stack.addArrangedSubview(l)
            if i < group.count - 2 { stack.addArrangedSubview(rule()) }
        }
        stack.addArrangedSubview(UIView())
        stack.addArrangedSubview(folio(left: "Open a thread to read the review", right: "\(step % groups.count + 1) / \(groups.count)"))
        return place(stack, in: v, inset: inset)
    }

    // MARK: Feature

    private func feature(story: Story, kicker: String, deck: String?, quotes: [String], quote q: Int,
                         commenters: [String], waiting: String?, folio right: String) -> UIView {
        let v = UIView()
        let head = column(spacing: 8)
        head.addArrangedSubview(label(Theme.kicker(kicker)))
        head.addArrangedSubview(doubleRule())
        let headline = FitLabel(maxSize: wide ? 30 : 34, minSize: 18, lines: 4) { Theme.serif($0, .heavy) }
        headline.text = story.title
        head.addArrangedSubview(headline)
        if let deck {
            let d = FitLabel(maxSize: 18, minSize: 13, lines: wide ? 5 : 4) { Theme.serif($0, italic: true) }
            d.text = deck
            d.textColor = Theme.muted
            head.addArrangedSubview(d)
        }

        let pull = PullQuote()
        if quotes.isEmpty {
            pull.set(quote: waiting ?? "Reading the comments so you don't have to…",
                     by: commenters.isEmpty ? "" : "Now reading " + commenters.prefix(3).joined(separator: ", "),
                     waiting: true, maxSize: 22)
        } else {
            let i = q % quotes.count
            pull.set(quote: quotes[i], by: commenters.isEmpty ? "— Hackernews" : "— on \(commenters[i % commenters.count])",
                     waiting: false, maxSize: wide ? 30 : 36)
        }

        let footer = folio(left: "\(story.points ?? 0) points  ·  \(story.num_comments ?? 0) comments",
                           right: right)
        let inset: CGFloat = 22
        if wide {
            head.addArrangedSubview(UIView())
            let row = UIStackView(arrangedSubviews: [head, verticalRule(), pull])
            row.axis = .horizontal
            row.spacing = 18
            row.alignment = .fill
            head.widthAnchor.constraint(equalTo: row.widthAnchor, multiplier: 0.42).isActive = true
            let all = column(spacing: 10)
            all.addArrangedSubview(row)
            all.addArrangedSubview(footer)
            return place(all, in: v, inset: inset)
        }
        let all = column(spacing: 12)
        all.addArrangedSubview(head)
        all.addArrangedSubview(rule())
        all.addArrangedSubview(pull)
        all.addArrangedSubview(footer)
        return place(all, in: v, inset: inset)
    }

    // MARK: Pieces

    private func column(spacing: CGFloat) -> UIStackView {
        let s = UIStackView()
        s.axis = .vertical
        s.spacing = spacing
        s.alignment = .fill
        return s
    }

    private func label(_ text: NSAttributedString) -> UILabel {
        let l = UILabel()
        l.attributedText = text
        l.numberOfLines = 0
        l.setContentCompressionResistancePriority(.required, for: .vertical)
        l.setContentHuggingPriority(.required, for: .vertical)
        return l
    }

    private func rule(_ height: CGFloat = 1, color: UIColor = Theme.rule) -> UIView {
        let r = UIView()
        r.backgroundColor = color
        r.heightAnchor.constraint(equalToConstant: height).isActive = true
        return r
    }

    private func verticalRule() -> UIView {
        let r = UIView()
        r.backgroundColor = Theme.rule
        r.widthAnchor.constraint(equalToConstant: 1).isActive = true
        return r
    }

    /// The heavy-over-hairline rule under a magazine section head.
    private func doubleRule() -> UIView {
        let s = column(spacing: 2)
        s.addArrangedSubview(rule(3, color: Theme.ink))
        s.addArrangedSubview(rule(1, color: Theme.ink))
        return s
    }

    private func folio(left: String, right: String) -> UIView {
        let a = label(Theme.kicker(left, size: 9, color: Theme.muted))
        let b = label(Theme.kicker(right, size: 9, color: Theme.muted))
        b.textAlignment = .right
        b.setContentHuggingPriority(.required, for: .horizontal)
        let row = UIStackView(arrangedSubviews: [a, b])
        row.axis = .horizontal
        let s = column(spacing: 6)
        s.addArrangedSubview(rule(1, color: Theme.ink))
        s.addArrangedSubview(row)
        return s
    }

    private func place(_ stack: UIStackView, in v: UIView, inset: CGFloat) -> UIView {
        stack.translatesAutoresizingMaskIntoConstraints = false
        v.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: v.leadingAnchor, constant: inset),
            stack.trailingAnchor.constraint(equalTo: v.trailingAnchor, constant: -inset),
            stack.topAnchor.constraint(equalTo: v.topAnchor, constant: inset),
            stack.bottomAnchor.constraint(equalTo: v.bottomAnchor, constant: -inset),
        ])
        return v
    }
}

/// A pull quote: a big orange opening mark, the quote at the largest size
/// that leaves room for its attribution, and the attribution right under it.
/// Laid out by hand because it has to measure the quote to size it.
final class PullQuote: UIView {
    private var quote = "", by = "", waiting = false, maxSize: CGFloat = 34
    private let mark = UILabel(), text = UILabel(), credit = UILabel()
    private static let markSize: CGFloat = 96

    override init(frame: CGRect) {
        super.init(frame: frame)
        mark.attributedText = NSAttributedString(string: "\u{201C}", attributes: [
            .font: Theme.serif(Self.markSize, .black), .foregroundColor: Theme.orange,
        ])
        text.numberOfLines = 0
        credit.numberOfLines = 1
        [mark, text, credit].forEach(addSubview)
        setContentHuggingPriority(.defaultLow, for: .vertical)
        setContentCompressionResistancePriority(.defaultLow, for: .vertical)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func set(quote: String, by: String, waiting: Bool, maxSize: CGFloat) {
        (self.quote, self.by, self.waiting, self.maxSize) = (quote, by, waiting, maxSize)
        credit.attributedText = NSAttributedString(string: by, attributes: [
            .font: Theme.sans(13, .semibold), .foregroundColor: Theme.muted, .kern: 0.4,
        ])
        setNeedsLayout()
    }

    private func font(_ size: CGFloat) -> UIFont {
        waiting ? Theme.serif(size, italic: true) : Theme.serif(size, .semibold)
    }

    private func attributed(_ size: CGFloat) -> NSAttributedString {
        let p = NSMutableParagraphStyle()
        p.lineHeightMultiple = 0.95
        return NSAttributedString(string: quote, attributes: [
            .font: font(size), .foregroundColor: waiting ? Theme.muted : Theme.ink, .paragraphStyle: p,
        ])
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let w = bounds.width
        guard w > 0 else { return }
        // The mark's glyph is in the top half of its line: show just that part.
        let markFont = Theme.serif(Self.markSize, .black)
        let markHeight = markFont.capHeight * 0.62
        mark.sizeToFit()
        mark.frame.origin = CGPoint(x: -4, y: -(markFont.ascender - markFont.capHeight) + 2)
        let top = markHeight + 14
        let creditHeight = by.isEmpty ? 0 : credit.sizeThatFits(bounds.size).height + 10
        let room = bounds.height - top - creditHeight
        var size = maxSize
        var h: CGFloat = 0
        while true {
            h = ceil(attributed(size).boundingRect(with: CGSize(width: w, height: .greatestFiniteMagnitude),
                                                   options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil).height)
            if h <= room || size <= 14 { break }
            size -= 1
        }
        text.attributedText = attributed(size)
        text.frame = CGRect(x: 0, y: top, width: w, height: min(h, max(0, room)))
        credit.frame = CGRect(x: 0, y: text.frame.maxY + 10, width: w, height: creditHeight - 10)
    }
}

/// A label that takes the largest font size, between two bounds, at which its
/// text fits the space layout gives it. Pull quotes run from four words to
/// forty, and should fill the page either way.
final class FitLabel: UILabel {
    private let maxSize: CGFloat, minSize: CGFloat
    private let make: (CGFloat) -> UIFont
    private var fittedFor: CGSize = .zero

    init(maxSize: CGFloat, minSize: CGFloat, lines: Int, font make: @escaping (CGFloat) -> UIFont) {
        self.maxSize = maxSize
        self.minSize = minSize
        self.make = make
        super.init(frame: .zero)
        numberOfLines = lines
        textColor = Theme.ink
        font = make(maxSize)
        lineBreakMode = .byTruncatingTail
        setContentHuggingPriority(.required, for: .vertical)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var text: String? { didSet { fittedFor = .zero; setNeedsLayout() } }

    /// Set from the top, like type on a page; UILabel centres vertically.
    override func drawText(in rect: CGRect) {
        let fits = textRect(forBounds: rect, limitedToNumberOfLines: numberOfLines)
        super.drawText(in: CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: min(rect.height, fits.height)))
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard let text, bounds.size != fittedFor, bounds.width > 0 else { return }
        fittedFor = bounds.size
        let f = fittingSize(width: bounds.width, height: numberOfLines > 0 ? .greatestFiniteMagnitude : bounds.height, text: text)
        font = make(f)
        invalidateIntrinsicContentSize()
    }

    /// With a line limit, the largest size that stays within it; without
    /// one, the largest that fits the height layout gave.
    private func fittingSize(width: CGFloat, height limit: CGFloat, text: String) -> CGFloat {
        var size = maxSize
        while size > minSize {
            let font = make(size)
            let h = height(text, font: font, width: width)
            let fits = numberOfLines > 0 ? h / font.lineHeight <= CGFloat(numberOfLines) + 0.5 : h <= limit
            if fits { break }
            size -= 1
        }
        return size
    }

    private func height(_ text: String, font: UIFont, width: CGFloat) -> CGFloat {
        (text as NSString).boundingRect(with: CGSize(width: width, height: .greatestFiniteMagnitude),
                                        options: [.usesLineFragmentOrigin, .usesFontLeading],
                                        attributes: [.font: font], context: nil).height
    }
}
