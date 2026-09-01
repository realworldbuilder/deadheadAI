"""Stage 5: AI review digests (optional; needs OPENAI_API_KEY).

Reads the built out/catalog.sqlite for show->recording grouping, pulls
review bodies from cache/metadata/, and asks gpt-4o-mini for a per-show
consensus digest. Results cache under cache/digests/{show_id}.json —
re-run stage4 afterwards to embed them.

The derived rating is deliberately de-inflated: base 2.5, a small boost
for review volume, and a sentiment adjustment — with the arithmetic
stored so the app can show its work.

Usage: python stage5_digests.py [--limit N] [--min-reviews N]
"""
import json
import os
import sqlite3
import sys
import threading
import time
import urllib.request
from concurrent.futures import ThreadPoolExecutor, as_completed

from util import CACHE, OUT, read_json, write_json

WORKERS = 4

MODEL = "gpt-4o-mini"
MAX_REVIEW_CHARS = 24000

PROMPT = """You summarize Grateful Dead concert reviews from archive.org tapers and fans.
Given all reviews for the {date} show at {venue}, produce JSON:
{{"consensus_summary": "2-3 sentences of what fans agree on (performance, not tape quality)",
 "standout_songs": ["Song", ...] (max 5, only songs reviewers repeatedly praise),
 "sentiment": "positive"|"mixed"|"negative",
 "sentiment_adjustment": <float -1.0..2.0, how far fan enthusiasm moves a neutral 2.5 baseline>,
 "rating_rationale": "one sentence explaining the adjustment"}}
Be honest: mixed reviews get mixed sentiment. Do not invent songs not mentioned.

REVIEWS:
{reviews}"""


def review_count_boost(n: int) -> float:
    if n >= 93: return 0.5
    if n >= 46: return 0.4
    if n >= 29: return 0.3
    if n >= 20: return 0.2
    if n >= 5: return 0.1
    return 0.0


def call_openai(key: str, prompt: str) -> dict:
    body = json.dumps({
        "model": MODEL,
        "messages": [{"role": "user", "content": prompt}],
        "response_format": {"type": "json_object"},
        "temperature": 0.2,
    }).encode()
    req = urllib.request.Request(
        "https://api.openai.com/v1/chat/completions", data=body,
        headers={"Authorization": f"Bearer {key}", "Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=120) as resp:
        data = json.load(resp)
    return json.loads(data["choices"][0]["message"]["content"])


def main() -> None:
    key = os.environ.get("OPENAI_API_KEY")
    if not key:
        print("stage5: OPENAI_API_KEY not set, skipping digests")
        return
    args = sys.argv[1:]
    limit = int(args[args.index("--limit") + 1]) if "--limit" in args else None
    min_reviews = int(args[args.index("--min-reviews") + 1]) if "--min-reviews" in args else 3

    db = sqlite3.connect(OUT / "catalog.sqlite")
    shows = db.execute(
        "SELECT show_id, date, venue, total_reviews FROM shows "
        "WHERE total_reviews >= ? ORDER BY total_reviews DESC", (min_reviews,)).fetchall()
    digest_dir = CACHE / "digests"
    digest_dir.mkdir(parents=True, exist_ok=True)

    # Gather review blobs on the main thread (sqlite conn isn't shared).
    jobs = []
    for show_id, date, venue, total_reviews in shows:
        out_path = digest_dir / f"{show_id}.json"
        if out_path.exists():
            continue
        if limit is not None and len(jobs) >= limit:
            break
        idents = [r[0] for r in db.execute(
            "SELECT identifier FROM recordings WHERE show_id=? ORDER BY quality_score DESC",
            (show_id,))]
        texts = []
        for ident in idents:
            p = CACHE / "metadata" / f"{ident}.json"
            if not p.exists():
                continue
            for r in read_json(p).get("reviews", []):
                body = (r.get("reviewbody") or "").strip()
                if body:
                    texts.append(f"[{r.get('stars', '?')}/5] {body}")
        blob = "\n---\n".join(texts)[:MAX_REVIEW_CHARS]
        if blob:
            jobs.append((show_id, date, venue, total_reviews, blob, out_path))

    done = 0
    done_lock = threading.Lock()

    def digest(job):
        show_id, date, venue, total_reviews, blob, out_path = job
        result = call_openai(key, PROMPT.format(date=date, venue=venue or "?", reviews=blob))
        adj = max(-1.0, min(2.0, float(result.get("sentiment_adjustment", 0))))
        boost = review_count_boost(total_reviews)
        derived = max(1.0, min(5.0, 2.5 + boost + adj))
        write_json(out_path, {
            "consensus_summary": result["consensus_summary"],
            "standout_songs": result.get("standout_songs", [])[:5],
            "sentiment": result.get("sentiment", "mixed"),
            "derived_rating": round(derived, 1),
            "rating_rationale": (
                f"2.5 base + {boost} for {total_reviews} reviews "
                f"+ {adj} sentiment: {result.get('rating_rationale', '')}"),
            "model": MODEL,
            "generated_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        })

    with ThreadPoolExecutor(max_workers=WORKERS) as pool:
        futures = {pool.submit(digest, job): job[0] for job in jobs}
        for future in as_completed(futures):
            try:
                future.result()
                with done_lock:
                    done += 1
                    if done % 50 == 0:
                        print(f"stage5: {done}/{len(jobs)}", file=sys.stderr)
            except Exception as e:  # noqa: BLE001
                print(f"stage5: FAILED {futures[future]}: {e}", file=sys.stderr)
    print(f"stage5: wrote {done} new digests")


if __name__ == "__main__":
    main()
