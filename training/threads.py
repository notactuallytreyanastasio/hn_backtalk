"""Fetches each n-gate entry's Hacker News thread from the Algolia HN API
into raw/threads/<id>.json (cached; 4 at a time, well under Algolia's 10k/hour). The app reads live
threads from the same API, and thread_prompt() below is mirrored exactly by
App/Thread.swift, so the model sees the same input in training and on the phone.
"""
import html, json, pathlib, re, sys, time, urllib.request

HERE = pathlib.Path(__file__).parent
THREADS = HERE / "raw/threads"
TOP_COMMENTS = 10    # top-level comments, biggest reply trees first
COMMENT_CHARS = 220  # each comment is clipped to this
PROMPT_CHARS = 7000  # all comment lines together, about 1,800 tokens

def fetch(hn_id):
    path = THREADS / f"{hn_id}.json"
    if path.exists():
        return json.loads(path.read_text())
    time.sleep(0.2)
    req = urllib.request.Request(f"https://hn.algolia.com/api/v1/items/{hn_id}",
                                 headers={"User-Agent": "backtalk-personal-lora/0.1"})
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            data = json.loads(r.read())
    except Exception as e:
        print(f"{hn_id}: {e}", file=sys.stderr)
        return None
    path.write_text(json.dumps(data))
    return data

def plain(text):
    text = re.sub(r"<p>", " ", text or "")
    text = html.unescape(re.sub(r"<[^>]+>", "", text))
    return " ".join(text.split())

def size(c):
    return 1 + sum(size(k) for k in c.get("children") or [])

def clip(text):
    if len(text) <= COMMENT_CHARS:
        return text
    cut = text[:COMMENT_CHARS]
    return cut[:cut.rfind(" ")] + "…" if " " in cut else cut + "…"

def comment_lines(c, depth):
    """A comment and its replies, depth first, biggest reply tree first, each
    reply indented two spaces deeper than what it answers."""
    if not c.get("author") or not c.get("text"):
        return
    yield c, "  " * depth + f"{c['author']}: {clip(plain(c['text']))}"
    for k in sorted(c.get("children") or [], key=size, reverse=True):
        yield from comment_lines(k, depth + 1)

def thread_prompt(title, thread):
    """The ten biggest arguments, each followed down its subthreads as far as
    its share of PROMPT_CHARS goes. Shares roll over: a short argument leaves
    room for the next. A reply that doesn't fit is left out with its replies,
    so nothing appears without what it answers."""
    tops = [c for c in (thread or {}).get("children") or [] if c.get("author") and c.get("text")]
    tops.sort(key=size, reverse=True)
    lines, used = [], 0
    for i, top in enumerate(tops[:TOP_COMMENTS]):
        budget = PROMPT_CHARS * (i + 1) // TOP_COMMENTS
        skip = None
        for c, line in comment_lines(top, 0):
            depth = (len(line) - len(line.lstrip(" "))) // 2
            if skip is not None and depth > skip:
                continue
            skip = None
            if c is not top and used + len(line) + 1 > budget:
                skip = depth
                continue
            lines.append(line)
            used += len(line) + 1
    return (f"Hacker News story: {title}\nComments:\n" + "\n".join(lines) +
            "\n\nWrite the n-gate.com webshit weekly entry for this story.")

if __name__ == "__main__":
    THREADS.mkdir(parents=True, exist_ok=True)
    entries = [json.loads(l) for l in open(HERE / "raw/entries.jsonl", encoding="utf-8")]
    from concurrent.futures import ThreadPoolExecutor
    with ThreadPoolExecutor(4) as pool:
        for i, _ in enumerate(pool.map(lambda e: fetch(e["hn"]), entries)):
            if i % 200 == 0:
                print(f"{i}/{len(entries)}", file=sys.stderr)
    print("done", file=sys.stderr)
