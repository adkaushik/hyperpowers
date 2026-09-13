#!/usr/bin/env python3
"""Co-passenger. A Stop hook: after a turn that did real work, one line about what to run next.

It speaks only when app.json says mode copassenger. In conductor mode the conductor is
already driving, and a second voice is noise.

It never blocks. It emits systemMessage, which shows the user a line and lets the turn end.
It never emits decision "block", which would force the agent to keep working - the opposite
of a passenger.

It never raises. Every failure exits 0 with no output. A hook that breaks the session is
worse than one that says nothing.
"""

import hashlib
import json
import os
import re
import subprocess
import sys

DONE_CLAIM = re.compile(
    r"\b(done|completed?|finished|all set|implemented|that'?s it|"
    r"should (?:now )?work|ready to (?:go|ship|merge)|fixed it|shipped)\b",
    re.IGNORECASE,
)

MANY_FILES = 5

# (key, test over the changed paths, the line to show). Highest priority first.
RULES = (
    ("schema",
     lambda files: any(re.search(r"(^|/)(migrations?|models?|schema)(/|\.|$)", f) for f in files),
     "that touched the schema. `/hyperpower:council` with the backend pair before it lands?"),
    ("deps",
     lambda files: any(os.path.basename(f) in (
         "package.json", "package-lock.json", "pnpm-lock.yaml", "yarn.lock",
         "requirements.txt", "pyproject.toml", "poetry.lock", "uv.lock",
         "go.mod", "go.sum", "Cargo.toml", "Cargo.lock") for f in files),
     "dependencies changed. `/hyperpower:janitor` will check what came along with them."),
    ("many",
     lambda files: len(files) >= MANY_FILES,
     None),
    ("ui",
     lambda files: any(re.search(r"\.(tsx|jsx|vue|svelte)$", f) for f in files),
     "that touched UI. `/hyperpower:humanize` catches the leftovers a model tends to leave in components."),
)


def silent():
    sys.exit(0)


def speak(line):
    sys.stdout.write(json.dumps({"systemMessage": "hyperpower · " + line}) + "\n")
    sys.exit(0)


def git(args, cwd):
    try:
        done = subprocess.run(["git"] + args, cwd=cwd, stdout=subprocess.PIPE,
                              stderr=subprocess.DEVNULL, timeout=5)
    except (OSError, subprocess.SubprocessError):
        return None
    return done.stdout.decode("utf-8", "replace") if done.returncode == 0 else None


def state_dir(root):
    """Same resolution as the kernel scripts, without failing when config is absent."""
    here = os.path.dirname(os.path.abspath(__file__))
    config = os.path.join(os.path.dirname(here), "scripts", "hp-config")
    try:
        import importlib.machinery
        import importlib.util
        loader = importlib.machinery.SourceFileLoader("hp_config", config)
        spec = importlib.util.spec_from_loader("hp_config", loader)
        module = importlib.util.module_from_spec(spec)
        loader.exec_module(module)
        try:
            return module.state_dir(root, module.load(root)["config"])
        except Exception:
            return module.state_dir(root, None)
    except Exception:
        return os.path.join(root, ".hyperpower")


def changed_files(root, base):
    """Changed and untracked files, excluding the state directory.

    The state directory holds app.json and this hook's own memo. Where it is not git-ignored,
    git reports those as untracked - so without this filter the hook counts its own memo
    write as real work, the fingerprint moves every turn, and it never stops talking.
    """
    tracked = git(["diff", "--name-only", "HEAD"], root) or ""
    untracked = git(["ls-files", "--others", "--exclude-standard"], root) or ""
    files = {f.strip() for f in (tracked + "\n" + untracked).split("\n") if f.strip()}
    try:
        state = os.path.relpath(base, root).replace(os.sep, "/")
    except ValueError:
        state = None
    if state and not state.startswith(".."):
        files = {f for f in files if f != state and not f.startswith(state + "/")}
    return sorted(files)


def fingerprint(root, files):
    """Another edit to the same files is new work, so the diff stat and mtimes go in, not just names."""
    digest = hashlib.sha1()
    stat = git(["diff", "HEAD", "--stat"], root) or ""
    digest.update(stat.encode("utf-8", "replace"))
    for name in files:
        digest.update(name.encode("utf-8", "replace"))
        try:
            digest.update(str(os.path.getmtime(os.path.join(root, name))).encode())
        except OSError:
            pass
    return digest.hexdigest()


def main():
    try:
        payload = json.loads(sys.stdin.read() or "{}")
    except (ValueError, OSError):
        silent()
    if not isinstance(payload, dict):
        silent()

    if payload.get("stop_hook_active"):
        silent()

    cwd = payload.get("cwd") or os.getcwd()
    top = git(["rev-parse", "--show-toplevel"], cwd)
    if not top:
        silent()
    root = top.strip()

    base = state_dir(root)
    try:
        with open(os.path.join(base, "app.json"), "r", encoding="utf-8") as fh:
            app = json.load(fh)
    except (OSError, ValueError):
        silent()
    if app.get("mode") != "copassenger":
        silent()

    files = changed_files(root, base)
    claim = bool(DONE_CLAIM.search(payload.get("last_assistant_message") or ""))

    if not files:
        silent()

    print_key = fingerprint(root, files)
    memo_path = os.path.join(base, "copassenger.json")
    try:
        with open(memo_path, "r", encoding="utf-8") as fh:
            memo = json.load(fh)
    except (OSError, ValueError):
        memo = {}

    # Nothing new since the last turn, and no fresh claim of being done: a trivial turn.
    if memo.get("fingerprint") == print_key and not claim:
        silent()

    key, line = None, None
    if claim:
        key = "done"
        line = ("the turn says it is done, with %d file%s changed. "
                "`/hyperpower:review` before trusting it."
                % (len(files), "" if len(files) == 1 else "s"))
    else:
        for rule_key, test, message in RULES:
            try:
                if test(files):
                    key = rule_key
                    line = message or (
                        "%d files changed. `/hyperpower:humanize` before this grows further."
                        % len(files))
                    break
            except Exception:
                continue

    if not key:
        remember(memo_path, print_key, memo.get("said"))
        silent()

    # Never the same suggestion twice for the same state of the code.
    if memo.get("fingerprint") == print_key and memo.get("said") == key:
        silent()

    remember(memo_path, print_key, key)
    speak(line)


def remember(path, print_key, said):
    try:
        directory = os.path.dirname(path)
        os.makedirs(directory, exist_ok=True)
        temp = path + ".tmp"
        with open(temp, "w", encoding="utf-8") as fh:
            json.dump({"fingerprint": print_key, "said": said}, fh)
        os.replace(temp, path)
    except OSError:
        pass


if __name__ == "__main__":
    try:
        main()
    except SystemExit:
        raise
    except BaseException:
        # Silent in a live session, because a hook that breaks it is worse than one that says
        # nothing. HYPERPOWER_HOOK_DEBUG=1 re-raises, because silence also hides a crash: a
        # hook that dies on every turn looks exactly like one with nothing to say.
        if os.environ.get("HYPERPOWER_HOOK_DEBUG"):
            raise
        sys.exit(0)
