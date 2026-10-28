import Foundation

/// What the rear display says. Gemma writes each story's n-gate.com
/// "webshit weekly" entry from the story and its comments: the top ten front
/// page stories in the background as soon as the front page loads, and an
/// opened thread ahead of them. Entries are cached per story for the session.
final class Roast {
    static let shared = Roast()
    static let changed = Notification.Name("RoastChanged")

    private(set) var frontPage: [Story] = []
    /// The thread open on the inner screen, if any.
    private(set) var current: Story?
    private(set) var entries: [Int: String] = [:]
    /// The authors of the comments each entry was written from.
    private(set) var commenters: [Int: [String]] = [:]
    private(set) var status = "Model not loaded"
    private(set) var lastSeconds: Double?

    private let queue = DispatchQueue(label: "gemma", qos: .userInitiated)
    private var gemma: Gemma?
    /// Written one at a time, the open thread first.
    private var busy = false
    private var opened: (story: Story, thread: Item)?
    private var backlog: [Story] = []
    static let precomputed = 10

    /// What the rear display shows: the front page as a magazine cover, or
    /// the open story as a feature page whose pull quotes are the roast.
    enum Page: Equatable {
        /// Nothing reviewed yet: masthead and cover lines.
        case cover([Story])
        /// The front page's reviews so far, one story per page.
        case front([Review])
        /// `deck` is the entry's first sentence, which is about the story
        /// itself; `quotes` are the rest, mostly about the commenters.
        case feature(story: Story, deck: String?, quotes: [String], commenters: [String], waiting: String?)
    }

    struct Review: Equatable {
        let story: Story, rank: Int, deck: String?, quotes: [String], commenters: [String]
    }

    func review(_ story: Story, rank: Int = 0) -> Review? {
        guard let entry = entries[story.id] else { return nil }
        let s = Self.sentences(entry)
        return Review(story: story, rank: rank, deck: s.count > 1 ? s[0] : nil, quotes: s.count > 1 ? Array(s.dropFirst()) : s,
                      commenters: commenters[story.id] ?? [])
    }

    var page: Page {
        guard let story = current else {
            let reviews = frontPage.prefix(Self.precomputed).enumerated().compactMap { review($0.element, rank: $0.offset + 1) }
            return reviews.isEmpty ? .cover(frontPage) : .front(reviews)
        }
        let names = commenters[story.id] ?? []
        guard let entry = entries[story.id] else {
            return .feature(story: story, deck: nil, quotes: [], commenters: names, waiting: status)
        }
        let s = Self.sentences(entry)
        if s.count < 2 { return .feature(story: story, deck: nil, quotes: s, commenters: names, waiting: nil) }
        return .feature(story: story, deck: s[0], quotes: Array(s.dropFirst()), commenters: names, waiting: nil)
    }

    static func sentences(_ text: String) -> [String] {
        var out: [String] = []
        text.enumerateSubstrings(in: text.startIndex..., options: .bySentences) { s, _, _, _ in
            if let s = s?.trimmingCharacters(in: .whitespaces), !s.isEmpty { out.append(s) }
        }
        return out
    }

    func show(frontPage stories: [Story]) {
        frontPage = stories
        #if DEBUG
        if UserDefaults.standard.bool(forKey: "previewRear") { return post() }
        #endif
        backlog = Array(stories.prefix(Self.precomputed))
        post()
        pump()
    }

    /// Starts the next entry if none is being written: the open thread's,
    /// else the next front-page story without one.
    private func pump() {
        guard !busy else { return }
        if let o = opened, entries[o.story.id] == nil {
            opened = nil
            busy = true
            let prompt = ThreadPrompt.make(title: o.story.title, thread: o.thread, deep: Gemma.readsDeepThreads)
            queue.async { self.write(o.story, prompt, shown: true) }
            return
        }
        opened = nil
        while let s = backlog.first, entries[s.id] != nil { backlog.removeFirst() }
        guard let s = backlog.first else { return }
        backlog.removeFirst()
        busy = true
        Task { @MainActor in
            guard let thread = try? await HN.thread(s.id) else {
                log("roast: thread \(s.id) failed, skipping")
                self.busy = false
                self.pump()
                return
            }
            self.commenters[s.id] = ThreadPrompt.top(thread).compactMap(\.author)
            let prompt = ThreadPrompt.make(title: s.title, thread: thread, deep: Gemma.readsDeepThreads)
            self.queue.async { self.write(s, prompt, shown: false) }
        }
    }

    func open(_ story: Story, thread: Item) {
        current = story
        commenters[story.id] = ThreadPrompt.top(thread).compactMap(\.author)
        post()
        guard entries[story.id] == nil else { return }
        opened = (story, thread)
        pump()
    }

    func close(_ story: Story) {
        if current == story { current = nil }
        post()
    }

    /// `shown`: the thread is open, so its progress is the status line.
    private func write(_ story: Story, _ prompt: String, shown: Bool) {
        if gemma == nil {
            guard let url = Gemma.modelURL() else {
                set(status: "No model: run scripts/push-model.sh on the Mac")
                DispatchQueue.main.async { self.busy = false }
                return
            }
            set(status: "Loading \(url.lastPathComponent)…")
            gemma = Gemma(url: url)
            set(status: gemma == nil ? "Could not load \(url.lastPathComponent)" : "Gemma ready")
        }
        if shown { set(status: "Writing about “\(story.title)”…") }
        let start = Date()
        // The fine-tuned model sometimes opens with ": ".
        let entry = gemma?.reply(to: prompt, maxTokens: 220)?
            .trimmingCharacters(in: CharacterSet(charactersIn: ":").union(.whitespacesAndNewlines))
        let seconds = Date().timeIntervalSince(start)
        DispatchQueue.main.async {
            self.busy = false
            self.lastSeconds = seconds
            if let entry, !entry.isEmpty {
                log("roast: \(story.title) -> \(entry)")
                self.entries[story.id] = entry
                self.status = "Gemma ready"
            } else if shown {
                self.status = "Gemma wrote nothing"
            }
            self.post()
            self.pump()
        }
    }

#if DEBUG
    /// `-previewRear YES`: the rear's feature page, shown on the main screen
    /// with a made-up entry, for checking the layout in the simulator (which
    /// can't run Gemma, and whose rear display only shows when unfolded).
    func preview() {
        let story = frontPage.first ?? Story(objectID: "1", title: "Show HN: I rewrote my static site generator in Rust for the fourth time",
                                             url: "https://example.com/post", author: "op", points: 412, num_comments: 287, created_at_i: nil)
        current = story
        commenters[story.id] = ["tptacek", "pjmlp", "throwaway_4417", "dang"]
        entries[story.id] = "A webshit rewrites a program nobody uses in a language nobody asked for. "
            + "Hackernews explains that the original was fine, then spends two hundred comments arguing about whether it was. "
            + "One commenter has been doing this since 1987 and would like everyone to know. "
            + "Another posts a benchmark. "
            + "Nobody reads the article."
        post()
    }
#endif

    private func set(status: String) {
        DispatchQueue.main.async {
            self.status = status
            log("roast: \(status)")
            self.post()
        }
    }

    private func post() {
        NotificationCenter.default.post(name: Roast.changed, object: nil)
    }
}
