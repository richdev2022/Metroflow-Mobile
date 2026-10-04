#!/usr/bin/env python3
"""Rough Dart syntax balance checker: strips comments and string literals
(handling escapes, raw strings, triple quotes and ${...} interpolation), then
verifies (), [], {} balance and reports the first imbalance with line info.
Also flags unterminated strings/comments. NOT a full parser — the checks that
caught real issues in previous mobile batches.
"""
import sys

OPEN = {'(': ')', '[': ']', '{': '}'}
CLOSE = {')': '(', ']': '[', '}': '{'}

def scan(path):
    with open(path, 'r', encoding='utf-8') as f:
        src = f.read()
    i, n = 0, len(src)
    line = 1
    stack = []  # (char, line)
    # string interpolation: stack of brace-depths active inside ${...}
    interp_depth = []  # list of counts of open braces per interpolation
    state = 'code'
    raw = False
    quote = ''
    errors = []

    def err(msg):
        errors.append(f'{path}: line {line}: {msg}')

    while i < n:
        c = src[i]
        nxt = src[i + 1] if i + 1 < n else ''
        if c == '\n':
            line += 1

        if state == 'code':
            if c == '/' and nxt == '/':
                state = 'line_comment'
                i += 2
                continue
            if c == '/' and nxt == '*':
                state = 'block_comment'
                i += 2
                continue
            if c == 'r' and nxt in ('"', "'"):
                # raw string (no escapes, no interpolation)
                if src[i+2:i+4] == nxt * 2:
                    quote = nxt * 3
                    i += 4
                else:
                    quote = nxt
                    i += 2
                state = 'string'
                raw = True
                continue
            if c in ('"', "'"):
                if src[i:i+3] == c * 3:
                    quote = c * 3
                    i += 3
                else:
                    quote = c
                    i += 1
                state = 'string'
                raw = False
                continue
            if c in OPEN:
                stack.append((c, line))
                # entering interpolation code resets nothing; fine
            elif c in CLOSE:
                if not stack:
                    err(f'unmatched closing {c!r}')
                else:
                    o, ol = stack.pop()
                    if o != CLOSE[c]:
                        err(f'closing {c!r} does not match {o!r} opened at line {ol}')
            elif c == '$' and nxt == '{':
                # interpolation start — brace counted on the NEXT loop iter
                pass
            i += 1
            continue

        if state == 'line_comment':
            if c == '\n':
                state = 'code'
            i += 1
            continue

        if state == 'block_comment':
            if c == '*' and nxt == '/':
                state = 'code'
                i += 2
                continue
            i += 1
            continue

        # state == 'string'
        if len(quote) == 3:
            if src[i:i+3] == quote:
                state = 'code'
                i += 3
                continue
        else:
            if c == quote:
                state = 'code'
                i += 1
                continue
            if c == '\n':
                err('unterminated single-line string')
                state = 'code'
                i += 1
                continue
        if not raw and c == '\\' and len(quote) != 3:
            i += 2
            continue
        if not raw and c == '\\' and len(quote) == 3:
            i += 2
            continue
        if not raw and c == '$' and nxt == '{':
            # jump into code-with-tracking until matching }
            depth = 1
            i += 2
            while i < n and depth > 0:
                ch = src[i]
                if ch == '\n':
                    line += 1
                elif ch == "'":
                    # nested single-quoted string inside interpolation
                    i += 1
                    while i < n:
                        ch2 = src[i]
                        if ch2 == '\n':
                            line += 1
                        if ch2 == '\\':
                            i += 2
                            continue
                        if ch2 == "'":
                            break
                        i += 1
                elif ch == '"':
                    i += 1
                    while i < n:
                        ch2 = src[i]
                        if ch2 == '\n':
                            line += 1
                        if ch2 == '\\':
                            i += 2
                            continue
                        if ch2 == '"':
                            break
                        i += 1
                elif ch == '{':
                    depth += 1
                elif ch == '}':
                    depth -= 1
                i += 1
            if depth != 0:
                err('unterminated ${...} interpolation')
                state = 'code'
            continue

        i += 1

    if state == 'string':
        err(f'unterminated string (quote={quote!r})')
    if state == 'block_comment':
        err('unterminated block comment')
    for o, ol in stack:
        err(f'unclosed {o!r} opened at line {ol}')

    return errors


if __name__ == '__main__':
    files = sys.argv[1:]
    all_ok = True
    for fpath in files:
        errs = scan(fpath)
        if errs:
            all_ok = False
            for e in errs:
                print('FAIL', e)
        else:
            print('OK  ', fpath)
    sys.exit(0 if all_ok else 1)
