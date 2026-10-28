"""Crawls n-gate.com's webshit weekly archive (2016-2021) into training/raw/.

One request per second, each page fetched once (re-runs skip what exists).
Output: raw/entries.jsonl, one {"title", "date", "hn", "url", "blurb"} per story.
"""
import html, json, pathlib, re, sys, time, urllib.request

BASE = "http://n-gate.com"
RAW = pathlib.Path(__file__).parent / "raw"
PAGES = RAW / "pages"
PAGES.mkdir(parents=True, exist_ok=True)

def get(path):
    cached = PAGES / (path.strip("/").replace("/", "_") or "index")
    if cached.exists():
        return cached.read_text(encoding="utf-8")
    time.sleep(1)
    req = urllib.request.Request(BASE + path, headers={"User-Agent": "backtalk-personal-lora/0.1"})
    with urllib.request.urlopen(req, timeout=30) as r:
        text = r.read().decode("utf-8", "replace")
    cached.write_text(text, encoding="utf-8")
    return text

def links(text, pattern):
    return sorted(set(re.findall(r'href="(' + pattern + ')"', text)))

def text_of(fragment):
    return html.unescape(re.sub(r"<[^>]+>", "", fragment)).strip()

ENTRY = re.compile(
    r'<span class="storylink"><a href="([^"]*)">(.*?)</a></span><br>\s*'
    r'<span class="smalldate">(.*?)</span>\s*'
    r'<span class="small"><a href="[^"]*item\?id=(\d+)">\(comments\)</a></span><br>\s*'
    r'(.*?)</p>', re.S)

issues = []
for year in range(2016, 2022):
    for month in links(get(f"/hackernews/{year}/"), rf"/hackernews/{year}/\d\d/"):
        # Month pages link to day pages; a day page may link numbered sub-issues.
        for day in links(get(month), rf"/hackernews/{year}/\d\d/\d\d/"):
            issues.append(day)
            issues += links(get(day), rf"/hackernews/{year}/\d\d/\d\d/\d+/")
issues = sorted(set(issues))
print(f"{len(issues)} issues", file=sys.stderr)

entries, seen = [], set()
for i, path in enumerate(issues):
    for url, title, date, hn, blurb in ENTRY.findall(get(path)):
        if hn in seen:
            continue
        seen.add(hn)
        entries.append({"title": text_of(title), "date": text_of(date), "hn": hn,
                        "url": html.unescape(url), "blurb": " ".join(text_of(blurb).split())})
    if i % 25 == 0:
        print(f"{i}/{len(issues)} issues, {len(entries)} entries", file=sys.stderr)

with open(RAW / "entries.jsonl", "w", encoding="utf-8") as f:
    for e in entries:
        f.write(json.dumps(e, ensure_ascii=False) + "\n")
print(f"wrote {len(entries)} entries from {len(issues)} issues", file=sys.stderr)
