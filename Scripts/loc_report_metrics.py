#!/usr/bin/env python3
"""Count name-dispatch constructs in Swift source files."""

from __future__ import annotations

import argparse
from dataclasses import dataclass
from pathlib import Path
import sys
from typing import Iterable, List, Optional, Sequence, Tuple


@dataclass(frozen=True)
class Token:
    kind: str
    value: str


def _is_identifier_start(character: str) -> bool:
    return character == "_" or character.isalpha() or ord(character) >= 128


def _is_identifier_continue(character: str) -> bool:
    return _is_identifier_start(character) or character.isdigit()


def _consume_string(source: str, start: int) -> int:
    """Return the first index after a normal, raw, or multiline string."""
    source_length = len(source)
    hash_count = 0
    while start + hash_count < source_length and source[start + hash_count] == "#":
        hash_count += 1

    quote_index = start + hash_count
    if quote_index >= source_length or source[quote_index] != '"':
        return start + 1

    multiline = source.startswith('"""', quote_index)
    opening_length = 3 if multiline else 1
    terminator = ('"""' if multiline else '"') + ("#" * hash_count)
    index = quote_index + opening_length
    while index < source_length:
        if source.startswith(terminator, index):
            return index + len(terminator)
        if source[index] == "\\":
            # This also skips escaped delimiters in raw strings.
            index += 2
        else:
            index += 1
    return source_length


def tokenize(source: str) -> List[Token]:
    """Tokenize enough Swift syntax to ignore comments and string contents."""
    tokens: List[Token] = []
    index = 0
    source_length = len(source)
    block_comment_depth = 0

    while index < source_length:
        if block_comment_depth:
            if source.startswith("/*", index):
                block_comment_depth += 1
                index += 2
            elif source.startswith("*/", index):
                block_comment_depth -= 1
                index += 2
            else:
                index += 1
            continue

        character = source[index]
        if character.isspace():
            index += 1
            continue
        if source.startswith("//", index):
            newline = source.find("\n", index + 2)
            index = source_length if newline < 0 else newline + 1
            continue
        if source.startswith("/*", index):
            block_comment_depth = 1
            index += 2
            continue
        if character == '"' or character == "#":
            string_end = _consume_string(source, index)
            if string_end != index + 1 or character == '"':
                tokens.append(Token("string", source[index:string_end]))
                index = string_end
                continue
        if character == "`":
            identifier_end = source.find("`", index + 1)
            if identifier_end >= 0:
                tokens.append(Token("identifier", source[index + 1 : identifier_end]))
                index = identifier_end + 1
                continue
        if _is_identifier_start(character):
            end = index + 1
            while end < source_length and _is_identifier_continue(source[end]):
                end += 1
            tokens.append(Token("identifier", source[index:end]))
            index = end
            continue
        if character.isdigit():
            end = index + 1
            while end < source_length and (source[end].isalnum() or source[end] in "_."):
                end += 1
            tokens.append(Token("number", source[index:end]))
            index = end
            continue

        tokens.append(Token("symbol", character))
        index += 1

    return tokens


def count_string_switch_cases(tokens: Sequence[Token]) -> int:
    """Count `case` clauses whose first pattern is a string literal."""
    return sum(
        1
        for index, token in enumerate(tokens[:-1])
        if token.kind == "identifier"
        and token.value == "case"
        and tokens[index + 1].kind == "string"
    )


def _is_literal_element(element: Sequence[Token]) -> bool:
    return len(element) == 1 and element[0].kind == "string"


def _count_array_literal_entries(tokens: Sequence[Token], opening_index: int) -> Tuple[int, int]:
    """Count direct string elements and return (count, closing-index)."""
    square_depth = 1
    parenthesis_depth = 0
    brace_depth = 0
    element: List[Token] = []
    count = 0
    index = opening_index + 1

    while index < len(tokens):
        token = tokens[index]
        value = token.value
        if value == "[":
            square_depth += 1
            element.append(token)
        elif value == "]":
            if square_depth == 1 and parenthesis_depth == 0 and brace_depth == 0:
                if _is_literal_element(element):
                    count += 1
                return count, index
            square_depth -= 1
            element.append(token)
        elif value == "(":
            parenthesis_depth += 1
            element.append(token)
        elif value == ")":
            parenthesis_depth = max(0, parenthesis_depth - 1)
            element.append(token)
        elif value == "{":
            brace_depth += 1
            element.append(token)
        elif value == "}":
            brace_depth = max(0, brace_depth - 1)
            element.append(token)
        elif value == "," and square_depth == 1 and parenthesis_depth == 0 and brace_depth == 0:
            if _is_literal_element(element):
                count += 1
            element = []
        else:
            element.append(token)
        index += 1

    return count, len(tokens)


def count_inline_string_set_entries(tokens: Sequence[Token]) -> int:
    """Count direct string elements in explicit `Set<String> = [...]` literals."""
    total = 0
    index = 0
    while index + 5 < len(tokens):
        pattern = tokens[index : index + 6]
        if (
            pattern[0].kind == "identifier"
            and pattern[0].value == "Set"
            and pattern[1].value == "<"
            and pattern[2].kind == "identifier"
            and pattern[2].value == "String"
            and pattern[3].value == ">"
            and pattern[4].value == "="
            and pattern[5].value == "["
        ):
            count, closing_index = _count_array_literal_entries(tokens, index + 5)
            total += count
            index = closing_index
        else:
            index += 1
    return total


def _count_metric(metric: str, paths: Iterable[str]) -> int:
    counter = count_string_switch_cases if metric == "string-switch-cases" else count_inline_string_set_entries
    total = 0
    for path in paths:
        if not Path(path).is_file():
            continue
        try:
            source = Path(path).read_text(encoding="utf-8")
        except OSError as error:
            raise RuntimeError(f"unable to read {path}: {error}") from error
        total += counter(tokenize(source))
    return total


def main(argv: Optional[Sequence[str]] = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "metric",
        choices=("string-switch-cases", "inline-string-set-entries"),
        help="metric to count",
    )
    parser.add_argument("paths", nargs="*", help="Swift source files to scan")
    args = parser.parse_args(argv)
    try:
        count = _count_metric(args.metric, args.paths)
    except RuntimeError as error:
        print(error, file=sys.stderr)
        return 1
    print(count)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
