#!/usr/bin/env python3
"""Test v12 and v23 QR codes from EquatePlus.lua."""
import subprocess
from pathlib import Path
from lupa import LuaRuntime

LUA_SRC = Path(__file__).parent.parent / "EquatePlus.lua"
OUT_DIR = Path(__file__).parent / "output"
OUT_DIR.mkdir(exist_ok=True)

# Extract QR IIFE
lines = LUA_SRC.read_text().splitlines()
qr_start = next(i for i, l in enumerate(lines) if l.startswith("QR = (function()"))
qr_end   = next(i for i, l in enumerate(lines) if i > qr_start and l.startswith("end)()"))
lua_code = "\n".join(lines[qr_start : qr_end + 1])

lua = LuaRuntime(unpack_returned_tuples=True, encoding=None)
lua.execute(lua_code)
QR = lua.globals().QR

CASES = [
    ("v5_totp", "otpauth://totp/EquatePlus:user@example.com?secret=JBSWY3DPEHPK3PXP&issuer=EquatePlus"),
    ("v12_short", "https://example.com/" + "x" * 305),   # 325 chars -> v12
    ("v23_long",  "https://example.com/" + "x" * 1022),  # 1042 chars -> v23
]

all_ok = True
for label, text in CASES:
    out = OUT_DIR / f"{label}.png"
    try:
        png = QR.encode(text.encode("utf-8"), 4)
        data = bytes(png) if not isinstance(png, bytes) else png
        out.write_bytes(data)
        r = subprocess.run(["zbarimg", "--quiet", "--raw", str(out)],
                           capture_output=True, text=True)
        decoded = r.stdout.strip()
        ok = (r.returncode == 0 and decoded == text)
        status = "PASS" if ok else f"FAIL rc={r.returncode}"
        print(f"{status} [{label}] len={len(text)}")
        if not ok:
            all_ok = False
            print(f"  decoded: {decoded[:80]!r}")
            print(f"  stderr:  {r.stderr.strip()[:80]}")
    except Exception as e:
        print(f"ERROR [{label}]: {e}")
        all_ok = False

print("\nResult:", "ALL PASS" if all_ok else "FAILURES")
