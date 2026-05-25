#!/usr/bin/env python3
"""Patch the official Antigravity Linux ARM64 agy binary for Termux.

The input binary is never modified in place. By default the patched output is
written next to the input as "<input>.patched"; callers may pass --output PATH for
transactional repair flows.
"""

from __future__ import annotations

import argparse
import hashlib
import shutil
import struct
import sys
from pathlib import Path


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "input",
        nargs="?",
        default=str(Path.home() / ".local/bin/agy"),
        help="official raw agy binary",
    )
    parser.add_argument(
        "--output",
        help="patched output path; defaults to <input>.patched",
    )
    parser.add_argument(
        "--skip-syscall",
        action="store_true",
        help="skip faccessat2 -> faccessat compatibility patch",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    src = Path(args.input).expanduser()
    dst = Path(args.output).expanduser() if args.output else Path(str(src) + ".patched")

    if not src.exists():
        print(f"Input binary does not exist: {src}", file=sys.stderr)
        return 1
    if src.resolve() == dst.resolve():
        print("Refusing to patch input binary in place", file=sys.stderr)
        return 1

    print(f"Input binary : {src}")
    print(f"SHA256 in    : {sha256(src)}")
    print()

    dst.parent.mkdir(parents=True, exist_ok=True)
    tmp = dst.with_name(f".{dst.name}.patching")
    shutil.copyfile(src, tmp)
    data = bytearray(tmp.read_bytes())

    def get(off: int) -> int:
        return struct.unpack_from("<I", data, off)[0]

    def put(off: int, word: int) -> None:
        struct.pack_into("<I", data, off, word)

    def find_section(name_target: str) -> tuple[int | None, int | None]:
        if data[:4] != b"\x7fELF":
            return None, None
        e_shoff = struct.unpack_from("<Q", data, 40)[0]
        e_shentsize = struct.unpack_from("<H", data, 58)[0]
        e_shnum = struct.unpack_from("<H", data, 60)[0]
        e_shstrndx = struct.unpack_from("<H", data, 62)[0]
        shstr_base = e_shoff + e_shstrndx * e_shentsize
        shstr_off = struct.unpack_from("<Q", data, shstr_base + 24)[0]
        for i in range(e_shnum):
            base = e_shoff + i * e_shentsize
            sh_name = struct.unpack_from("<I", data, base)[0]
            sh_offset = struct.unpack_from("<Q", data, base + 24)[0]
            sh_size = struct.unpack_from("<Q", data, base + 32)[0]
            try:
                nend = data.index(b"\x00", shstr_off + sh_name)
            except ValueError:
                continue
            section = data[shstr_off + sh_name : nend].decode("utf-8", errors="replace")
            if section == name_target:
                return sh_offset, sh_offset + sh_size
        return None, None

    lo, hi = 0, len(data)
    sec_lo, sec_hi = find_section("google_malloc")
    if sec_lo is not None and sec_hi is not None:
        lo, hi = sec_lo, sec_hi
        print(f"Found google_malloc section: file 0x{lo:x} - 0x{hi:x} ({(hi - lo) // 1024} KB)")
    else:
        print("google_malloc section not found - scanning entire binary.")
        print("This is slower and should be reviewed carefully.")
    print()

    ubfx_count = 0
    lsl_count = 0
    for off in range(lo, hi, 4):
        w = get(off)
        if (w & 0x7F800000) != 0x53000000:
            continue
        immr = (w >> 16) & 0x3F
        imms = (w >> 10) & 0x3F
        if immr == 42 and imms == 44:
            put(off, (w & ~((0x3F << 16) | (0x3F << 10))) | (35 << 16) | (37 << 10))
            ubfx_count += 1
        elif immr == 22 and imms == 21:
            put(off, (w & ~((0x3F << 16) | (0x3F << 10))) | (29 << 16) | (28 << 10))
            lsl_count += 1
    print(f"[1] ubfx patches : {ubfx_count}")
    print(f"    lsl  patches : {lsl_count}")

    mask_count = 0
    for off in range(lo, hi - 4, 4):
        if get(off) == 0x92D3800A and get(off + 4) == 0xF2E0000A:
            put(off, 0x9280000A)
            put(off + 4, 0xD35DFD4A)
            mask_count += 1
    print(f"[2] Random mask  : {mask_count}")

    mmap_count = 0
    for off in range(lo, hi, 4):
        if get(off) == 0xF2E00029:
            put(off, 0xD3596129)
            mmap_count += 1
    print(f"[3] MmapAligned  : {mmap_count}")

    word_rewrites = {
        0xD2C20009: 0xD2C00409,
        0xD2C2000A: 0xD2C0040A,
        0xF2C20008: 0xF2DFF408,
        0xF2C20009: 0xF2DFF409,
        0xD2C10009: 0xD2C00209,
        0xD2C1000A: 0xD2C0020A,
        0xF2C38008: 0xF2DFF708,
        0xF2C38009: 0xF2DFF709,
        0x92560A6C: 0x925D0A6C,
        0x92560A6A: 0x925D0A6A,
        0xD2C3000D: 0xD2C0060D,
        0xD2C3000C: 0xD2C0060C,
        0xD2C08008: 0xD2C00108,
    }
    counts = {old: 0 for old in word_rewrites}
    for off in range(lo, hi, 4):
        w = get(off)
        if w in word_rewrites:
            put(off, word_rewrites[w])
            counts[w] += 1
    tag_count = sum(counts.values())
    print(f"[4] Tag constants: {tag_count} words rewritten")

    faccessat2_count = 0
    if args.skip_syscall:
        print("[5] faccessat2   : kept native by request")
    else:
        for off in range(0, len(data) - 12, 4):
            if (
                get(off) == 0xAA1F03E5
                and get(off + 4) == 0xAA1F03E6
                and get(off + 8) == 0xD28036E0
                and (get(off + 12) & 0xFC000000) == 0x94000000
            ):
                put(off + 8, 0xD2800600)
                faccessat2_count += 1
        print(f"[5] faccessat2   : {faccessat2_count} syscall wrapper rewritten")

    total = ubfx_count + lsl_count + mask_count + mmap_count + tag_count + faccessat2_count
    if total == 0:
        print("ERROR: no patches applied; refusing output", file=sys.stderr)
        tmp.unlink(missing_ok=True)
        return 2
    if ubfx_count == 0 or mask_count == 0:
        print("ERROR: expected VA39 patch patterns missing; refusing output", file=sys.stderr)
        tmp.unlink(missing_ok=True)
        return 2

    tmp.write_bytes(data)
    tmp.chmod(0o755)
    tmp.replace(dst)
    print()
    print(f"SHA256 out   : {sha256(dst)}")
    print(f"Output       : {dst}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
