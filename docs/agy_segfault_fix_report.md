# Agy Segmentation Fault / VA39 Investigation Note

Date: 2026-05-24

## Summary

The previous report overclaimed the cause and the fix. The current evidence
supports keeping `tcmalloc_fix.so` as an experimental, opt-in shim only.

## Corrected Arithmetic

The earlier report said these addresses were above the 39-bit upper bound
`0x7fffffffff`. That is false.

```text
0x2e80000000  = 199715979264
0x622fe3cdd0  = 421710253520
0x7ce81be000  = 536470085632
0x7fffffffff  = 549755813887
```

All three cited addresses are below `0x7fffffffff`.

## Evidence

Observed local files:

- `experiments/tcmalloc_fix.c`
- `~/.local/glibc-shim/tcmalloc_fix.so`
- live wrappers under `~/bin/agy` and `~/.local/lib/agy-termux/run`

The shim source exports a replacement `mmap`:

```c
void* mmap(void* addr, size_t length, int prot, int flags, int fd, off_t offset) {
    if ((uintptr_t)addr > 0x7fffffffff) {
        addr = NULL;
    }
    return (void*)syscall(SYS_mmap, addr, length, prot, flags, fd, offset);
}
```

Local binary inspection showed:

- `file tcmalloc_fix.so`: ARM aarch64 shared object
- `readelf -Ws`: exported `mmap`
- no exported `execve`, `system`, `python`, `patch`, or `patchelf` hook symbols

## Interpretation

The shim can only alter requested `mmap` hints that are already above
`0x7fffffffff`. It does not verify returned addresses and does not prove that a
segfault cannot happen. It also does not explain the previously cited crash
address, because that address is inside the stated 39-bit bound.

The more defensible default is:

- keep the static VA39 binary patch as the primary compatibility mechanism
- keep `tcmalloc_fix.so` available for manual experiments
- do not load it by default
- keep any `LD_PRELOAD` use scoped to the glibc `agy` runtime only

## Current Policy

Status: experimental/gated.

Default wrapper behavior does not load `tcmalloc_fix.so`. To test it for one
invocation:

```bash
AGY_ENABLE_TCMALLOC_SHIM=1 agy --version
```

Do not export `LD_PRELOAD` globally in Termux.
