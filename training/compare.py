"""Adapter vs base, old (4 comments) vs deep (10 arguments and their
subthreads) prompts, on held-out stories, beside n-gate's real entry."""
import json, pathlib, sys
from mlx_lm import load, generate
from mlx_lm.sample_utils import make_sampler
import threads, importlib.util

HERE = pathlib.Path(__file__).parent
spec = importlib.util.spec_from_file_location("v1", sys.argv[1])
v1 = importlib.util.module_from_spec(spec); spec.loader.exec_module(v1)
n = int(sys.argv[2]) if len(sys.argv) > 2 else 5

by_title = {json.loads(l)["title"]: json.loads(l) for l in open(HERE / "raw/entries.jsonl", encoding="utf-8")}
valid = [json.loads(l) for l in open(HERE / "data/valid.jsonl", encoding="utf-8")]
picks = []
for r in valid:
    title = r["messages"][0]["content"].split("\n")[0].removeprefix("Hacker News story: ")
    e = by_title.get(title)
    if e and (HERE / f"raw/threads/{e['hn']}.json").exists():
        picks.append(e)
    if len(picks) == n:
        break

model, tok = load(str(HERE / "models/gemma-4-e4b-it-8bit"), adapter_path=str(HERE / "models/ngate-300"))
sampler = make_sampler(temp=0.9, top_p=0.95)
for e in picks:
    thread = threads.fetch(e["hn"])
    print("=" * 80); print(e["title"]); print("REAL:", e["blurb"])
    for name, prompt in [("4 comments", v1.thread_prompt(e["title"], thread)), ("deep", threads.thread_prompt(e["title"], thread))]:
        text = tok.apply_chat_template([{"role": "user", "content": prompt}], add_generation_prompt=True, tokenize=False)
        out = generate(model, tok, text, max_tokens=220, sampler=sampler, verbose=False)
        print(f"-- adapter, {name} ({len(tok.encode(text))} tokens):", out.split("<turn|>")[0].strip())
