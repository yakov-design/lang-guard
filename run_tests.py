"""Run every check in the repo.

    python run_tests.py            every check
    python run_tests.py lease      only the files with "lease" in their name
    python run_tests.py --real     also the checks that need Yakov's real data

The checks are FOUND, not listed: every test_*.py in the repo's folder and one folder down
runs, so adding a check edits neither a shared list nor .github/workflows/tests.yml (which
just runs this file). A .py file with "test" in its name that matches neither pattern fails
the run, so a check can't go unrun by being misnamed.

A check that needs Yakov's real data (files or databases that only exist on his PC) says so
with a line `# runner: needs-real-data`; it is skipped, by name, unless --real is given.
"""
import ast, fnmatch, os, re, subprocess, sys, time

ROOT = os.path.dirname(os.path.abspath(__file__))
PATTERNS = ("test_*.py", "*/test_*.py")
SKIP_DIRS = {".git", "__pycache__", "node_modules", "venv", ".venv", "env"}
REAL_MARK = "# runner: needs-real-data"


def found():
    """Every .py with "test" in its name, as (relative path, matches a pattern)."""
    out = []
    for folder, dirs, files in os.walk(ROOT):
        dirs[:] = sorted(d for d in dirs if d not in SKIP_DIRS and not d.startswith("."))
        for name in sorted(files):
            if (name.endswith(".py") and "test" in name.lower()
                    and os.path.join(folder, name) != os.path.abspath(__file__)):
                rel = os.path.relpath(os.path.join(folder, name), ROOT).replace(os.sep, "/")
                matches = any(fnmatch.fnmatch(rel, p) and rel.count("/") == p.count("/")
                              for p in PATTERNS)
                out.append((rel, matches))
    return out


def label(path):
    """The first line of the file's own docstring says what it checks."""
    try:
        doc = ast.get_docstring(ast.parse(open(path, encoding="utf-8").read())) or ""
    except Exception:
        doc = ""
    line = doc.strip().splitlines()[0].strip() if doc.strip() else os.path.basename(path)
    return line if len(line) <= 70 else line[:69] + "…"


def main(argv):
    real = "--real" in argv
    only = [a for a in argv if not a.startswith("--")]
    files = found()
    stray = [rel for rel, ok in files if not ok]
    run_these = [rel for rel, ok in files if ok and (not only or any(o in rel for o in only))]

    passed = failed = 0
    broken, skipped = [], []
    start = time.time()
    for rel in run_these:
        path = os.path.join(ROOT, rel)
        if REAL_MARK in open(path, encoding="utf-8", errors="replace").read() and not real:
            skipped.append(rel)
            continue
        run = subprocess.run([sys.executable, os.path.basename(path)], capture_output=True,
                             text=True, cwd=os.path.dirname(path))
        lines = (run.stdout or "").splitlines()
        # House styles: "PASS"/"FAIL" at the start of the line, or "  ok   "/"  FAIL ".
        ok = sum(1 for line in lines if line.startswith("PASS") or line.startswith("  ok "))
        no = [line.strip() for line in lines if line.startswith("FAIL") or line.startswith("  FAIL ")]
        if not ok:      # a third style only sums up: "24 passed, 0 failed" or unittest's "Ran 5 tests"
            said = re.search(r"(\d+) passed|Ran (\d+) tests?", run.stdout + run.stderr)
            ok = int(said.group(1) or said.group(2)) if said and run.returncode == 0 else 0
        passed += ok
        failed += len(no)
        mark = "ok " if not no and run.returncode == 0 else "!! "
        print(f"  {mark} {rel:<44} {ok:>4} checks  {label(path)}")
        for line in no:
            print(f"        {line}")
        if run.returncode != 0 and not no:
            tail = ((run.stderr or "").strip() or (run.stdout or "").strip()).splitlines()[-1:]
            broken.append((rel, tail or ["no output"]))

    print(f"\n{passed} checks passed, {failed} failed, in {time.time() - start:.0f}s")
    for rel, why in broken:
        print(f"  {rel} did not finish: {why[0]}")
    for rel in skipped:
        print(f"  {rel} skipped: needs the real data on Yakov's PC (run with --real)")
    for rel in stray:
        print(f"  {rel} is never run: name a check test_*.py, at the top or one folder down")
    return 1 if failed or broken or stray else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
