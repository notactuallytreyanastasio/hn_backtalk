"""raw/entries.jsonl -> data/{train,valid}.jsonl in mlx_lm's chat format.

The user turn is thread_prompt() (threads.py), which App/Thread.swift mirrors, so the
trained model sees the same input on the phone. mask_prompt in lora.yaml
trains only on the n-gate paragraph.
"""
import json, pathlib, random
from threads import fetch, thread_prompt

HERE = pathlib.Path(__file__).parent

entries = [json.loads(l) for l in open(HERE / "raw/entries.jsonl", encoding="utf-8")]
seen, rows = set(), []
for e in entries:
    if not e["blurb"] or e["hn"] in seen:
        continue
    seen.add(e["hn"])
    rows.append({"messages": [
        {"role": "user", "content": thread_prompt(e["title"], fetch(e["hn"]))},
        {"role": "assistant", "content": e["blurb"]},
    ]})
random.Random(4).shuffle(rows)
n_valid = max(1, len(rows) // 20)
out = HERE / "data"
out.mkdir(exist_ok=True)
for name, part in [("valid", rows[:n_valid]), ("train", rows[n_valid:])]:
    with open(out / f"{name}.jsonl", "w", encoding="utf-8") as f:
        for r in part:
            f.write(json.dumps(r, ensure_ascii=False) + "\n")
    print(name, len(part))
words = sorted(len(r["messages"][1]["content"].split()) for r in rows)
print("blurb words: median", words[len(words) // 2], "p95", words[int(len(words) * .95)])
