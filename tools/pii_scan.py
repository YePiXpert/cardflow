#!/usr/bin/env python3
"""Log PII scanner (T-014; security-privacy SEC-S-08 / TC-SEC-S07).

Finds amounts, card numbers and card tails, tokens and credentials, PRC ID numbers,
mobile numbers, e-mail addresses and secret-looking strings in log files::

    uv run --project services/api python tools/pii_scan.py <file-or-directory>... [-]

Each line is scanned on its own:

* A line holding a JSON object or array -- optionally after a prefix such as
  ``api-1  | `` from ``docker compose logs`` -- is decoded, and every value is scanned
  separately with its field name and the names of the enclosing fields as rule context.
  Keys are scanned too.
* Any other line, and every JSON string value, is scanned as text. ``key=value`` /
  ``key: value`` pairs in it (the ``LOG_FORMAT=text`` layout, query strings, header lines,
  ``"amount_minor=800000"`` inside a message) get the same field-name context, and their
  values are also checked URL-decoded (``%C2%A5`` = ``¥``, ``+`` = space).
* A whitelisted field (``FIELD_POLICIES``: ``request_id``, ``status``, ``duration_ms``...)
  is skipped only while its value has the expected shape; any other value in it is
  scanned like a normal field.

Each hit is printed to stdout as ``FILE:LINE:FIELD:RULE``. FIELD is the JSON path
(``error.details.errors[0].msg``), the key of a ``key=value`` pair, or ``-`` for free text;
a key that is not a plain ASCII identifier, or that itself contains a hit, is shown as
``<key>``. The matched text is never printed. A summary and errors go to stderr.

Exit status: 0 = no hits, 1 = hits, 2 = usage or read error (missing path, unreadable
file, a line that is not UTF-8, nothing to scan). Lines are decoded one by one, so the rest
of a file with a bad line is still scanned and reported. 2 takes precedence over 1: an
incomplete scan is never reported as a plain result.

All rules and the whitelist are defined once below (``TEXT_RULES``, ``FIELD_RULES``,
``FIELD_POLICIES``). Standard library only, so any Python 3.13 can run it.
"""

import argparse
import base64
import binascii
import json
import re
import sys
from bisect import bisect_left
from collections.abc import Callable, Iterable, Iterator, Mapping, Sequence
from contextlib import nullcontext
from dataclasses import dataclass
from datetime import date
from functools import lru_cache
from itertools import accumulate
from pathlib import Path
from types import MappingProxyType
from typing import Final, TextIO
from urllib.parse import unquote_plus

type JsonScalar = str | int | float | bool | None
type JsonValue = JsonScalar | list[JsonValue] | dict[str, JsonValue]
type Span = tuple[int, int]
type Finder = Callable[[str], Iterator[Span]]

EXIT_CLEAN: Final = 0
EXIT_HITS: Final = 1
EXIT_ERROR: Final = 2

FREE_TEXT: Final = "-"  # FIELD of a hit that is not inside a field or key=value pair
HIDDEN_KEY: Final = "<key>"  # FIELD segment for a key that must not be printed
STDIN_ARGUMENT: Final = "-"


# --------------------------------------------------------------------------- text rules


@dataclass(frozen=True, slots=True)
class TextRule:
    """Finds sensitive text anywhere in a value, a key or a non-JSON line."""

    name: str
    summary: str
    find: Finder


def _finder(
    pattern: re.Pattern[str], accept: Callable[[re.Match[str]], bool] | None = None
) -> Finder:
    """Spans of the matches of ``pattern`` that ``accept`` (when given) agrees with."""

    def find(text: str) -> Iterator[Span]:
        for match in pattern.finditer(text):
            if accept is None or accept(match):
                yield match.span()

    return find


# Amounts: a number with a currency marker before it (¥ ￥ CNY RMB 人民币) or after it
# (元 美元 港元 ... CNY RMB 人民币); 1.2万元 counts. 元组/元素/元数据/元旦/元宵 are words,
# not money. The suffix form never starts inside a comma-grouped number, and \s*+ is
# possessive, so long digit or whitespace runs cannot cause quadratic backtracking.
_NUMBER: Final = r"(?:\d{1,3}(?:[,\uff0c]\d{3})+|\d+)(?:\.\d+)?"
_CURRENCY_CODE: Final = r"(?<![A-Za-z])(?i:cny|rmb)(?![A-Za-z])"
_AMOUNT: Final = re.compile(
    rf"(?:[\u00a5\uffe5]|{_CURRENCY_CODE}|人民币)\s*[-+]?{_NUMBER}"
    rf"|(?<![\d.])(?<!\d[,\uff0c]){_NUMBER}\s*+[万千百]?\s*"
    rf"(?:[美港日欧澳英]?元(?![组素数旦宵])|{_CURRENCY_CODE}|人民币)"
)

# Card numbers: 13-19 digits, contiguous or in groups of 3-6 separated by one space or
# hyphen; Luhn-valid; first digit 2-9 (no card scheme issues PANs starting with 0 or 1,
# which keeps epoch-millisecond timestamps out). Digits glued to letters are ignored.
CARD_MIN_DIGITS: Final = 13
CARD_MAX_DIGITS: Final = 19
_CARD_FIRST_DIGITS: Final = frozenset("23456789")
_DIGIT_RUN: Final = re.compile(r"(?<![0-9A-Za-z])\d+(?:[ -]\d+)*(?![0-9A-Za-z])")
_DIGIT_GROUP: Final = re.compile(r"\d+")


def luhn_valid(digits: str) -> bool:
    """Luhn (mod 10) check of a string of ASCII digits."""
    total = 0
    for position, char in enumerate(reversed(digits)):
        value = int(char)
        if position % 2:
            value = value * 2 - 9 if value > 4 else value * 2
        total += value
    return total % 10 == 0


def _groupable(span: Span) -> bool:
    return 3 <= span[1] - span[0] <= 6


def _find_card_numbers(text: str) -> Iterator[Span]:
    for run in _DIGIT_RUN.finditer(text):
        offset = run.start()
        groups = [
            (offset + group.start(), offset + group.end())
            for group in _DIGIT_GROUP.finditer(run.group())
        ]
        for first, (start, _) in enumerate(groups):
            digits = ""
            for last in range(first, len(groups)):
                if last > first and not (_groupable(groups[first]) and _groupable(groups[last])):
                    break
                group_start, group_end = groups[last]
                digits += text[group_start:group_end]
                if len(digits) > CARD_MAX_DIGITS:
                    break
                if (
                    len(digits) >= CARD_MIN_DIGITS
                    and digits[0] in _CARD_FIRST_DIGITS
                    and luhn_valid(digits)
                ):
                    yield start, group_end


# Card tail in context: 尾号1234 / 末四位: 1234, last4=1234 / "last 4 digits": "1234",
# ending in 1234, and masked numbers such as **** **** **** 1234 or XXXX-1234. Possessive
# quantifiers keep long runs of * or whitespace from causing catastrophic backtracking.
_LAST4: Final = re.compile(
    r"(?:尾号|末四位|末4位|后四位|后4位|尾数)\s*+(?:为|是|[:=\uff1a])?\s*[\"']?\d{4}(?!\d)"
    r"|(?<![A-Za-z])(?i:last[\s_-]?(?:4|four)(?:[\s_-]?digits?)?)[\"']?\s*+"
    r"(?:(?i:is)|[:=\uff1a])?\s*[\"']?\d{4}(?!\d)"
    r"|(?<![A-Za-z])(?i:ending\s+(?:in|with))\s*+[:\uff1a]?\s*\d{4}(?!\d)"
    r"|(?<![*\u2022\u25cf])(?:(?:\*{2,}+|[xX]{4}|[\u2022\u25cf]{2,}+)[\s-]?)++"
    r"\d{4}(?![0-9A-Za-z])"
)

# JWT / JWS compact form: base64url header that starts with '{"' (eyJ), two more segments.
_JWT: Final = re.compile(
    r"(?<![A-Za-z0-9_-])eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{2,}\.[A-Za-z0-9_-]*"
)

# Authorization header values, Bearer tokens and Basic credentials.
_CRED_CHARS: Final = r"[A-Za-z0-9._~+/=-]"
_AUTHORIZATION: Final = re.compile(
    r"(?<![A-Za-z])(?i:(?:proxy[-_])?authorization)[\"']?\s*[:=\uff1a]\s*[\"']?"
    rf"(?:(?i:bearer|basic|digest|token|negotiate|apikey)\s+{_CRED_CHARS}{{4,}}"
    rf"|{_CRED_CHARS}{{16,}})"
    rf"|(?<![A-Za-z])(?i:bearer)\s+(?P<bearer>{_CRED_CHARS}{{6,}})"
    r"|(?<![A-Za-z])(?i:basic)\s+(?P<basic>[A-Za-z0-9+/]{8,}={0,2})(?![A-Za-z0-9+/=])"
)


def _credential_like(match: re.Match[str]) -> bool:
    """Bearer: not a plain word ("Bearer authentication"). Basic: base64 of ``user:pass``."""
    bearer = match.group("bearer")
    if bearer is not None:
        has_symbol_or_digit = any(char.isdigit() or not char.isalnum() for char in bearer)
        mixed_case = not bearer.islower() and not bearer.isupper()
        return has_symbol_or_digit or (mixed_case and len(bearer) >= 20)
    basic = match.group("basic")
    if basic is not None:
        try:
            return b":" in base64.b64decode(basic, validate=True)
        except (binascii.Error, ValueError):
            return False
    return True


# PRC resident identity card (GB 11643): 18 characters, valid birth date, ISO 7064 check.
_CN_ID_CARD: Final = re.compile(
    r"(?<![0-9A-Za-z])[1-9]\d{5}(?:18|19|20)\d{2}(?:0[1-9]|1[0-2])(?:0[1-9]|[12]\d|3[01])"
    r"\d{3}[\dXx](?![0-9A-Za-z])"
)
_ID_WEIGHTS: Final = (7, 9, 10, 5, 8, 4, 2, 1, 6, 3, 7, 9, 10, 5, 8, 4, 2)
_ID_CHECK_CHARS: Final = "10X98765432"


def cn_id_valid(number: str) -> bool:
    """True for an 18-character PRC ID number with a real birth date and check character."""
    number = number.upper()
    try:
        date(int(number[6:10]), int(number[10:12]), int(number[12:14]))
    except ValueError:
        return False
    total = sum(int(digit) * weight for digit, weight in zip(number[:17], _ID_WEIGHTS, strict=True))
    return _ID_CHECK_CHARS[total % 11] == number[17]


# Mainland China mobile: 1[3-9]X XXXX XXXX, optional +86 / 0086 / 86 prefix, single space or
# hyphen separators. Digits glued to letters (hex strings) are ignored.
_CN_MOBILE: Final = re.compile(
    r"(?<![0-9A-Za-z+])(?:(?:\+|00)?86[\s-]?)?1[3-9]\d(?:[\s-]?\d{4}){2}(?![0-9A-Za-z])"
)

_EMAIL: Final = re.compile(
    r"(?<![A-Za-z0-9._%+-])[A-Za-z0-9._%+-]+@[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)*\.[A-Za-z]{2,}"
    r"(?![A-Za-z0-9-])"
)

# Secret-looking strings: 32+ characters of the base64/base64url alphabet that are hex, or
# mix upper case, lower case and digits, or mix letters and digits without separators.
# UUIDs (8-4-4-4-12, or 32 hex digits with RFC 9562 version and variant bits) are excluded.
_SECRET_CANDIDATE: Final = re.compile(
    r"(?<![A-Za-z0-9+/_-])[A-Za-z0-9+/_-]{32,}={0,2}(?![A-Za-z0-9+/_=-])"
)
_HEX: Final = re.compile(r"[0-9a-fA-F]+")
_UUID: Final = re.compile(
    r"[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}"
    r"|[0-9a-fA-F]{12}[1-8][0-9a-fA-F]{3}[89abAB][0-9a-fA-F]{15}"
)


def is_uuid(text: str) -> bool:
    """Canonical UUID, or 32 hex digits carrying UUID version (1-8) and variant bits."""
    return _UUID.fullmatch(text) is not None


def _random_looking(match: re.Match[str]) -> bool:
    token = match.group().rstrip("=")
    if is_uuid(token):
        return False
    if _HEX.fullmatch(token):
        return True
    has_digit = any(char.isdigit() for char in token)
    has_lower = any(char.islower() for char in token)
    has_upper = any(char.isupper() for char in token)
    if has_digit and has_lower and has_upper:
        return True
    return token.isalnum() and has_digit and (has_lower or has_upper)


TEXT_RULES: Final[tuple[TextRule, ...]] = (
    TextRule(
        "amount",
        "number with a currency marker: ¥/￥/CNY/RMB/人民币 before it, or 元/CNY/RMB after it",
        _finder(_AMOUNT),
    ),
    TextRule(
        "card_number",
        "13-19 digits (groups split by one space or hyphen allowed), Luhn-valid, first digit 2-9",
        _find_card_numbers,
    ),
    TextRule(
        "card_last4",
        "card tail in context: 尾号1234, last4=1234, ending in 1234, **** 1234",
        _finder(_LAST4),
    ),
    TextRule("jwt", "JSON Web Token: eyJ... header plus two base64url segments", _finder(_JWT)),
    TextRule(
        "authorization",
        "Authorization header value, Bearer token, or Basic credentials (base64 of user:pass)",
        _finder(_AUTHORIZATION, _credential_like),
    ),
    TextRule(
        "cn_id_card",
        "18-character PRC resident ID number with a valid birth date and check character",
        _finder(_CN_ID_CARD, lambda match: cn_id_valid(match.group())),
    ),
    TextRule(
        "cn_mobile",
        "mainland China mobile number 1[3-9]x-xxxx-xxxx, optional +86/0086/86 prefix",
        _finder(_CN_MOBILE),
    ),
    TextRule("email", "e-mail address", _finder(_EMAIL)),
    TextRule(
        "secret_string",
        "32+ char hex, or base64/base64url with mixed case and digits; UUIDs excluded",
        _finder(_SECRET_CANDIDATE, _random_looking),
    ),
)

# A match of the rule on the left is dropped where it overlaps a match of a rule on the
# right: a JWT, a Bearer token or a card number is reported as such, not also as a secret.
_SHADOWED_BY: Final[Mapping[str, frozenset[str]]] = MappingProxyType(
    {
        "secret_string": frozenset(rule.name for rule in TEXT_RULES) - {"secret_string"},
        "card_number": frozenset({"cn_id_card"}),
    }
)


def _span_index(spans: Iterable[Span]) -> tuple[list[int], list[int]]:
    """Sorted starts and the running maximum of ends, for overlap queries."""
    ordered = sorted(spans)
    return [start for start, _ in ordered], list(accumulate((end for _, end in ordered), max))


def _overlaps(span: Span, index: tuple[list[int], list[int]]) -> bool:
    starts, reach = index
    before_end = bisect_left(starts, span[1])  # spans that start before ``span`` ends
    return before_end > 0 and reach[before_end - 1] > span[0]


def find_text(text: str) -> list[tuple[str, Span]]:
    """``(rule name, span)`` of every text-rule match in ``text``, shadowed ones removed."""
    found = [(rule.name, span) for rule in TEXT_RULES for span in rule.find(text)]
    indexes: dict[str, tuple[list[int], list[int]]] = {}
    kept: list[tuple[str, Span]] = []
    for name, span in found:
        shadows = _SHADOWED_BY.get(name)
        if shadows:
            if name not in indexes:
                indexes[name] = _span_index(other for rule, other in found if rule in shadows)
            if _overlaps(span, indexes[name]):
                continue
        kept.append((name, span))
    return kept


def _variants(text: str) -> tuple[str, ...]:
    """``text``, plus its URL-decoded form when that differs (query strings: %XX and +)."""
    if "%" in text or "+" in text:
        decoded = unquote_plus(text)
        if decoded != text:
            return text, decoded
    return (text,)


# Keys and short values (event names, route templates, log levels) repeat on almost every
# line, so their results are cached. Only short strings, to keep the cache's memory small.
CACHED_TEXT_MAX: Final = 256
CACHE_ENTRIES: Final = 4096


def _uncached_text_rule_names(text: str) -> tuple[str, ...]:
    return tuple(
        dict.fromkeys(name for variant in _variants(text) for name, _ in find_text(variant))
    )


_cached_text_rule_names: Final = lru_cache(maxsize=CACHE_ENTRIES)(_uncached_text_rule_names)


def _text_rule_names(text: str) -> tuple[str, ...]:
    """Names of the text rules hit by ``text`` or by its URL-decoded form."""
    if len(text) <= CACHED_TEXT_MAX:
        return _cached_text_rule_names(text)
    return _uncached_text_rule_names(text)


# -------------------------------------------------------------------------- field rules


@dataclass(frozen=True, slots=True)
class FieldRule:
    """Flags a value because of the name of its field or of an enclosing field."""

    name: str
    summary: str
    key: re.Pattern[str]  # searched in every normalised key on the value's path
    accepts: Callable[[JsonScalar], bool]

    def applies(self, keys: Sequence[str], value: JsonScalar) -> bool:
        """True when some key on the path matches and the value is of the flagged kind."""
        return self.accepts(value) and any(self.key.search(key) for key in keys)


_CAMEL_BOUNDARY: Final = re.compile(r"(?<=[a-z0-9])(?=[A-Z])")
_KEY_SEPARATORS: Final = re.compile(r"[^0-9A-Za-z\u4e00-\u9fff]+")


def normalize_key(key: str) -> str:
    """``creditLimit`` / ``Credit-Limit`` / ``credit.limit`` -> ``credit_limit``."""
    return _KEY_SEPARATORS.sub("_", _CAMEL_BOUNDARY.sub("_", key)).strip("_").lower()


_NUMERIC_TEXT: Final = re.compile(r"\s*[-+]?(?:\d{1,3}(?:,\d{3})+|\d+)(?:\.\d+)?\s*")
_FOUR_DIGITS: Final = re.compile(r"\s*\d{4}\s*")
_REDACTED: Final = re.compile(
    r"\s*(?:\*+|x{3,}|[\u2022\u25cf]+|[\[<(]?(?:redacted|masked|filtered|hidden|removed|omitted)"
    r"[\]>)]?)\s*",
    re.IGNORECASE,
)


def _is_number(value: JsonScalar) -> bool:
    if isinstance(value, bool):
        return False
    if isinstance(value, int | float):
        return True
    return isinstance(value, str) and _NUMERIC_TEXT.fullmatch(value) is not None


def _is_four_digits(value: JsonScalar) -> bool:
    if isinstance(value, bool):
        return False
    if isinstance(value, int):
        return 0 <= value <= 9999
    return isinstance(value, str) and _FOUR_DIGITS.fullmatch(value) is not None


def _is_present(value: JsonScalar) -> bool:
    """Any number, or a non-empty string that is not just a redaction marker."""
    if value is None or isinstance(value, bool):
        return False
    if isinstance(value, int | float):
        return True
    return bool(value.strip()) and _REDACTED.fullmatch(value) is None


# Keys are matched after normalize_key(): lower case, parts joined by "_".
_AMOUNT_KEY: Final = re.compile(
    r"(?:^|_)(?:amount|amounts|amt|balance|balances|principal|cashback|clawback)(?:_|$)"
    r"|^(?:limit|limits|price|prices|fee|fees)(?:_|$)"
    r"|_(?:minor|limit|limits|price|prices|fee|fees|cents|yuan)$"
    r"|金额|余额|额度|本金|手续费|年费|欠款|应还"
)
_LAST4_KEY: Final = re.compile(
    r"(?:^|_)last_?(?:4|four)(?:_|$)|(?:^|_)(?:card|pan)_tail$|(?:^|_)tail_(?:no|num|number)$"
    r"|尾号|末四位|末4位|后四位|后4位"
)
_AUTHORIZATION_KEY: Final = re.compile(r"(?:^|_)authorization$")
_CREDENTIAL_KEY: Final = re.compile(
    r"(?:^|_)(?:token|secret|password|passwd|pwd|passphrase|api_key|apikey|access_key"
    r"|secret_key|private_key|client_secret|cookie|cookies|set_cookie|session_id|sessionid"
    r"|jwt|kek|dek|cvv|cvv2|cvc|cvn|pin|otp|sms_code|verify_code|verification_code)$"
    r"|密码|口令|验证码|令牌|密钥"
)
_SENSITIVE_KEY: Final = re.compile(
    r"(?:^|_)(?:merchant|merchant_name|payee|payee_name|payer|payer_name|counterparty"
    r"|counterparty_name|card_number|card_no|cardno|pan|id_card|idcard|id_number|id_no"
    r"|phone|phone_number|mobile|mobile_number|telephone|tel|email|email_address|real_name"
    r"|full_name|bank_account|account_number|account_no)$"
    r"|商户|收款方|付款方|对方户名|卡号|手机|电话|邮箱|身份证|姓名|户名"
)

FIELD_RULES: Final[tuple[FieldRule, ...]] = (
    FieldRule(
        "amount_field",
        "number or numeric string in an amount-like field: amount*, balance*, limit*, price*, "
        "fee*, *_minor, *_amount, *_balance, *_limit, 金额/余额/额度...",
        _AMOUNT_KEY,
        _is_number,
    ),
    FieldRule(
        "card_last4",
        "four digits in a card-tail field: last4, card_last4, last_four, card_tail, 尾号...",
        _LAST4_KEY,
        _is_four_digits,
    ),
    FieldRule(
        "authorization",
        "any unredacted value in an Authorization field",
        _AUTHORIZATION_KEY,
        _is_present,
    ),
    FieldRule(
        "credential_field",
        "any unredacted value in a token/secret/password/cookie/session_id/PIN/CVV/OTP field",
        _CREDENTIAL_KEY,
        _is_present,
    ),
    FieldRule(
        "sensitive_field",
        "any unredacted value in a merchant/payee/counterparty/card number/phone/e-mail/"
        "ID number/real name/bank account field",
        _SENSITIVE_KEY,
        _is_present,
    ),
)

RULE_NAMES: Final[tuple[str, ...]] = tuple(
    dict.fromkeys(rule.name for rule in (*TEXT_RULES, *FIELD_RULES))
)


# ---------------------------------------------------------------------- field whitelist


@dataclass(frozen=True, slots=True)
class FieldPolicy:
    """Expected shape of a whitelisted log field; a value of that shape is not scanned."""

    shape: str
    accepts: Callable[[JsonScalar], bool]


def _matching(pattern: re.Pattern[str]) -> Callable[[JsonScalar], bool]:
    def accepts(value: JsonScalar) -> bool:
        return isinstance(value, str) and pattern.fullmatch(value) is not None

    return accepts


def _is_status(value: JsonScalar) -> bool:
    return isinstance(value, int) and not isinstance(value, bool) and 100 <= value <= 599


def _is_duration(value: JsonScalar) -> bool:
    return isinstance(value, int | float) and not isinstance(value, bool) and value >= 0


def _is_uuid_value(value: JsonScalar) -> bool:
    return isinstance(value, str) and is_uuid(value)


_TIMESTAMP: Final = re.compile(
    r"\d{4}-\d{2}-\d{2}[T ]\d{2}:\d{2}:\d{2}(?:[.,]\d{1,9})?(?:Z|[+-]\d{2}:?\d{2})?"
)
_LEVEL: Final = re.compile(r"(?i:debug|info|warning|warn|error|critical|fatal|notset)")
_DOTTED_NAME: Final = re.compile(
    r"[A-Za-z_][A-Za-z0-9_]*(?:\.(?:[A-Za-z_][A-Za-z0-9_]*|<locals>))*"
)
_HTTP_METHOD: Final = re.compile(r"[A-Z]{3,10}")
_FRAME: Final = re.compile(r"[\w.\-/<> ]{1,200}:(?:\d{1,7}|None):[\w<>.]{1,200}")

# Fields written by services/api/cardflow/log.py (record_fields + ALLOWED_FIELDS). ``path``
# and ``message`` are deliberately absent: they are always scanned. A route template such
# as /v1/plans/{plan_id} contains nothing any rule matches; a concrete path would.
FIELD_POLICIES: Final[Mapping[str, FieldPolicy]] = MappingProxyType(
    {
        "ts": FieldPolicy("ISO-8601 timestamp", _matching(_TIMESTAMP)),
        "level": FieldPolicy("log level name", _matching(_LEVEL)),
        "logger": FieldPolicy("dotted logger name", _matching(_DOTTED_NAME)),
        "request_id": FieldPolicy("UUID: 32 hex digits or 8-4-4-4-12", _is_uuid_value),
        "method": FieldPolicy(
            "HTTP method token (3-10 upper-case letters)", _matching(_HTTP_METHOD)
        ),
        "status": FieldPolicy("HTTP status code 100-599", _is_status),
        "duration_ms": FieldPolicy("non-negative number", _is_duration),
        "exc_type": FieldPolicy("exception type name", _matching(_DOTTED_NAME)),
        "exc_chain": FieldPolicy("exception type names", _matching(_DOTTED_NAME)),
        "exc_frames": FieldPolicy("frame location dir/file.py:LINE:function", _matching(_FRAME)),
    }
)


def _exempt(key: str, value: JsonScalar) -> bool:
    policy = FIELD_POLICIES.get(key)
    return policy is not None and policy.accepts(value)


# ----------------------------------------------------------------------------- scanning


@dataclass(frozen=True, slots=True)
class Hit:
    """One rule hit in one field of a line (no matched text is kept)."""

    field: str
    rule: str


@dataclass(frozen=True, slots=True)
class Finding:
    """A hit located in a file: rendered as ``FILE:LINE:FIELD:RULE``."""

    source: str
    line: int
    field: str
    rule: str

    def render(self) -> str:
        """The output line for this finding."""
        return f"{self.source}:{self.line}:{self.field}:{self.rule}"


_PRINTABLE_KEY: Final = re.compile(r"[A-Za-z_][A-Za-z0-9_.-]{0,63}")


def _display_key(key: str, key_rules: Sequence[str]) -> str:
    """The key itself if it is a plain identifier without hits, else ``<key>``."""
    if key_rules or _PRINTABLE_KEY.fullmatch(key) is None:
        return HIDDEN_KEY
    return key


def _as_text(value: JsonScalar) -> str | None:
    if value is None or isinstance(value, bool):
        return None
    return value if isinstance(value, str) else str(value)


def _field_rule_names(value: JsonScalar, keys: Sequence[str]) -> list[str]:
    """Names of the field rules hit by ``value`` under the field names ``keys``."""
    normalized = [normalize_key(key) for key in keys]
    return [rule.name for rule in FIELD_RULES if rule.applies(normalized, value)]


def _value_rules(value: JsonScalar, keys: Sequence[str]) -> list[str]:
    """Rule names hit by the value of a ``key=value`` pair (``keys``: innermost last)."""
    if keys and _exempt(keys[-1], value):
        return []
    names = _field_rule_names(value, keys)
    text = _as_text(value)
    if text:
        names.extend(_text_rule_names(text))
    return names


def _join(path: str, segment: str) -> str:
    return f"{path}.{segment}" if path else segment


def _scan_json(
    document: JsonValue, hits: list[Hit], path: str = "", keys: tuple[str, ...] = ()
) -> None:
    """Scan a decoded JSON value; ``path``/``keys`` locate it inside an enclosing document.

    Every key is scanned as text. A string value is scanned like a text line (so
    ``"message": "amount_minor=800000"`` gets field context too) and all of its hits are
    reported under the value's own path.
    """
    # Iterative, so deeply nested input cannot exhaust the interpreter stack.
    stack: list[tuple[JsonValue, str, tuple[str, ...]]] = [(document, path, keys)]
    while stack:
        value, value_path, value_keys = stack.pop()
        if isinstance(value, dict):
            children: list[tuple[JsonValue, str, tuple[str, ...]]] = []
            for key, child in value.items():
                key_rules = _text_rule_names(key)
                child_path = _join(value_path, _display_key(key, key_rules))
                hits.extend(Hit(child_path, rule) for rule in key_rules)
                children.append((child, child_path, (*value_keys, key)))
            stack.extend(reversed(children))
        elif isinstance(value, list):
            stack.extend(
                (child, f"{value_path}[{index}]", value_keys)
                for index, child in reversed(list(enumerate(value)))
            )
        elif not (value_keys and _exempt(value_keys[-1], value)):
            names = _field_rule_names(value, value_keys)
            if isinstance(value, str):
                names.extend(_string_rule_names(value, value_keys))
            elif (text := _as_text(value)) is not None:
                names.extend(_text_rule_names(text))
            field = value_path or FREE_TEXT
            hits.extend(Hit(field, name) for name in names)


def _uncached_string_rule_names(text: str, keys: tuple[str, ...]) -> tuple[str, ...]:
    inner: list[Hit] = []
    _scan_text(text, inner, keys)  # the text rules on ``text`` plus its key=value pairs
    names = [hit.rule for hit in inner]
    for variant in _variants(text)[1:]:  # URL-decoded form, if any
        names.extend(name for name, _ in find_text(variant))
    return tuple(dict.fromkeys(names))


_cached_string_rule_names: Final = lru_cache(maxsize=CACHE_ENTRIES)(_uncached_string_rule_names)


def _string_rule_names(text: str, keys: tuple[str, ...]) -> tuple[str, ...]:
    """Rule names hit by a JSON string value, scanned like a text line (``keys``: its path)."""
    if len(text) <= CACHED_TEXT_MAX:
        return _cached_string_rule_names(text, keys)
    return _uncached_string_rule_names(text, keys)


# A key is a word (Unicode letters allowed, no leading digit) at a token boundary; an
# optional closing quote lets "key": value inside non-JSON text count as well.
_KEY_VALUE: Final = re.compile(
    r"(?<![\w.-])(?P<key>[^\W\d][\w.-]{0,63})[\"']?[ \t]*[=:\uff1a][ \t]*"
)
# A bare value ends at whitespace, a separator or a quote, so bare values never nest.
_BARE_VALUE: Final = re.compile(r"[^\s,;&=:\uff1a\"']+")
_SINGLE_QUOTED: Final = re.compile(r"'([^'\n]*)'")
_JSON_VALUE_START: Final = frozenset('"[{-0123456789tfn')
_JSON_VALUE_END: Final = frozenset(",;&)]}\"'")
_DECODER: Final = json.JSONDecoder()


def _json_value_at(line: str, start: int) -> tuple[JsonValue, int] | None:
    """A JSON value starting at ``start`` and ending at a delimiter, if there is one."""
    if line[start] not in _JSON_VALUE_START:
        return None
    try:
        value, end = _DECODER.raw_decode(line, start)
    except (ValueError, RecursionError):
        return None
    if end < len(line) and not (line[end].isspace() or line[end] in _JSON_VALUE_END):
        return None  # e.g. 0042 or 8000元: not one JSON value, use the bare token
    return value, end


def _value_at(text: str, start: int) -> tuple[JsonValue, int] | None:
    """The value of a pair starting at ``start``: JSON, single-quoted text or a bare token."""
    decoded = _json_value_at(text, start)
    if decoded is not None:
        return decoded
    quoted = _SINGLE_QUOTED.match(text, start)
    if quoted is not None:
        return quoted.group(1), quoted.end()
    bare = _BARE_VALUE.match(text, start)
    return None if bare is None else (bare.group(), bare.end())


def _scan_text(text: str, hits: list[Hit], keys: tuple[str, ...] = ()) -> None:
    """Scan free text (a non-JSON line, or a JSON string value): pairs, then the whole text.

    Each ``key=value`` pair is checked with its key (after the enclosing ``keys``) as
    context. Values that were scanned as JSON structures, and whitelisted values of the
    expected shape, are blanked before the whole-text pass. Other values stay in place so
    that patterns spanning a value and its surroundings ("card: ending in 1234") still
    match; a whole-text hit that starts inside a pair is reported under that pair's key.
    """
    masked = list(text)
    consumed_until = 0  # end of the last JSON structure that was scanned on its own
    owners: list[tuple[int, int, str]] = []  # (key start, value end, FIELD) of scalar pairs
    for match in _KEY_VALUE.finditer(text):
        key_start, start = match.start("key"), match.end()
        if key_start < consumed_until or start >= len(text):
            continue  # inside a structure scanned already, or nothing after the separator
        located = _value_at(text, start)
        if located is None:
            continue
        value, end = located
        key = match.group("key")
        field = _display_key(key, _text_rule_names(key))
        pair_keys = (*keys, key)
        if isinstance(value, dict | list):
            _scan_json(value, hits, field, pair_keys)
            consumed_until = end
        elif not _exempt(key, value):
            hits.extend(Hit(field, rule) for rule in _value_rules(value, pair_keys))
            owners.append((key_start, end, field))
            continue
        masked[start:end] = " " * (end - start)
    found = find_text("".join(masked))
    if not found:
        return
    owner_of = [FREE_TEXT] * len(text)
    for owner_start, owner_end, field in owners:  # a later (inner) pair overwrites its host
        owner_of[owner_start:owner_end] = [field] * (owner_end - owner_start)
    hits.extend(Hit(owner_of[start], rule) for rule, (start, _) in found)


def _json_document(line: str) -> tuple[JsonValue, int] | None:
    """The JSON object/array filling the rest of ``line``, and where it starts."""
    stripped_start = len(line) - len(line.lstrip())
    starts = [stripped_start] if line[stripped_start : stripped_start + 1] in ("{", "[") else []
    brace = line.find("{")  # prefixed line, e.g. `api-1  | {...}` from docker compose logs
    if brace > stripped_start:
        starts.append(brace)
    for start in starts:
        try:
            document = json.loads(line[start:])
        except (ValueError, RecursionError):
            continue
        if isinstance(document, dict | list):
            return document, start
    return None


def scan_line(line: str) -> list[Hit]:
    """Hits in one log line (without its line terminator), de-duplicated, in order."""
    hits: list[Hit] = []
    document = _json_document(line)
    if document is None:
        _scan_text(line, hits)
    else:
        value, start = document
        if line[:start].strip():
            _scan_text(line[:start], hits)
        _scan_json(value, hits)
    return list(dict.fromkeys(hits))


def scan_lines(lines: Iterable[str], source: str) -> Iterator[Finding]:
    """Findings for ``lines`` (with or without terminators), numbered from 1."""
    for number, raw in enumerate(lines, start=1):
        for hit in scan_line(raw.rstrip("\r\n")):
            yield Finding(source, number, hit.field, hit.rule)


def rule_catalogue() -> list[tuple[str, str, str]]:
    """``(rule, kind, summary)`` for every text and field rule."""
    return [(rule.name, "text", rule.summary) for rule in TEXT_RULES] + [
        (rule.name, "field", rule.summary) for rule in FIELD_RULES
    ]


# ---------------------------------------------------------------------------------- CLI


@dataclass(frozen=True, slots=True)
class _Source:
    display: str
    path: Path | None  # None = standard input


def _os_reason(error: OSError) -> str:
    return error.strerror or type(error).__name__


def _expand(argument: str, errors: list[str]) -> list[_Source]:
    """Files named by one command-line argument; problems are appended to ``errors``."""
    if argument == STDIN_ARGUMENT:
        return [_Source("<stdin>", None)]
    path = Path(argument)
    if path.is_dir():

        def record(error: OSError) -> None:
            errors.append(f"{error.filename}: {_os_reason(error)}")

        found: list[Path] = []
        for directory, dirnames, filenames in path.walk(on_error=record):
            dirnames.sort()
            for name in filenames:
                candidate = directory / name
                if candidate.is_file():
                    found.append(candidate)
                else:
                    errors.append(f"{candidate}: not a regular file")
        return [_Source(str(file), file) for file in sorted(found)]
    if path.is_file():
        return [_Source(argument, path)]
    if path.exists():
        errors.append(f"{argument}: not a regular file or directory")
    else:
        errors.append(f"{argument}: no such file or directory")
    return []


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="pii_scan",
        description="Scan log files for amounts, card data, tokens and personal data. "
        "Prints FILE:LINE:FIELD:RULE per hit, never the matched text. "
        "Exit status: 0 no hits, 1 hits, 2 usage or read error.",
    )
    parser.add_argument(
        "paths",
        nargs="*",
        metavar="PATH",
        help="log file, directory (scanned recursively) or - for standard input",
    )
    parser.add_argument("--list-rules", action="store_true", help="print the rules and exit")
    return parser


@dataclass(slots=True)
class _Tally:
    """Running totals for the summary line."""

    files: int
    lines: int
    hits: int
    rules: set[str]


MAX_LISTED_BAD_LINES: Final = 5


def _scan_source(source: _Source, out: TextIO, tally: _Tally) -> str | None:
    """Scan one source, writing each finding as soon as it is found.

    Lines are decoded one by one, so a line that is not UTF-8 is reported with its number
    and the rest of the file is still scanned. Returns an error text (lines that could not
    be decoded) or None. Raises ``OSError`` when the source cannot be read.
    """
    bad_lines: list[int] = []
    stream = nullcontext(sys.stdin.buffer) if source.path is None else source.path.open("rb")
    with stream as binary:
        for number, raw in enumerate(binary, start=1):
            tally.lines += 1
            try:
                line = raw.decode("utf-8").rstrip("\r\n")
            except UnicodeDecodeError:
                bad_lines.append(number)
                continue
            if number == 1:
                line = line.removeprefix("\N{ZERO WIDTH NO-BREAK SPACE}")  # byte order mark
            for hit in scan_line(line):
                out.write(Finding(source.display, number, hit.field, hit.rule).render() + "\n")
                tally.hits += 1
                tally.rules.add(hit.rule)
    tally.files += 1
    if not bad_lines:
        return None
    listed = ", ".join(str(number) for number in bad_lines[:MAX_LISTED_BAD_LINES])
    more = ", ..." if len(bad_lines) > MAX_LISTED_BAD_LINES else ""
    return f"not valid UTF-8 on {len(bad_lines)} line(s): {listed}{more}"


def main(argv: Sequence[str] | None = None) -> int:
    """Command-line entry point; returns the exit status."""
    parser = _parser()
    args = parser.parse_args(argv)
    if args.list_rules:
        for name, kind, summary in rule_catalogue():
            sys.stdout.write(f"{name}\t{kind}\t{summary}\n")
        return EXIT_CLEAN
    if not args.paths:
        parser.error("at least one PATH is required")

    errors: list[str] = []
    sources = [source for argument in args.paths for source in _expand(argument, errors)]
    if not sources and not errors:
        errors.append("no files to scan")
    tally = _Tally(files=0, lines=0, hits=0, rules=set())
    for source in sources:
        try:
            problem = _scan_source(source, sys.stdout, tally)
        except OSError as error:
            problem = _os_reason(error)
        if problem is not None:
            errors.append(f"{source.display}: {problem}")
    sys.stdout.flush()

    for error in errors:
        sys.stderr.write(f"pii_scan: error: {error}\n")
    summary = f"pii_scan: {tally.files} file(s), {tally.lines} line(s), {tally.hits} hit(s)"
    if tally.rules:
        summary += " [" + ", ".join(name for name in RULE_NAMES if name in tally.rules) + "]"
    if errors:
        summary += f"; {len(errors)} error(s)"
    sys.stderr.write(summary + "\n")
    if errors:
        return EXIT_ERROR
    return EXIT_HITS if tally.hits else EXIT_CLEAN


if __name__ == "__main__":
    sys.exit(main())
