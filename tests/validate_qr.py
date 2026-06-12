#!/usr/bin/env python3
"""QR code validator for EquatePlus.lua generator."""
import subprocess
import sys
import os
from pathlib import Path

LUA_SRC = Path(__file__).parent.parent / "EquatePlus.lua"
OUT_DIR = Path(__file__).parent / "output"
OUT_DIR.mkdir(exist_ok=True)

# Test cases: (label, text)
TEST_CASES = [
    ("simple", "Hello QR"),
    ("digits", "1234567890"),
    ("url", "https://example.com/test"),
    ("totp", "otpauth://totp/EquatePlus:user@example.com?secret=JBSWY3DPEHPK3PXP&issuer=EquatePlus"),
    ("alphanum", "THE QUICK BROWN FOX"),
    ("long", "A" * 50),
]

# Build standalone Lua test script: extract lines 736..1326, wrap in harness
lines = LUA_SRC.read_text().splitlines()
# Find QR IIFE boundaries (1-indexed → 0-indexed)
qr_start = next(i for i, l in enumerate(lines) if l.startswith("QR = (function()"))
qr_end   = next(i for i, l in enumerate(lines) if i > qr_start and l.startswith("end)()"))

# Rewrite: replace outer IIFE with simple local
inner = lines[qr_start + 1 : qr_end]  # everything between QR=(function() and end)()
lua_script = ["local QR = (function()"] + inner + ["end)()", ""]

# Append test harness
lua_script += [
    "-- Test harness",
    'local cases = {',
]
for label, text in TEST_CASES:
    escaped = text.replace("\\", "\\\\").replace('"', '\\"')
    lua_script.append(f'  {{label="{label}", text="{escaped}"}},')
lua_script += [
    "}",
    "local errors = 0",
    "for _, c in ipairs(cases) do",
    f'  local outfile = "{OUT_DIR}/" .. c.label .. ".png"',
    "  local ok, err = pcall(function()",
    "    local png = QR.encode(c.text, 4)",
    '    local f = assert(io.open(outfile, "wb"))',
    "    f:write(png); f:close()",
    '    print("GEN OK: " .. c.label .. " (" .. #c.text .. " chars)")',
    "  end)",
    "  if not ok then",
    '    print("GEN FAIL: " .. c.label .. " -> " .. tostring(err))',
    "    errors = errors + 1",
    "  end",
    "end",
    "os.exit(errors == 0 and 0 or 1)",
]

lua_path = OUT_DIR / "test_qr.lua"
lua_path.write_text("\n".join(lua_script))

# Run Lua
print("=== Running Lua QR generator ===")
result = subprocess.run(["lua", str(lua_path)], capture_output=True, text=True)
print(result.stdout, end="")
if result.stderr:
    print("STDERR:", result.stderr, file=sys.stderr)
if result.returncode != 0:
    print("FATAL: Lua generation failed", file=sys.stderr)
    sys.exit(1)

# Validate with pyzbar
print("\n=== Validating QR codes ===")
try:
    from pyzbar.pyzbar import decode as pyzbar_decode
    from PIL import Image
    use_pyzbar = True
except ImportError:
    use_pyzbar = False

all_ok = True
for label, expected in TEST_CASES:
    png = OUT_DIR / f"{label}.png"
    if not png.exists():
        print(f"MISSING: {label}.png")
        all_ok = False
        continue

    # zbarimg
    r = subprocess.run(["zbarimg", "--quiet", "--raw", str(png)],
                       capture_output=True, text=True)
    zbar_out = r.stdout.strip()

    # pyzbar
    pyzbar_out = None
    if use_pyzbar:
        try:
            img = Image.open(png)
            decoded = pyzbar_decode(img)
            if decoded:
                pyzbar_out = decoded[0].data.decode("utf-8")
        except Exception as e:
            pyzbar_out = f"ERROR: {e}"

    ok = (zbar_out == expected)
    status = "OK  " if ok else "FAIL"
    print(f"{status} [{label}]")
    if not ok:
        all_ok = False
        print(f"     expected: {expected!r}")
        print(f"     zbar got: {zbar_out!r}")
        if pyzbar_out is not None:
            print(f"     pyzbar:   {pyzbar_out!r}")

print("\n=== Result:", "ALL PASS" if all_ok else "FAILURES FOUND", "===")
sys.exit(0 if all_ok else 1)
