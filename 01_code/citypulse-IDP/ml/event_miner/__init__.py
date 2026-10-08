"""Event miner (ADR-030, PLAN.md M3.4): official posts and news text in, reviewed street events out.

Every event the model reports must quote its source word for word, its place is chosen only from the project's gazetteer, and
nothing leaves the review queue without a person. Accepted events are a dataset; they do not reach the router.
See docs/EVENT_MINER.md for how to run it.
"""

PROMPT_VERSION = "miner-prompt-v2"
