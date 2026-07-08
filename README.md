# Bun for HarmonyOS (OpenHarmony)

Run [Bun](https://bun.sh) — the fast all-in-one JavaScript runtime — on HarmonyOS (HongMeng Kernel).

## Background

HarmonyOS uses the HongMeng Kernel (based on Linux, heavily modified) with aarch64 musl libc. Standard Linux binaries can't run due to:

1. **Code signature required** — HongMeng's hmdfs filesystem only loads ELF binaries with a valid `.codesign` section
2. **Missing shared libraries** — `libstdc++.so.6` and `libgcc_s.so.1` are not provided by the system
3. **Blocked syscall** — `faccessat2` (syscall 436) is not permitted by the kernel

## How It Works

```
┌─────────────────────────────┐
│  bun (shell wrapper)        │  ← sets LD_LIBRARY_PATH + LD_PRELOAD
├─────────────────────────────┤
│  bun.bin (signed ELF)       │  ← original bun binary + .codesign
├─────────────────────────────┤
│  lib/                       │
│  ├── libstdc++.so.6 (signed)│
│  ├── libgcc_s.so.1 (signed) │
│  ├── libc.musl-aarch64.so.1 │  → symlink to /lib/ld-musl-aarch64.so.1
│  └── intercept.so (signed)  │  ← LD_PRELOAD: faccessat2 → faccessat
└─────────────────────────────┘
```

### The faccessat2 Problem

Bun calls `faccessat2` (Linux 5.8+), which is blocked by the HongMeng Kernel. The `intercept.so` LD_PRELOAD library hooks the `syscall()` libc function and transparently redirects syscall 436 to `faccessat`, which the kernel permits.

## Prerequisites

- HarmonyOS device with developer mode enabled
- [OHOS SDK](https://developer.harmonyos.com) (native LLVM toolchain) — for code signing
- Node.js (for downloading bun from npm)

## Quick Install

```bash
git clone https://github.com/sxgou/bun-harmonyos.git
cd bun-harmonyos
bash setup.sh
```

### Manual Steps

If you prefer to do it step by step:

1. **Sign the OHOS SDK authority** (if not already done):
   ```bash
   # Ensure binary-sign-tool is in PATH
   ```

2. **Download bun**:
   ```bash
   npm pack @oven/bun-linux-aarch64-musl@1.3.14
   tar xzf oven-bun-linux-aarch64-musl-1.3.14.tgz
   ```

3. **Sign the binary**:
   ```bash
   binary-sign-tool sign -selfSign 1 \
     -inFile package/bin/bun \
     -outFile /usr/local/bin/bun.bun \
     -signAlg SHA256withECDSA
   ```

4. **Build and sign libraries**:
   ```bash
   make          # builds intercept.so
   make sign     # signs intercept.so + copies libs
   ```

5. **Run**:
   ```bash
   export LD_LIBRARY_PATH="/path/to/bun-libs"
   export LD_PRELOAD="/path/to/bun-libs/intercept.so"
   bun.bun --version
   ```

## Verification

```bash
bun --version
# → 1.3.14

bun -e 'console.log("Hello from HarmonyOS!")'
# → Hello from HarmonyOS!

bun -e 'console.log(2 + 2)'
# → 4
```

## Files

| File | Purpose |
|------|---------|
| `setup.sh` | Full automated install script |
| `intercept.c` | Source for the `faccessat2 → faccessat` LD_PRELOAD shim |
| `Makefile` | Build intercept.so and sign everything |
| `README.md` | This file |

## How to Update Bun

```bash
npm pack @oven/bun-linux-aarch64-musl@<version>
tar xzf oven-bun-linux-aarch64-musl-<version>.tgz
binary-sign-tool sign -selfSign 1 \
  -inFile package/bin/bun \
  -outFile ~/.bun/bin/bun.bin \
  -signAlg SHA256withECDSA
```

## Known Limitations

- `faccessat2` interception via LD_PRELOAD only works when bun calls `syscall(436, ...)` through libc. Direct `svc` instructions bypass the hook.
- Network access may be restricted depending on device configuration
- Some Node.js APIs with esoteric Linux-specific syscalls may fail

## Related Projects

- [ohos-libs](https://github.com/sxgou/ohos-libs) — System library cross-compilation suite for HarmonyOS
- [codewhale-harmonyos-build](https://github.com/sxgou/codewhale-harmonyos-build) — Native build tutorial for HarmonyOS
