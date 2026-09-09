#!/usr/bin/env python3
"""Run deterministic token mutations from diff_cases through kswiftc.

The runner deliberately treats compiler signals, timeouts, silent failures,
and ICE diagnostics as findings. It never converts an unexpected process state
into a successful fuzz result.
"""

from __future__ import annotations

import argparse
import json
import os
import random
import re
import signal
import subprocess
import sys
import tempfile
import time
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Iterable, Sequence


ICE_PATTERN = re.compile(r"\bKSWIFTK-ICE-[A-Z0-9-]+\b")
# Must equal the `Keyword` enum in Sources/CompilerCore/Lexer/TokenModel.swift; see Scripts/check_mutation_fuzzer_keywords.sh.
IDENTIFIER_KEYWORDS = {
    "abstract",
    "actual",
    "annotation",
    "as",
    "break",
    "catch",
    "class",
    "companion",
    "const",
    "constructor",
    "continue",
    "crossinline",
    "data",
    "do",
    "dynamic",
    "else",
    "enum",
    "expect",
    "external",
    "false",
    "final",
    "finally",
    "for",
    "fun",
    "if",
    "import",
    "in",
    "infix",
    "inline",
    "inner",
    "interface",
    "internal",
    "is",
    "lateinit",
    "noinline",
    "null",
    "object",
    "open",
    "operator",
    "override",
    "package",
    "private",
    "protected",
    "public",
    "reified",
    "return",
    "sealed",
    "super",
    "suspend",
    "tailrec",
    "this",
    "throw",
    "true",
    "try",
    "typealias",
    "val",
    "value",
    "var",
    "vararg",
    "when",
    "while",
}
KEYWORD_REPLACEMENTS = (
    "class",
    "else",
    "false",
    "for",
    "fun",
    "if",
    "object",
    "return",
    "true",
    "val",
    "var",
    "when",
    "while",
)
IDENTIFIER_REPLACEMENTS = (
    "x",
    "y",
    "value",
    "main",
    "missing",
    "other",
)
OPERATOR_REPLACEMENTS = (
    "!",
    "!=",
    "%",
    "&&",
    "*",
    "+",
    "-",
    "/",
    "<",
    "<=",
    "==",
    ">",
    ">=",
    "=",
    "||",
    "?:",
    "..",
)
PUNCTUATION_REPLACEMENTS = (
    "(",
    ")",
    "[",
    "]",
    "{",
    "}",
    ",",
    ".",
    ":",
    ";",
    "?",
)


@dataclass(frozen=True)
class Token:
    start: int
    end: int
    text: str
    kind: str


@dataclass(frozen=True)
class Mutation:
    operation: str
    token_index: int
    second_token_index: int | None
    replacement: str | None


@dataclass(frozen=True)
class GeneratedCase:
    ordinal: int
    seed: int
    seed_file: str
    mutation: Mutation
    source: str


@dataclass(frozen=True)
class RunResult:
    kind: str
    returncode: int | None
    elapsed_seconds: float
    signal_name: str | None
    diagnostic_codes: tuple[str, ...]
    output: str


def is_identifier_start(char: str) -> bool:
    return char == "_" or char.isalpha() or ord(char) >= 0x80


def is_identifier_part(char: str) -> bool:
    return is_identifier_start(char) or char.isdigit()


def scan_tokens(source: str) -> list[Token]:
    """Scan significant Kotlin tokens while leaving trivia immutable."""

    tokens: list[Token] = []
    index = 0
    length = len(source)
    operators = (
        "===",
        "!==",
        "::",
        "?.",
        "!!",
        "->",
        "+=",
        "-=",
        "*=",
        "/=",
        "%=",
        "==",
        "!=",
        "<=",
        ">=",
        "&&",
        "||",
        "++",
        "--",
        "..",
        "?:",
        "<>",
    )

    while index < length:
        char = source[index]
        if char.isspace():
            index += 1
            continue
        if source.startswith("//", index):
            newline = source.find("\n", index + 2)
            index = length if newline == -1 else newline
            continue
        if source.startswith("/*", index):
            end = source.find("*/", index + 2)
            index = length if end == -1 else end + 2
            continue
        if char == "`":
            end = source.find("`", index + 1)
            end = length if end == -1 else end + 1
            tokens.append(Token(index, end, source[index:end], "identifier"))
            index = end
            continue
        if source.startswith('"""', index):
            end = source.find('"""', index + 3)
            end = length if end == -1 else end + 3
            tokens.append(Token(index, end, source[index:end], "string"))
            index = end
            continue
        if char in {'"', "'"}:
            quote = char
            end = index + 1
            while end < length:
                if source[end] == "\\":
                    end += 2
                    continue
                if source[end] == quote:
                    end += 1
                    break
                end += 1
            tokens.append(Token(index, min(end, length), source[index:min(end, length)], "string" if quote == '"' else "char"))
            index = min(end, length)
            continue
        if is_identifier_start(char):
            end = index + 1
            while end < length and is_identifier_part(source[end]):
                end += 1
            text = source[index:end]
            kind = "keyword" if text in IDENTIFIER_KEYWORDS else "identifier"
            tokens.append(Token(index, end, text, kind))
            index = end
            continue
        if char.isdigit():
            end = index + 1
            while end < length and (source[end].isalnum() or source[end] in "_."):
                if source.startswith("..", end):
                    break
                end += 1
            tokens.append(Token(index, end, source[index:end], "number"))
            index = end
            continue
        operator = next((candidate for candidate in operators if source.startswith(candidate, index)), None)
        if operator is not None:
            tokens.append(Token(index, index + len(operator), operator, "operator"))
            index += len(operator)
            continue
        kind = "operator" if char in "+-*/%=<>!&|?:" else "punctuation"
        tokens.append(Token(index, index + 1, char, kind))
        index += 1
    return tokens


def replacement_candidates(token: Token) -> tuple[str, ...]:
    if token.kind == "keyword":
        return KEYWORD_REPLACEMENTS
    if token.kind == "identifier":
        return IDENTIFIER_REPLACEMENTS
    if token.kind == "number":
        return ("0", "1", "2", "-1", "2147483647")
    if token.kind == "string":
        return ('""', '"x"', '"mutated"')
    if token.kind == "char":
        return ("'a'", "'\\n'", "'0'")
    if token.kind == "operator":
        return OPERATOR_REPLACEMENTS
    return PUNCTUATION_REPLACEMENTS


def choose_replacement(token: Token, rng: random.Random) -> str:
    candidates = tuple(candidate for candidate in replacement_candidates(token) if candidate != token.text)
    return rng.choice(candidates or (token.text,))


def mutate_source(source: str, rng: random.Random) -> tuple[str, Mutation]:
    tokens = scan_tokens(source)
    if not tokens:
        return source, Mutation("noop", 0, None, None)

    operation = rng.choice(("replace", "delete", "swap"))
    token_index = rng.randrange(len(tokens))
    token = tokens[token_index]
    if operation == "replace":
        replacement = choose_replacement(token, rng)
        mutated = source[:token.start] + replacement + source[token.end:]
        return mutated, Mutation(operation, token_index, None, replacement)
    if operation == "delete" or len(tokens) == 1:
        mutated = source[:token.start] + source[token.end:]
        return mutated, Mutation("delete", token_index, None, None)

    second_index = rng.randrange(len(tokens) - 1)
    if second_index >= token_index:
        second_index += 1
    first_index, second_index = sorted((token_index, second_index))
    first = tokens[first_index]
    second = tokens[second_index]
    mutated = (
        source[:first.start]
        + second.text
        + source[first.end:second.start]
        + first.text
        + source[second.end:]
    )
    return mutated, Mutation("swap", first_index, second_index, None)


def sanitize_name(value: str) -> str:
    sanitized = re.sub(r"[^A-Za-z0-9_.-]+", "_", value)
    return sanitized.strip("._") or "case"


def case_seed_stem(case: GeneratedCase) -> str:
    return sanitize_name(Path(case.seed_file).stem)


def discover_seed_files(seed_dir: Path, max_source_bytes: int) -> list[Path]:
    if not seed_dir.is_dir():
        raise ValueError(f"Seed directory does not exist: {seed_dir}")
    files = sorted(path for path in seed_dir.rglob("*.kt") if path.is_file())
    files = [path for path in files if path.stat().st_size <= max_source_bytes]
    if not files:
        raise ValueError(f"No Kotlin seed files at or below {max_source_bytes} bytes: {seed_dir}")
    return files


def generate_cases(
    seed_files: Sequence[Path],
    seed: int,
    cases: int,
    duration_seconds: float,
    deadline: float | None = None,
) -> list[GeneratedCase]:
    rng = random.Random(seed)
    generation_deadline = deadline if deadline is not None else time.monotonic() + duration_seconds
    generated: list[GeneratedCase] = []
    source_cache: dict[Path, str] = {}
    for ordinal in range(1, cases + 1):
        if time.monotonic() >= generation_deadline:
            break
        seed_file = rng.choice(seed_files)
        if seed_file not in source_cache:
            source_cache[seed_file] = seed_file.read_text(encoding="utf-8")
        mutated, mutation = mutate_source(source_cache[seed_file], rng)
        generated.append(GeneratedCase(ordinal, seed, str(seed_file), mutation, mutated))
    return generated


def write_generated_cases(output_dir: Path, generated: Iterable[GeneratedCase]) -> None:
    output_dir.mkdir(parents=True, exist_ok=True)
    manifest: list[dict[str, object]] = []
    for case in generated:
        filename = f"case-{case.ordinal:06d}-{case_seed_stem(case)}.kt"
        path = output_dir / filename
        path.write_text(case.source, encoding="utf-8")
        manifest.append(
            {
                "ordinal": case.ordinal,
                "seed": case.seed,
                "seed_file": case.seed_file,
                "mutation": asdict(case.mutation),
                "path": filename,
            }
        )
    (output_dir / "manifest.json").write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def run_compiler(
    compiler: Path,
    source_path: Path,
    output_path: Path,
    timeout_seconds: float,
    stdlib_library: Path | None,
) -> RunResult:
    started = time.monotonic()
    command = [str(compiler)]
    if stdlib_library is not None:
        command.extend(["--no-stdlib", "--stdlib-library", str(stdlib_library)])
    command.extend([str(source_path), "-o", str(output_path)])
    process = subprocess.Popen(
        command,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        start_new_session=True,
        text=False,
    )
    timed_out = False
    try:
        stdout, stderr = process.communicate(timeout=timeout_seconds)
    except subprocess.TimeoutExpired as error:
        timed_out = True
        try:
            os.killpg(process.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        stdout, stderr = process.communicate()
        if error.stdout:
            stdout = error.stdout + (stdout or b"")
        if error.stderr:
            stderr = error.stderr + (stderr or b"")

    elapsed = time.monotonic() - started
    output = (stdout or b"") + (stderr or b"")
    decoded = output.decode("utf-8", errors="replace")
    codes = tuple(sorted(set(ICE_PATTERN.findall(decoded))))
    returncode = process.returncode
    signal_name = None
    if timed_out:
        kind = "timeout"
    elif returncode is not None and returncode < 0:
        signal_name = signal.Signals(-returncode).name
        kind = "signal"
    elif codes:
        kind = "ice"
    elif returncode == 0:
        kind = "clean"
    elif decoded.strip():
        kind = "diagnostic"
    else:
        kind = "silent"
    return RunResult(kind, returncode, elapsed, signal_name, codes, decoded)


def save_finding(corpus_dir: Path, case_path: Path, case: GeneratedCase, result: RunResult) -> Path:
    corpus_dir.mkdir(parents=True, exist_ok=True)
    name = f"{case.ordinal:06d}-{case_seed_stem(case)}-{result.kind}"
    target = corpus_dir / f"{name}.kt"
    target.write_text(case.source, encoding="utf-8")
    target.with_suffix(".expect").write_text("no-crash\n", encoding="utf-8")
    metadata = {
        "seed": case.seed,
        "seed_file": case.seed_file,
        "mutation": asdict(case.mutation),
        "observed": asdict(result),
        "temporary_case": str(case_path),
    }
    target.with_suffix(".json").write_text(json.dumps(metadata, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    return target


def is_fuzzer_finding(result: RunResult) -> bool:
    return result.kind in {"signal", "timeout", "silent", "ice"}


def expectation_matches(expectation: str, result: RunResult) -> bool:
    if expectation == "no-crash":
        return result.kind in {"clean", "diagnostic", "ice"}
    if expectation == "clean":
        return result.kind == "clean"
    if expectation == "diagnostic":
        return result.kind == "diagnostic"
    if expectation == "ice":
        return result.kind == "ice"
    raise ValueError(f"Unsupported corpus expectation '{expectation}'")


def replay_corpus(
    compiler: Path,
    corpus_dir: Path,
    timeout_seconds: float,
    stdlib_library: Path | None,
) -> int:
    cases = sorted(path for path in corpus_dir.rglob("*.kt") if path.is_file())
    if not cases:
        print(f"PASS corpus is empty: {corpus_dir}")
        return 0
    failures = 0
    with tempfile.TemporaryDirectory(prefix="kswiftk-corpus-") as temporary:
        work_dir = Path(temporary)
        for index, source_path in enumerate(cases, start=1):
            expectation_path = source_path.with_suffix(".expect")
            expectation = expectation_path.read_text(encoding="utf-8").strip() if expectation_path.exists() else "no-crash"
            result = run_compiler(
                compiler,
                source_path,
                work_dir / f"corpus-{index}.out",
                timeout_seconds,
                stdlib_library,
            )
            try:
                matches = expectation_matches(expectation, result)
            except ValueError as error:
                print(f"FAIL {source_path}: {error}", file=sys.stderr)
                failures += 1
                continue
            if matches:
                print(f"PASS {source_path} [{expectation} -> {result.kind}]")
            else:
                print(
                    f"FAIL {source_path}: expected {expectation}, observed {result.kind}"
                    + (f" ({result.signal_name})" if result.signal_name else ""),
                    file=sys.stderr,
                )
                if result.output.strip():
                    print(result.output.rstrip(), file=sys.stderr)
                failures += 1
    print(f"Corpus replay: {len(cases) - failures}/{len(cases)} passed")
    return 1 if failures else 0


def fuzz(
    compiler: Path,
    seed_files: Sequence[Path],
    seed: int,
    cases: int,
    duration_seconds: float,
    timeout_seconds: float,
    corpus_dir: Path | None,
    report_path: Path | None,
    stdlib_library: Path | None,
) -> int:
    findings = 0
    records: list[dict[str, object]] = []
    deadline = time.monotonic() + duration_seconds
    with tempfile.TemporaryDirectory(prefix="kswiftk-fuzz-") as temporary:
        work_dir = Path(temporary)
        generated = generate_cases(seed_files, seed, cases, duration_seconds, deadline=deadline)
        for case in generated:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                break
            source_path = work_dir / f"case-{case.ordinal:06d}.kt"
            output_path = work_dir / f"case-{case.ordinal:06d}.out"
            source_path.write_text(case.source, encoding="utf-8")
            case_timeout = min(timeout_seconds, remaining)
            try:
                result = run_compiler(
                    compiler,
                    source_path,
                    output_path,
                    case_timeout,
                    stdlib_library,
                )
            except OSError as error:
                result = RunResult("silent", None, 0.0, None, (), f"failed to launch kswiftc: {error}")
            # A timeout observed under a truncated per-case budget (the duration
            # deadline shortened the timeout) is inconclusive: the case never
            # received the full timeout a legitimate compile may need.
            budget_truncated = result.kind == "timeout" and case_timeout < timeout_seconds
            finding = is_fuzzer_finding(result) and not budget_truncated
            if finding:
                findings += 1
                saved = save_finding(corpus_dir, source_path, case, result) if corpus_dir else None
                print(
                    f"FINDING case={case.ordinal} seed_file={case.seed_file} kind={result.kind}"
                    + (f" signal={result.signal_name}" if result.signal_name else "")
                    + (f" saved={saved}" if saved else ""),
                    file=sys.stderr,
                )
                if result.output.strip():
                    print(result.output.rstrip(), file=sys.stderr)
            elif budget_truncated:
                print(f"CASE {case.ordinal}/{cases} timeout (budget-truncated, inconclusive)")
            else:
                print(f"CASE {case.ordinal}/{cases} {result.kind}")
            records.append(
                {
                    "ordinal": case.ordinal,
                    "seed": case.seed,
                    "seed_file": case.seed_file,
                    "mutation": asdict(case.mutation),
                    "result": asdict(result),
                    "finding": finding,
                }
            )
    if report_path:
        report_path.parent.mkdir(parents=True, exist_ok=True)
        report_path.write_text(json.dumps(records, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(f"Mutation fuzzer: {len(records)} cases, {findings} findings, seed={seed}, workers=1")
    return 1 if findings else 0


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--seed-dir", type=Path, default=Path("Scripts/diff_cases"))
    parser.add_argument("--kswiftc", type=Path, default=Path(os.environ.get("KSWIFTC", ".build/debug/kswiftc")))
    parser.add_argument("--stdlib-library", type=Path)
    parser.add_argument("--seed", type=int, default=0)
    parser.add_argument("--cases", type=int, default=100)
    parser.add_argument("--duration-seconds", type=float, default=600.0)
    parser.add_argument("--timeout-seconds", type=float, default=10.0)
    parser.add_argument("--max-source-bytes", type=int, default=200_000)
    parser.add_argument("--workers", type=int, default=1)
    parser.add_argument("--corpus-dir", type=Path)
    parser.add_argument("--report", type=Path)
    parser.add_argument("--replay-dir", type=Path)
    parser.add_argument("--generate-only", action="store_true")
    parser.add_argument("--output-dir", type=Path)
    args = parser.parse_args()
    if args.workers != 1:
        parser.error("--workers must be 1; parallel mutation execution is intentionally not supported")
    if args.cases <= 0 or args.duration_seconds <= 0 or args.timeout_seconds <= 0:
        parser.error("--cases, --duration-seconds, and --timeout-seconds must be positive")
    if args.replay_dir and args.generate_only:
        parser.error("--replay-dir cannot be combined with --generate-only")
    if args.generate_only and not args.output_dir:
        parser.error("--generate-only requires --output-dir")
    return args


def main() -> int:
    args = parse_args()
    if args.replay_dir:
        if not args.replay_dir.is_dir():
            print(f"Corpus directory does not exist: {args.replay_dir}", file=sys.stderr)
            return 2
        if not args.kswiftc.is_file():
            print(f"kswiftc does not exist: {args.kswiftc}", file=sys.stderr)
            return 2
        if args.stdlib_library and not args.stdlib_library.exists():
            print(f"stdlib library does not exist: {args.stdlib_library}", file=sys.stderr)
            return 2
        return replay_corpus(
            args.kswiftc.resolve(),
            args.replay_dir,
            args.timeout_seconds,
            args.stdlib_library.resolve() if args.stdlib_library else None,
        )

    try:
        seed_files = discover_seed_files(args.seed_dir, args.max_source_bytes)
    except (OSError, ValueError) as error:
        print(str(error), file=sys.stderr)
        return 2

    if args.generate_only:
        generated = generate_cases(seed_files, args.seed, args.cases, args.duration_seconds)
        write_generated_cases(args.output_dir, generated)
        print(f"Generated {len(generated)} cases in {args.output_dir} with seed={args.seed}")
        return 0
    if not args.kswiftc.is_file():
        print(f"kswiftc does not exist: {args.kswiftc}", file=sys.stderr)
        return 2
    if args.stdlib_library and not args.stdlib_library.exists():
        print(f"stdlib library does not exist: {args.stdlib_library}", file=sys.stderr)
        return 2
    return fuzz(
        args.kswiftc.resolve(),
        seed_files,
        args.seed,
        args.cases,
        args.duration_seconds,
        args.timeout_seconds,
        args.corpus_dir,
        args.report,
        args.stdlib_library.resolve() if args.stdlib_library else None,
    )


if __name__ == "__main__":
    raise SystemExit(main())
