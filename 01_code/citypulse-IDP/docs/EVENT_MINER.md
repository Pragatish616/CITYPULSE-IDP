# Event miner: operator and labelling guide (ADR-030)

Written 8 October 2026. **The miner has not been evaluated.** Its accuracy is unknown until the labelled test in section 4 is run.
Nothing it produces reaches routes, the belief or travellers.

## 1. What it does

You paste a post or a news paragraph about Chennai rain (English or Tamil). A small model running on this laptop lists the
street-level events it states, each with a word-for-word quote. The code drops any event whose quote is not in the text, or whose
place is not in the quoted sentence. The place is then matched only to the project's gazetteer (661 OSM places and 186 named
candidate sites), or left as "no match". Every event waits for a person to accept, reject or correct it. Accepted events can be
exported as a CSV dataset.

| Condition | Means |
|---|---|
| `closed` | traffic stopped, diverted, barricaded; road or subway closed or not motorable |
| `cleared` | water drained or receded; traffic restored; reopened |
| `flooded` | water on the road, without saying traffic is stopped |
| `unknown` | the place is mentioned in a rain context but its condition is not stated |

Rainfall readings at a station ("Nungambakkam recorded 9 cm") are not events.

## 2. Setting up (once)

- Ollama running locally, with the two models: `ollama pull qwen3.5:0.8b` (about 1.3 GB, Apache 2.0) and
  `nomic-embed-text` (274 MB, Apache 2.0). Both were installed on the authoring laptop on 8 October 2026.
- From `01_code/citypulse-IDP`, with the project's virtual environment: `python -m ml.event_miner check`.
- The first item that needs place matching builds the place embeddings (one item that included the build took 116 seconds on the authoring laptop), cached in
  `data/miner/gazetteer_embeddings.npz`.
- Measured on the authoring laptop (GTX 1650 4 GB, 7.4 GB RAM): the model runs fully on the GPU (560 MB) and a short item takes
  2 to 7 seconds once warm.

Settings: `OLLAMA_URL` (default `http://127.0.0.1:11434`), `MINER_MODEL`, `MINER_EMBED_MODEL`, `MINER_DIR` (default
`data/miner`; point it elsewhere for trial runs so they stay out of the real review queue).

## 3. Daily use

```bash
python -m ml.event_miner mine --text-file post.txt --source "Greater Chennai Traffic Police (pasted)" --url https://... --published 2023-12-04T10:00+05:30
python -m ml.event_miner pending
python -m ml.event_miner places "ganesapuram"
python -m ml.event_miner decide ITEM_ID 0 accept --reviewer v01
python -m ml.event_miner decide ITEM_ID 0 correct --place place:perambur --condition closed --reviewer v01 --note "subway, not the road"
python -m ml.event_miner decide ITEM_ID 1 reject --reviewer v01 --note "rain reading, not a road"
python -m ml.event_miner export --out exports/miner.csv
```

- **Sources.** Paste only what you may read. Do not scrape any site or platform. An automatic feed (a newspaper's RSS, for
  example) needs the owner's go-ahead and a check of its terms first; none is built.
- **Publication time** is the time the source published it, with the zone (`+05:30`), not the time you pasted it.
- **Review rule.** Accept only if the quote says it and the place is right. When the place is a subway or street not in the
  gazetteer, correct the place to the area that contains it, or to `none`. A later decision replaces an earlier one; nothing is
  erased.
- **Duplicates.** The same place, condition and source within 6 hours is marked `DUPLICATE`; review it like any other.
- **Privacy.** `data/miner/` and exports hold source text and quotes. They are git-ignored; never commit or publish them.

## 4. The evaluation (pre-registered in ADR-030; nothing run yet)

1. Collect at least 100 real items about Chennai rain, any year, from sources you may read: official posts, news paragraphs. Aim
   for at least 30 in Tamil and at least 20 with no street event. **Do not use** the development sentences listed in ADR-030.
2. **Label before running the miner on them.** One JSON line per item in `data/miner/labels.jsonl` (git-ignored):

   ```json
   {"text": "…", "source_name": "…", "source_url": "…", "published_at": "2023-12-04T10:00+05:30", "language": "en", "labeller": "v01",
    "events": [{"place_id": "place:perambur", "place_text": "Perambur subway", "condition": "closed", "time_stated": true}]}
   ```

   - one entry per street event the text states; `[]` if none;
   - `place_id`: the most specific gazetteer entry that is the place or contains it (look it up with `places`), or `null` with
     the place text when nothing fits;
   - a second person labels every fifth item independently, adding `"second_labeller"` and `"second_events"`.
3. Run `python -m ml.event_miner evaluate --labels data/miner/labels.jsonl`. It writes the numbers (no text) to
   `data/results/<date>-event-miner-eval/result.json` and the detail with quotes to `data/miner/eval/` (git-ignored).
4. Record the result in ADR-030, whatever it is. The bar: precision at least 0.7 and recall at least 0.6, per language, for "useful
   for suggestions". Nothing skips review either way.
