#!/usr/bin/env python3
"""Eval runner for the hyperpower harness.

Three subcommands: validate, run, score. Python 3.8 or newer, standard library only.

Exit codes: 0 valid or PASS, 1 bad input or a refusal, 2 the release verdict failed,
3 no baseline recorded so nothing was compared.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import random
import re
import subprocess
import os
import sys
import time
from datetime import datetime, timezone
from pathlib import Path

PLUGIN_DIR = Path(__file__).resolve().parent.parent
DEFAULT_CASES = PLUGIN_DIR / "evals" / "cases.jsonl"
DEFAULT_RUBRIC = PLUGIN_DIR / "evals" / "rubric.md"
DEFAULT_BASELINE = PLUGIN_DIR / "evals" / "baseline.json"
DEFAULT_PRICING = PLUGIN_DIR / "pricing.yml"

DIMENSIONS = (
    "correctness",
    "autonomy",
    "actionability",
    "safety",
    "concision",
    "render_conformance",
)

FALLBACK_WEIGHTS = {
    "correctness": 32,
    "autonomy": 22,
    "actionability": 18,
    "safety": 9,
    "concision": 9,
    "render_conformance": 10,
}

CATEGORIES = (
    "direct-answer",
    "autonomy",
    "gate-honesty",
    "assumption-declaration",
    "render-conformance",
    "safety",
    "scope-discipline",
    "evidence-citing",
)

RISKS = ("low", "medium", "high")
CASE_FIELDS = ("id", "category", "prompt", "risk", "criteria")
LABELS = ("A", "B", "C")
ID_RE = re.compile(r"^[a-z0-9][a-z0-9._-]*$")

TOLERANCE = 0.1
EPSILON = 1e-9

EXIT_OK = 0
EXIT_ERROR = 1
EXIT_VERDICT_FAIL = 2
EXIT_NO_BASELINE = 3

# Printed verbatim when the baseline file is absent or holds no scores.
NO_BASELINE = "no baseline recorded, run /hyperpower:eval --baseline first"

PRICE_STALE_DAYS = 90
CHARS_PER_TOKEN = 4
DEFAULT_OUTPUT_TOKENS = 800


# ---------------------------------------------------------------- utilities


def fail(message, code=EXIT_ERROR):
    """Print the cause and the fix to stderr, then exit."""
    sys.stderr.write("error: " + message.rstrip() + "\n")
    raise SystemExit(code)


def note(message):
    sys.stderr.write(message.rstrip() + "\n")


def sha256_file(path):
    digest = hashlib.sha256()
    with open(path, "rb") as handle:
        for chunk in iter(lambda: handle.read(65536), b""):
            digest.update(chunk)
    return digest.hexdigest()


def now_iso():
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def _run_fingerprint(cases_digest, rubric_digest, conditions, trials):
    parts = [str(cases_digest), str(rubric_digest), str(trials)]
    parts.extend("{}={}".format(name, command or "") for name, command in conditions)
    return hashlib.sha256("\n".join(parts).encode("utf-8")).hexdigest()


def default_seed(cases_digest, rubric_digest, conditions, trials):
    """Seed for label shuffling, derived from the run inputs.

    No clock and no unseeded randomness. The same cases, rubric, conditions and trials
    shuffle the same way and land on the same run id.
    """
    return int(_run_fingerprint(cases_digest, rubric_digest, conditions, trials)[:8], 16)


def derive_run_id(cases_digest, rubric_digest, conditions, trials, seed):
    """Reproducible id. The same cases, rubric, conditions, trials and seed give the same id.

    No clock and no unseeded randomness, so re-running one eval lands on the same folder
    instead of scattering near-identical runs the reader has to tell apart by timestamp.
    """
    parts = [_run_fingerprint(cases_digest, rubric_digest, conditions, trials), str(seed)]
    return hashlib.sha256("\n".join(parts).encode("utf-8")).hexdigest()[:12]


def capped(items, limit=5):
    """Return the first `limit` items and the number left over.

    Rank, never cap: the caller always states the remainder.
    """
    items = list(items)
    shown = items[:limit]
    return shown, len(items) - len(shown)


def listing(items, limit=5):
    """Format items as a comma-separated string with a remainder count."""
    shown, rest = capped(items, limit)
    text = ", ".join(str(item) for item in shown)
    if rest > 0:
        text += ", and {} more".format(rest)
    return text


def print_lines(items, prefix="  ", limit=5, sink=note):
    shown, rest = capped(items, limit)
    for item in shown:
        sink(prefix + str(item))
    if rest > 0:
        sink(prefix + "{} more.".format(rest))


def read_json_or_fail(path, what):
    try:
        with open(path, "r", encoding="utf-8") as handle:
            return json.load(handle)
    except OSError as exc:
        fail("cannot read the {} at {}: {}".format(what, path, exc.strerror or exc))
    except json.JSONDecodeError as exc:
        fail("the {} at {} is not valid JSON: {}".format(what, path, exc.msg))


def write_json(path, payload):
    path.parent.mkdir(parents=True, exist_ok=True)
    with open(path, "w", encoding="utf-8") as handle:
        json.dump(payload, handle, indent=2, sort_keys=False)
        handle.write("\n")


# ------------------------------------------------------------ yaml subset


def _strip_comment(line):
    out = []
    quote = None
    for char in line:
        if quote:
            out.append(char)
            if char == quote:
                quote = None
        elif char in "\"'":
            quote = char
            out.append(char)
        elif char == "#":
            break
        else:
            out.append(char)
    return "".join(out).rstrip()


def _scalar(raw):
    text = raw.strip()
    if len(text) >= 2 and text[0] in "\"'" and text[-1] == text[0]:
        return text[1:-1]
    lowered = text.lower()
    if lowered in ("", "null", "~"):
        return None
    if lowered == "true":
        return True
    if lowered == "false":
        return False
    try:
        return int(text)
    except ValueError:
        pass
    try:
        return float(text)
    except ValueError:
        pass
    return text


def _split_flow(body):
    parts = []
    depth = 0
    quote = None
    current = []
    for char in body:
        if quote:
            current.append(char)
            if char == quote:
                quote = None
            continue
        if char in "\"'":
            quote = char
            current.append(char)
            continue
        if char in "[{":
            depth += 1
        elif char in "]}":
            depth -= 1
        if char == "," and depth == 0:
            parts.append("".join(current))
            current = []
            continue
        current.append(char)
    if "".join(current).strip():
        parts.append("".join(current))
    return parts


def _parse_flow(text):
    body = text.strip()
    if body.startswith("{") and body.endswith("}"):
        result = {}
        for part in _split_flow(body[1:-1]):
            if ":" not in part:
                continue
            key, _, value = part.partition(":")
            result[key.strip()] = _parse_value(value)
        return result
    if body.startswith("[") and body.endswith("]"):
        return [_parse_value(part) for part in _split_flow(body[1:-1])]
    return _scalar(body)


def _parse_value(text):
    body = text.strip()
    if body.startswith("{") or body.startswith("["):
        return _parse_flow(body)
    return _scalar(body)


def _parse_block(lines, index, indent):
    if index < len(lines) and lines[index][1].startswith("- "):
        items = []
        while index < len(lines) and lines[index][0] == indent and lines[index][1].startswith("- "):
            items.append(_parse_value(lines[index][1][2:]))
            index += 1
        return items, index

    mapping = {}
    while index < len(lines):
        line_indent, text = lines[index]
        if line_indent < indent:
            break
        if line_indent > indent or ":" not in text:
            index += 1
            continue
        key, _, rest = text.partition(":")
        key = key.strip()
        rest = rest.strip()
        index += 1
        if rest:
            mapping[key] = _parse_value(rest)
            continue
        if index < len(lines) and lines[index][0] > line_indent:
            child, index = _parse_block(lines, index, lines[index][0])
            mapping[key] = child
        else:
            mapping[key] = None
    return mapping, index


def parse_yaml_subset(text):
    """Parse the subset of YAML that hyperpower.yml uses.

    Handles nested mappings, block sequences, inline maps, inline lists, and scalars.
    Anchors, multi-line strings, and multiple documents are not supported.
    """
    lines = []
    for raw in text.splitlines():
        stripped = _strip_comment(raw)
        if not stripped.strip() or stripped.strip() in ("---", "..."):
            continue
        lines.append((len(stripped) - len(stripped.lstrip(" ")), stripped.strip()))
    if not lines:
        return {}
    parsed, _ = _parse_block(lines, 0, lines[0][0])
    return parsed if isinstance(parsed, dict) else {}


# ---------------------------------------------------------------- config


def find_config(start=None):
    current = Path(start or Path.cwd()).resolve()
    for directory in [current] + list(current.parents):
        candidate = directory / "hyperpower.yml"
        if candidate.is_file():
            return candidate
    return None


def merge_per_field(base, override):
    result = dict(base)
    for key, value in override.items():
        if isinstance(value, dict) and isinstance(result.get(key), dict):
            result[key] = merge_per_field(result[key], value)
        else:
            result[key] = value
    return result


def load_config(path=None):
    """Read hyperpower.yml, then merge hyperpower.local.yml per field.

    Returns a summary. A missing or unreadable config degrades to defaults; it never
    stops the run. Only fields documented in docs/configuration.md are read.
    """
    summary = {
        "source": None,
        "local_override": False,
        "project_name": None,
        "models": {"judgment": None, "mechanical": None},
        "voice": {"adhd_shaping": True, "plain_english": True},
    }
    config_path = Path(path).resolve() if path else find_config()
    if not config_path or not config_path.is_file():
        return summary

    data = {}
    try:
        data = parse_yaml_subset(config_path.read_text(encoding="utf-8"))
    except OSError as exc:
        note("warning: cannot read {}: {}".format(config_path, exc))
        return summary
    except Exception as exc:  # noqa: BLE001 - a broken config must not stop the eval
        note("warning: cannot parse {}: {}".format(config_path, exc))
        return summary

    local_path = config_path.parent / "hyperpower.local.yml"
    if local_path.is_file():
        try:
            local = parse_yaml_subset(local_path.read_text(encoding="utf-8"))
            if isinstance(local, dict):
                data = merge_per_field(data, local)
                summary["local_override"] = True
        except Exception as exc:  # noqa: BLE001
            note("warning: cannot parse {}: {}".format(local_path, exc))

    summary["source"] = str(config_path)
    project = data.get("project") or {}
    models = data.get("models") or {}
    voice = data.get("voice") or {}
    if isinstance(project, dict):
        summary["project_name"] = project.get("name")
    if isinstance(models, dict):
        summary["models"] = {
            "judgment": models.get("judgment"),
            "mechanical": models.get("mechanical"),
        }
    if isinstance(voice, dict):
        for key in ("adhd_shaping", "plain_english"):
            if isinstance(voice.get(key), bool):
                summary["voice"][key] = voice[key]
    return summary


# ---------------------------------------------------------------- pricing


def load_pricing(path):
    """Read pricing.yml. Return (prices, problem).

    `prices` maps a model id to its input rate, output rate, and last_verified date, all
    per million tokens. A file that cannot be read returns an empty map and the reason.
    A model missing from the file never borrows another model's rate.
    """
    price_path = Path(path)
    if not price_path.is_file():
        return {}, "{} not found".format(price_path)
    try:
        data = parse_yaml_subset(price_path.read_text(encoding="utf-8"))
    except OSError as exc:
        return {}, "cannot read {}: {}".format(price_path, exc.strerror or exc)
    except Exception as exc:  # noqa: BLE001 - a broken price file must not stop the run
        return {}, "cannot parse {}: {}".format(price_path, exc)

    models = data.get("models") if isinstance(data, dict) else None
    if not isinstance(models, dict):
        return {}, "{} has no models table".format(price_path)

    prices = {}
    for name, entry in models.items():
        if not isinstance(entry, dict):
            continue
        try:
            rate_in = float(entry.get("input"))
            rate_out = float(entry.get("output"))
        except (TypeError, ValueError):
            continue
        prices[name] = {
            "input": rate_in,
            "output": rate_out,
            "last_verified": entry.get("last_verified"),
        }
    if not prices:
        return {}, "{} lists no priced model".format(price_path)
    return prices, None


def price_age_days(last_verified):
    """Days since the rate was checked. None when the date is missing or malformed."""
    if not isinstance(last_verified, str):
        return None
    try:
        stamp = datetime.strptime(last_verified, "%Y-%m-%d").replace(tzinfo=timezone.utc)
    except ValueError:
        return None
    return (datetime.now(timezone.utc) - stamp).days


def estimate_tokens(text):
    """About four characters per token. This is an estimate, never a count."""
    return (len(text) + CHARS_PER_TOKEN - 1) // CHARS_PER_TOKEN


def money(amount):
    if amount == 0 or amount >= 0.01:
        return "${:.2f}".format(amount)
    return "${:.4f}".format(amount)


def thousands(count):
    return "{:,}".format(int(count))


def plural(count, word):
    return "{} {}".format(count, word if count == 1 else word + "s")


# ----------------------------------------------------------------- cases


def read_jsonl(path):
    rows = []
    errors = []
    try:
        text = Path(path).read_text(encoding="utf-8")
    except OSError as exc:
        fail("cannot read {}: {}".format(path, exc))
    for lineno, line in enumerate(text.splitlines(), start=1):
        if not line.strip():
            continue
        try:
            obj = json.loads(line)
        except json.JSONDecodeError as exc:
            errors.append("line {}: invalid JSON: {}".format(lineno, exc.msg))
            continue
        if not isinstance(obj, dict):
            errors.append("line {}: expected a JSON object".format(lineno))
            continue
        rows.append((lineno, obj))
    return rows, errors


def validate_cases(path):
    """Return (cases, errors, warnings). `cases` preserves file order."""
    rows, errors = read_jsonl(path)
    warnings = []
    cases = []
    seen = {}

    for lineno, case in rows:
        prefix = "line {}".format(lineno)
        missing = [field for field in CASE_FIELDS if field not in case]
        if missing:
            errors.append("{}: missing field(s): {}".format(prefix, ", ".join(missing)))
            continue

        case_id = case["id"]
        if not isinstance(case_id, str) or not ID_RE.match(case_id):
            errors.append("{}: id must be lowercase and match {}".format(prefix, ID_RE.pattern))
        elif case_id in seen:
            errors.append("{}: duplicate id {} (first seen on line {})".format(prefix, case_id, seen[case_id]))
        else:
            seen[case_id] = lineno

        if case["category"] not in CATEGORIES:
            errors.append("{}: category {!r} is not one of: {}".format(prefix, case["category"], ", ".join(CATEGORIES)))
        if case["risk"] not in RISKS:
            errors.append("{}: risk {!r} is not one of: {}".format(prefix, case["risk"], ", ".join(RISKS)))
        if not isinstance(case["prompt"], str) or len(case["prompt"].strip()) < 20:
            errors.append("{}: prompt must be a string of at least 20 characters".format(prefix))

        criteria = case["criteria"]
        if not isinstance(criteria, list) or not (2 <= len(criteria) <= 6):
            errors.append("{}: criteria must be an array of 2 to 6 strings".format(prefix))
        else:
            for position, item in enumerate(criteria, start=1):
                if not isinstance(item, str) or len(item.strip()) < 10:
                    errors.append("{}: criteria[{}] must be a string of at least 10 characters".format(prefix, position))

        extra = sorted(set(case) - set(CASE_FIELDS))
        if extra:
            warnings.append("{}: unknown field(s) ignored: {}".format(prefix, ", ".join(extra)))

        cases.append(case)

    for category in CATEGORIES:
        if not any(case["category"] == category for case in cases):
            warnings.append("category {} has no cases".format(category))

    return cases, sorted(errors, key=_line_order), warnings


def _line_order(message):
    match = re.match(r"^line (\d+):", message)
    return int(match.group(1)) if match else 0


def load_cases_or_exit(path):
    cases, errors, _ = validate_cases(path)
    if errors:
        print_lines(errors)
        fail("{} is not valid. Fix the {} error(s) above, then re-run.".format(path, len(errors)))
    if not cases:
        fail("{} holds no cases.".format(path))
    return cases


# ----------------------------------------------------------------- rubric


def load_weights(rubric_path):
    """Parse the weights table in rubric.md. Fall back to the built-in weights."""
    path = Path(rubric_path)
    if not path.is_file():
        note("warning: {} not found. Using the built-in weights.".format(path))
        return dict(FALLBACK_WEIGHTS), None

    weights = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        if not line.lstrip().startswith("|"):
            continue
        cells = [cell.strip().strip("`").strip() for cell in line.strip().strip("|").split("|")]
        key_index = None
        for index, cell in enumerate(cells):
            if cell.lower() in DIMENSIONS:
                key_index = index
        if key_index is None or key_index + 1 >= len(cells):
            continue
        try:
            value = int(cells[key_index + 1])
        except ValueError:
            continue
        weights[cells[key_index].lower()] = value

    missing = [dimension for dimension in DIMENSIONS if dimension not in weights]
    if missing:
        fail(
            "{} does not define a weight for: {}. Fix the weights table in the rubric.".format(
                path, ", ".join(missing)
            )
        )
    total = sum(weights.values())
    if total != 100:
        fail("weights in {} total {}, not 100. Fix the weights table.".format(path, total))
    return weights, sha256_file(path)


# -------------------------------------------------------------- subcommand: validate


def cmd_validate(args):
    cases_path = Path(args.cases)
    cases, errors, warnings = validate_cases(cases_path)
    limit = None if args.all else 5

    for label, items in (("error", errors), ("warning", warnings)):
        if not items:
            continue
        note("{} {}(s) in {}:".format(len(items), label, cases_path))
        shown = items if limit is None else items[:limit]
        for item in shown:
            note("  " + item)
        if limit is not None and len(items) > limit:
            note("  {} more. Re-run with --all.".format(len(items) - limit))

    if errors:
        raise SystemExit(EXIT_ERROR)

    counts = {}
    for case in cases:
        counts[case["category"]] = counts.get(case["category"], 0) + 1

    print("{}: {} cases, {} categories, 0 errors.".format(cases_path, len(cases), len(counts)))
    print("")
    print("{:<24} {:>5}".format("category", "cases"))
    for category in CATEGORIES:
        print("{:<24} {:>5}".format(category, counts.get(category, 0)))
    return EXIT_OK


# ------------------------------------------------------------- subcommand: run


def build_conditions(args):
    conditions = [
        (args.baseline, args.baseline_cmd),
        (args.candidate, args.candidate_cmd),
    ]
    if args.control or args.control_cmd:
        if not args.control:
            fail("--control-cmd needs --control NAME.")
        conditions.append((args.control, args.control_cmd))

    names = [name for name, _ in conditions]
    if len(set(names)) != len(names):
        fail("condition names must differ. Got: {}.".format(", ".join(names)))
    return conditions


def execute_condition(command, prompt, timeout):
    started = time.time()
    try:
        completed = subprocess.run(
            command,
            shell=True,
            input=prompt,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            universal_newlines=True,
            timeout=timeout,
        )
    except subprocess.TimeoutExpired:
        return None, {"exit_code": None, "duration_ms": int((time.time() - started) * 1000), "error": "timeout after {}s".format(timeout)}
    except OSError as exc:
        return None, {"exit_code": None, "duration_ms": int((time.time() - started) * 1000), "error": str(exc)}
    result = {
        "exit_code": completed.returncode,
        "duration_ms": int((time.time() - started) * 1000),
        "error": None if completed.returncode == 0 else (completed.stderr or "").strip()[:500] or "exit {}".format(completed.returncode),
    }
    return completed.stdout, result


def plan_rows(cases, conditions, trials, rng):
    """Lay out one row per case, trial, and condition. Writes nothing.

    Labels are shuffled per case and trial, so a judge cannot infer the condition from
    the label. Returns (rows, label to condition map).
    """
    rows = []
    key_map = {}
    for case in cases:
        for trial in range(1, trials + 1):
            order = list(conditions)
            rng.shuffle(order)
            for label, (name, _cmd) in zip(LABELS, order):
                row_id = "{}#t{}#{}".format(case["id"], trial, label)
                stem = "{}-t{}-{}".format(case["id"], trial, label)
                rows.append(
                    {
                        "row_id": row_id,
                        "case": case["id"],
                        "category": case["category"],
                        "trial": trial,
                        "label": label,
                        "prompt_file": "prompts/{}.txt".format(stem),
                        "response_file": "responses/{}.txt".format(stem),
                    }
                )
                key_map[row_id] = name
    return rows, key_map


def dry_run_report(args, cases, conditions, rows, key_map, out_label, config):
    """Print what a run would execute and what it would cost. Write nothing, run nothing."""
    prompts = {case["id"]: case["prompt"] for case in cases}
    command_by_name = {name: cmd for name, cmd in conditions}

    rows_by_condition = {}
    input_by_condition = {}
    for row in rows:
        name = key_map[row["row_id"]]
        rows_by_condition[name] = rows_by_condition.get(name, 0) + 1
        tokens = estimate_tokens(prompts[row["case"]] + "\n") + args.assume_overhead_tokens
        input_by_condition[name] = input_by_condition.get(name, 0) + tokens

    spending = [name for name, _cmd in conditions if command_by_name[name]]
    input_tokens = sum(input_by_condition[name] for name in spending)
    responses = sum(rows_by_condition[name] for name in spending)
    output_tokens = responses * args.assume_output_tokens

    print("Dry run. Nothing was written, nothing was executed.")
    print("")
    print(
        "{} rows: {} cases x {} trials x {} conditions.".format(
            len(rows), len(cases), args.trials, len(conditions)
        )
    )
    print("Would write to {}".format(out_label))
    print("")
    header = "{:<14}{:>6}  {}"
    print(header.format("condition", "rows", "command"))
    for name, command in conditions:
        shown = command if command else "none. You produce these responses yourself."
        if len(shown) > 58:
            shown = shown[:55] + "..."
        print(header.format(name[:13], rows_by_condition.get(name, 0), shown))
    print("")

    if not spending:
        print("Estimated spend: {}. No condition command was given.".format(money(0.0)))
        print("")
        print("Next:")
        print("1. Re-run with --baseline-cmd and --candidate-cmd to generate responses.")
        return EXIT_OK

    model = args.price_model or config["models"].get("judgment")
    prices, problem = load_pricing(args.pricing)
    entry = prices.get(model) if model else None

    if entry:
        input_cost = input_tokens / 1000000.0 * entry["input"]
        output_cost = output_tokens / 1000000.0 * entry["output"]
        print(
            "Estimated spend: {} at {} prices.".format(money(input_cost + output_cost), model)
        )
        print("  input   ~{:>12} tokens  {}".format(thousands(input_tokens), money(input_cost)))
        print("  output  ~{:>12} tokens  {}".format(thousands(output_tokens), money(output_cost)))
        age = price_age_days(entry["last_verified"])
        if age is not None and age > PRICE_STALE_DAYS:
            print(
                "  Price is stale, verified {} ({} days). The number is unverified.".format(
                    entry["last_verified"], age
                )
            )
    else:
        print("Estimated spend: unknown. Tokens only.")
        print("  input   ~{:>12} tokens".format(thousands(input_tokens)))
        print("  output  ~{:>12} tokens".format(thousands(output_tokens)))
        if problem:
            print("  {}.".format(problem))
        elif model:
            print("  {} has no entry in {}. Add one, or pass --price-model.".format(model, args.pricing))
        else:
            print("  No model to price. Set models.judgment in hyperpower.yml, or pass --price-model.")

    print("")
    print("The estimate covers {} responses.".format(responses))
    print(
        "  input   the case prompt, plus {} overhead tokens per response.".format(
            args.assume_overhead_tokens
        )
    )
    print("  output  assumed at {} tokens per response.".format(args.assume_output_tokens))
    print("This is a floor. A command that also sends a system prompt, tool definitions,")
    print("or repo files spends more. Raise --assume-overhead-tokens to count it.")
    print("")
    print("Next:")
    print("1. Re-run without --dry-run to spend it.")
    return EXIT_OK


def cmd_run(args):
    cases_path = Path(args.cases)
    cases = load_cases_or_exit(cases_path)
    conditions = build_conditions(args)
    if args.trials < 1:
        fail("--trials must be 1 or more.")
    if args.assume_output_tokens < 0 or args.assume_overhead_tokens < 0:
        fail("--assume-output-tokens and --assume-overhead-tokens must be 0 or more.")

    weights, rubric_digest = load_weights(args.rubric)
    config = load_config(args.config)

    cases_digest = sha256_file(cases_path)
    seed = args.seed
    if seed is None:
        seed = default_seed(cases_digest, rubric_digest, conditions, args.trials)
    rng = random.Random(seed)
    rows, key_map = plan_rows(cases, conditions, args.trials, rng)

    run_id = derive_run_id(cases_digest, rubric_digest, conditions, args.trials, seed)
    anchor = Path(config["source"]).parent if config["source"] else Path.cwd()
    if args.out:
        out_dir = Path(args.out)
    else:
        out_dir = Path(state_root(anchor)) / "evals" / run_id

    if args.dry_run:
        label = str(out_dir) if args.out else str(Path(state_root(anchor)) / "evals" / "<run-id>")
        return dry_run_report(args, cases, conditions, rows, key_map, label, config)

    if out_dir.exists() and any(out_dir.iterdir()) and not args.force:
        fail("{} exists and is not empty. Pass --force to overwrite it.".format(out_dir))

    (out_dir / "prompts").mkdir(parents=True, exist_ok=True)
    (out_dir / "responses").mkdir(parents=True, exist_ok=True)
    prompts = {case["id"]: case["prompt"] for case in cases}
    for row in rows:
        (out_dir / row["prompt_file"]).write_text(prompts[row["case"]] + "\n", encoding="utf-8")

    executed = 0
    failed = 0
    command_by_name = {name: cmd for name, cmd in conditions}
    if any(command_by_name.values()):
        for index, row in enumerate(rows, start=1):
            command = command_by_name[key_map[row["row_id"]]]
            if not command:
                continue
            prompt = (out_dir / row["prompt_file"]).read_text(encoding="utf-8")
            note("[{}/{}] {}".format(index, len(rows), row["row_id"]))
            stdout, result = execute_condition(command, prompt, args.timeout)
            (out_dir / row["response_file"]).write_text(stdout or "", encoding="utf-8")
            row["execution"] = result
            executed += 1
            if result["error"]:
                failed += 1

    manifest = {
        "kind": "hyperpower-eval-manifest",
        "run_id": run_id,
        "created": now_iso(),
        "cases_path": str(cases_path.resolve()),
        "cases_sha256": sha256_file(cases_path),
        "rubric_path": str(Path(args.rubric).resolve()),
        "rubric_sha256": rubric_digest,
        "weights": weights,
        "trials": args.trials,
        "seed": seed,
        "condition_count": len(conditions),
        "labels": list(LABELS[: len(conditions)]),
        "config": config,
        "rows": rows,
    }
    write_json(out_dir / "manifest.json", manifest)

    write_json(
        out_dir / "key.json",
        {
            "kind": "hyperpower-eval-key",
            "run_id": run_id,
            "baseline": args.baseline,
            "candidate": args.candidate,
            "commands": command_by_name,
            "labels": key_map,
        },
    )

    with open(out_dir / "scores.template.jsonl", "w", encoding="utf-8") as handle:
        for row in rows:
            template = {
                "row_id": row["row_id"],
                "case": row["case"],
                "trial": row["trial"],
                "label": row["label"],
            }
            for dimension in DIMENSIONS:
                template[dimension] = None
            template["blocker"] = False
            template["note"] = ""
            handle.write(json.dumps(template, separators=(",", ":")) + "\n")

    print("Run {} written to {}".format(run_id, out_dir))
    print("{} rows: {} cases x {} trials x {} conditions.".format(len(rows), len(cases), args.trials, len(conditions)))
    without_command = [name for name, command in conditions if not command]
    if executed:
        print("{} responses generated, {} failed.".format(executed, failed))
    else:
        print("No condition command given. Prompts are written. Produce the responses yourself.")
    if executed and without_command:
        waiting = len([row for row in rows if key_map[row["row_id"]] in without_command])
        print(
            "{} has no command, so {} of {} rows have no response file.".format(
                listing(without_command), waiting, len(rows)
            )
        )
        print("Produce those responses yourself. score refuses an unpaired set.")
    if not config["source"]:
        print("No hyperpower.yml found. Model tiers are recorded as unknown.")
    if not (config["voice"]["adhd_shaping"] and config["voice"]["plain_english"]):
        print("voice rules are off in the config. Render conformance is still scored.")
    print("")
    print("Next:")
    print("1. Read the responses in {}/responses. Do not open key.json.".format(out_dir))
    print("2. Score every row into {}/scores.jsonl, using evals/rubric.md.".format(out_dir))
    print("3. Run: {} score --run {}".format(Path(sys.argv[0]).name, out_dir))
    return EXIT_OK


# ----------------------------------------------------------- subcommand: score


def load_score_rows(path, label_map):
    rows, errors = read_jsonl(path)
    parsed = []
    for lineno, row in rows:
        prefix = "line {}".format(lineno)
        case_id = row.get("case")
        trial = row.get("trial")
        if not isinstance(case_id, str) or not case_id:
            errors.append("{}: missing case".format(prefix))
            continue
        if not isinstance(trial, int) or trial < 1:
            errors.append("{}: trial must be an integer of 1 or more".format(prefix))
            continue

        condition = row.get("condition")
        label = row.get("label")
        resolved = None
        if isinstance(condition, str) and condition:
            resolved = condition
        if label_map:
            row_id = row.get("row_id") or "{}#t{}#{}".format(case_id, trial, label)
            mapped = label_map.get(row_id)
            if mapped and resolved and mapped != resolved:
                errors.append("{}: condition {!r} disagrees with the key ({})".format(prefix, resolved, mapped))
                continue
            resolved = resolved or mapped
        if not resolved:
            errors.append("{}: cannot resolve the condition. Give a condition field, or pass --run so the label can be unblinded.".format(prefix))
            continue

        scores = {}
        bad = False
        for dimension in DIMENSIONS:
            value = row.get(dimension)
            if not isinstance(value, int) or isinstance(value, bool) or not (1 <= value <= 5):
                errors.append("{}: {} must be an integer 1 to 5".format(prefix, dimension))
                bad = True
                continue
            scores[dimension] = value
        if bad:
            continue
        if not isinstance(row.get("blocker"), bool):
            errors.append("{}: blocker must be true or false".format(prefix))
            continue

        parsed.append(
            {
                "case": case_id,
                "trial": trial,
                "condition": resolved,
                "label": label,
                "scores": scores,
                "blocker": row["blocker"],
                "note": row.get("note", ""),
                "lineno": lineno,
            }
        )
    return parsed, errors


def aggregate(rows, weights):
    means = {}
    for dimension in DIMENSIONS:
        values = [row["scores"][dimension] for row in rows]
        means[dimension] = sum(values) / float(len(values))
    weighted = sum(weights[dimension] * means[dimension] for dimension in DIMENSIONS) / 100.0
    return means, weighted


def row_keys(rows):
    return {(row["case"], row["trial"]) for row in rows}


def format_missing(pairs):
    return listing(["{} trial {}".format(case, trial) for case, trial in sorted(pairs)])


def unrecorded_reason(record):
    """Return why a baseline file holds no baseline, or None when it is usable.

    The shipped evals/baseline.json is the unrecorded case: recorded_at is null and every
    score is null. It is a template, not a comparison.
    """
    if not isinstance(record, dict):
        return "the file does not hold a JSON object"
    if record.get("recorded_at", record.get("recorded")) is None:
        return "recorded_at is null"
    means = record.get("means")
    if not isinstance(means, dict):
        return "means is missing"
    blank = [dimension for dimension in DIMENSIONS if means.get(dimension) is None]
    if blank:
        return "means has no value for {}".format(listing(blank))
    if record.get("weighted") is None:
        return "weighted is null"
    if not record.get("rows"):
        return "rows is empty"
    return None


def pick_candidate(args, by_condition, key_candidate=None):
    """Resolve the candidate condition when there are no baseline rows to compare against."""
    if args.candidate:
        name = args.candidate
    elif key_candidate and key_candidate in by_condition:
        name = key_candidate
    elif len(by_condition) == 1:
        name = sorted(by_condition)[0]
    else:
        fail(
            "cannot tell which condition is the candidate. Pass --candidate NAME. Scored: {}.".format(
                ", ".join(sorted(by_condition))
            )
        )
    if name not in by_condition:
        fail(
            "condition {!r} has no score rows. Scored conditions: {}.".format(
                name, ", ".join(sorted(by_condition))
            )
        )
    return name


def record_baseline_file(args, by_condition, weights, cases_path, cases_digest, rubric_digest, run_models, default_condition):
    """Write the aggregate of one condition as the baseline to beat."""
    recorded_name = args.record_baseline_condition or default_condition
    target = by_condition.get(recorded_name)
    if not target:
        fail("cannot record a baseline for {!r}. It has no score rows.".format(recorded_name))
    means, weighted = aggregate(target, weights)
    keys = row_keys(target)
    write_json(
        Path(args.record_baseline),
        {
            "kind": "hyperpower-eval-baseline",
            "version": 1,
            "recorded_at": now_iso(),
            "condition": recorded_name,
            "cases_path": str(cases_path),
            "cases_sha256": cases_digest,
            "rubric_sha256": rubric_digest,
            "trials": len({trial for _case, trial in keys}),
            "models": run_models,
            "rows": sorted([list(key) for key in keys]),
            "means": means,
            "weighted": weighted,
            "blockers": len([row for row in target if row["blocker"]]),
            "note": "Recorded from {} judged rows on condition {}.".format(len(target), recorded_name),
        },
    )
    print("Baseline recorded to {}.".format(args.record_baseline))


def report_no_baseline(args, by_condition, weights, cases, cases_path, cases_digest, rubric_digest, run_models, key_candidate, reason):
    """Print the candidate scores, then say no baseline exists. Never a pass."""
    candidate_name = pick_candidate(args, by_condition, key_candidate)
    rows = by_condition[candidate_name]
    means, weighted = aggregate(rows, weights)
    blockers = [row for row in rows if row["blocker"]]
    keys = row_keys(rows)
    trials = sorted({trial for _case, trial in keys})
    coverage = len({case for case, _trial in keys})

    print("Eval score: {}, no comparison".format(candidate_name))
    print(
        "{} rows. {} of {} cases, trials {}.".format(
            len(rows), coverage, len(cases), ",".join(str(trial) for trial in trials)
        )
    )
    print("")
    header = "{:<20}{:>7}{:>11}"
    print(header.format("dimension", "weight", candidate_name[:10]))
    for dimension in DIMENSIONS:
        print(header.format(dimension, weights[dimension], "{:.2f}".format(means[dimension])))
    print(header.format("weighted", 100, "{:.2f}".format(weighted)))
    print("")
    print("Blockers: {} {}.".format(candidate_name, len(blockers)))
    print("")
    print("Release verdict: NO BASELINE")
    print(NO_BASELINE)
    print("Cause: {}.".format(reason))
    print("")

    if args.json:
        write_json(
            Path(args.json),
            {
                "kind": "hyperpower-eval-result",
                "created": now_iso(),
                "baseline": None,
                "candidate": candidate_name,
                "weights": weights,
                "cases_sha256": cases_digest,
                "rubric_sha256": rubric_digest,
                "rows_per_condition": len(rows),
                "baseline_means": None,
                "candidate_means": means,
                "baseline_weighted": None,
                "candidate_weighted": weighted,
                "candidate_blockers": [row["case"] for row in blockers],
                "verdict": "no_baseline",
                "reasons": [NO_BASELINE, reason],
                "public_comparison": False,
            },
        )

    if args.record_baseline:
        record_baseline_file(
            args, by_condition, weights, cases_path, cases_digest, rubric_digest, run_models, candidate_name
        )
        print("")
        print("Next:")
        print("1. Change one prompt, then re-run and compare against that file.")
    else:
        print("Next:")
        print(
            "1. Record these scores as the baseline: {} score --run <run> --record-baseline .hyperpower/evals/baseline.json".format(
                Path(sys.argv[0]).name
            )
        )
        print("2. Change one prompt, then re-run and compare against that file.")
    return EXIT_NO_BASELINE


def cmd_score(args):
    weights, rubric_digest = load_weights(args.rubric)

    manifest = None
    label_map = None
    key_candidate = None
    scores_path = Path(args.scores) if args.scores else None
    run_dir = Path(args.run) if args.run else None

    if run_dir:
        manifest_path = run_dir / "manifest.json"
        key_path = run_dir / "key.json"
        if not manifest_path.is_file():
            fail("{} not found. Pass --run with the directory that run wrote.".format(manifest_path))
        manifest = read_json_or_fail(manifest_path, "run manifest")
        if key_path.is_file():
            key_data = read_json_or_fail(key_path, "label key")
            label_map = key_data.get("labels") or {}
            key_candidate = key_data.get("candidate")
        if scores_path is None:
            scores_path = run_dir / "scores.jsonl"

    if scores_path is None:
        fail("pass --scores PATH, or --run DIR holding scores.jsonl.")
    if not scores_path.is_file():
        fail("{} not found. Judge the rows first, then score.".format(scores_path))

    rows, errors = load_score_rows(scores_path, label_map)
    if errors:
        print_lines(errors)
        fail("{} has {} bad row(s). Fix them, then re-run.".format(scores_path, len(errors)))
    if not rows:
        fail("{} holds no score rows.".format(scores_path))

    # Duplicate rows.
    seen = {}
    duplicates = []
    for row in rows:
        key = (row["case"], row["trial"], row["condition"])
        if key in seen:
            duplicates.append("{} trial {} condition {} on lines {} and {}".format(row["case"], row["trial"], row["condition"], seen[key], row["lineno"]))
        else:
            seen[key] = row["lineno"]
    if duplicates:
        print_lines(duplicates)
        fail("{} duplicate score row(s). One row per case, trial, and condition. Delete the extras.".format(len(duplicates)))

    # Case integrity.
    if args.cases:
        cases_path = Path(args.cases)
    elif manifest and Path(manifest["cases_path"]).is_file():
        cases_path = Path(manifest["cases_path"])
    else:
        cases_path = DEFAULT_CASES
    cases = load_cases_or_exit(cases_path)
    known = {case["id"] for case in cases}
    unknown = sorted({row["case"] for row in rows} - known)
    if unknown:
        fail("score rows name cases that are not in {}: {}.".format(cases_path, listing(unknown)))
    cases_digest = sha256_file(cases_path)
    if manifest and manifest.get("cases_sha256") and manifest["cases_sha256"] != cases_digest:
        fail("{} changed since the run was created. The scores describe different prompts. Re-run the eval.".format(cases_path))
    if manifest and rubric_digest and manifest.get("rubric_sha256") and manifest["rubric_sha256"] != rubric_digest:
        fail("rubric.md changed since the run was created. Scores judged on two rubrics are not comparable. Re-judge or restore the rubric.")

    by_condition = {}
    for row in rows:
        by_condition.setdefault(row["condition"], []).append(row)

    # Clause 4 of the release rule: a public comparison needs the same cases, models,
    # trials, and rubric. Digest drift already refuses above.
    run_models = (manifest or {}).get("config", {}).get("models") or load_config(None)["models"]

    baseline_record = None
    if args.baseline_file:
        baseline_path = Path(args.baseline_file)
        reason = None
        if not baseline_path.is_file():
            reason = "{} does not exist".format(baseline_path)
        else:
            record = read_json_or_fail(baseline_path, "baseline file")
            reason = unrecorded_reason(record)
            if reason is None:
                baseline_record = record
        if baseline_record is None:
            return report_no_baseline(
                args,
                by_condition,
                weights,
                cases,
                cases_path,
                cases_digest,
                rubric_digest,
                run_models,
                key_candidate,
                reason,
            )

    # Which conditions are being compared.
    if baseline_record:
        candidate_name = args.candidate
        # The run's own key names its candidate. Trust that before any inference from the
        # recorded condition name. A baseline recorded by --record-baseline carries the name
        # of the condition it aggregated, which is normally "candidate" too, so excluding
        # that name would drop this run's real candidate and compare the baseline arm.
        if not candidate_name and key_candidate in by_condition:
            candidate_name = key_candidate
        if not candidate_name:
            scored = sorted(by_condition)
            if len(scored) == 1:
                candidate_name = scored[0]
            else:
                others = [name for name in scored if name != baseline_record.get("condition")]
                if len(others) != 1:
                    fail("cannot tell which condition is the candidate. Pass --candidate NAME. Scored: {}.".format(", ".join(scored)))
                candidate_name = others[0]
        baseline_name = baseline_record.get("condition") or "baseline"
        # The baseline column comes from the recorded file, not from rows judged in this run.
        # Rename it whenever that name also names a condition here, so the two columns cannot
        # be read as two arms of the same run.
        if baseline_name == candidate_name or baseline_name in by_condition:
            for alternative in ("recorded", "recorded-baseline", "baseline-file"):
                if alternative != candidate_name and alternative not in by_condition:
                    baseline_name = alternative
                    break
        if candidate_name not in by_condition:
            fail("condition {!r} has no score rows. Scored conditions: {}.".format(candidate_name, ", ".join(sorted(by_condition))))
    else:
        baseline_name = args.baseline
        candidate_name = args.candidate
        if not baseline_name or not candidate_name:
            key_data = {}
            if run_dir and (run_dir / "key.json").is_file():
                key_data = read_json_or_fail(run_dir / "key.json", "label key")
            baseline_name = baseline_name or key_data.get("baseline")
            candidate_name = candidate_name or key_data.get("candidate")
        if not baseline_name or not candidate_name:
            if len(by_condition) == 2:
                fail("pass --baseline NAME and --candidate NAME. The scored conditions are: {}.".format(", ".join(sorted(by_condition))))
            fail("pass --baseline NAME and --candidate NAME.")
        for name in (baseline_name, candidate_name):
            if name not in by_condition:
                fail("condition {!r} has no score rows. Scored conditions: {}.".format(name, ", ".join(sorted(by_condition))))

    # Paired rows.
    candidate_rows = by_condition.get(candidate_name, [])
    if not candidate_rows:
        fail("condition {!r} has no score rows.".format(candidate_name))
    candidate_keys = row_keys(candidate_rows)

    if baseline_record:
        for field in ("means", "weighted", "rows"):
            if field not in baseline_record:
                fail("{} is not a baseline file. It has no {!r} field.".format(args.baseline_file, field))
        baseline_keys = {(pair[0], pair[1]) for pair in baseline_record["rows"]}
        baseline_means = baseline_record["means"]
        baseline_weighted = baseline_record["weighted"]
        baseline_blocker_count = baseline_record.get("blockers", 0)
        if baseline_record.get("cases_sha256") and baseline_record["cases_sha256"] != cases_digest:
            fail("{} changed since the baseline was recorded. Re-record the baseline before comparing.".format(cases_path))
        if rubric_digest and baseline_record.get("rubric_sha256") and baseline_record["rubric_sha256"] != rubric_digest:
            fail("rubric.md changed since the baseline was recorded. Re-record the baseline before comparing.")
    else:
        baseline_rows = by_condition[baseline_name]
        baseline_keys = row_keys(baseline_rows)
        baseline_means, baseline_weighted = aggregate(baseline_rows, weights)
        baseline_blocker_count = len([row for row in baseline_rows if row["blocker"]])

    missing_from_candidate = baseline_keys - candidate_keys
    missing_from_baseline = candidate_keys - baseline_keys
    if missing_from_candidate or missing_from_baseline:
        note("conditions are not paired. Both must be judged on identical rows.")
        if missing_from_candidate:
            note("  missing from {}: {}".format(candidate_name, format_missing(missing_from_candidate)))
        if missing_from_baseline:
            note("  missing from {}: {}".format(baseline_name, format_missing(missing_from_baseline)))
        fail("refusing to aggregate. Judge the missing rows, then re-run.")

    paired_already = {candidate_name} if baseline_record else {baseline_name, candidate_name}
    for name, condition_rows in sorted(by_condition.items()):
        if name in paired_already:
            continue
        extra_keys = row_keys(condition_rows)
        if extra_keys != candidate_keys:
            diff = (candidate_keys - extra_keys) | (extra_keys - candidate_keys)
            fail("condition {!r} was judged on different rows: {}. Refusing to aggregate.".format(name, format_missing(diff)))

    candidate_means, candidate_weighted = aggregate(candidate_rows, weights)
    candidate_blockers = [row for row in candidate_rows if row["blocker"]]

    trials = sorted({trial for _case, trial in candidate_keys})
    coverage = len({case for case, _trial in candidate_keys})

    # Verdict.
    reasons = []
    if candidate_blockers:
        reasons.append(
            "Blocking findings on {}: {}.".format(
                candidate_name,
                listing(["{} trial {}".format(row["case"], row["trial"]) for row in candidate_blockers]),
            )
        )
    for dimension in ("correctness", "safety"):
        delta = candidate_means[dimension] - baseline_means[dimension]
        if delta < -TOLERANCE - EPSILON:
            reasons.append("{} dropped {:.2f} below baseline. The limit is {:.2f}.".format(dimension, -delta, TOLERANCE))
    if candidate_weighted <= baseline_weighted + EPSILON:
        reasons.append("Weighted score {:.2f} does not beat baseline {:.2f}.".format(candidate_weighted, baseline_weighted))

    baseline_models = baseline_record.get("models") if baseline_record else run_models
    same_models = bool(run_models) and run_models == baseline_models and any(run_models.values())
    same_trials = (baseline_record.get("trials") == len(trials)) if baseline_record else True
    public = coverage == len(cases) and same_models and same_trials

    # Output.
    print("Eval score: {} vs {}".format(candidate_name, baseline_name))
    print("{} rows per condition. {} of {} cases, trials {}.".format(len(candidate_rows), coverage, len(cases), ",".join(str(trial) for trial in trials)))
    print("")
    header = "{:<20}{:>7}{:>10}{:>11}{:>8}"
    print(header.format("dimension", "weight", baseline_name[:9], candidate_name[:10], "delta"))
    for dimension in DIMENSIONS:
        delta = candidate_means[dimension] - baseline_means[dimension]
        print(header.format(dimension, weights[dimension], "{:.2f}".format(baseline_means[dimension]), "{:.2f}".format(candidate_means[dimension]), "{:+.2f}".format(delta)))
    print(header.format("weighted", 100, "{:.2f}".format(baseline_weighted), "{:.2f}".format(candidate_weighted), "{:+.2f}".format(candidate_weighted - baseline_weighted)))
    print("")
    print("Blockers: {} {}, {} {}.".format(candidate_name, len(candidate_blockers), baseline_name, baseline_blocker_count))
    print("")

    if reasons:
        print("Release verdict: FAIL")
        shown, rest = capped(reasons)
        for index, reason in enumerate(shown, start=1):
            print("{}. {}".format(index, reason))
        if rest > 0:
            print("{} more.".format(rest))
    else:
        print("Release verdict: PASS")

    if not public:
        print("Public comparison: no. Report these numbers internally only.")
        if coverage != len(cases):
            print("  {} of {} cases were judged.".format(coverage, len(cases)))
        if not same_models:
            print("  Model tiers differ between the baseline and this run, or are unknown.")
        if not same_trials:
            print("  Trial count differs from the baseline.")
    else:
        print("Public comparison: yes. Same cases, models, trials, and rubric.")

    if args.json:
        write_json(
            Path(args.json),
            {
                "kind": "hyperpower-eval-result",
                "created": now_iso(),
                "baseline": baseline_name,
                "candidate": candidate_name,
                "weights": weights,
                "cases_sha256": cases_digest,
                "rubric_sha256": rubric_digest,
                "rows_per_condition": len(candidate_rows),
                "baseline_means": baseline_means,
                "candidate_means": candidate_means,
                "baseline_weighted": baseline_weighted,
                "candidate_weighted": candidate_weighted,
                "candidate_blockers": [row["case"] for row in candidate_blockers],
                "verdict": "fail" if reasons else "pass",
                "reasons": reasons,
                "public_comparison": public,
            },
        )

    if args.record_baseline:
        record_baseline_file(
            args, by_condition, weights, cases_path, cases_digest, rubric_digest, run_models, candidate_name
        )

    return EXIT_VERDICT_FAIL if reasons else EXIT_OK


# ------------------------------------------------------------------- cli


RUN_EPILOG = """condition commands

  --baseline-cmd and --candidate-cmd each take one shell command. It runs once per row
  through `sh -c`, so pass it as a single quoted argument.

  stdin   the case prompt, verbatim, plus one trailing newline. Nothing else. No case
          id, no category, no criteria, no JSON wrapper.
  stdout  the whole response. It is written to responses/<case>-t<trial>-<label>.txt
          and judged exactly as printed. Print nothing but the response.
  stderr  ignored on exit 0. On any other exit the first 500 characters are recorded as
          execution.error on that row.
  exit    0 means a response was produced. Any other status, or a timeout, marks the row
          as did not run. A row that did not run is never folded into the score.

  Worked example. The baseline is the committed prompt, the candidate the edited one.

    git show HEAD:plugins/hyperpower/skills/review/SKILL.md > /tmp/hp-base.md
    cp plugins/hyperpower/skills/review/SKILL.md /tmp/hp-cand.md

    run_evals.py run \\
      --baseline-cmd  'claude -p --append-system-prompt "$(cat /tmp/hp-base.md)"' \\
      --candidate-cmd 'claude -p --append-system-prompt "$(cat /tmp/hp-cand.md)"'

  Check the wiring first with --baseline-cmd cat. The response file then holds the
  prompt back, and nothing is spent.

  --dry-run prints the row count, the commands, and the estimated cost from pricing.yml.
  It writes nothing and executes nothing.
"""

SCORE_EPILOG = """baseline file

  --baseline-file compares this run against scores recorded earlier, instead of against
  baseline rows judged in the same run. Write it with --record-baseline.

  A file that is absent, or one whose recorded_at is null, means no baseline exists. The
  command then prints the candidate scores, prints
  "%s", and exits 3.
  It never prints PASS.
""" % (NO_BASELINE,)


def build_parser():
    parser = argparse.ArgumentParser(
        prog="run_evals.py",
        description="Validate, run, and score the hyperpower eval suite.",
        epilog="Exit codes: 0 valid or PASS, 1 bad input, 2 verdict FAIL, 3 no baseline recorded.",
    )
    subparsers = parser.add_subparsers(dest="command")

    validate = subparsers.add_parser("validate", help="check cases.jsonl is well formed")
    validate.add_argument("--cases", default=str(DEFAULT_CASES), help="path to cases.jsonl")
    validate.add_argument("--all", action="store_true", help="print every error, not the first five")
    validate.set_defaults(func=cmd_validate)

    run = subparsers.add_parser(
        "run",
        help="write blind-labelled rows and, when a command is given, generate responses",
        epilog=RUN_EPILOG,
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    run.add_argument("--cases", default=str(DEFAULT_CASES), help="path to cases.jsonl")
    run.add_argument("--rubric", default=str(DEFAULT_RUBRIC), help="path to rubric.md")
    run.add_argument("--config", default=None, help="path to hyperpower.yml. Default: nearest one above the working directory")
    run.add_argument("--baseline", default="baseline", help="baseline condition name")
    run.add_argument("--baseline-cmd", default=None, help="shell command for the baseline. The prompt arrives on stdin, the response is read from stdout.")
    run.add_argument("--candidate", default="candidate", help="candidate condition name")
    run.add_argument("--candidate-cmd", default=None, help="shell command for the candidate. The prompt arrives on stdin, the response is read from stdout.")
    run.add_argument("--control", default=None, help="optional third condition name")
    run.add_argument("--control-cmd", default=None, help="shell command for the third condition")
    run.add_argument("--trials", type=int, default=3, help="trials per case per condition. Default 3.")
    run.add_argument("--seed", type=int, default=None, help="seed for label shuffling. Recorded in the manifest. Default: derived from the cases, rubric, conditions and trials, so the same run lands on the same run id.")
    run.add_argument("--timeout", type=int, default=600, help="per-response timeout in seconds. Default 600.")
    run.add_argument("--out", default=None, help="output directory. Default: .hyperpower/evals/<run-id>")
    run.add_argument("--force", action="store_true", help="overwrite a non-empty output directory")
    run.add_argument("--dry-run", action="store_true", help="print what would run and what it would cost. Writes nothing, executes nothing.")
    run.add_argument("--pricing", default=str(DEFAULT_PRICING), help="path to pricing.yml, for the --dry-run estimate")
    run.add_argument("--price-model", default=None, help="model to price the estimate at. Default: models.judgment from the config")
    run.add_argument("--assume-output-tokens", type=int, default=DEFAULT_OUTPUT_TOKENS, help="assumed output tokens per response, for --dry-run. Default {}.".format(DEFAULT_OUTPUT_TOKENS))
    run.add_argument("--assume-overhead-tokens", type=int, default=0, help="input tokens each condition sends on top of the case prompt, for --dry-run. Default 0.")
    run.set_defaults(func=cmd_run)

    score = subparsers.add_parser(
        "score",
        help="aggregate judged score rows and print the release verdict",
        epilog=SCORE_EPILOG,
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    score.add_argument("--run", default=None, help="run directory holding manifest.json and key.json")
    score.add_argument("--scores", default=None, help="path to scores.jsonl. Default: <run>/scores.jsonl")
    score.add_argument("--cases", default=None, help="path to cases.jsonl. Default: the one named in the manifest")
    score.add_argument("--rubric", default=str(DEFAULT_RUBRIC), help="path to rubric.md")
    score.add_argument("--baseline", default=None, help="baseline condition name")
    score.add_argument("--candidate", default=None, help="candidate condition name")
    score.add_argument("--baseline-file", default=None, help="recorded baseline to compare against, instead of baseline rows. An unrecorded or missing file exits 3.")
    score.add_argument("--record-baseline", default=None, help="write the baseline aggregate to this path")
    score.add_argument("--record-baseline-condition", default=None, help="condition to record. Default: the baseline condition")
    score.add_argument("--json", default=None, help="write the aggregate result to this path")
    score.set_defaults(func=cmd_score)

    return parser


_CONFIG_MODULE = []


def load_config_module():
    """Import the sibling hp-config once. It has no .py suffix, so name the loader."""
    if _CONFIG_MODULE:
        return _CONFIG_MODULE[0]
    import importlib.machinery
    import importlib.util
    path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "hp-config")
    loader = importlib.machinery.SourceFileLoader("hp_config", path)
    spec = importlib.util.spec_from_loader("hp_config", loader)
    module = importlib.util.module_from_spec(spec)
    loader.exec_module(module)
    _CONFIG_MODULE.append(module)
    return module


def state_root(root):
    """The directory the harness writes into. paths.state in config, or .hyperpower."""
    cfg = load_config_module()
    try:
        return cfg.state_dir_for(root)
    except cfg.ConfigError as exc:
        fail(exc.render())

def main(argv=None):
    parser = build_parser()
    args = parser.parse_args(argv)
    if not getattr(args, "func", None):
        parser.print_help()
        return EXIT_ERROR
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())
