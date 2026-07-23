#!/usr/bin/env python3
"""AZON (Azora Object Notation) reader for the engine's package tooling.

AZON is a tiny, comma-free data language (see ../../azon):
  * the whole document is an *implicit* object — top-level members need no braces,
  * members are `key: value` separated by newlines (no commas),
  * values are strings, numbers (int/float), objects `{ }`, arrays `[ ]`,
    or the barewords true / false / null,
  * `//` line comments are allowed anywhere whitespace is.

`load(path)` / `loads(text)` return ordinary Python dicts/lists/scalars.
This mirrors ../../azon/src/Azon.az closely enough for manifest parsing.
"""

from __future__ import annotations


class AzonError(ValueError):
    pass


class _Parser:
    def __init__(self, src: str):
        self.s = src
        self.i = 0
        self.n = len(src)

    # ── whitespace / comments ────────────────────────────────────────────
    def _skip_ws(self, stop_at_newline: bool = False) -> None:
        while self.i < self.n:
            c = self.s[self.i]
            if c == "\n":
                if stop_at_newline:
                    return
                self.i += 1
            elif c in " \t\r":
                self.i += 1
            elif c == "/" and self.i + 1 < self.n and self.s[self.i + 1] == "/":
                while self.i < self.n and self.s[self.i] != "\n":
                    self.i += 1
            else:
                return

    def _peek(self) -> str:
        return self.s[self.i] if self.i < self.n else ""

    # ── values ───────────────────────────────────────────────────────────
    def parse_document(self):
        obj = self._parse_members(top_level=True)
        self._skip_ws()
        if self.i < self.n:
            raise AzonError(f"trailing content at offset {self.i}")
        return obj

    def _parse_value(self):
        self._skip_ws()
        c = self._peek()
        if c == "{":
            return self._parse_object()
        if c == "[":
            return self._parse_array()
        if c == '"':
            return self._parse_string()
        return self._parse_word_or_number()

    def _parse_object(self):
        assert self.s[self.i] == "{"
        self.i += 1
        obj = self._parse_members(top_level=False)
        self._skip_ws()
        if self._peek() != "}":
            raise AzonError(f"expected '}}' at offset {self.i}")
        self.i += 1
        return obj

    def _parse_members(self, top_level: bool):
        obj: dict = {}
        while True:
            self._skip_ws()
            c = self._peek()
            if c == "" or (not top_level and c == "}"):
                return obj
            key = self._parse_key()
            self._skip_ws()
            if self._peek() != ":":
                raise AzonError(f"expected ':' after key '{key}' at offset {self.i}")
            self.i += 1
            obj[key] = self._parse_value()

    def _parse_array(self):
        assert self.s[self.i] == "["
        self.i += 1
        items = []
        while True:
            self._skip_ws()
            c = self._peek()
            if c == "":
                raise AzonError("unterminated array")
            if c == "]":
                self.i += 1
                return items
            items.append(self._parse_value())

    def _parse_key(self) -> str:
        c = self._peek()
        if c == '"':
            return self._parse_string()
        start = self.i
        while self.i < self.n and (self.s[self.i].isalnum() or self.s[self.i] in "_-."):
            self.i += 1
        if self.i == start:
            raise AzonError(f"expected a key at offset {self.i}")
        return self.s[start:self.i]

    def _parse_string(self) -> str:
        assert self.s[self.i] == '"'
        self.i += 1
        out = []
        while self.i < self.n:
            c = self.s[self.i]
            if c == "\\" and self.i + 1 < self.n:
                nxt = self.s[self.i + 1]
                out.append({"n": "\n", "t": "\t", "r": "\r", '"': '"', "\\": "\\"}.get(nxt, nxt))
                self.i += 2
                continue
            if c == '"':
                self.i += 1
                return "".join(out)
            out.append(c)
            self.i += 1
        raise AzonError("unterminated string")

    def _parse_word_or_number(self):
        start = self.i
        while self.i < self.n and self.s[self.i] not in " \t\r\n{}[]:\"":
            # stop a bareword at the start of a `//` comment
            if self.s[self.i] == "/" and self.i + 1 < self.n and self.s[self.i + 1] == "/":
                break
            self.i += 1
        word = self.s[start:self.i].strip()
        if word == "":
            raise AzonError(f"expected a value at offset {start}")
        if word == "true":
            return True
        if word == "false":
            return False
        if word == "null":
            return None
        try:
            return int(word)
        except ValueError:
            pass
        try:
            return float(word)
        except ValueError:
            pass
        return word


def loads(text: str):
    return _Parser(text).parse_document()


def load(path: str):
    with open(path, "r", encoding="utf-8") as fh:
        return loads(fh.read())


if __name__ == "__main__":
    import json
    import sys

    if len(sys.argv) != 2:
        print("usage: azon.py <file.azon>", file=sys.stderr)
        raise SystemExit(2)
    print(json.dumps(load(sys.argv[1]), indent=2))
