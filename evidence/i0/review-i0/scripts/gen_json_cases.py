"""Generate JSON byte strings that probe strict-JSON / canonical-JSON corner cases."""
import base64, random, struct, sys
from decimal import Decimal, getcontext

getcontext().prec = 2000
rng = random.Random(int(sys.argv[2]) if len(sys.argv) > 2 else 1)
cases: list[bytes] = []

def add(b):
    if isinstance(b, str):
        b = b.encode("utf-8", "surrogatepass")
    cases.append(b)

# 1. float tokens
def rand_digits(n):
    return "".join(rng.choice("0123456789") for _ in range(n))
for _ in range(3000):
    k = rng.randint(1, 40)
    d = rand_digits(k).lstrip("0") or "0"
    if rng.random() < 0.5 and len(d) > 1:
        p = rng.randint(1, len(d) - 1)
        tok = d[:p] + "." + d[p:]
    else:
        tok = d + "." + rand_digits(rng.randint(1, 5))
    if rng.random() < 0.7:
        tok += rng.choice("eE") + rng.choice(["", "+", "-"]) + str(rng.randint(0, 400))
    if rng.random() < 0.3:
        tok = "-" + tok
    add("[" + tok + "]")
# near-halfway: midpoint between two adjacent doubles, perturbed
for _ in range(2000):
    bits = rng.getrandbits(63)
    x = struct.unpack("<d", struct.pack("<Q", bits))[0]
    if x != x or x in (float("inf"), float("-inf")):
        continue
    y = struct.unpack("<d", struct.pack("<Q", bits + 1))[0]
    if y != y or y in (float("inf"), float("-inf")):
        continue
    mid = (Decimal(x) + Decimal(y)) / 2
    choice = rng.randint(0, 2)
    if choice == 0:
        s = format(mid, "e")
    elif choice == 1:
        s = format(mid + Decimal(10) ** (mid.adjusted() - 60), "e")
    else:
        s = format(mid - Decimal(10) ** (mid.adjusted() - 60), "e")
    s = s.replace("E", "e")
    if "e" not in s:
        s += "e0"
    add("[" + s + "]")
# specials
for tok in ["1e-400", "-1e-400", "-0.0", "0e5", "0.0e-999", "1e308", "1.7976931348623157e308",
            "1.7976931348623158e308", "1.7976931348623159e308", "2e308", "4.9e-324", "2.4703282292062327e-324",
            "2.4703282292062328e-324", "2.4703282292062327208828439643411068618252990130716238221279284125033775364e-324",
            "1e99999999", "1e9999999", "0e99999999", "1.5e-99999999", "1e-9999999", "1e+0000000000000400",
            "1e-0000000000000400", "1" + "0" * 400 + "e-400", "0." + "0" * 400 + "1e400",
            "1" + "0" * 330 + ".0", "9" * 309 + ".0", "0.1", "0.30000000000000004", "123456789012345678901234567890.0",
            "5e-324", "1e23", "8.98846567431158e307", "2.2250738585072011e-308", "2.2250738585072014e-308",
            "1e-7", "1E21", "1e21", "-1e21", "100e-2", "3600.0000000000001", "1.0", "-0", "0", "-0e0",
            "1E400", "1e-324", "-1e-324", "3e-324", "7.4e-324"]:
    add("[" + tok + "]")
# 2. integers
for tok in ["9" * 4300, "9" * 4301, "-" + "9" * 4300, "-" + "9" * 4301, "1" + "0" * 4299, "-0",
            "9223372036854775807", "9223372036854775808", "-9223372036854775808", "-9223372036854775809",
            "00", "01", "-01", "+1", "1.", ".1", "1e", "1e+", "-", "--1", "0x10", "1_000", "١"]:
    add("[" + tok + "]")
# 3. strings
BS = chr(92)
def esc(h):
    return BS + "u" + h
strs = ['"' + esc("0041") + '"', '"' + esc("d83d") + esc("de00") + '"', '"' + esc("d800") + '"',
        '"' + esc("dc00") + '"', '"' + esc("de00") + esc("d83d") + '"', '"' + esc("d83d") + '"',
        '"' + esc("d83d") + 'x"', '"' + esc("DBFF") + esc("DFFF") + '"', '"' + BS + 'u00"',
        '"' + BS + 'u00zz"', '"' + BS + 'U0041"', '"' + BS + '/"', '"' + BS + "'" + '"',
        '"' + BS + 'a"', '"a' + chr(0x7f) + 'b"', '"a' + chr(0x2028) + 'b"', '"a' + chr(0xfeff) + 'b"',
        '"' + chr(9) + '"', '"' + chr(0) + '"', '"' + chr(0x1f) + '"', '" "',
        '"' + BS + 'b' + BS + 'f' + BS + 'n' + BS + 'r' + BS + 't' + BS + '"' + BS + BS + '"',
        '"' + chr(0x4e2d) + chr(0x1f600) + '"', '"a', '"' + BS, '"' + BS + 'u12', "'a'",
        '"' + esc("0000") + '"', '"' + esc("001f") + '"', '"' + esc("007f") + '"', '"' + esc("2028") + '"']
for s in strs:
    add("[" + s + "]")
add(b'["\xc0\x80"]')            # overlong NUL
add(b'["\xed\xa0\x80"]')        # encoded surrogate
add(b'["\xed\xb0\x80"]')        # encoded low surrogate
add(b'["\xf4\x90\x80\x80"]')    # > U+10FFFF
add(b'["\xf8\x88\x80\x80\x80"]')  # 5-byte
add(b'["\xe2\x82"]')            # truncated
add(b'["\x80"]')                # continuation only
add(b'["\xef\xbb\xbf"]')        # BOM inside a string (U+FEFF char)
add(b'\xef\xbb\xbf[1]')        # leading BOM
add(b' \xef\xbb\xbf[1]')       # BOM after whitespace
add(b'["\xf0\x9f\x98\x80"]')    # valid 4-byte
add(b'["\xc3\xa9"]')
add(b'[1]\x00')
add(b'')
add(b'   ')
add(b'\x0c[1]')
add(b'\x0b[1]')
add(b'\xc2\xa0[1]')
# 4. structure
for depth in [1, 100, 499, 500, 511, 512, 513, 600, 800, 900, 950, 990, 995, 1000, 1100, 3000]:
    add("[" * depth + "]" * depth)
    add('{"a":' * depth + "1" + "}" * depth)
for t in ["trueX", "[trueX]", "[nul]", "[tru]", "[True]", "[NULL]", "[NaN]", "[-NaN]", "[Infinity]",
          "[-Infinity]", "[+Infinity]", "[infinity]", "[1,]", "[,1]", "{,}", '{"a":1,}', '{"a" 1}',
          '{"a":1 "b":2}', "[1 2]", "[[1],[2]]", '{"a":{"a":1},"b":{"a":1}}', '{"a":1,"b":{"c":1,"c":2}}',
          '[{"a":1},{"a":1}]', '{"":1}', '{"a":1,"A":2,"é":3,"":4,"\U0001f600":5,"ﬁ":6}',
          '{"\\ud83d\\ude00":1,"\\uffff":2,"\\ue000":3}', '{"a":1}{', "1 2", "[1] x", "\"x\"", "null",
          "true", "123", "-", "[-]", "[1e5]", "[1E+5]", "[1e-5]", '{"a":[{"b":[{"c":null}]}]}']:
    add(t)
# keys sorting probe with random unicode keys
alphabet = ["a", "B", "é", "中", "", "￿", "\U0001f600", "\U00010000", "ﬁ", "~", "/", "\x7f"]
for _ in range(300):
    keys = set()
    for _ in range(rng.randint(1, 8)):
        keys.add("".join(rng.choice(alphabet) for _ in range(rng.randint(0, 4))))
    import json
    add(json.dumps({k: i for i, k in enumerate(keys)}, ensure_ascii=rng.random() < 0.5))

with open(sys.argv[1], "w") as f:
    for c in cases:
        f.write(base64.b64encode(c).decode() + "\n")
print(len(cases), "cases")
