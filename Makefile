CC := gcc
CFLAGS := -fPIC -shared
LDFLAGS := -ldl

BUN_VERSION ?= 1.3.14
BUN_NPM_PKG := @oven/bun-linux-aarch64-musl
BUN_TARBALL := oven-bun-linux-aarch64-musl-$(BUN_VERSION).tgz

BUN_HOME ?= $(HOME)/.bun
BUN_BIN := $(BUN_HOME)/bin/bun.bin
BUN_WRAPPER := $(BUN_HOME)/bin/bun
BUN_LIB_DIR := $(BUN_HOME)/lib
INTERCEPT := $(BUN_LIB_DIR)/intercept.so
LIBS_TARGET := libstdc++.so.6 libgcc_s.so.1

# OHOS SDK binary signing tool
SIGN_TOOL ?= /storage/Users/currentUser/.harmonybrew/Cellar/ohos-sdk/26.0.0.18_1/toolchains/lib/binary-sign-tool

# Where to find pre-built GCC libraries on HarmonyOS
LIB_SRC_DIR ?= /storage/Users/currentUser/.harmonybrew/lib/opencode-libs

.PHONY: all clean install sign download

all: $(INTERCEPT)

$(INTERCEPT): intercept.c
	$(CC) $(CFLAGS) -o $@ intercept.c $(LDFLAGS)

sign: $(INTERCEPT) $(BUN_BIN) $(BUN_LIB_DIR)/$(LIBS_TARGET)
	@for f in $^; do \
		echo "Signing $$f..."; \
		$(SIGN_TOOL) sign -selfSign 1 \
			-inFile $$f -outFile $$f.signed \
			-signAlg SHA256withECDSA 2>&1 | tail -1; \
		cp $$f.signed $$f; \
	done
	@echo "All files signed."

$(BUN_BIN): $(BUN_TARBALL) | $(BUN_HOME)/bin
	tar xzf $(BUN_TARBALL)
	cp package/bin/bun $(BUN_BIN)
	chmod +x $(BUN_BIN)
	rm -rf package

$(BUN_TARBALL):
	npm pack $(BUN_NPM_PKG)@$(BUN_VERSION)

$(BUN_LIB_DIR)/libstdc++.so.6: | $(BUN_LIB_DIR)
	cp $(LIB_SRC_DIR)/libstdc++.so.6.0.34 $@

$(BUN_LIB_DIR)/libgcc_s.so.1: | $(BUN_LIB_DIR)
	cp $(LIB_SRC_DIR)/libgcc_s.so.1 $@

$(BUN_LIB_DIR)/libc.musl-aarch64.so.1: | $(BUN_LIB_DIR)
	ln -sf /lib/ld-musl-aarch64.so.1 $@

$(BUN_HOME)/bin $(BUN_LIB_DIR):
	mkdir -p $@

download: $(BUN_TARBALL)

install: all download sign $(BUN_LIB_DIR)/libc.musl-aarch64.so.1
	# Create wrapper script
	printf '#!/bin/sh\n' > $(BUN_WRAPPER)
	printf 'export LD_LIBRARY_PATH="$(BUN_LIB_DIR)"\n' >> $(BUN_WRAPPER)
	printf 'export LD_PRELOAD="$(BUN_LIB_DIR)/intercept.so"\n' >> $(BUN_WRAPPER)
	printf 'exec $(BUN_BIN) "$$@"\n' >> $(BUN_WRAPPER)
	chmod +x $(BUN_WRAPPER)
	@echo ""
	@echo "=== Bun $(BUN_VERSION) installed to $(BUN_HOME) ==="
	@echo "Run: $(BUN_WRAPPER) --version"

clean:
	rm -f $(BUN_TARBALL) intercept.so
	rm -rf package
