import Foundation
import llama

/// Gemma 4 through llama.cpp, after ../my_me_bot's LlamaCppEngine: all layers
/// on Metal, a fresh KV cache per generation, the turn markers as stops.
///
/// The template is Gemma 4's own (from the model's chat_template.jinja), which
/// training/ also uses: `<|turn>user\n…<turn|>\n<|turn>model\n`. my_me_bot
/// uses Gemma 3's `<start_of_turn>`, which Gemma 4 tolerates but was not
/// trained on.
/// The model is any .gguf in Documents (scripts/push-model.sh puts it there).
final class Gemma {
    private var model: OpaquePointer?
    private var context: OpaquePointer?
    private var vocab: OpaquePointer?

    static func modelURL() -> URL? {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let files = (try? FileManager.default.contentsOfDirectory(at: docs, includingPropertiesForKeys: nil)) ?? []
        // A fine-tuned model over the base one, the deep-prompt one first.
        let ggufs = files.filter { $0.pathExtension == "gguf" }
        return ggufs.first { $0.lastPathComponent.contains("deep") }
            ?? ggufs.first { $0.lastPathComponent.contains("ngate") } ?? ggufs.first
    }

    /// Whether the model on the phone was trained on the deep thread prompt
    /// (ten arguments and their subthreads) or the first one (four comments).
    static var readsDeepThreads: Bool {
        modelURL()?.lastPathComponent.contains("deep") ?? false
    }

    init?(url: URL) {
        llama_backend_init()
        let start = Date()
        var mp = llama_model_default_params()
        mp.use_mmap = true
        mp.n_gpu_layers = 99
        guard let m = llama_model_load_from_file(url.path, mp) else {
            log("gemma: failed to load \(url.lastPathComponent)")
            return nil
        }
        var cp = llama_context_default_params()
        // A thread prompt is up to ~7,000 characters of comments (about 2,000
        // tokens) plus a ~200-token entry.
        cp.n_ctx = 3072
        cp.n_batch = 512
        guard let c = llama_init_from_model(m, cp) else {
            log("gemma: failed to create context")
            llama_model_free(m)
            return nil
        }
        model = m
        context = c
        vocab = llama_model_get_vocab(m)
        log("gemma: loaded \(url.lastPathComponent) in \(String(format: "%.1f", Date().timeIntervalSince(start))) s")
    }

    deinit {
        if let context { llama_free(context) }
        if let model { llama_model_free(model) }
        llama_backend_free()
    }

    /// One user turn in Gemma's template, answered until a stop marker.
    func reply(to user: String, maxTokens: Int = 48, temperature: Float = 0.9) -> String? {
        guard let context, let vocab, let memory = llama_get_memory(context) else { return nil }
        llama_memory_clear(memory, true)
        let prompt = "<|turn>user\n\(user)<turn|>\n<|turn>model\n"
        var tokens = [llama_token](repeating: 0, count: prompt.utf8.count + 1)
        let n = llama_tokenize(vocab, prompt, Int32(prompt.utf8.count), &tokens, Int32(tokens.count), true, true)
        guard n > 0 else { log("gemma: tokenization failed"); return nil }
        tokens = Array(tokens.prefix(Int(n)))

        let sampler = llama_sampler_chain_init(llama_sampler_chain_default_params())
        defer { llama_sampler_free(sampler) }
        llama_sampler_chain_add(sampler, llama_sampler_init_temp(temperature))
        llama_sampler_chain_add(sampler, llama_sampler_init_top_p(0.95, 1))
        llama_sampler_chain_add(sampler, llama_sampler_init_penalties(64, 1.1, 0, 0))
        llama_sampler_chain_add(sampler, llama_sampler_init_dist(UInt32.random(in: 0...UInt32.max)))

        guard tokens.count + maxTokens <= Int(llama_n_ctx(context)) else {
            log("gemma: \(tokens.count)-token prompt does not fit the context")
            return nil
        }
        let start = Date()
        // In n_batch pieces: one llama_decode takes at most that many tokens.
        for i in stride(from: 0, to: tokens.count, by: 512) {
            var chunk = Array(tokens[i..<min(i + 512, tokens.count)])
            guard llama_decode(context, llama_batch_get_one(&chunk, Int32(chunk.count))) == 0 else {
                log("gemma: prompt decode failed at token \(i)")
                return nil
            }
        }
        let prefill = Date().timeIntervalSince(start)
        var out = ""
        var generated = 0
        for _ in 0..<maxTokens {
            var t = llama_sampler_sample(sampler, context, -1)
            if llama_vocab_is_eog(vocab, t) { break }
            if !llama_vocab_is_control(vocab, t) { out += piece(t, vocab) }
            if Self.stops.contains(where: out.contains) || out.contains("\n") { break }
            generated += 1
            guard llama_decode(context, llama_batch_get_one(&t, 1)) == 0 else { break }
        }
        let seconds = Date().timeIntervalSince(start)
        log("gemma: \(tokens.count) prompt tokens in \(String(format: "%.2f", prefill)) s, \(generated) generated in \(String(format: "%.2f", seconds - prefill)) s")
        for marker in Self.stops {
            if let r = out.range(of: marker) { out = String(out[..<r.lowerBound]) }
        }
        return out.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "\"*")))
    }

    /// End of turn, start of turn, and the thinking channel the base model
    /// sometimes opens instead of answering.
    static let stops = ["<turn|>", "<|turn>", "<|channel>"]

    private func piece(_ t: llama_token, _ vocab: OpaquePointer) -> String {
        var buf = [CChar](repeating: 0, count: 256)
        let len = llama_token_to_piece(vocab, t, &buf, Int32(buf.count), 0, false)
        guard len > 0 else { return "" }
        return String(decoding: buf.prefix(Int(len)).map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }
}
