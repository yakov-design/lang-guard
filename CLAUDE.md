# Claude Code instructions

Merge conflicts in the notes files (`PROJECT-WIREFRAME.md`, `DEPLOY-LEDGER.md`, `HANDOFF.md`):
keep BOTH sides' entries, never pick one. `.gitattributes` marks them `merge=union`, so a local
`git merge` does this by itself; GitHub's own conflict check and web editor may still flag them,
and a branch cut before `.gitattributes` existed merges the old way. After a union merge, read
the file once: two edits to the same line both survive.

Open PRs update themselves: after each merge into `main`, the "update open PRs" workflow merges
main into every open PR and starts its tests. So pull your own branch before you push
(`git pull --no-rebase origin <branch>`); a real conflict is left to you, with a comment on the PR.

Tests: `python run_tests.py` finds every `test_*.py` itself (top folder and one folder down), and
`.github/workflows/tests.yml` just runs it, so a new check edits neither. A check that needs
Yakov's real data (files or databases that only exist on his PC) carries the line
`# runner: needs-real-data` and runs only with `--real`. Today the AutoHotkey script (LangGuard.ahk) has no automated check; it is tested by running it on the PC.
