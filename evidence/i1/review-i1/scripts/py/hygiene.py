"""公开仓库卫生扫描（只读）：邮箱、令牌/私钥特征、IP、端口清单、宿主信息、Luhn 卡号形态。
用法：python3 -I hygiene.py <仓库根> <路径...>。只扫 git 跟踪的文本文件；输出命中行（卡号形态只给位置与位数，不回显数字）。"""
import re, subprocess, sys
root = sys.argv[1]
paths = sys.argv[2:]
files = subprocess.run(["git", "-C", root, "ls-files", "--", *paths], capture_output=True, text=True, check=True).stdout.split()
pats = {
    "email": re.compile(r"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}"),
    "token": re.compile(r"ghp_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|gho_[A-Za-z0-9]{20,}|AKIA[0-9A-Z]{16}|sk-[A-Za-z0-9]{20,}|xox[baprs]-[A-Za-z0-9-]{10,}|-----BEGIN [A-Z ]*PRIVATE KEY-----"),
    "ipv4": re.compile(r"\b(?:\d{1,3}\.){3}\d{1,3}\b"),
    "port": re.compile(r"(?<![0-9A-Za-z])(?:localhost|127\.0\.0\.1|0\.0\.0\.0)(?::\d{2,5})|:(?:5432|6379|8000|8080|3000|9000|22)\b"),
    "host": re.compile(r"Debian|Ubuntu [0-9]|Linux [0-9]+\.[0-9]+|deb13|HTTP_PROXY|HTTPS_PROXY|NO_PROXY|/root/|hostname", re.I),
    "secretword": re.compile(r"(?i)\b(password|passwd|secret|api[_-]?key|token)\b\s*[:=]\s*['\"][^'\"]{6,}"),
}
digits = re.compile(r"(?<![0-9])[0-9][0-9 -]{11,30}[0-9](?![0-9])")
def luhn(d):
    s, dbl = 0, False
    for ch in reversed(d):
        x = ord(ch) - 48
        if dbl:
            x *= 2
            if x > 9: x -= 9
        s += x; dbl = not dbl
    return s % 10 == 0
counts = {k: 0 for k in list(pats) + ["luhn"]}
for f in files:
    try:
        text = open(f"{root}/{f}", encoding="utf-8").read()
    except (UnicodeDecodeError, IsADirectoryError, FileNotFoundError):
        continue
    for n, line in enumerate(text.splitlines(), 1):
        for k, p in pats.items():
            for m in p.finditer(line):
                counts[k] += 1
                print(f"[{k}] {f}:{n}: {m.group(0)[:80]}")
        for m in digits.finditer(line):
            d = re.sub(r"[ -]", "", m.group(0))
            if 13 <= len(d) <= 19 and luhn(d):
                counts["luhn"] += 1
                print(f"[luhn] {f}:{n}: {len(d)} 位数字通过 Luhn（不回显）")
print("files scanned:", len(files), "counts:", counts)
