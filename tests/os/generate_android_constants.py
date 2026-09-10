#!/usr/bin/env python3
"""Generate XIRASM constants and structure layouts from the Android NDK headers.

The symbol catalog answers "which library provides this name". This generator
answers the other half of writing native Android code by hand: the constants the
headers declare (window formats, key codes, event actions, asset modes) and the
byte offsets of the structures the platform hands back (ANativeActivity's
callback table, ANativeWindow_Buffer's fields, and so on), which a source
otherwise has to count by hand.

The generator parses the headers itself -- no compiler is involved -- and
`tests/os/validate_android_constants.py` puts every number it produced in front of
clang as a `_Static_assert`, so the two sides are checked against each other.

usage:
  python tests/os/generate_android_constants.py --ndk <ndk root> [--check]
"""
from __future__ import annotations

import argparse
import hashlib
import json
import re
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
GENERATOR = "generate_android_constants.py"
HEADER_PREFIX = "toolchains/llvm/prebuilt/windows-x86_64/sysroot/usr/include/android"

# Sizes and alignments for the two Android data models we emit: LP64 (arm64,
# x86-64) and ILP32 (armv7, i686). A value is (size, align). Types that are as
# wide as a pointer or as `long` differ between the models, so they are listed as
# pointer-sized instead of carrying one fixed size.
POINTER_SIZED = {
    "long", "long int", "signed long", "unsigned long", "unsigned long int",
    "size_t", "ssize_t", "ptrdiff_t", "intptr_t", "uintptr_t",
    "off_t", "time_t", "suseconds_t", "clock_t",
    "dev_t", "ino_t", "blkcnt_t", "blksize_t", "fsblkcnt_t", "fsfilcnt_t",
    "pthread_t", "pthread_key_t",
    "jobject", "jclass", "jstring", "jarray", "jthrowable", "jweak",
    "jmethodID", "jfieldID", "JNIEnv", "JavaVM",
    "AImageReader", "ACameraManager", "ACameraDevice", "ACameraCaptureSession",
    "ACameraMetadata", "ACaptureRequest", "ACaptureSessionOutput",
    "ACaptureSessionOutputContainer", "ANativeWindow", "AAssetManager", "AAsset",
    "AAssetDir", "AConfiguration", "AInputQueue", "ALooper", "AKeyEvent",
    "AMotionEvent", "AInputEvent", "ASensorManager", "ASensor", "ASensorEventQueue",
    "ASensorEventListener", "ASurfaceControl", "ASurfaceTransaction",
    "ASurfaceTransactionStats", "AFontMatcher", "AFont", "AThermalManager",
    "AStorageManager", "AObbInfo", "APerformanceHintManager", "APerformanceHintSession",
    "AChoreographer", "AHardwareBuffer", "ABuffer", "AImageDecoder",
    "AImageDecoderHeaderInfo", "AMediaCodec", "AMediaFormat", "AMediaDrm",
    "ASharedMemory", "AParcel", "AIBinder", "AIBinder_Class", "AStatus",
    "APersistableBundle", "ANativeActivity", "ANativeActivityCallbacks",
    "AInputEventExtra", "AImage", "FILE", "DIR",
}
PRIMITIVES = {
    "void": (0, 1),
    "char": (1, 1), "signed char": (1, 1), "unsigned char": (1, 1),
    "short": (2, 2), "short int": (2, 2), "signed short": (2, 2), "unsigned short": (2, 2),
    "unsigned short int": (2, 2),
    "int": (4, 4), "signed": (4, 4), "signed int": (4, 4), "unsigned": (4, 4), "unsigned int": (4, 4),
    "long long": (8, 8), "long long int": (8, 8), "unsigned long long": (8, 8),
    "unsigned long long int": (8, 8),
    "float": (4, 4), "double": (8, 8), "long double": (8, 8),
    "bool": (1, 1), "_Bool": (1, 1),
    "int8_t": (1, 1), "uint8_t": (1, 1), "int16_t": (2, 2), "uint16_t": (2, 2),
    "int32_t": (4, 4), "uint32_t": (4, 4), "int64_t": (8, 8), "uint64_t": (8, 8),
    "wchar_t": (4, 4), "char16_t": (2, 2), "char32_t": (4, 4),
    "va_list": (8, 4),
}
# Android or libc typedefs whose definition needs a header we do not parse, and
# whose size is the same under both models.
TYPEDEF_FALLBACK = {
    "pthread_mutex_t": (40, 8), "pthread_cond_t": (48, 8), "pthread_attr_t": (56, 8),
    "pthread_rwlock_t": (56, 8), "sem_t": (32, 8),
    "clockid_t": (4, 4), "useconds_t": (4, 4), "off64_t": (8, 8),
    "mode_t": (4, 4), "uid_t": (4, 4), "gid_t": (4, 4), "pid_t": (4, 4),
    "nlink_t": (4, 4), "socklen_t": (4, 4), "sa_family_t": (2, 2), "in_port_t": (2, 2),
    "in_addr_t": (4, 4), "fpos_t": (16, 8),
    "struct timespec": (16, 8), "struct timeval": (16, 8), "struct tm": (40, 8),
    "struct stat": (120, 8), "struct sockaddr": (16, 2), "struct sigaction": (32, 8),
    "siginfo_t": (128, 8), "sigset_t": (128, 8),
    "AInputEventType": (4, 4), "ARect": (16, 4),
}
# Compiler builtins the headers use in constant expressions, and the system
# headers whose names they reference (errno values, integer limits).
BUILTIN_MACROS = {
    "__INT8_MAX__": 127, "__INT16_MAX__": 32767, "__INT32_MAX__": 2147483647,
    "__INT64_MAX__": 9223372036854775807,
    "__INT8_MIN__": -128, "__INT16_MIN__": -32768, "__INT32_MIN__": -2147483648,
    "__INT64_MIN__": -9223372036854775808,
    "__UINT8_MAX__": 255, "__UINT16_MAX__": 65535, "__UINT32_MAX__": 4294967295,
    "__UINT64_MAX__": 18446744073709551615,
    "__SIZE_MAX__": 18446744073709551615, "__PTRDIFF_MAX__": 9223372036854775807,
    "__CHAR_BIT__": 8, "__SIZEOF_INT__": 4, "__SIZEOF_LONG__": 8, "__SIZEOF_POINTER__": 8,
    "__SIZEOF_SIZE_T__": 8, "__WCHAR_MAX__": 2147483647,
    "INT8_MAX": 127, "INT16_MAX": 32767, "INT32_MAX": 2147483647,
    "INT64_MAX": 9223372036854775807, "UINT8_MAX": 255, "UINT16_MAX": 65535,
    "UINT32_MAX": 4294967295, "UINT64_MAX": 18446744073709551615,
    "INT8_MIN": -128, "INT16_MIN": -32768, "INT32_MIN": -2147483648,
    "INT64_MIN": -9223372036854775808,
    "SIZE_MAX": 18446744073709551615, "TRUE": 1, "FALSE": 0,
}
SYSTEM_HEADERS = ("errno.h", "stdint.h", "limits.h", "sys/types.h", "sys/errno.h",
                  "time.h", "unistd.h", "fcntl.h", "sys/stat.h", "sys/mman.h",
                  "dlfcn.h", "pthread.h", "signal.h", "sys/socket.h", "netinet/in.h",
                  "stdlib.h", "stdio.h", "string.h", "sched.h", "jni.h",
                  "linux/errno.h", "asm-generic/errno.h", "asm-generic/errno-base.h")

TYPE_START = re.compile(r"^\s*(typedef\s+)?(struct|union|enum)\b")
ENUM_HEAD = re.compile(r"\benum\s+([A-Za-z_]\w*)?\s*(?::\s*([A-Za-z_]\w*)\s*)?\{")
RECORD_HEAD = re.compile(r"\b(?:typedef\s+)?(struct|union)\s*([A-Za-z_]\w*)?\s*\{")
DEFINE = re.compile(r"^\s*#\s*define\s+([A-Za-z_]\w*)(\([^)]*\))?\s*(.*)$")
INCLUDE = re.compile(r'^\s*#\s*include\s*[<"]([^">]+)[">]')
CONDITIONAL_START = re.compile(r"^\s*#\s*(if|ifdef|ifndef)\b\s*(.*)$")
CONDITIONAL_MID = re.compile(r"^\s*#\s*(elif|else|endif)\b\s*(.*)$")
CPP_MARKER = re.compile(r"^\s*(namespace|class|template\s*<)|::")


class InputError(Exception):
    pass


def require(condition, location, message):
    if not condition:
        raise InputError(f"{location}: {message}")


def strip_comments(text: str) -> str:
    text = re.sub(r"/\*.*?\*/", " ", text, flags=re.DOTALL)
    return re.sub(r"//[^\n]*", "", text)


def balanced(text: str, start: int, open_char: str = "{", close_char: str = "}") -> int:
    """Index just past the delimiter matching the one at `start`."""
    depth = 0
    index = start
    while index < len(text):
        char = text[index]
        if char == open_char:
            depth += 1
        elif char == close_char:
            depth -= 1
            if depth == 0:
                return index + 1
        index += 1
    raise InputError("unterminated block")


def split_top_level(text: str, separator: str = ",") -> list[str]:
    parts, depth, current = [], 0, []
    for char in text:
        if char in "([{":
            depth += 1
        elif char in ")]}":
            depth -= 1
        if char == separator and depth == 0:
            parts.append("".join(current))
            current = []
            continue
        current.append(char)
    if "".join(current).strip():
        parts.append("".join(current))
    return parts


class Evaluator:
    """Integer constant expressions over the names collected so far.

    C gives these expressions a type, and the type decides the result: `1 << 31`
    stays an `int` and wraps to -2147483648, while `0x80000000` is an `unsigned
    int` and keeps 2147483648. Values therefore carry a type tag through the
    evaluation instead of being plain Python integers.
    """

    I32, U32, I64, U64 = (32, True), (32, False), (64, True), (64, False)

    def __init__(self):
        self.values: dict[str, int] = {}
        self.pending: dict[str, tuple[str, str]] = {}

    def define(self, name: str, expression: str, location: str) -> None:
        self.pending[name] = (expression, location)

    def resolve(self, expression: str, location: str, seen: tuple[str, ...] = ()) -> int:
        value, _ = self.typed(expression, location, seen)
        return value

    def uses_long_suffix(self, expression: str, seen: tuple[str, ...] = ()) -> bool:
        """True when the expression depends on `long` being 64 bits wide.

        `1UL << 32` is 4294967296 on arm64 and x86-64 but zero on armv7 and i686,
        so those constants cannot carry one value for both data models.
        """
        if re.search(r"\b(?:0[xX][0-9a-fA-F]+|\d+)[uU]?[lL]\b", expression):
            return True
        for name in re.findall(r"[A-Za-z_]\w*", expression):
            if name in seen:
                continue
            entry = self.pending.get(name)
            if entry and self.uses_long_suffix(entry[0], seen + (name,)):
                return True
        return False

    def typed(self, expression: str, location: str, seen: tuple[str, ...] = ()) -> tuple[int, tuple]:
        self.tokens = self.tokenize(expression, location)
        self.position = 0
        value, kind = self.expression(location, seen)
        if self.position != len(self.tokens):
            raise InputError(f"{location}: trailing tokens in {' '.join(self.tokens)}")
        return value, kind

    @staticmethod
    def tokenize(expression: str, location: str) -> list[str]:
        cleaned = expression.strip().rstrip(";").strip()
        if not cleaned:
            raise InputError(f"{location}: empty constant expression")
        # The suffix stays attached: it decides signedness and width. Nullability
        # annotations and casts of a known type do not change the value.
        cleaned = re.sub(r"\b_?(Nullable|Nonnull|null_unspecified|nullable|nonnull)\b", " ", cleaned)
        cleaned = re.sub(r"\(\s*(?:unsigned\s+|signed\s+)?(?:long\s+long|long|int|short|char|"
                         r"u?int(?:8|16|32|64)_t|size_t|u?intptr_t)\s*\*?\s*\)", " ", cleaned)
        return re.findall(r"0[xX][0-9a-fA-F]+[uUlL]*|\d+[uUlL]*|[A-Za-z_]\w*|<<|>>|<=|>=|==|!=|&&|\|\||\S",
                          cleaned)

    def value_of(self, name: str, location: str, seen: tuple[str, ...]) -> tuple[int, tuple]:
        if name in self.values:
            value = self.values[name]
            if -2**31 <= value <= 2**31 - 1:
                return value, self.I32
            return value, self.U64 if value > 2**63 - 1 else self.I64
        if name in seen:
            raise InputError(f"{location}: cyclic constant {name}")
        if name not in self.pending:
            raise InputError(f"{location}: unknown constant {name}")
        expression, origin = self.pending[name]
        # Resolving a referenced name parses another expression, so the cursor has
        # to survive the nested call: without this, `A | B` would evaluate to A.
        saved = (self.tokens, self.position)
        try:
            value, kind = self.typed(expression, origin, seen + (name,))
        finally:
            self.tokens, self.position = saved
        self.values[name] = value
        return value, kind

    PRECEDENCE = [["|"], ["^"], ["&"], ["<<", ">>"], ["+", "-"], ["*", "/", "%"]]

    @staticmethod
    def wrap(value: int, kind: tuple) -> int:
        bits, signed = kind
        value &= (1 << bits) - 1
        if signed and value >= 1 << (bits - 1):
            value -= 1 << bits
        return value

    @staticmethod
    def common(left: tuple, right: tuple) -> tuple:
        if 64 in (left[0], right[0]):
            return Evaluator.U64 if not (left[1] and right[1]) else Evaluator.I64
        if not (left[1] and right[1]):
            return Evaluator.U32
        return Evaluator.I32

    def peek(self):
        return self.tokens[self.position] if self.position < len(self.tokens) else None

    def take(self):
        token = self.peek()
        self.position += 1
        return token

    def expression(self, location, seen) -> tuple[int, tuple]:
        return self.binary(0, location, seen)

    def binary(self, level: int, location, seen) -> tuple[int, tuple]:
        if level >= len(self.PRECEDENCE):
            return self.unary(location, seen)
        value, kind = self.binary(level + 1, location, seen)
        while self.peek() in self.PRECEDENCE[level]:
            operator = self.take()
            right, right_kind = self.binary(level + 1, location, seen)
            if operator in ("<<", ">>"):
                # C keeps the type of the left operand for a shift.
                result = value << right if operator == "<<" else value >> right
            else:
                kind = self.common(kind, right_kind)
                result = {
                    "|": lambda a, b: a | b, "^": lambda a, b: a ^ b, "&": lambda a, b: a & b,
                    "+": lambda a, b: a + b, "-": lambda a, b: a - b, "*": lambda a, b: a * b,
                    "/": lambda a, b: int(a / b), "%": lambda a, b: a % b,
                }[operator](value, right)
            value = self.wrap(result, kind)
        return value, kind

    def unary(self, location, seen) -> tuple[int, tuple]:
        token = self.peek()
        if token in ("-", "+", "~", "!"):
            self.take()
            value, kind = self.unary(location, seen)
            if token == "-":
                return self.wrap(-value, kind), kind
            if token == "+":
                return value, kind
            if token == "~":
                return self.wrap(~value, kind), kind
            return (0 if value else 1), self.I32
        return self.primary(location, seen)

    def primary(self, location, seen) -> tuple[int, tuple]:
        token = self.take()
        if token is None:
            raise InputError(f"{location}: incomplete constant expression")
        if token == "(":
            value, kind = self.expression(location, seen)
            require(self.take() == ")", location, "unbalanced parenthesis in constant")
            return value, kind
        literal = re.fullmatch(r"(0[xX][0-9a-fA-F]+|\d+)([uUlL]*)", token)
        if literal:
            digits, suffix = literal.group(1), literal.group(2).lower()
            # C reads a leading zero as octal, which the headers use for masks.
            if digits[:2].lower() == "0x":
                value = int(digits, 16)
            elif len(digits) > 1 and digits.startswith("0"):
                value = int(digits, 8)
            else:
                value = int(digits, 10)
            unsigned = "u" in suffix
            long_count = suffix.count("l")
            # This generator targets the 64-bit data models, where `long` is 64
            # bits wide; constants that lean on that are marked for the checker.
            wide = long_count >= 1 or value > 2**32 - 1
            if wide:
                return value, (self.U64 if unsigned else self.I64)
            if unsigned:
                return value, self.U32
            if digits[:2].lower() == "0x" and value > 2**31 - 1:
                return value, self.U32
            return value, self.I32
        if re.fullmatch(r"[A-Za-z_]\w*", token):
            return self.value_of(token, location, seen)
        raise InputError(f"{location}: unsupported token {token!r} in constant expression")


class Layout:
    """Sizes and alignments of one type, under both Android data models."""

    def __init__(self, name: str):
        self.name = name
        self.kind = "opaque"
        self.origin = ""
        self.c_kind = ""
        self.incomplete = False
        self.fields: list[tuple[str, str, int]] = []      # (field, type text, array count or 0)
        self.complete = False


class HeaderParser:
    def __init__(self, evaluator: Evaluator, api: int):
        self.evaluator = evaluator
        self.api = api
        self.types: dict[str, Layout] = {}
        self.constants: dict[str, list[tuple[str, int]]] = {}
        self.notes: dict[str, list[str]] = {}
        self.enums: dict[str, list[tuple[str, list[tuple[str, str | None]]]]] = {}
        self.defines: dict[str, list[tuple[str, str]]] = {}
        self.anonymous = 0

    def next_anonymous(self) -> str:
        """A unique name for an unnamed record or enum.

        Unnamed types used to be numbered by their offset in the body, which made
        two records in the same header share a name; the second definition then
        replaced the first and layouts silently picked up the wrong members.
        """
        self.anonymous += 1
        return f"anonymous_{self.anonymous}"

    # --- preprocessing ----------------------------------------------------
    def read(self, path: Path, include_root: Path, expand: bool = False,
             seen: tuple[str, ...] = ()) -> str:
        """Strip comments and resolve conditionals.

        Android headers are read without expanding includes: each header owns the
        declarations it spells itself, so the partitions do not repeat everything
        a header happens to include. System headers are read with expansion,
        because the constants the Android headers reference (errno values, limits)
        live behind one or two more includes. Types are collected globally either
        way, so a structure may use a type another header declares.
        """
        text = strip_comments(path.read_text(encoding="utf-8", errors="replace"))
        if any(CPP_MARKER.search(line) for line in text.splitlines()):
            raise InputError("C++ header")
        lines, stack, out = text.splitlines(), [], []
        for line in lines:
            match = CONDITIONAL_START.match(line)
            if match:
                stack.append(self.condition(match.group(1), match.group(2)))
                continue
            match = CONDITIONAL_MID.match(line)
            if match:
                require(stack, str(path), "conditional without an opening directive")
                if match.group(1) == "elif":
                    stack[-1] = False if stack[-1] else self.condition("if", match.group(2))
                elif match.group(1) == "else":
                    stack[-1] = not stack[-1]
                else:
                    stack.pop()
                continue
            if stack and not all(stack):
                continue
            include = INCLUDE.match(line)
            if include:
                if not expand:
                    continue
                relative = include.group(1)
                candidates = [path.parent / relative, include_root / relative]
                target = next((item for item in candidates if item.is_file()), None)
                if target is not None and relative not in seen:
                    out.append(self.read(target, include_root, True, seen + (relative,)))
                continue
            out.append(line)
        return "\n".join(out)

    def condition(self, keyword: str, expression: str) -> bool:
        expression = expression.strip()
        if keyword == "ifdef":
            return expression in self.evaluator.values or expression in self.evaluator.pending
        if keyword == "ifndef":
            return not (expression in self.evaluator.values or expression in self.evaluator.pending)
        expression = re.sub(r"defined\s*\(\s*(\w+)\s*\)",
                            lambda m: "1" if m.group(1) in self.evaluator.pending or m.group(1) in self.evaluator.values else "0",
                            expression)
        # The `__has_*` operators take arguments, so they cannot be substituted as
        # values; a header that guards on them takes the conservative branch.
        expression = re.sub(r"\b__has_\w+\s*\([^()]*\)", "0", expression)
        expression = re.sub(r"\b[A-Za-z_]\w*\b",
                            lambda m: str(self.evaluator.values.get(m.group(0), 0)), expression)
        expression = re.sub(r"[^0-9()+\-*/%<>=!&|^~ ]", " ", expression)
        try:
            return bool(eval(expression, {"__builtins__": {}}, {}))  # noqa: S307 - digits and operators only
        except Exception:
            return False

    # --- declarations -----------------------------------------------------
    def harvest_defines(self, text: str, header: str) -> None:
        for match in re.finditer(r"^\s*#\s*define\s+([A-Za-z_]\w*)(\([^)]*\))?\s*(.*)$", text, re.MULTILINE):
            name, parameters, value = match.group(1), match.group(2), match.group(3).strip()
            if parameters or not value:
                continue
            if re.search(r'["\']|\\$', value):
                continue
            if re.search(r"\d+\.\d*[fFlL]?|\d+[fF]\b", value):
                continue                                   # floating point, not an integer
            if not re.fullmatch(r"[A-Za-z_0-9xX() \t+\-*/%<>&|^~!.,]+", value):
                continue
            self.evaluator.define(name, value, f"{header}:{name}")
            self.defines.setdefault(header, []).append((name, value))

    def parse(self, header: str, text: str) -> None:
        self.constants.setdefault(header, [])
        self.notes.setdefault(header, [])
        index = 0
        while index < len(text):
            candidates = []
            enum_match = ENUM_HEAD.search(text, index)
            if enum_match:
                candidates.append((enum_match.start(), "enum", enum_match))
            record_match = RECORD_HEAD.search(text, index)
            if record_match:
                candidates.append((record_match.start(), "record", record_match))
            typedef_index = text.find("typedef", index)
            if typedef_index >= 0:
                candidates.append((typedef_index, "typedef", None))
            if not candidates:
                break
            position, kind, match = min(candidates, key=lambda item: item[0])
            if kind == "typedef":
                # `typedef struct X { ... } X;` starts with the keyword, but the
                # definition is what declares the type; letting the typedef branch
                # win would rescan the members as if they were declarations.
                keyword = re.match(r"\s*(struct|union|enum)\b", text[position + len("typedef"):])
                if keyword:
                    start = position + len("typedef") + keyword.start(1)
                    brace, semi = text.find("{", start), text.find(";", start)
                    if brace >= 0 and (semi < 0 or brace < semi):
                        if keyword.group(1) == "enum":
                            index = self.parse_enum(header, text, start)[0]
                        else:
                            sub = RECORD_HEAD.match(text, start)
                            require(sub, header, "unparsable record after typedef")
                            index = self.parse_record(header, text, sub, True)[0]
                        continue
                index = self.parse_typedef(header, text, position)
            elif kind == "enum":
                index = self.parse_enum(header, text, position)[0]
            else:
                index = self.parse_record(header, text, match)[0]

    def parse_enum(self, header: str, text: str, index: int) -> tuple[int, str]:
        match = ENUM_HEAD.match(text, index)
        require(match, header, "unparsable enum")
        end = balanced(text, match.end() - 1)
        body = text[match.end():end - 1]
        name = match.group(1) or self.next_anonymous()
        entries: list[tuple[str, str | None]] = []
        for entry in split_top_level(body):
            entry = entry.strip()
            if not entry:
                continue
            expression = None
            if "=" in entry:
                label, expression = entry.split("=", 1)
                expression = expression.strip()
            else:
                label = entry
            label = label.strip()
            if not re.fullmatch(r"[A-Za-z_]\w*", label):
                self.notes[header].append(f"enum {name}: skipped {label!r}")
                continue
            if expression is not None:
                self.evaluator.define(label, expression, f"{header}:{label}")
            entries.append((label, expression))
        self.enums.setdefault(header, []).append((name, entries))
        layout = Layout(name)
        layout.kind = "enum"
        layout.origin = header
        self.types[name] = layout
        return end, name

    def resolve_constants(self, header: str) -> list[tuple[str, int, bool]]:
        """Evaluate a header's enumerators and defines, in declaration order.

        Values are resolved here rather than while parsing, because a header may
        reference a constant that another header declares and that header may not
        have been read yet.
        """
        resolved: list[tuple[str, int, bool]] = []
        for name, entries in self.enums.get(header, []):
            # The first enumerator without a value is zero, so the counter starts
            # one below it.
            current, kind = -1, Evaluator.I32
            for label, expression in entries:
                if expression is None:
                    current = Evaluator.wrap(current + 1, kind)
                else:
                    try:
                        current, kind = self.evaluator.typed(expression, f"{header}:{label}")
                    except InputError as error:
                        self.notes[header].append(f"enum {name}: {error}")
                        continue
                resolved.append((label, current, self.evaluator.uses_long_suffix(expression or "")))
        for name, expression in self.defines.get(header, []):
            try:
                value = self.evaluator.resolve(expression, f"{header}:{name}")
            except InputError as error:
                self.notes[header].append(f"define {name}: {error}")
                continue
            resolved.append((name, value, self.evaluator.uses_long_suffix(expression)))
        return resolved

    def parse_record(self, header: str, text: str, match: re.Match, aliasing: bool = False) -> tuple[int, str]:
        kind, name = match.group(1), match.group(2)
        end = balanced(text, match.end() - 1)
        body = text[match.end():end - 1]
        tail = re.match(r"\s*([A-Za-z_]\w*)?", text[end:])
        # The word after the closing brace names the type only inside a typedef;
        # on a nested member it names the member, not a type.
        alias = tail.group(1) if aliasing and tail and tail.group(1) else None
        layout = Layout(name or alias or self.next_anonymous())
        layout.kind = kind
        layout.origin = header
        # A tag has to be spelled `struct X` in C; a typedef name stands alone.
        layout.c_kind = kind if name else "typedef"
        body = self.hoist_nested(header, body)
        for field in split_top_level(body, ";"):
            entry = self.parse_field(field.strip())
            if entry is None:
                if field.strip():
                    self.notes[header].append(f"{kind} {layout.name}: skipped field {field.strip()[:48]!r}")
                    layout.incomplete = True
                continue
            layout.fields.append(entry)
        self.types[layout.name] = layout
        if alias and alias != layout.name:
            self.types[alias] = layout
        return end, layout.name

    def hoist_nested(self, header: str, body: str) -> str:
        """Register definitions nested inside a record and name their members.

        An anonymous `struct`/`union` member still occupies space and alignment, so
        it is turned into an unnamed field of the nested type instead of being
        dropped, which would move every offset that follows it.
        """
        pattern = re.compile(r"\b(struct|union|enum)\s*([A-Za-z_]\w*)?\s*\{")
        pieces, index, counter = [], 0, 0
        while True:
            match = pattern.search(body, index)
            if not match:
                pieces.append(body[index:])
                break
            pieces.append(body[index:match.start()])
            if match.group(1) == "enum":
                end, nested_name = self.parse_enum(header, body, match.start())
            else:
                end, nested_name = self.parse_record(header, body, match)
            tail = re.match(r"\s*([A-Za-z_]\w*)?", body[end:])
            declarator = tail.group(1) if tail and tail.group(1) else ""
            if declarator:
                pieces.append(f"{nested_name} {declarator};")
                index = end + tail.end()
            else:
                counter += 1
                pieces.append(f"{nested_name} __unnamed_{counter};")
                index = end
        return "".join(pieces)

    FIELD = re.compile(r"^(?P<type>.+?)\s*(?P<stars>\*+)?\s*(?P<name>[A-Za-z_]\w*)"
                       r"(?P<array>\s*\[[^\]]*\])?$")

    def parse_field(self, field: str) -> tuple[str, str, int] | None:
        if not field or field.startswith("typedef"):
            return None
        field = re.sub(r"__attribute__\s*\(\(.*?\)\)", " ", field)
        field = re.sub(r"\[\[.*?\]\]", " ", field).strip()
        if not field:
            return None
        if ":" in field and "(" not in field.split(":")[0]:
            return None                                    # bitfield
        function = re.match(r"^(?P<type>.+?)\(\s*\*\s*(?P<name>[A-Za-z_]\w*)\s*\)\s*\(.*\)$", field)
        if function:
            return function.group("name"), function.group("type").strip() + "*", 0
        match = self.FIELD.match(field)
        if not match:
            return None
        type_text = match.group("type").strip()
        if match.group("stars"):
            type_text += match.group("stars")
        count = 0
        if match.group("array"):
            inner = match.group("array").strip()[1:-1].strip()
            count = int(inner) if inner.isdigit() else -1   # -1 marks an incomplete array
        return match.group("name"), type_text, count

    def parse_typedef(self, header: str, text: str, index: int) -> int:
        # The statement ends at the first semicolon outside any braces.
        end, depth = index, 0
        while end < len(text):
            if text[end] == "{":
                depth += 1
            elif text[end] == "}":
                depth -= 1
            elif text[end] == ";" and depth <= 0:
                break
            end += 1
        if end >= len(text):
            return len(text)
        statement = text[index:end + 1]
        body = statement[len("typedef"):].strip().rstrip(";").strip()
        match = re.match(r"^(?P<type>.+?)\s*(?P<stars>\*+)?\s*(?P<name>[A-Za-z_]\w*)$", body)
        if match:
            type_text = match.group("type").strip() + (match.group("stars") or "")
            existing = self.types.get(type_text)
            if existing is not None:
                self.types[match.group("name")] = existing
            else:
                layout = Layout(match.group("name"))
                layout.kind = "alias:" + type_text
                self.types[match.group("name")] = layout
        return end + 1

    # --- layout -----------------------------------------------------------
    def measure(self, type_text: str, model: int) -> tuple[int, int]:
        text = type_text.strip()
        text = re.sub(r"\b_?(Nullable|Nonnull|nullable|nonnull|null_unspecified)\b", " ", text)
        text = re.sub(r"\b(const|volatile|restrict|struct|union|enum|signed|unsigned)\b",
                      lambda m: m.group(1) if m.group(1) in ("struct", "union", "enum", "signed", "unsigned") else "", text)
        text = re.sub(r"\s+", " ", text).strip()
        if text.endswith("*"):
            return model, model
        key = text.replace("struct ", "").replace("union ", "").replace("enum ", "").strip()
        if text in POINTER_SIZED or key in POINTER_SIZED:
            return model, model
        if text in PRIMITIVES:
            return PRIMITIVES[text]
        if key in PRIMITIVES:
            return PRIMITIVES[key]
        if text in TYPEDEF_FALLBACK:
            return TYPEDEF_FALLBACK[text]
        if key in TYPEDEF_FALLBACK:
            return TYPEDEF_FALLBACK[key]
        layout = self.types.get(key)
        if layout is None:
            raise InputError(f"unknown type {type_text!r}")
        return self.sizeof(layout, model)

    def sizeof(self, layout: Layout, model: int, seen: tuple[str, ...] = ()) -> tuple[int, int]:
        if layout.kind.startswith("alias:"):
            return self.measure(layout.kind.removeprefix("alias:"), model)
        if layout.kind == "enum":
            return 4, 4
        if layout.name in seen:
            raise InputError(f"recursive type {layout.name}")
        if layout.kind == "opaque":
            raise InputError(f"incomplete type {layout.name}")
        if layout.incomplete:
            raise InputError(f"{layout.name} has a field the generator could not lay out")
        if not layout.fields:
            return 0, 1
        offset, align, largest = 0, 1, 0
        for _, type_text, count in layout.fields:
            size, field_align = self.measure(type_text, model)
            align = max(align, field_align)
            if count < 0:
                raise InputError(f"incomplete array in {layout.name}")
            total = size * count if count else size
            if layout.kind == "union":
                largest = max(largest, total)
                continue
            offset = (offset + field_align - 1) // field_align * field_align
            offset += total
        size = largest if layout.kind == "union" else offset
        size = (size + align - 1) // align * align
        return size, align

    def flatten(self, layout: Layout, model: int, base: int = 0,
                prefix: str = "", seen: tuple[str, ...] = ()) -> list[tuple[str, int]]:
        """Named members of a record, in declaration order.

        An anonymous `struct`/`union` member is transparent in C11 -- `event->x` is
        the same as `event->anonymous.x` -- so its members are reported here with
        the offsets they have in the outer record.
        """
        if layout.kind.startswith("alias:"):
            return []
        if layout.name in seen:
            raise InputError(f"recursive type {layout.name}")
        result, offset, align, largest = [], 0, 1, 0
        for name, type_text, count in layout.fields:
            size, field_align = self.measure(type_text, model)
            align = max(align, field_align)
            anonymous = name.startswith("__unnamed")
            if layout.kind != "union":
                offset = (offset + field_align - 1) // field_align * field_align
            here = base + (0 if layout.kind == "union" else offset)
            if anonymous:
                nested = self.types.get(type_text.strip().rstrip("*"))
                if nested is not None and nested.kind in ("struct", "union"):
                    result.extend(self.flatten(nested, model, here, prefix, seen + (layout.name,)))
            else:
                result.append((name, here))
            total = size * count if count else size
            if layout.kind == "union":
                largest = max(largest, total)
            else:
                offset += total
        return result

    def offsets(self, layout: Layout, model: int) -> list[tuple[str, int]]:
        if layout.kind.startswith("alias:") or not layout.fields:
            return []
        members, unique = [], {}
        for name, offset in self.flatten(layout, model):
            if name in unique:
                continue
            unique[name] = offset
            members.append((name, offset))
        return members


def c_kind_of(parser: HeaderParser, name: str) -> str:
    layout = parser.types.get(name)
    return getattr(layout, "c_kind", "struct") or "struct"


def identifier(stem: str) -> str:
    return re.sub(r"[^A-Za-z0-9_]", "_", stem).lower()


def render_header(header: str, constants: list[tuple[str, int, bool]], parser: HeaderParser,
                  structs: list[tuple[str, int, int, list[tuple[str, int]], list[tuple[str, int]]]],
                  notes: list[str]) -> str:
    stem = identifier(Path(header).stem)
    lines = [f"// Generated Android constants from NDK header {header}.",
             "// Source: NDK stub headers; counts and provenance are in",
             "// os/android/catalog/defs-manifest.json.",
             "// Do not edit this file directly.",
             ""]
    for name, value, long_only in constants:
        if long_only:
            lines.append("// 64-bit data models only: this value depends on `long` being 64 bits")
        lines.append(f"const android_{stem}_{name}: u64 = {value}")
    if constants and structs:
        lines.append("")
    for name, size64, size32, offsets64, offsets32 in structs:
        lines.append(f"// {c_kind_of(parser, name)} {name}: {size64} bytes on 64-bit ABIs, {size32} on 32-bit")
        lines.append(f"const android_layout_{name}_size64: u64 = {size64}")
        lines.append(f"const android_layout_{name}_size32: u64 = {size32}")
        for offset64, offset32 in zip(offsets64, offsets32):
            field = offset64[0]
            lines.append(f"const android_layout_{name}_{field}_offset64: u64 = {offset64[1]}")
            lines.append(f"const android_layout_{name}_{field}_offset32: u64 = {offset32[1]}")
        lines.append("")
    for note in notes:
        lines.append(f"// skipped: {note}")
    while lines and not lines[-1].strip():
        lines.pop()
    return "\n".join(lines) + "\n"


def build(ndk: Path, api: int) -> tuple[dict[str, str], dict, dict[str, list[str]]]:
    include_dir = ndk / HEADER_PREFIX
    require(include_dir.is_dir(), str(include_dir), "NDK android include directory is missing")
    evaluator = Evaluator()
    parser = HeaderParser(evaluator, api)
    evaluator.values.update(BUILTIN_MACROS)
    evaluator.values["__ANDROID_API__"] = api
    evaluator.values["__ANDROID_API_MIN__"] = 21
    sysroot_include = include_dir.parent
    for name in SYSTEM_HEADERS:
        path = sysroot_include / name
        if path.is_file():
            try:
                parser.harvest_defines(parser.read(path, sysroot_include, True), name)
            except InputError as error:
                parser.notes.setdefault("__system__", []).append(f"{name}: {error}")
    headers = sorted(path.name for path in include_dir.glob("*.h"))
    skipped_headers = []
    for header in headers:
        try:
            text = parser.read(include_dir / header, include_dir)
        except InputError as error:
            skipped_headers.append(f"{header}: {error}")
            continue
        parser.parse(header, text)
        parser.harvest_defines(text, header)
    artifacts, counts, notes = {}, {}, {}
    for header in headers:
        if any(entry.startswith(f"{header}:") for entry in skipped_headers):
            continue
        resolved = parser.resolve_constants(header)
        unique, seen_names = [], set()
        for name, value, long_only in resolved:
            if name in seen_names:
                continue
            seen_names.add(name)
            unique.append((name, value, long_only))
        constants = sorted(unique)
        structs = []
        for name, layout in sorted(parser.types.items()):
            if layout.kind not in ("struct", "union") or not layout.fields:
                continue
            if getattr(layout, "origin", None) != header or name.startswith("anonymous_"):
                continue
            try:
                size64, _ = parser.sizeof(layout, 8)
                size32, _ = parser.sizeof(layout, 4)
                offsets64 = parser.offsets(layout, 8)
                offsets32 = parser.offsets(layout, 4)
            except InputError as error:
                parser.notes.setdefault(header, []).append(f"struct {name}: {error}")
                continue
            if not offsets64:
                parser.notes.setdefault(header, []).append(f"struct {name}: no named fields, layout skipped")
                continue
            structs.append((name, size64, size32, offsets64, offsets32))
        if not constants and not structs:
            continue
        artifacts[f"defs/{identifier(Path(header).stem)}.inc"] = render_header(
            header, constants, parser, structs, parser.notes.get(header, []))
        counts[header] = {"constants": len(constants), "structs": len(structs),
                          "fields": sum(len(s[3]) for s in structs)}
        notes[header] = parser.notes.get(header, [])
    index = ["// Generated Android constant partitions for XIRASM.",
             "// Source: NDK stub headers; see os/android/catalog/defs-manifest.json.",
             "// Do not edit this file directly.", ""]
    index += [f'import("os/android/defs/{identifier(Path(header).stem)}.inc")' for header in sorted(counts)]
    artifacts["defs.inc"] = "\n".join(index) + "\n"
    digests = {}
    for header in sorted(counts):
        data = (include_dir / header).read_bytes()
        digests[header] = {"bytes": len(data), "sha256": hashlib.sha256(data).hexdigest()}
    manifest = {
        "schema": 1,
        "generator": GENERATOR,
        "api_level": api,
        "data_models": {"64": "LP64 (arm64, x86-64)", "32": "ILP32 (armv7, i686)"},
        "headers_scanned": len(headers),
        "headers_emitted": len(counts),
        "headers_skipped": skipped_headers,
        "constants": sum(row["constants"] for row in counts.values()),
        "structs": sum(row["structs"] for row in counts.values()),
        "fields": sum(row["fields"] for row in counts.values()),
        "per_header": counts,
        "skipped_entries": {header: notes[header] for header in sorted(notes) if notes[header]},
        "sources": digests,
    }
    from json import dumps
    artifacts["catalog/defs-manifest.json"] = dumps(manifest, indent=2, sort_keys=True) + "\n"
    return artifacts, manifest, notes


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--ndk", type=Path, required=True)
    parser.add_argument("--api", type=int, default=35)
    parser.add_argument("--out", type=Path, default=ROOT / "include/os/android")
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()

    artifacts, manifest, _ = build(args.ndk, args.api)
    for name, text in artifacts.items():
        path = args.out / name
        data = text.encode("utf-8")
        if args.check:
            require(path.is_file() and path.read_bytes() == data, name, "stale generated artifact")
        else:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(data)
    print(f"{'Checked' if args.check else 'Generated'} {manifest['constants']} constants, "
          f"{manifest['structs']} structures ({manifest['fields']} fields) "
          f"from {manifest['headers_emitted']} of {manifest['headers_scanned']} headers")
    if manifest["headers_skipped"]:
        print(f"  skipped headers: {len(manifest['headers_skipped'])}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
