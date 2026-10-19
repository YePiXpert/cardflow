"""列出 lib/data 下每个查询/更新语句起点，及其后 14 行内是否出现 workspace 过滤。只读扫描。"""
import re, sys, pathlib
root = pathlib.Path(sys.argv[1])
pat = re.compile(r"(_db|db|_scope\.db)\.(select|update|delete|customSelect|customUpdate|customStatement|selectOnly)\(")
for f in sorted(root.rglob("*.dart")):
    if f.name.endswith(".g.dart"):
        continue
    lines = f.read_text(encoding="utf-8").splitlines()
    for i, line in enumerate(lines):
        if pat.search(line):
            window = "\n".join(lines[i:i + 14])
            ok = ("workspaceId" in window) or ("workspace_id" in window) or ("_ws" in window)
            if not ok:
                print(f"{f.relative_to(root)}:{i+1}: {line.strip()[:110]}")
