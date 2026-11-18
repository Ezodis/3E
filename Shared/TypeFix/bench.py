"""Benchmark a TypeFix model served by llama-server (OpenAI-compatible API).

    python bench.py http://127.0.0.1:8089

Prints each sample's first option, its latency, and a rough word-level similarity to the
intended meaning (accents and case ignored), so models can be compared on the same samples.
"""
import difflib, json, sys, time, unicodedata, urllib.request
from pathlib import Path

HERE = Path(__file__).parent
PROMPT = (HERE / "prompt.txt").read_text(encoding="utf-8")
SCHEMA = {"type": "object", "properties": {"options": {"type": "array", "items": {"type": "string"},
          "minItems": 3, "maxItems": 3}}, "required": ["options"]}


def fold(s):
    s = unicodedata.normalize("NFD", s.lower())
    return "".join(c for c in s if c.isalnum() or c == " ").split()


def message(typed, dictionary):
    if dictionary is None:
        return typed
    from hints import hints
    found = hints(typed, dictionary)
    if not found:
        return typed
    return typed + "\n\nKeyboard hints (likely intended words per typed chunk):\n" + "\n".join(found)


def ask(url, typed, dictionary=None):
    body = {"messages": [{"role": "system", "content": PROMPT}, {"role": "user", "content": message(typed, dictionary)}],
            "temperature": 0.3, "max_tokens": 600,
            "response_format": {"type": "json_object", "schema": SCHEMA},
            "chat_template_kwargs": {"enable_thinking": False}}
    req = urllib.request.Request(url + "/v1/chat/completions", json.dumps(body).encode(),
                                 {"Content-Type": "application/json"})
    t = time.time()
    with urllib.request.urlopen(req, timeout=300) as r:
        reply = json.load(r)
    return json.loads(reply["choices"][0]["message"]["content"])["options"], time.time() - t


def main():
    url = sys.argv[1].rstrip("/")
    dictionary = None
    if "--hints" in sys.argv:
        import os
        sys.path.insert(0, str(HERE))
        from hints import Dictionary
        dictionary = Dictionary(Path(os.environ["LOCALAPPDATA"]) / "3EWindows" / "AI" / "words")
    samples = json.loads((HERE / "samples.json").read_text(encoding="utf-8"))
    total, score = 0.0, 0.0
    for s in samples:
        options, secs = ask(url, s["typed"], dictionary)
        sim = difflib.SequenceMatcher(None, fold(options[0]), fold(s["meaning"])).ratio()
        total += secs
        score += sim
        print(f"{secs:5.1f}s  {sim:.2f}  {options[0]}")
    print(f"average {total/len(samples):.1f}s, similarity {score/len(samples):.2f}")


if __name__ == "__main__":
    main()
