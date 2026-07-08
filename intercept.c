/*
 * intercept.c — faccessat2 (syscall 436) compatibility shim for HongMeng Kernel
 *
 * HarmonyOS (HongMeng Kernel) blocks the faccessat2 syscall (436),
 * which Bun calls on startup. This LD_PRELOAD library hooks the
 * libc syscall() function and redirects 436 → faccessat.
 *
 * Build:  gcc -fPIC -shared -o intercept.so intercept.c -ldl
 * Sign:   binary-sign-tool sign -selfSign 1 \
 *           -inFile intercept.so -outFile intercept.signed.so \
 *           -signAlg SHA256withECDSA
 * Use:    LD_PRELOAD=/path/to/intercept.so bun
 */

#define _GNU_SOURCE
#include <dlfcn.h>
#include <fcntl.h>

/* Forward declarations to avoid unistd.h ABI conflict with syscall() */
extern int faccessat(int, const char *, int, int);
extern void *dlsym(void *, const char *);

#define RTLD_NEXT ((void *)-1) /* find the real syscall past this shim */

/* The real libc syscall — takes number + up to 6 args (Linux calling conv) */
typedef long (*syscall_fn_t)(long, long, long, long, long, long, long);
static syscall_fn_t real_syscall = NULL;

long syscall(long number, long a1, long a2, long a3, long a4, long a5, long a6)
{
    if (!real_syscall)
        real_syscall = (syscall_fn_t)(unsigned long)dlsym(RTLD_NEXT, "syscall");

    /* faccessat2 was added in Linux 5.8. HongMeng Kernel blocks it. */
    if (number == 436) {
        /* Signature: faccessat(int dirfd, const char *path, int mode, int flags) */
        return faccessat((int)a1, (const char *)a2, (int)a3, (int)a4);
    }

    return real_syscall(number, a1, a2, a3, a4, a5, a6);
}
