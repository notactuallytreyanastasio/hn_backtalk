import SafariServices
import UIKit

/// Paper navigation bars with serif titles, for every screen in the reader.
func styleNavigation(_ nav: UINavigationController) {
    let a = UINavigationBarAppearance()
    a.configureWithOpaqueBackground()
    a.backgroundColor = Theme.paper
    a.shadowColor = Theme.rule
    a.titleTextAttributes = [.font: Theme.serif(17, .bold), .foregroundColor: Theme.ink]
    a.largeTitleTextAttributes = [.font: Theme.serif(38, .black), .foregroundColor: Theme.ink, .kern: -0.8]
    nav.navigationBar.standardAppearance = a
    nav.navigationBar.scrollEdgeAppearance = a
    nav.navigationBar.compactAppearance = a
    nav.navigationBar.tintColor = Theme.ink
    nav.navigationBar.prefersLargeTitles = true
}

private func host(_ url: String?) -> String? {
    url.flatMap { URL(string: $0)?.host() }.map { $0.hasPrefix("www.") ? String($0.dropFirst(4)) : $0 }
}

// MARK: - Front page

/// The front page. The rear display shows it as a magazine cover until you
/// open a story.
final class StoriesViewController: UITableViewController {
    private var stories: [Story] = []

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Backtalk"
        navigationItem.largeTitleDisplayMode = .always
        tableView.backgroundColor = Theme.paper
        tableView.separatorColor = Theme.rule
        tableView.separatorInset = UIEdgeInsets(top: 0, left: 62, bottom: 0, right: 16)
        tableView.register(StoryCell.self, forCellReuseIdentifier: "story")
        tableView.tableHeaderView = dateline()
        refreshControl = UIRefreshControl()
        refreshControl?.addAction(UIAction { [weak self] _ in self?.load() }, for: .valueChanged)
        navigationItem.rightBarButtonItem = brightButton()
        NotificationCenter.default.addObserver(forName: Roast.changed, object: nil, queue: .main) { [weak self] _ in
            guard let self, self.view.window != nil else { return }
            self.tableView.reloadData()
        }
        load()
    }

    #if DEBUG
    /// `-openFirst YES` opens the top story once it loads, for screenshots.
    private var opened = false
    #endif

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // Stories reviewed while you were in a thread get their tag.
        tableView.reloadData()
    }

    private func dateline() -> UIView {
        let v = UIView(frame: CGRect(x: 0, y: 0, width: 0, height: 34))
        let l = UILabel()
        let date = Date().formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
        l.attributedText = Theme.kicker("The Hacker News Review  ·  \(date)", size: 10, color: Theme.muted)
        l.adjustsFontSizeToFitWidth = true
        l.translatesAutoresizingMaskIntoConstraints = false
        v.addSubview(l)
        NSLayoutConstraint.activate([
            l.leadingAnchor.constraint(equalTo: v.leadingAnchor, constant: 20),
            l.trailingAnchor.constraint(lessThanOrEqualTo: v.trailingAnchor, constant: -20),
            l.centerYAnchor.constraint(equalTo: v.centerYAnchor),
        ])
        return v
    }

    private func brightButton() -> UIBarButtonItem {
        let item = UIBarButtonItem(image: UIImage(systemName: Rear.bright ? "sun.max.fill" : "sun.min"), primaryAction: nil)
        item.primaryAction = UIAction(image: item.image) { [weak self] _ in
            Rear.bright.toggle()
            Rear.bright ? Camera.shared.start() : Camera.shared.stop()
            self?.navigationItem.rightBarButtonItem = self?.brightButton()
        }
        item.accessibilityLabel = Rear.bright ? "Rear bright (camera on)" : "Rear dim (camera off)"
        return item
    }

    private func load() {
        Task {
            do {
                stories = try await HN.frontPage()
                Roast.shared.show(frontPage: stories)
                tableView.reloadData()
                #if DEBUG
                if UserDefaults.standard.bool(forKey: "openFirst"), !opened, let s = stories.first {
                    opened = true
                    navigationController?.pushViewController(CommentsViewController(story: s), animated: false)
                }
                #endif
            } catch {
                log("hn: front page failed: \(error)")
            }
            refreshControl?.endRefreshing()
        }
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { stories.count }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "story", for: indexPath) as! StoryCell
        let s = stories[indexPath.row]
        cell.show(s, rank: indexPath.row + 1, reviewed: Roast.shared.entries[s.id] != nil)
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        navigationController?.pushViewController(CommentsViewController(story: stories[indexPath.row]), animated: true)
    }
}

final class StoryCell: UITableViewCell {
    private let rank = UILabel(), headline = UILabel(), meta = UILabel()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = Theme.paper
        let selected = UIView()
        selected.backgroundColor = Theme.rule
        selectedBackgroundView = selected
        rank.font = Theme.serif(22, .black)
        rank.textColor = Theme.orange
        rank.textAlignment = .right
        headline.font = Theme.serif(19, .semibold)
        headline.textColor = Theme.ink
        headline.numberOfLines = 0
        meta.numberOfLines = 0
        let text = UIStackView(arrangedSubviews: [headline, meta])
        text.axis = .vertical
        text.spacing = 5
        for v in [rank, text] {
            v.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview(v)
        }
        let g = contentView.layoutMarginsGuide
        NSLayoutConstraint.activate([
            rank.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 8),
            rank.widthAnchor.constraint(equalToConstant: 36),
            rank.firstBaselineAnchor.constraint(equalTo: headline.firstBaselineAnchor),
            text.leadingAnchor.constraint(equalTo: rank.trailingAnchor, constant: 18),
            text.trailingAnchor.constraint(equalTo: g.trailingAnchor),
            text.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 14),
            text.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -14),
        ])
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func show(_ s: Story, rank n: Int, reviewed: Bool) {
        rank.text = "\(n)"
        headline.text = s.title
        let m = NSMutableAttributedString()
        if reviewed {
            m.append(Theme.kicker("Reviewed", size: 10))
            m.append(NSAttributedString(string: "   "))
        }
        if let h = host(s.url) {
            m.append(NSAttributedString(string: h + "   ", attributes: [.font: Theme.sans(13, .semibold), .foregroundColor: Theme.ink]))
        }
        m.append(NSAttributedString(string: "\(s.points ?? 0) points · \(s.num_comments ?? 0) comments · \(Theme.ago(s.created_at_i))",
                                    attributes: [.font: Theme.sans(13), .foregroundColor: Theme.muted]))
        meta.attributedText = m
    }
}

// MARK: - Thread

/// A thread, flattened with depth bars, tap a comment to fold its replies.
/// Opening it sets the rear display roasting the story and its commenters.
final class CommentsViewController: UITableViewController {
    private struct Row { let id: Int, depth: Int, author: String, ago: String, body: NSAttributedString, replies: Int }

    private let story: Story
    private var rows: [Row] = []
    private var visible: [Row] = []
    private var folded: Set<Int> = []
    private let header = ThreadHeader()

    init(story: Story) {
        self.story = story
        super.init(style: .plain)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "\(story.num_comments ?? 0) comments"
        navigationItem.largeTitleDisplayMode = .never
        tableView.backgroundColor = Theme.paper
        tableView.separatorStyle = .none
        tableView.register(CommentCell.self, forCellReuseIdentifier: "comment")
        header.show(story)
        header.onArticle = { [weak self] in self?.openArticle() }
        showRoast()
        NotificationCenter.default.addObserver(forName: Roast.changed, object: nil, queue: .main) { [weak self] _ in
            self?.showRoast()
        }
        Task {
            do {
                let thread = try await HN.thread(story.id)
                rows = []
                flatten(thread.children, depth: 0)
                refold()
                Roast.shared.open(story, thread: thread)
            } catch {
                log("hn: thread \(story.id) failed: \(error)")
                header.set(roast: nil, status: "Could not load the thread")
                sizeHeader()
            }
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if isMovingFromParent { Roast.shared.close(story) }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        sizeHeader()
    }

    private func openArticle() {
        guard let s = story.url, let url = URL(string: s) else { return }
        let safari = SFSafariViewController(url: url)
        safari.preferredControlTintColor = Theme.orange
        // A sheet, not full screen: the navigation controller that holds the
        // rear display's registration has to stay on screen.
        safari.modalPresentationStyle = .pageSheet
        present(safari, animated: true)
    }

    private func showRoast() {
        header.set(roast: Roast.shared.entries[story.id], status: Roast.shared.status)
        sizeHeader()
    }

    private func sizeHeader() {
        let width = tableView.bounds.width
        guard width > 0 else { return }
        let h = header.systemLayoutSizeFitting(CGSize(width: width, height: 0),
                                               withHorizontalFittingPriority: .required, verticalFittingPriority: .fittingSizeLevel).height
        if header.frame.size != CGSize(width: width, height: h) || tableView.tableHeaderView !== header {
            header.frame = CGRect(x: 0, y: 0, width: width, height: h)
            tableView.tableHeaderView = header
        }
    }

    @discardableResult
    private func flatten(_ items: [Item], depth: Int) -> Int {
        var count = 0
        for item in items {
            let index = rows.count
            if let author = item.author, let text = item.text {
                rows.append(Row(id: item.id, depth: depth, author: author, ago: Theme.ago(item.created_at_i),
                                body: CommentText.attributed(text), replies: 0))
            }
            let replies = flatten(item.children, depth: depth + 1)
            if index < rows.count, rows[index].id == item.id {
                let r = rows[index]
                rows[index] = Row(id: r.id, depth: r.depth, author: r.author, ago: r.ago, body: r.body, replies: replies)
                count += 1
            }
            count += replies
        }
        return count
    }

    private func refold() {
        visible = []
        var hideBelow: Int?
        for r in rows {
            if let d = hideBelow, r.depth > d { continue }
            hideBelow = folded.contains(r.id) ? r.depth : nil
            visible.append(r)
        }
        tableView.reloadData()
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { visible.count }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "comment", for: indexPath) as! CommentCell
        let r = visible[indexPath.row]
        cell.show(author: r.author, op: r.author == story.author, ago: r.ago, body: r.body, depth: r.depth,
                  folded: folded.contains(r.id) ? r.replies : nil)
        cell.onFold = { [weak self] in self?.fold(r.id) }
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: false)
        fold(visible[indexPath.row].id)
    }

    private func fold(_ id: Int) {
        guard let r = rows.first(where: { $0.id == id }), r.replies > 0 || folded.contains(id) else { return }
        if folded.contains(id) { folded.remove(id) } else { folded.insert(id) }
        refold()
    }
}

/// The top of a thread: the story set as a headline, a link out, and the
/// review in a card, so it can be read with the phone folded too.
final class ThreadHeader: UIView {
    var onArticle: (() -> Void)?
    private let kicker = UILabel(), headline = UILabel(), meta = UILabel()
    private let article = UIButton(type: .system)
    private let card = UIView(), cardKicker = UILabel(), roast = UILabel()
    private let spinner = UIActivityIndicatorView(style: .medium)

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = Theme.paper
        headline.font = Theme.serif(28, .heavy)
        headline.textColor = Theme.ink
        headline.numberOfLines = 0
        meta.font = Theme.sans(13)
        meta.textColor = Theme.muted
        meta.numberOfLines = 0

        var c = UIButton.Configuration.plain()
        c.attributedTitle = AttributedString("Read the article  →", attributes: AttributeContainer([.font: Theme.sans(14, .semibold)]))
        c.baseForegroundColor = Theme.orange
        c.contentInsets = .zero
        article.configuration = c
        article.contentHorizontalAlignment = .leading
        article.addAction(UIAction { [weak self] _ in self?.onArticle?() }, for: .touchUpInside)

        card.backgroundColor = Theme.card
        card.layer.cornerRadius = 4
        card.layer.borderColor = Theme.rule.cgColor
        card.layer.borderWidth = 1
        let bar = UIView()
        bar.backgroundColor = Theme.orange
        cardKicker.attributedText = Theme.kicker("Webshit Weekly", size: 10)
        roast.numberOfLines = 0
        spinner.color = Theme.muted
        let kickerRow = UIStackView(arrangedSubviews: [cardKicker, UIView(), spinner])
        kickerRow.axis = .horizontal
        let cardText = UIStackView(arrangedSubviews: [kickerRow, roast])
        cardText.axis = .vertical
        cardText.spacing = 8
        for v in [bar, cardText] {
            v.translatesAutoresizingMaskIntoConstraints = false
            card.addSubview(v)
        }
        NSLayoutConstraint.activate([
            bar.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            bar.topAnchor.constraint(equalTo: card.topAnchor),
            bar.bottomAnchor.constraint(equalTo: card.bottomAnchor),
            bar.widthAnchor.constraint(equalToConstant: 4),
            cardText.leadingAnchor.constraint(equalTo: bar.trailingAnchor, constant: 14),
            cardText.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -14),
            cardText.topAnchor.constraint(equalTo: card.topAnchor, constant: 14),
            cardText.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -16),
        ])

        let rule = UIView()
        rule.backgroundColor = Theme.ink
        rule.heightAnchor.constraint(equalToConstant: 2).isActive = true
        let stack = UIStackView(arrangedSubviews: [kicker, headline, meta, article, card, rule])
        stack.axis = .vertical
        stack.spacing = 10
        stack.setCustomSpacing(14, after: article)
        stack.setCustomSpacing(22, after: card)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 18),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6),
        ])
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func traitCollectionDidChange(_ previous: UITraitCollection?) {
        super.traitCollectionDidChange(previous)
        card.layer.borderColor = Theme.rule.resolvedColor(with: traitCollection).cgColor
    }

    func show(_ s: Story) {
        kicker.attributedText = Theme.kicker(host(s.url) ?? "Ask / Show HN", size: 10)
        headline.text = s.title
        meta.text = "\(s.points ?? 0) points by \(s.author ?? "?") · \(Theme.ago(s.created_at_i)) ago · \(s.num_comments ?? 0) comments"
        article.isHidden = s.url == nil
    }

    func set(roast entry: String?, status: String) {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = 3
        if let entry {
            spinner.stopAnimating()
            roast.attributedText = NSAttributedString(string: entry, attributes: [
                .font: Theme.serif(17, italic: true), .foregroundColor: Theme.ink, .paragraphStyle: style,
            ])
        } else {
            spinner.startAnimating()
            roast.attributedText = NSAttributedString(string: status == "Gemma ready" ? "Reading the comments so you don't have to…" : status,
                                                      attributes: [.font: Theme.serif(15, italic: true), .foregroundColor: Theme.muted])
        }
    }
}

final class CommentCell: UITableViewCell {
    var onFold: (() -> Void)?
    private let bars = DepthBars()
    private let byline = UIButton(type: .custom)
    private let body = UITextView()
    private var indent: NSLayoutConstraint!

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = Theme.paper
        selectionStyle = .none
        bars.backgroundColor = .clear
        byline.contentHorizontalAlignment = .leading
        byline.addAction(UIAction { [weak self] _ in self?.onFold?() }, for: .touchUpInside)
        body.isEditable = false
        body.isScrollEnabled = false
        body.backgroundColor = .clear
        body.textContainerInset = .zero
        body.textContainer.lineFragmentPadding = 0
        body.linkTextAttributes = [.foregroundColor: Theme.orange, .underlineStyle: NSUnderlineStyle.single.rawValue]
        let stack = UIStackView(arrangedSubviews: [byline, body])
        stack.axis = .vertical
        stack.spacing = 4
        for v in [bars, stack] {
            v.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview(v)
        }
        indent = bars.widthAnchor.constraint(equalToConstant: 0)
        NSLayoutConstraint.activate([
            bars.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor, constant: 4),
            bars.topAnchor.constraint(equalTo: contentView.topAnchor),
            bars.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            indent,
            stack.leadingAnchor.constraint(equalTo: bars.trailingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor, constant: -4),
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 10),
            stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -10),
        ])
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func show(author: String, op: Bool, ago: String, body text: NSAttributedString, depth: Int, folded replies: Int?) {
        let shown = min(depth, 8)
        bars.depth = shown
        indent.constant = CGFloat(shown) * DepthBars.step
        let b = NSMutableAttributedString(string: author, attributes: [
            .font: Theme.sans(13, .bold), .foregroundColor: op ? Theme.orange : Theme.ink,
        ])
        if op { b.append(Theme.kicker("  OP", size: 9)) }
        b.append(NSAttributedString(string: "  \(ago)", attributes: [.font: Theme.sans(13), .foregroundColor: Theme.muted]))
        if let replies {
            b.append(NSAttributedString(string: "   +\(replies) folded", attributes: [.font: Theme.sans(12, .semibold), .foregroundColor: Theme.orange]))
        }
        byline.setAttributedTitle(b, for: .normal)
        body.attributedText = text
        body.isHidden = replies != nil
    }
}

/// One thin coloured line per level of reply.
final class DepthBars: UIView {
    static let step: CGFloat = 12
    var depth = 0 { didSet { setNeedsDisplay() } }

    override func draw(_ rect: CGRect) {
        for i in 0..<depth {
            Theme.depth[i % Theme.depth.count].withAlphaComponent(i == depth - 1 ? 0.9 : 0.35).setFill()
            UIRectFill(CGRect(x: CGFloat(i) * Self.step + 2, y: 0, width: 2, height: bounds.height))
        }
    }
}

/// HN's comment HTML is a small language: <p>, <i>, <a href>, <pre><code>,
/// and entities. This renders exactly that.
enum CommentText {
    static func attributed(_ html: String) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 2.5
        paragraph.paragraphSpacing = 8
        let base: [NSAttributedString.Key: Any] = [.font: Theme.serif(16), .foregroundColor: Theme.ink, .paragraphStyle: paragraph]
        let out = NSMutableAttributedString()
        var italic = false, code = false
        var link: URL?
        var rest = Substring(html)
        func emit(_ text: Substring) {
            guard !text.isEmpty else { return }
            var a = base
            if italic { a[.font] = Theme.serif(16, italic: true) }
            if code { a[.font] = UIFont.monospacedSystemFont(ofSize: 13, weight: .regular); a[.foregroundColor] = Theme.muted }
            if let link { a[.link] = link }
            out.append(NSAttributedString(string: ThreadPrompt.unescape(String(text)), attributes: a))
        }
        while let open = rest.firstIndex(of: "<") {
            emit(rest[..<open])
            guard let close = rest[open...].firstIndex(of: ">") else { rest = rest[open...]; break }
            let raw = rest[rest.index(after: open)..<close]
            let tag = raw.lowercased()
            rest = rest[rest.index(after: close)...]
            switch tag {
            case "p": out.append(NSAttributedString(string: "\n", attributes: base))
            case "i", "em": italic = true
            case "/i", "/em": italic = false
            case "pre": code = true; out.append(NSAttributedString(string: "\n", attributes: base))
            case "/pre": code = false
            case "/a": link = nil
            default:
                if tag.hasPrefix("a "), let r = raw.range(of: "href=\"") {
                    let after = raw[r.upperBound...]
                    link = after.firstIndex(of: "\"").flatMap { URL(string: ThreadPrompt.unescape(String(after[..<$0]))) }
                }
            }
        }
        emit(rest)
        return out
    }
}
