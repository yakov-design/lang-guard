# -*- coding: utf-8 -*-
"""Open PRs are brought up to date by themselves after a merge.

.github/update_open_prs.py runs on a throwaway repo with four PR branches: one with notes-only
"conflicts" (wireframe and DEPLOY-LEDGER, merged keeping both sides, even on a branch cut before
.gitattributes existed), one with a real code conflict (left alone, one comment naming the file),
one already current, one from a fork. GitHub is faked; nothing leaves the machine.

  python test_update_open_prs.py
"""
import importlib.util, os, subprocess, sys, tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
out = []


def check(name, ok, detail=""):
    out.append(bool(ok))
    print(("  ok   " if ok else "  FAIL ") + name + (f" - {detail}" if detail else ""))


def sh(cwd, *args):
    p = subprocess.run(["git", *args], cwd=cwd, capture_output=True, text=True)
    if p.returncode:
        raise RuntimeError(p.stderr)
    return p.stdout.strip()


def write(cwd, name, text):
    with open(os.path.join(cwd, name), "w") as f:
        f.write(text)


def commit(cwd, msg):
    sh(cwd, "add", "-A")
    sh(cwd, "-c", "user.name=t", "-c", "user.email=t@t", "commit", "-q", "-m", msg)


spec = importlib.util.spec_from_file_location("upd", os.path.join(HERE, ".github", "update_open_prs.py"))
upd = importlib.util.module_from_spec(spec)
spec.loader.exec_module(upd)

tmp = tempfile.mkdtemp(prefix="update-prs-")
remote, work, run = (os.path.join(tmp, d) for d in ("remote.git", "work", "run"))
sh(tmp, "init", "-q", "--bare", "-b", "base", remote)
sh(tmp, "clone", "-q", remote, work)
sh(work, "checkout", "-q", "-b", "base")

# The base before .gitattributes: a branch cut here merges the old way unless the run fixes it.
write(work, "PROJECT-WIREFRAME.md", "# Wireframe\n\n## Done\n- slice 1\n")
write(work, "DEPLOY-LEDGER.md", "## Waiting to push\n- slice 1\n")
write(work, "app.py", "PRICE = 100\n")
commit(work, "start")
sh(work, "push", "-q", "origin", "base")
sh(work, "checkout", "-q", "-b", "old-notes")
write(work, "PROJECT-WIREFRAME.md", "# Wireframe\n\n## Done\n- slice 1\n- slice 3 (old branch)\n")
write(work, "old.py", "OLD = 1\n")
commit(work, "slice 3")
sh(work, "push", "-q", "origin", "old-notes")

sh(work, "checkout", "-q", "base")
write(work, ".gitattributes", "# notes\nPROJECT-WIREFRAME.md merge=union\nDEPLOY-LEDGER.md merge=union\n")
commit(work, "notes keep both sides")
sh(work, "push", "-q", "origin", "base")

def branch(name, files):
    sh(work, "checkout", "-q", "-b", name, "base")
    for k, v in files.items():
        write(work, k, v)
    commit(work, name)
    sh(work, "push", "-q", "origin", name)
    sh(work, "checkout", "-q", "base")

branch("notes", {"PROJECT-WIREFRAME.md": "# Wireframe\n\n## Done\n- slice 1\n- slice 4\n",
                 "DEPLOY-LEDGER.md": "## Waiting to push\n- slice 4\n- slice 1\n", "four.py": "X = 4\n"})
branch("clash", {"app.py": "PRICE = 150\n"})
branch("current", {"cur.py": "C = 1\n"})

# The merge that starts the run: another PR lands on the base.
write(work, "PROJECT-WIREFRAME.md", "# Wireframe\n\n## Done\n- slice 1\n- slice 2\n")
write(work, "DEPLOY-LEDGER.md", "## Waiting to push\n- slice 2\n- slice 1\n")
write(work, "app.py", "PRICE = 120\n")
commit(work, "slice 2 merged")
sh(work, "push", "-q", "origin", "base")
sh(work, "checkout", "-q", "-b", "current2", "base")  # 'current' re-cut on the new base
write(work, "cur.py", "C = 1\n")
commit(work, "current")
sh(work, "push", "-q", "-f", "origin", "current2:current")

tips = {b: sh(remote, "rev-parse", b) for b in ("old-notes", "notes", "clash", "current")}


class FakeGitHub:
    comments_by_pr, posted, dispatched = {}, [], []

    def __init__(self, repo, token):
        pass

    def open_prs(self, base):
        def pr(n, ref, repo="o/r"):
            return {"number": n, "head": {"ref": ref, "sha": tips.get(ref, "f" * 40),
                                          "repo": {"full_name": repo}}}
        return [pr(1, "old-notes"), pr(2, "notes"), pr(3, "clash"), pr(4, "current"),
                pr(5, "fork-branch", "someone/r")]

    def comments(self, n):
        return self.comments_by_pr.get(n, [])

    def comment(self, n, body):
        self.posted.append((n, body))
        self.comments_by_pr.setdefault(n, []).append({"body": body})

    def dispatch(self, wf, ref):
        self.dispatched.append((wf, ref))


upd.GitHub = FakeGitHub
sh(tmp, "clone", "-q", remote, run)
for k in ("user.name", "user.email"):
    sh(run, "config", k, "bot")
os.environ.update(GITHUB_REPOSITORY="o/r", GITHUB_TOKEN="x", DISPATCH_WORKFLOW="tests.yml")
os.chdir(run)
code = upd.main(["update_open_prs.py", "base"])
check("the run finishes without a failure", code == 0, code)

for b in ("old-notes", "notes"):
    tip = sh(remote, "rev-parse", b)
    parents = sh(remote, "rev-list", "--parents", "-n1", b).split()[1:]
    check(f"{b}: base merged in with a merge commit on top of the PR's own work (no rebase)",
          tip != tips[b] and len(parents) == 2 and parents[0] == tips[b], parents)
    wf = sh(remote, "show", f"{b}:PROJECT-WIREFRAME.md")
    check(f"{b}: the wireframe keeps both sides", "slice 2" in wf and ("slice 4" in wf or "slice 3" in wf), wf)
check("notes: DEPLOY-LEDGER keeps both waiting entries",
      all(s in sh(remote, "show", "notes:DEPLOY-LEDGER.md") for s in ("slice 2", "slice 4")))
check("notes: the base's code change came in too", sh(remote, "show", "notes:app.py") == "PRICE = 120")
check("old branch (cut before .gitattributes): merged the same way",
      "slice 3 (old branch)" in sh(remote, "show", "old-notes:PROJECT-WIREFRAME.md"))
check("clash: a real conflict leaves the branch exactly as it was", sh(remote, "rev-parse", "clash") == tips["clash"])
clash_notes = [b for n, b in FakeGitHub.posted if n == 3]
check("clash: one comment on the PR naming the file", len(clash_notes) == 1 and "`app.py`" in clash_notes[0],
      clash_notes)
check("the notes files are never named as a conflict", not any("WIREFRAME" in b or "LEDGER" in b
                                                              for _n, b in FakeGitHub.posted))
check("current: an up-to-date branch is not touched", sh(remote, "rev-parse", "current") == tips["current"])
check("only the two pushed branches get the tests started",
      sorted(r for _w, r in FakeGitHub.dispatched) == ["notes", "old-notes"], FakeGitHub.dispatched)
check("no comment on the PRs that merged cleanly or the fork", {n for n, _b in FakeGitHub.posted} == {3})

FakeGitHub.dispatched.clear()
code = upd.main(["update_open_prs.py", "base"])
check("a second run changes nothing and does not comment again",
      code == 0 and len(FakeGitHub.posted) == 1 and not FakeGitHub.dispatched, FakeGitHub.posted)

print(f"\n{sum(out)} of {len(out)} checks passed")
sys.exit(0 if all(out) else 1)
