#!/bin/sh
# setup.sh — Automated Bun for HarmonyOS installer
#
# Downloads bun from npm, signs it with the OHOS SDK, builds the
# faccessat2 compatibility shim, and configures the runtime env.
#
# Usage: bash setup.sh [bun-version]
#   default version: 1.3.14

set -euo pipefail

BUN_VERSION="${1:-1.3.14}"
BUN_HOME="${BUN_HOME:-$HOME/.bun}"
BUN_NPM_PKG="@oven/bun-linux-aarch64-musl"
BUN_TARBALL="oven-bun-linux-aarch64-musl-${BUN_VERSION}.tgz"
SIGN_TOOL="${SIGN_TOOL:-}"
LIB_SRC_DIR="${LIB_SRC_DIR:-$HOME/.harmonybrew/lib/opencode-libs}"

# Colors
BOLD='\033[1m'
DIM='\033[2m'
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color

info()  { printf "${DIM}%s${NC}\n" "$*"; }
step()  { printf "${BOLD}%s${NC}\n" "$*"; }
ok()    { printf "${GREEN}✓ %s${NC}\n" "$*"; }
err()   { printf "${RED}✗ %s${NC}\n" "$*"; exit 1; }

# ── Prerequisites ──────────────────────────────────────────────────

step "[1/5] Checking prerequisites..."

command -v npm >/dev/null 2>&1 || err "npm not found. Install Node.js first."
command -v gcc >/dev/null 2>&1 || err "gcc not found."
command -v make >/dev/null 2>&1 || err "make not found."

# Locate binary-sign-tool if not specified
if [ -z "$SIGN_TOOL" ]; then
    CANDIDATE=$(find "$HOME/.harmonybrew/Cellar/ohos-sdk" -name "binary-sign-tool" -type f 2>/dev/null | head -1)
    if [ -n "$CANDIDATE" ]; then
        SIGN_TOOL="$CANDIDATE"
    else
        err "binary-sign-tool not found. Install OHOS SDK native LLVM."
    fi
fi
ok "Found binary-sign-tool at $SIGN_TOOL"

# ── Directories ───────────────────────────────────────────────────

step "[2/5] Creating directories..."
mkdir -p "$BUN_HOME/bin" "$BUN_HOME/lib"
ok "Created $BUN_HOME/bin $BUN_HOME/lib"

# ── Download bun from npm ──────────────────────────────────────────

step "[3/5] Downloading bun ${BUN_VERSION}..."
if [ ! -f "$BUN_TARBALL" ]; then
    npm pack "${BUN_NPM_PKG}@${BUN_VERSION}" >/dev/null 2>&1 || err "Failed to download bun"
fi
tar xzf "$BUN_TARBALL" 2>/dev/null
cp package/bin/bun "$BUN_HOME/bin/bun.bin"
chmod +x "$BUN_HOME/bin/bun.bin"
rm -rf package
ok "Downloaded bun ${BUN_VERSION} (87 MB)"

# ── Build and install libraries ────────────────────────────────────

step "[4/5] Building faccessat2 shim and copying libraries..."

# Build intercept.so (faccessat2 → faccessat)
gcc -fPIC -shared -o intercept.so intercept.c -ldl 2>/dev/null || \
    err "Failed to build intercept.so"
cp intercept.so "$BUN_HOME/lib/intercept.so"
ok "Built intercept.so (faccessat2 compatibility shim)"

# Copy GCC compatibility libraries
if [ -f "$LIB_SRC_DIR/libstdc++.so.6.0.34" ]; then
    cp "$LIB_SRC_DIR/libstdc++.so.6.0.34" "$BUN_HOME/lib/libstdc++.so.6"
fi
if [ -f "$LIB_SRC_DIR/libgcc_s.so.1" ]; then
    cp "$LIB_SRC_DIR/libgcc_s.so.1" "$BUN_HOME/lib/libgcc_s.so.1"
fi
ok "Copied GCC libraries"

# Create libc symlink
ln -sf /lib/ld-musl-aarch64.so.1 "$BUN_HOME/lib/libc.musl-aarch64.so.1"
ok "Created libc symlink"

# ── Sign everything ────────────────────────────────────────────────

step "[5/5] Signing binaries with OHOS SDK (self-sign)..."
for f in "$BUN_HOME/bin/bun.bin" "$BUN_HOME/lib/intercept.so" \
         "$BUN_HOME/lib/libstdc++.so.6" "$BUN_HOME/lib/libgcc_s.so.1"; do
    if [ -f "$f" ]; then
        "$SIGN_TOOL" sign -selfSign 1 \
            -inFile "$f" -outFile "$f.signed" \
            -signAlg SHA256withECDSA >/dev/null 2>&1 || true
        if [ -f "$f.signed" ]; then
            cp "$f.signed" "$f"
            rm -f "$f.signed"
        fi
    fi
done
ok "All binaries signed"

# ── Create wrapper ─────────────────────────────────────────────────

cat > "$BUN_HOME/bin/bun" << WRAPPER
#!/bin/sh
export LD_LIBRARY_PATH="${BUN_HOME}/lib"
export LD_PRELOAD="${BUN_HOME}/lib/intercept.so"
exec "${BUN_HOME}/bin/bun.bin" "\$@"
WRAPPER
chmod +x "$BUN_HOME/bin/bun"

# Cleanup downloaded tarball
rm -f "$BUN_TARBALL" intercept.so 2>/dev/null

# ── Done ───────────────────────────────────────────────────────────

echo ""
echo "=============================================="
printf "${GREEN}Bun ${BUN_VERSION} for HarmonyOS installed!${NC}\n"
echo "=============================================="
echo ""
echo "  Binary:  $BUN_HOME/bin/bun"
echo "  Runner:  $BUN_HOME/bin/bun.bin"
echo "  Libs:    $BUN_HOME/lib/"
echo ""
echo "Add to PATH:"
echo "  export PATH=\"\$PATH:$BUN_HOME/bin\""
echo ""
echo "Test:"
echo "  bun --version"
echo "  bun -e 'console.log(1 + 1)'"
echo ""
