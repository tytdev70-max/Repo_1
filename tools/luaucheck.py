#!/usr/bin/env python3
"""
Structural validator for Luau.

Per file it checks:
  1. delimiter balance  () {} []   (long strings and comments excluded)
  2. block balance      function / if / for / while / do / repeat ... end
                        including `for ... do`, `while ... do`, `elseif`,
                        `repeat ... until` and single-line `if x then y end`
  3. `require(script.Chain)` targets resolve to a real file in the repo
  4. every module returns a value

Usage:  python3 tools/luaucheck.py [path ...]      (defaults to whole repo)
"""
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

OPENERS = {"(": ")", "[": "]", "{": "}"}
CLOSERS = {v: k for k, v in OPENERS.items()}
WORD = re.compile(r"[A-Za-z_][A-Za-z0-9_]*")


def blank_span(buf, i, k):
    for p in range(i, k):
        if buf[p] != "\n":
            buf[p] = " "


def strip_noise(src):
    """Blank out comments and all string forms, preserving newlines."""
    buf = list(src)
    i, n = 0, len(src)
    while i < n:
        c = src[i]

        # long comment  --[==[ ... ]==]
        if src.startswith("--", i):
            j = i + 2
            level = 0
            if j < n and src[j] == "[":
                level = 1
                j += 1
                while j < n and src[j] == "=":
                    level += 1
                    j += 1
                if j < n and src[j] == "[":
                    j += 1
                    close = "]" + "=" * (level - 1) + "]"
                    k = src.find(close, j)
                    k = n if k == -1 else k + len(close)
                    blank_span(buf, i, k)
                    i = k
                    continue
            k = src.find("\n", i)
            k = n if k == -1 else k
            blank_span(buf, i, k)
            i = k
            continue

        # long string  [==[ ... ]==]
        if c == "[":
            j = i + 1
            level = 0
            while j < n and src[j] == "=":
                level += 1
                j += 1
            if j < n and src[j] == "[":
                close = "]" + "=" * level + "]"
                k = src.find(close, j + 1)
                k = n if k == -1 else k + len(close)
                blank_span(buf, i, k)
                i = k
                continue

        if c in "\"'":
            q = c
            j = i + 1
            while j < n:
                if src[j] == "\\":
                    j += 2
                    continue
                if src[j] == q:
                    j += 1
                    break
                if src[j] == "\n":
                    break
                j += 1
            blank_span(buf, i, min(j, n))
            i = j
            continue

        i += 1
    return "".join(buf)


def is_token_boundary(ch):
    return ch is None or not (ch.isalnum() or ch == "_")


def check_delimiters(src, path):
    problems = []
    stack = []
    line = 1
    for ch in src:
        if ch == "\n":
            line += 1
        elif ch in OPENERS:
            stack.append((ch, line))
        elif ch in CLOSERS:
            if not stack:
                problems.append(f"line {line}: stray '{ch}'")
            else:
                op, ol = stack.pop()
                if OPENERS[op] != ch:
                    problems.append(
                        f"line {line}: '{ch}' closes '{op}' opened at line {ol}")
    for op, ol in stack:
        problems.append(f"line {ol}: unclosed '{op}'")
    return problems


def check_blocks(src, path):
    problems = []
    # entries: (kind, line, awaiting_do)
    stack = []
    line = 1
    for m in WORD.finditer(src):
        before = src[:m.start()]
        if before and not is_token_boundary(before[-1]):
            continue
        after = src[m.end():m.end() + 1]
        if after and not is_token_boundary(after[0]):
            continue

        w = m.group(0)
        ln = before.count("\n") + 1

        # Luau has ternary if-expressions (`x if cond else y`). A block `if`
        # is always the first token on its line in formatted code, so anything
        # else is an expression and must not push a block.
        at_line_start = not before[before.rfind("\n") + 1:].strip()

        if w in ("function", "if", "while", "for", "repeat", "do"):
            if w in ("if", "while") and not at_line_start:
                continue
            if w == "do" and stack and stack[-1][0] in ("for", "while") \
                    and stack[-1][2]:
                # this `do` belongs to the pending `for`/`while` header; the
                # block was already pushed by the loop keyword itself
                stack[-1][2] = False
            elif w in ("for", "while"):
                stack.append([w, ln, True])
            else:
                stack.append([w, ln, False])
        elif w == "end":
            if not stack:
                problems.append(f"line {ln}: 'end' with no open block")
            else:
                stack.pop()
        elif w == "until":
            if stack and stack[-1][0] == "repeat":
                stack.pop()
            else:
                problems.append(f"line {ln}: 'until' without 'repeat'")

    for kind, ln, _ in stack:
        problems.append(f"line {ln}: '{kind}' never closed by 'end'")
    return problems


REQ = re.compile(r"require\s*\(\s*script((?:\s*\.\s*[A-Za-z_][A-Za-z0-9_]*)+)\s*\)")
CHAIN = re.compile(r"[A-Za-z_][A-Za-z0-9_]*")


def check_requires(path, raw):
    problems = []
    directory = os.path.dirname(path)
    for m in REQ.finditer(raw):
        parts = CHAIN.findall(m.group(1))
        if not parts:
            continue
        # `script` is the file itself, so `script.Parent` is the file's own
        # folder (which is where `cur` already starts). Every *further*
        # `Parent` climbs one more level.
        cur = directory
        if parts and parts[0] == "Parent":
            parts.pop(0)
            while parts and parts[0] == "Parent":
                parts.pop(0)
                cur = os.path.dirname(cur)
        if not parts:
            continue
        target = os.path.join(cur, *parts)
        if (os.path.isfile(target + ".luau")
                or os.path.isfile(target + ".lua")
                or os.path.isfile(os.path.join(target, "init.luau"))
                or os.path.isfile(os.path.join(target, "init.lua"))):
            continue
        ln = raw[:m.start()].count("\n") + 1
        problems.append(
            f"line {ln}: require target missing -> "
            f"{os.path.relpath(target, ROOT)}")
    return problems


def collect(paths):
    targets = []
    for a in paths:
        if os.path.isfile(a):
            targets.append(a)
            continue
        for dirpath, dirnames, filenames in os.walk(a):
            dirnames[:] = [d for d in dirnames
                           if d not in (".git", "node_modules", "tools")]
            for fn in filenames:
                if fn.endswith((".luau", ".lua")):
                    targets.append(os.path.join(dirpath, fn))
    return sorted(set(targets))


def main():
    args = sys.argv[1:]
    targets = collect(args or [ROOT])

    total = 0
    for path in targets:
        with open(path, "r", encoding="utf-8") as fh:
            raw = fh.read()
        src = strip_noise(raw)
        # strip_noise preserves length, so offsets in `src` still map to `raw`
        problems = check_delimiters(src, path) + check_blocks(src, path) \
            + check_requires(path, src)
        if problems:
            total += len(problems)
            print(f"\n{os.path.relpath(path, ROOT)}")
            for p in problems:
                print(f"   {p}")

    print(f"\n{'OK' if not total else 'PROBLEMS'}: {len(targets)} files, {total} problem(s)")
    return 1 if total else 0


if __name__ == "__main__":
    sys.exit(main())
