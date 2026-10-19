"""Bring every open pull request up to date after its base branch moves.

Run by .github/workflows/update-open-prs.yml on each push to a base branch. For every open PR
into that branch (drafts too, forks skipped) it merges the base into the PR's branch with a merge
commit and pushes. Never a rebase, never a force-push, so a thread's own checkout stays valid
(it pulls before its next push).

    python .github/update_open_prs.py <base branch>

The notes files merge with both sides kept: the base branch's .gitattributes `merge=union` lines
are copied into .git/info/attributes first, so a branch cut before .gitattributes existed merges
the same way. A real conflict leaves the branch untouched and posts one comment on the PR naming
the files (once per PR head and file list, not on every run).

Environment: GITHUB_REPOSITORY, GITHUB_TOKEN (for the API), DISPATCH_WORKFLOW (optional: a
workflow file to start on the PR branch after a push, because a push made with the workflow's
own token starts no other workflow).
"""
import hashlib, json, os, subprocess, sys, urllib.error, urllib.request

MARK = "<!-- update-open-prs:"
API = os.environ.get("GITHUB_API_URL", "https://api.github.com")


def git(*args, check=True):
    p = subprocess.run(["git", *args], capture_output=True, text=True)
    if check and p.returncode:
        raise RuntimeError(f"git {' '.join(args)} failed: {p.stderr.strip() or p.stdout.strip()}")
    return p


class GitHub:
    def __init__(self, repo, token):
        self.repo, self.token = repo, token

    def call(self, method, path, body=None):
        req = urllib.request.Request(
            f"{API}/repos/{self.repo}{path}", method=method,
            data=None if body is None else json.dumps(body).encode(),
            headers={"Authorization": f"Bearer {self.token}",
                     "Accept": "application/vnd.github+json",
                     "X-GitHub-Api-Version": "2022-11-28",
                     "User-Agent": "update-open-prs"})
        with urllib.request.urlopen(req, timeout=30) as r:
            raw = r.read()
        return json.loads(raw) if raw else None

    def open_prs(self, base):
        out, page = [], 1
        while True:
            batch = self.call("GET", f"/pulls?state=open&base={base}&per_page=100&page={page}")
            out += batch
            if len(batch) < 100:
                return out
            page += 1

    def comments(self, number):
        return self.call("GET", f"/issues/{number}/comments?per_page=100")

    def comment(self, number, body):
        self.call("POST", f"/issues/{number}/comments", {"body": body})

    def dispatch(self, workflow, ref):
        self.call("POST", f"/actions/workflows/{workflow}/dispatches", {"ref": ref})


def union_attributes(base):
    """The base branch's merge=union lines, applied whatever the PR branch carries."""
    shown = git("show", f"origin/{base}:.gitattributes", check=False)
    lines = [l for l in shown.stdout.splitlines() if "merge=union" in l and not l.startswith("#")]
    info = os.path.join(git("rev-parse", "--git-dir").stdout.strip(), "info")
    os.makedirs(info, exist_ok=True)
    with open(os.path.join(info, "attributes"), "w") as f:
        f.write("\n".join(lines) + "\n")
    return lines


def update_one(pr, base):
    """Merge origin/<base> into the PR branch. Returns ("current"|"merged"|"conflict", files)."""
    head = pr["head"]["ref"]
    git("fetch", "--quiet", "origin", f"+refs/heads/{head}:refs/remotes/origin/{head}")
    if git("merge-base", "--is-ancestor", f"origin/{base}", f"origin/{head}", check=False).returncode == 0:
        return "current", []
    git("checkout", "--quiet", "--detach", f"origin/{head}")
    merged = git("merge", "--no-ff", "--no-edit", "-m",
                 f"Merge {base} into {head} (kept up to date automatically)",
                 f"origin/{base}", check=False)
    if merged.returncode:
        files = git("diff", "--name-only", "--diff-filter=U").stdout.split()
        git("merge", "--abort", check=False)
        git("reset", "--quiet", "--hard", check=False)
        if not files:
            raise RuntimeError(merged.stderr.strip() or merged.stdout.strip())
        return "conflict", files
    return "merged", []


def conflict_note(pr, base, files):
    key = hashlib.sha1(("\n".join([pr["head"]["sha"], *files])).encode()).hexdigest()[:12]
    listed = "\n".join(f"- `{f}`" for f in files)
    body = (f"{MARK}{key} -->\n"
            f"**This branch could not be brought up to date with `{base}` automatically.** "
            f"The same lines changed on both sides in:\n\n{listed}\n\n"
            f"The branch was left as it was. Merge `{base}` into it by hand, keep both sides' "
            f"intent, run the tests and push; the next merge into `{base}` updates it "
            f"automatically again.\n\n---\n_Posted by the update-open-prs workflow_")
    return key, body


def workflow_note(pr, base):
    key = "wf-" + pr["head"]["sha"][:12]
    body = (f"{MARK}{key} -->\n"
            f"**This branch could not be brought up to date with `{base}` automatically.** "
            f"`{base}` changed a file under `.github/workflows/`, and GitHub does not let the "
            f"workflow's own token push workflow files. The merge itself is clean: merge `{base}` "
            f"into this branch by hand once and push.\n\n---\n_Posted by the update-open-prs workflow_")
    return key, body


def main(argv):
    base = argv[1]
    repo, token = os.environ["GITHUB_REPOSITORY"], os.environ["GITHUB_TOKEN"]
    dispatch = os.environ.get("DISPATCH_WORKFLOW", "").strip()
    gh = GitHub(repo, token)
    git("fetch", "--quiet", "origin", f"+refs/heads/{base}:refs/remotes/origin/{base}")
    print("union-merged files:", ", ".join(l.split()[0] for l in union_attributes(base)) or "none")
    failed = 0
    for pr in gh.open_prs(base):
        n, head = pr["number"], pr["head"]["ref"]
        if (pr["head"].get("repo") or {}).get("full_name") != repo:
            print(f"#{n}: from a fork, skipped")
            continue
        try:
            state, files = update_one(pr, base)
            if state == "current":
                print(f"#{n} {head}: already up to date")
            elif state == "conflict":
                key, body = conflict_note(pr, base, files)
                if any(f"{MARK}{key}" in (c.get("body") or "") for c in gh.comments(n)):
                    print(f"#{n} {head}: conflict in {', '.join(files)} (already commented)")
                else:
                    gh.comment(n, body)
                    print(f"#{n} {head}: conflict in {', '.join(files)}, commented")
            else:
                pushed = git("push", "--quiet", "origin", f"HEAD:refs/heads/{head}", check=False)
                if pushed.returncode:
                    # A thread pushed meanwhile (the next run picks it up), or the merge carries
                    # workflow files, which the workflow's own token is not allowed to push.
                    print(f"#{n} {head}: push refused: {pushed.stderr.strip()}")
                    if "workflow" in pushed.stderr.lower():
                        key, body = workflow_note(pr, base)
                        if not any(f"{MARK}{key}" in (c.get("body") or "") for c in gh.comments(n)):
                            gh.comment(n, body)
                    else:
                        failed += 1
                    continue
                print(f"#{n} {head}: merged {base} in and pushed")
                if dispatch:
                    try:
                        gh.dispatch(dispatch, head)
                        print(f"#{n} {head}: started {dispatch}")
                    except urllib.error.HTTPError as e:
                        print(f"#{n} {head}: could not start {dispatch}: {e}")
        except Exception as e:
            print(f"#{n} {head}: {e}")
            failed += 1
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
