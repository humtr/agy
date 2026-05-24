#define _GNU_SOURCE
#include <unistd.h>
#include <sys/syscall.h>
#include <sys/mman.h>
#include <stdint.h>

/*
 * Experimental gated shim only. This clears mmap address hints above the
 * 39-bit userspace bound, but it does not verify returned addresses or make
 * segfaults impossible.
 */
void* mmap(void* addr, size_t length, int prot, int flags, int fd, off_t offset) {
    if ((uintptr_t)addr > 0x7fffffffff) {
        addr = NULL;
    }
    return (void*)syscall(SYS_mmap, addr, length, prot, flags, fd, offset);
}
