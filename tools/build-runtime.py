#!/usr/bin/env python3
"""Build the Termux-compatible runtime copy from the official agy binary.

The source binary is treated as immutable input. The output is a separate
runtime image for the wrapper to validate and install transactionally.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import shutil
import struct
import sys
from dataclasses import dataclass
from pathlib import Path


RUNTIME_SECTION = "google_malloc"
CHUNK_SIZE = 1024 * 1024
RESOLV_CONF_SOURCE = b"/etc/resolv.conf"
RESOLV_CONF_TARGET = b"/proc/self/fd/33"


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
    resolver_path_count: int
    section_offset: int | None
    section_size: int | None
    allocator_profile: str
    allocator_required: bool
    allocator_status: str
    missing_required: list[str]

    @property
    def total(self) -> int:
        return (
            sum(self.bitfield_counts.values())
            + sum(self.pair_counts.values())
            + sum(self.word_counts.values())
            + self.syscall_count
            + self.resolver_path_count
        )


class BuildError(RuntimeError):
    def __init__(self, message: str, report: BuildReport | None = None):
        super().__init__(message)
        self.report = report


BITFIELD_WINDOW_RULES = (
    BitfieldWindowRule("range-window", 42, 44, 35, 37),
    BitfieldWindowRule("shift-window", 22, 21, 29, 28),
)

PAIR_REWRITE_RULES = (
    PairRewriteRule(
        "address-mask",
        first_word=0x92D3800A,
        second_word=0xF2E0000A,
        replacement_first=0x9280000A,
        replacement_second=0xD35DFD4A,
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

ALLOCATOR_CORE_RULES = ("range-window", "address-mask")


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
        default=None,
        help="official raw agy binary; defaults to the managed raw cache when omitted",
    )
    parser.add_argument(
        "--output",
        help=(
            "runtime output path; defaults to the managed runtime path when input "
            "is omitted, otherwise <input>.runtime"
        ),
    )
    parser.add_argument(
        "--skip-syscall-compat",
        action="store_true",
        help="skip the faccessat2 compatibility rewrite for diagnostics",
    )
    parser.add_argument(
        "--allow-broad-scan",
        action="store_true",
        help="allow full-binary scan when google_malloc section is missing (diagnostic only)",
    )
    parser.add_argument(
        "--report-json",
        help="write machine-readable report JSON to path",
    )
    return parser.parse_args()


def read_word(data: bytearray, offset: int) -> int:
    return struct.unpack_from("<I", data, offset)[0]


def write_word(data: bytearray, offset: int, word: int) -> None:
    struct.pack_into("<I", data, offset, word)


def find_elf_section(data: bytearray, wanted_name: str) -> tuple[int | None, int | None]:
    if data[:4] != b"\x7fELF":
        return None, None
    if len(data) < 64:
        return None, None

    ei_class = data[4]
    ei_data = data[5]
    if ei_class != 2 or ei_data != 1:
        return None, None

    section_header_offset = struct.unpack_from("<Q", data, 40)[0]
    section_header_size = struct.unpack_from("<H", data, 58)[0]
    section_count = struct.unpack_from("<H", data, 60)[0]
    string_table_index = struct.unpack_from("<H", data, 62)[0]
    if section_header_size == 0 or section_count == 0:
        return None, None
    if string_table_index >= section_count:
        return None, None
    table_end = section_header_offset + section_header_size * section_count
    if table_end > len(data):
        return None, None
    string_table_header = section_header_offset + string_table_index * section_header_size
    if string_table_header + 40 > len(data):
        return None, None
    string_table_offset = struct.unpack_from("<Q", data, string_table_header + 24)[0]
    string_table_size = struct.unpack_from("<Q", data, string_table_header + 32)[0]
    if string_table_offset + string_table_size > len(data):
        return None, None

    for index in range(section_count):
        header = section_header_offset + index * section_header_size
        if header + 40 > len(data):
            return None, None
        name_offset = struct.unpack_from("<I", data, header)[0]
        file_offset = struct.unpack_from("<Q", data, header + 24)[0]
        file_size = struct.unpack_from("<Q", data, header + 32)[0]
        if file_offset + file_size > len(data):
            continue
        if name_offset >= string_table_size:
            continue
        try:
            name_end = data.index(b"\x00", string_table_offset + name_offset)
        except ValueError:
            continue
        if name_end > string_table_offset + string_table_size:
            continue
        section_name = data[string_table_offset + name_offset : name_end].decode(
            "utf-8", errors="replace"
        )
        if section_name == wanted_name:
            return file_offset, file_offset + file_size
    return None, None


def allocator_counts(report: BuildReport) -> dict[str, int]:
    return {
        "range-window": report.bitfield_counts.get("range-window", 0),
        "shift-window": report.bitfield_counts.get("shift-window", 0),
        "address-mask": report.pair_counts.get("address-mask", 0),
        "mapping-window": report.word_counts.get("mapping-window", 0),
        "tag-window": report.word_counts.get("tag-window", 0),
    }


def classify_allocator_profile(report: BuildReport) -> tuple[str, bool, str, list[str]]:
    counts = allocator_counts(report)
    signal_total = sum(counts.values())
    if signal_total == 0:
        return "compact-google-malloc", False, "not-applicable", []

    missing_core = [name for name in ALLOCATOR_CORE_RULES if counts.get(name, 0) == 0]
    if not missing_core:
        return "legacy-va39", True, "ok", []

    return "unknown-partial", True, "missing", missing_core


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


def rewrite_resolver_path_compat(data: bytearray) -> int:
    if len(RESOLV_CONF_SOURCE) != len(RESOLV_CONF_TARGET):
        raise RuntimeError("resolver path rewrite must preserve byte length")
    count = data.count(RESOLV_CONF_SOURCE)
    data[:] = data.replace(RESOLV_CONF_SOURCE, RESOLV_CONF_TARGET)
    return count


def validate_report(report: BuildReport) -> None:
    if report.total == 0:
        raise BuildError("no runtime rewrites applied", report)

    missing_required = list(report.missing_required)
    if report.allocator_required and report.allocator_status != "ok":
        missing_required = list(dict.fromkeys(missing_required))
    if report.resolver_path_count == 0:
        missing_required.append("resolver-path")

    if missing_required:
        names = ", ".join(dict.fromkeys(missing_required))
        raise BuildError(f"allocator profile {report.allocator_profile} (missing: {names})", report)


def build_runtime(
    src: Path,
    dst: Path,
    syscall_compat: bool,
    allow_broad_scan: bool,
) -> BuildReport:
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
        if not allow_broad_scan:
            raise RuntimeError(
                f"{RUNTIME_SECTION} section not found; fail-closed. "
                "Use --allow-broad-scan for diagnostics."
            )
        lo, hi = 0, len(data)
        print(f"{RUNTIME_SECTION} section not found; broad scan enabled by flag.")
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
        resolver_path_count=rewrite_resolver_path_compat(data),
        section_offset=section_lo,
        section_size=(section_hi - section_lo) if section_lo is not None and section_hi is not None else None,
        allocator_profile="unknown",
        allocator_required=False,
        allocator_status="unknown",
        missing_required=[],
    )
    profile, required, status, missing = classify_allocator_profile(report)
    report.allocator_profile = profile
    report.allocator_required = required
    report.allocator_status = status
    report.missing_required = missing
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
    print(f"  resolver-path: {report.resolver_path_count}")
    print(f"  allocator-profile: {report.allocator_profile}")
    print(f"  allocator-required: {'yes' if report.allocator_required else 'no'}")
    print(
        "  missing-required: "
        + (", ".join(report.missing_required) if report.missing_required else "none")
    )
    print(f"  total: {report.total}")

def report_to_dict(report: BuildReport) -> dict:
    return {
        "bitfield_counts": report.bitfield_counts,
        "pair_counts": report.pair_counts,
        "word_counts": report.word_counts,
        "syscall_count": report.syscall_count,
        "resolver_path_count": report.resolver_path_count,
        "section_offset": report.section_offset,
        "section_size": report.section_size,
        "allocator_profile": report.allocator_profile,
        "allocator_required": report.allocator_required,
        "allocator_status": report.allocator_status,
        "missing_required": report.missing_required,
        "total": report.total,
        "required": {
            "resolver_path_required": True,
        },
    }


def main() -> int:
    args = parse_args()
    input_omitted = args.input is None
    src = (
        Path.home() / ".local/lib/agy/termux/raw/agy"
        if input_omitted
        else Path(args.input).expanduser()
    )
    if args.output:
        dst = Path(args.output).expanduser()
    elif input_omitted:
        dst = Path.home() / ".local/lib/agy/termux/runtime/agy"
    else:
        dst = Path(str(src) + ".runtime")

    try:
        print(f"input          : {src}")
        print(f"sha256 input   : {sha256(src)}")
        report = build_runtime(
            src=src,
            dst=dst,
            syscall_compat=not args.skip_syscall_compat,
            allow_broad_scan=args.allow_broad_scan,
        )
        print_report(report)
        if args.report_json:
            out = Path(args.report_json).expanduser()
            out.parent.mkdir(parents=True, exist_ok=True)
            out.write_text(json.dumps(report_to_dict(report), sort_keys=True) + "\n")
        print(f"sha256 output  : {sha256(dst)}")
        print(f"output         : {dst}")
        return 0
    except BuildError as exc:
        report = exc.report
        if report is not None:
            print_report(report)
            if args.report_json:
                out = Path(args.report_json).expanduser()
                out.parent.mkdir(parents=True, exist_ok=True)
                out.write_text(json.dumps(report_to_dict(report), sort_keys=True) + "\n")
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1
    except Exception as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
