/* Read-only GPU identification probe (PMC_BOOT_0).
 *
 * On this laptop the NVIDIA driver owns BAR0, and mmap() of
 * /sys/bus/pci/devices/.../resource0 returns EINVAL while bound, so this
 * utility exits with "mmap 4k: Invalid argument". It is kept as the record of
 * that experiment: the chip-ID check has to be left to the module's own gate.
 *
 * Build: gcc -O2 -o readgpu readgpu.c
 * Run:   sudo ./readgpu
 */
#include <stdio.h>
#include <stdint.h>
#include <fcntl.h>
#include <unistd.h>
#include <sys/mman.h>

#define PMC_BOOT_0 0x00000000u

int main(void)
{
    const char *path = "/sys/bus/pci/devices/0000:01:00.0/resource0";
    int fd = open(path, O_RDWR | O_SYNC);
    if (fd < 0) { perror("open resource0"); return 1; }

    void *bar = mmap(NULL, 4096, PROT_READ, MAP_SHARED, fd, 0);
    if (bar == MAP_FAILED) { perror("mmap 4k"); close(fd); return 1; }

    uint32_t boot0 = *(volatile uint32_t *)((char *)bar + PMC_BOOT_0);
    printf("PMC_BOOT_0 = 0x%08x\n", boot0);
    printf("chip       = 0x%03x  (module expects 0x177 for GA107)\n",
           (boot0 >> 20) & 0x1ff);

    munmap(bar, 4096);
    close(fd);
    return 0;
}
