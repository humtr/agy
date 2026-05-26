#!/usr/bin/env python3
"""Build the Termux-compatible runtime copy from the official agy binary.

The source binary is treated as immutable input. The output is a separate
runtime image for the wrapper to validate and install transactionally.
"""

from __future__ import annotations

import argparse
import hashlib
import shutil
import struct
import sys
from dataclasses import dataclass
from pathlib import Path


RUNTIME_SECTION = "google_malloc"
CHUNK_SIZE = 1024 * 1024


@dataclass(frozen=True)
class BitfieldWindowRule:
    name: str
    old_immr: int
    old_imms: int
    new_immr: int
    new_imms: int
    required: bool = False


@dataclass(frozen=True)
class PairRewriteRule:
    name: str
    first_word: int
    second_word: int
    replacement_first: int
    replacement_second: int
    required: bool = False


@dataclass(frozen=True)
class WordRewriteGroup:
    name: str
    replacements: dict[int, int]
    required: bool = False


@dataclass(frozen=True)
class SyscallCompatRule:
    name: str
    prefix_words: tuple[int, int]
    syscall_word: int
    replacement_word: int
    call_mask: int
    call_value: int


@dataclass
class BuildReport:
    bitfield_counts: dict[str, int]
    pair_counts: dict[str, int]
    word_counts: dict[str, int]
    syscall_count: int

    @property
    def total(self) -> int:
        return (
            sum(self.bitfield_counts.values())
            + sum(self.pair_counts.values())
            + sum(self.word_counts.values())
            + self.syscall_count
        )


BITFIELD_WINDOW_RULES = (
    BitfieldWindowRule("range-window", 42, 44, 35, 37, required=True),
    BitfieldWindowRule("shift-window", 22, 21, 29, 28),
)

PAIR_REWRITE_RULES = (
    PairRewriteRule(
        "address-mask",
        first_word=0x92D3800A,
        second_word=0xF2E0000A,
        replacement_first=0x9280000A,
        replacement_second=0xD35DFD4A,
        required=True,
    ),
)

WORD_REWRITE_GROUPS = (
    WordRewriteGroup(
        "mapping-window",
        {
            0xF2E00029: 0xD3596129,
        },
    ),
    WordRewriteGroup(
        "tag-window",
        {
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
        },
    ),
)

SYSCALL_COMPAT_RULE = SyscallCompatRule(
    "syscall-compat",
    prefix_words=(0xAA1F03E5, 0xAA1F03E6),
    syscall_word=0xD28036E0,
    replacement_word=0xD2800600,
    call_mask=0xFC000000,
    call_value=0x94000000,
)


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(CHUNK_SIZE), b""):
            digest.update(chunk)
    return digest.hexdigest()


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
        help="runtime output path; defaults to <input>.runtime",
    )
    parser.add_argument(
        "--skip-syscall-compat",
        action="store_true",
        help="skip the faccessat2 compatibility rewrite for diagnostics",
    )
    return parser.parse_args()


def read_word(data: bytearray, offset: int) -> int:
    return struct.unpack_from("<I", data, offset)[0]


def write_word(data: bytearray, offset: int, word: int) -> None:
    struct.pack_into("<I", data, offset, word)


def find_elf_section(data: bytearray, wanted_name: str) -> tuple[int | None, int | None]:
    if data[:4] != b"\x7fELF":
        return None, None

    section_header_offset = struct.unpack_from("<Q", data, 40)[0]
    section_header_size = struct.unpack_from("<H", data, 58)[0]
    section_count = struct.unpack_from("<H", data, 60)[0]
    string_table_index = struct.unpack_from("<H", data, 62)[0]
    string_table_header = section_header_offset + string_table_index * section_header_size
    string_table_offset = struct.unpack_from("<Q", data, string_table_header + 24)[0]

    for index in range(section_count):
        header = section_header_offset + index * section_header_size
        name_offset = struct.unpack_from("<I", data, header)[0]
        file_offset = struct.unpack_from("<Q", data, header + 24)[0]
        file_size = struct.unpack_from("<Q", data, header + 32)[0]
        try:
            name_end = data.index(b"\x00", string_table_offset + name_offset)
        except ValueError:
            continue
        section_name = data[string_table_offset + name_offset : name_end].decode(
            "utf-8", errors="replace"
        )
        if section_name == wanted_name:
            return file_offset, file_offset + file_size
    return None, None


def rewrite_bitfield_windows(data: bytearray, lo: int, hi: int) -> dict[str, int]:
    counts = {rule.name: 0 for rule in BITFIELD_WINDOW_RULES}
    rules_by_window = {
        (rule.old_immr, rule.old_imms): rule for rule in BITFIELD_WINDOW_RULES
    }
    field_mask = (0x3F << 16) | (0x3F << 10)

    for offset in range(lo, hi, 4):
        word = read_word(data, offset)
        if (word & 0x7F800000) != 0x53000000:
            continue
        immr = (word >> 16) & 0x3F
        imms = (word >> 10) & 0x3F
        rule = rules_by_window.get((immr, imms))
        if rule is None:
            continue
        replacement = (word & ~field_mask) | (rule.new_immr << 16) | (rule.new_imms << 10)
        write_word(data, offset, replacement)
        counts[rule.name] += 1
    return counts


def rewrite_word_pairs(data: bytearray, lo: int, hi: int) -> dict[str, int]:
    counts = {rule.name: 0 for rule in PAIR_REWRITE_RULES}
    for offset in range(lo, hi - 4, 4):
        for rule in PAIR_REWRITE_RULES:
            if (
                read_word(data, offset) == rule.first_word
                and read_word(data, offset + 4) == rule.second_word
            ):
                write_word(data, offset, rule.replacement_first)
                write_word(data, offset + 4, rule.replacement_second)
                counts[rule.name] += 1
    return counts


def rewrite_word_groups(data: bytearray, lo: int, hi: int) -> dict[str, int]:
    counts = {group.name: 0 for group in WORD_REWRITE_GROUPS}
    replacement_index: dict[int, tuple[str, int]] = {}
    for group in WORD_REWRITE_GROUPS:
        for source, replacement in group.replacements.items():
            replacement_index[source] = (group.name, replacement)

    for offset in range(lo, hi, 4):
        word = read_word(data, offset)
        entry = replacement_index.get(word)
        if entry is None:
            continue
        group_name, replacement = entry
        write_word(data, offset, replacement)
        counts[group_name] += 1
    return counts


def rewrite_syscall_compat(data: bytearray, enabled: bool) -> int:
    if not enabled:
        return 0

    count = 0
    rule = SYSCALL_COMPAT_RULE
    for offset in range(0, len(data) - 12, 4):
        if (
            read_word(data, offset) == rule.prefix_words[0]
            and read_word(data, offset + 4) == rule.prefix_words[1]
            and read_word(data, offset + 8) == rule.syscall_word
            and (read_word(data, offset + 12) & rule.call_mask) == rule.call_value
        ):
            write_word(data, offset + 8, rule.replacement_word)
            count += 1
    return count


def validate_report(report: BuildReport) -> None:
    if report.total == 0:
        raise RuntimeError("no runtime rewrites applied")

    missing_required: list[str] = []
    for rule in BITFIELD_WINDOW_RULES:
        if rule.required and report.bitfield_counts.get(rule.name, 0) == 0:
            missing_required.append(rule.name)
    for rule in PAIR_REWRITE_RULES:
        if rule.required and report.pair_counts.get(rule.name, 0) == 0:
            missing_required.append(rule.name)
    for group in WORD_REWRITE_GROUPS:
        if group.required and report.word_counts.get(group.name, 0) == 0:
            missing_required.append(group.name)

    if missing_required:
        names = ", ".join(missing_required)
        raise RuntimeError(f"required rewrite pattern missing: {names}")


def build_runtime(src: Path, dst: Path, syscall_compat: bool) -> BuildReport:
    if not src.exists():
        raise FileNotFoundError(f"input binary does not exist: {src}")
    if src.resolve() == dst.resolve():
        raise RuntimeError("refusing to overwrite input binary")

    dst.parent.mkdir(parents=True, exist_ok=True)
    tmp = dst.with_name(f".{dst.name}.building")
    shutil.copyfile(src, tmp)
    data = bytearray(tmp.read_bytes())

    section_lo, section_hi = find_elf_section(data, RUNTIME_SECTION)
    if section_lo is None or section_hi is None:
        lo, hi = 0, len(data)
        print(f"{RUNTIME_SECTION} section not found; scanning entire binary.")
    else:
        lo, hi = section_lo, section_hi
        print(
            f"section        : {RUNTIME_SECTION} file 0x{lo:x}-0x{hi:x} ({(hi - lo) // 1024} KB)"
        )

    report = BuildReport(
        bitfield_counts=rewrite_bitfield_windows(data, lo, hi),
        pair_counts=rewrite_word_pairs(data, lo, hi),
        word_counts=rewrite_word_groups(data, lo, hi),
        syscall_count=rewrite_syscall_compat(data, syscall_compat),
    )
    validate_report(report)

    tmp.write_bytes(data)
    tmp.chmod(0o755)
    tmp.replace(dst)
    return report


def print_report(report: BuildReport) -> None:
    print("rewrite counts :")
    for name, count in report.bitfield_counts.items():
        print(f"  {name}: {count}")
    for name, count in report.pair_counts.items():
        print(f"  {name}: {count}")
    for name, count in report.word_counts.items():
        print(f"  {name}: {count}")
    print(f"  {SYSCALL_COMPAT_RULE.name}: {report.syscall_count}")
    print(f"  total: {report.total}")


def main() -> int:
    args = parse_args()
    src = Path(args.input).expanduser()
    dst = Path(args.output).expanduser() if args.output else Path(str(src) + ".runtime")

    try:
        print(f"input          : {src}")
        print(f"sha256 input   : {sha256(src)}")
        report = build_runtime(
            src=src,
            dst=dst,
            syscall_compat=not args.skip_syscall_compat,
        )
        print_report(report)
        print(f"sha256 output  : {sha256(dst)}")
        print(f"output         : {dst}")
        return 0
    except Exception as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
