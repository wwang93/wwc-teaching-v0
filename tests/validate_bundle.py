"""Validate compiled corpus and the actual Posit runtime manifest, without network."""
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
corpus = json.loads((ROOT / "data/actions.json").read_text(encoding="utf-8"))
catalog = json.loads((ROOT / "data/catalog.json").read_text(encoding="utf-8"))
passages = json.loads((ROOT / "data/passages.json").read_text(encoding="utf-8"))
guides = {g["guide_id"]: g for g in corpus["guides"]}
actions = {a["action_id"]: a for a in corpus["actions"]}
pages = {p["source_id"]: p for p in passages}
assert len(guides) == 30 and len(actions) == 165 and len(pages) == len(passages) == 1161
assert sum(len(a["steps"]) for a in actions.values()) == 600
assert corpus["human_review_completed"] is False
assert len(catalog["documents"]) == 33
for g in catalog["documents"]:
    path = ROOT / "www/sources" / g["source_filename"]
    assert path.is_file()
    assert hashlib.sha256(path.read_bytes()).hexdigest() == g["sha256"], path.name
for a in actions.values():
    assert a["review_status"] == "needs_review"
    assert a["guide_id"] in guides
    assert a["evidence_source_id"] in pages
    if a["parent_id"]:
        assert actions[a["parent_id"]]["guide_id"] == a["guide_id"]
    locators = {p["source_id"]: p for p in a["locators"]}
    for sid in a["page_ids"]:
        assert pages[sid]["guide_id"] == a["guide_id"]
    for step in a["steps"]:
        assert step["source_ids"]
        for sid in step["source_ids"]:
            p = locators.get(sid) or pages.get(sid)
            assert p and p["text"].strip(), (a["action_id"], sid)
            assert 1 <= p["pdf_page"] <= guides[a["guide_id"]]["page_count"]

manifest = json.loads((ROOT / "manifest.json").read_text(encoding="utf-8"))
for name, entry in manifest["files"].items():
    p = ROOT / name
    assert p.is_file(), f"Missing manifest file: {name}"
    assert not any(x in p.parts for x in ("private", ".r-library", "reviews", "rsconnect"))
    assert p.name not in (".Renviron", ".env")
    assert hashlib.md5(p.read_bytes()).hexdigest() == entry["checksum"], f"Stale manifest: {name}"
print(f"PASS: 33 PDF hashes, 30 guides, 165 actions, 600 components, 1,161 source pages; {len(manifest['files'])} manifest file checksums and release exclusions.")
