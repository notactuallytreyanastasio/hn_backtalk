import Foundation

/// Hacker News through the Algolia HN API: the front page, and a whole thread
/// in one request. training/threads.py reads threads from the same API.
struct Story: Decodable, Equatable {
    let objectID: String
    let title: String
    let url: String?
    let author: String?
    let points: Int?
    let num_comments: Int?
    let created_at_i: Int?
    var id: Int { Int(objectID) ?? 0 }
}

/// One node of a thread: the story itself, or a comment.
struct Item: Decodable {
    let id: Int
    let author: String?
    let title: String?
    let text: String?
    let url: String?
    let points: Int?
    let created_at_i: Int?
    let children: [Item]
}

enum HN {
    static func frontPage() async throws -> [Story] {
        struct Page: Decodable { let hits: [Story] }
        let url = URL(string: "https://hn.algolia.com/api/v1/search?tags=front_page&hitsPerPage=40")!
        let (data, _) = try await URLSession.shared.data(from: url)
        return try JSONDecoder().decode(Page.self, from: data).hits
    }

    static func thread(_ id: Int) async throws -> Item {
        let url = URL(string: "https://hn.algolia.com/api/v1/items/\(id)")!
        let (data, _) = try await URLSession.shared.data(from: url)
        return try JSONDecoder().decode(Item.self, from: data)
    }
}

/// The model's input, character for character what training/threads.py's
/// thread_prompt() builds: the LoRA was trained on exactly this shape.
enum ThreadPrompt {
    static let topComments = 10
    static let commentChars = 220
    static let promptChars = 7000

    /// The ten biggest arguments, each followed down its subthreads as far as
    /// its share of `promptChars` goes. Shares roll over: a short argument
    /// leaves room for the next. A reply that doesn't fit is left out with its
    /// replies, so nothing appears without what it answers.
    ///
    /// `deep: false` is the first model's prompt: the four biggest
    /// arguments' opening comments only, no replies (the same lines, since
    /// an opening comment always fits).
    static func make(title: String, thread: Item, deep: Bool = true) -> String {
        var lines: [String] = []
        var used = 0
        for (i, top) in top(thread, count: deep ? topComments : 4).enumerated() {
            let budget = promptChars * (i + 1) / topComments
            var skip: Int?
            for (depth, line) in commentLines(top, depth: 0) {
                if !deep && depth > 0 { continue }
                if let s = skip, depth > s { continue }
                skip = nil
                // Python's len() counts code points.
                let n = line.unicodeScalars.count
                if depth > 0 && used + n + 1 > budget {
                    skip = depth
                    continue
                }
                lines.append(line)
                used += n + 1
            }
        }
        return "Hacker News story: \(title)\nComments:\n" + lines.joined(separator: "\n")
            + "\n\nWrite the n-gate.com webshit weekly entry for this story."
    }

    private static func usable(_ c: Item) -> Bool { !(c.author ?? "").isEmpty && !(c.text ?? "").isEmpty }

    /// A comment and its replies, depth first, biggest reply tree first, each
    /// reply indented two spaces deeper than what it answers.
    static func commentLines(_ c: Item, depth: Int) -> [(Int, String)] {
        guard usable(c) else { return [] }
        var out = [(depth, String(repeating: "  ", count: depth) + "\(c.author!): \(clip(plain(c.text!)))")]
        for k in bySize(c.children) { out += commentLines(k, depth: depth + 1) }
        return out
    }

    /// Biggest reply tree first. Python's sort(reverse=True) is stable: ties
    /// keep thread order.
    static func bySize(_ items: [Item]) -> [Item] {
        items.enumerated()
            .sorted { size($0.element) != size($1.element) ? size($0.element) > size($1.element) : $0.offset < $1.offset }
            .map(\.element)
    }

    /// The top-level comments the model sees: the biggest reply trees.
    static func top(_ thread: Item, count: Int = topComments) -> [Item] {
        Array(bySize(thread.children.filter(usable)).prefix(count))
    }

    static func size(_ item: Item) -> Int { 1 + item.children.reduce(0) { $0 + size($1) } }

    /// Python: `<p>` to a space, tags dropped, entities unescaped, whitespace collapsed.
    static func plain(_ html: String) -> String {
        var s = html.replacingOccurrences(of: "<p>", with: " ")
        s = s.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        s = unescape(s)
        // Split on scalars, not Characters: a space followed by U+FE0F is one
        // whitespace Character to Swift, but Python keeps the selector.
        var words: [String] = [], word = String.UnicodeScalarView()
        for c in s.unicodeScalars {
            if c.properties.isWhitespace || (0x1C...0x1F).contains(c.value) {
                if !word.isEmpty { words.append(String(word)); word = .init() }
            } else {
                word.append(c)
            }
        }
        if !word.isEmpty { words.append(String(word)) }
        return words.joined(separator: " ")
    }

    /// Python slices code points, so this counts unicode scalars, not characters.
    static func clip(_ text: String) -> String {
        let scalars = Array(text.unicodeScalars)
        guard scalars.count > commentChars else { return text }
        var cut = String(String.UnicodeScalarView(scalars[0..<commentChars]))
        if let space = cut.lastIndex(of: " ") { cut = String(cut[..<space]) }
        return cut + "…"
    }

    private static let named = ["amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": "\u{00A0}"]

    static func unescape(_ s: String) -> String {
        var out = ""
        var rest = Substring(s)
        while let amp = rest.firstIndex(of: "&") {
            out += rest[..<amp]
            let after = rest[rest.index(after: amp)...]
            if let semi = after.prefix(10).firstIndex(of: ";") {
                let name = after[..<semi]
                var replacement: String?
                if name.hasPrefix("#x") || name.hasPrefix("#X"), let v = UInt32(name.dropFirst(2), radix: 16) {
                    replacement = Unicode.Scalar(v).map(String.init)
                } else if name.hasPrefix("#"), let v = UInt32(name.dropFirst()) {
                    replacement = Unicode.Scalar(v).map(String.init)
                } else {
                    replacement = named[String(name)]
                }
                if let replacement {
                    out += replacement
                    rest = after[after.index(after: semi)...]
                    continue
                }
            }
            out += "&"
            rest = after
        }
        return out + rest
    }
}
