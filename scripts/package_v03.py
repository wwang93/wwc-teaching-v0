"""Create a portable release from the validated runtime manifest plus named support files."""
import hashlib
import json
import runpy
import zipfile
from pathlib import Path

root = Path(__file__).resolve().parents[1]
runpy.run_path(str(root / "tests/validate_bundle.py"))
manifest = json.loads((root / "manifest.json").read_text(encoding="utf-8"))
extra = ["manifest.json", "README.md", "DEPLOYMENT.md", "VALIDATION.md", "V0-design.md",
         "install.R", ".Renviron.example", ".gitignore", ".rscignore",
         "scripts/preflight.R", "scripts/live_smoke.R", "scripts/build_manifest.R",
         "scripts/package_v03.py", "deploy/supabase.sql", "deploy/analysis-queries.sql",
         "tests/check.R", "tests/check_v03.R", "tests/check_async.R", "tests/check_ai_errors.R", "tests/check_supabase_auth.R", "tests/validate_bundle.py"]
files = sorted(set(manifest["files"]) | set(extra))
destination = root.parent / "outputs" / "WWC_V0_3_1_2026-09-08.zip"
destination.parent.mkdir(exist_ok=True)
with zipfile.ZipFile(destination, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=6) as bundle:
    for name in files:
        assert not name.startswith(("private/", ".r-library/", "reviews/", "rsconnect/"))
        assert Path(name).name not in (".Renviron", ".env")
        bundle.write(root / name, arcname="wwc-v0-shiny/" + name)
with zipfile.ZipFile(destination) as bundle:
    assert bundle.testzip() is None
    assert len(bundle.namelist()) == len(files)
digest = hashlib.sha256(destination.read_bytes()).hexdigest()
destination.with_suffix(".sha256").write_text(digest + "  " + destination.name + "\n", encoding="ascii")
print(f"Created {destination.name}: {len(files)} files, {destination.stat().st_size / 1024**2:.1f} MiB. ZIP integrity passed.")
print(f"SHA-256: {digest}")
