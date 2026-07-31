GOFLAGS := -tags load_dll_from_rsrc -ldflags="-H windowsgui -s -w" -trimpath -buildvcs=false -v
export GOOS := windows
export CGO_ENABLED := 1
export PATH := $(CURDIR)/.deps/go/bin:$(PATH)

VERSION := $(shell sed -n 's/^\s*Number\s*=\s*"\([0-9.]\+\)"$$/\1/p' version/version.go)
empty :=
space := $(empty) $(empty)
comma := ,
RCFLAGS := -DPHOBOS_VERSION_ARRAY=$(subst $(space),$(comma),$(wordlist 1,4,$(subst .,$(space),$(VERSION)) 0 0 0 0)) -DPHOBOS_VERSION_STR=$(VERSION) -O coff -c 65001

rwildcard=$(foreach d,$(filter-out .deps,$(wildcard $1*)),$(call rwildcard,$d/,$2) $(filter $(subst *,%,$2),$d))
SOURCE_FILES := $(call rwildcard,,*.go) .deps/go/prepared go.mod go.sum
OBFUSCATOR_DIR := ../src/phobos-obfuscator
OBFUSCATOR_FILES := $(wildcard $(OBFUSCATOR_DIR)/*.c) $(wildcard $(OBFUSCATOR_DIR)/*.h) phobos/cobf/bridge.c phobos/cobf/bridge.h
OBFUSCATOR_ID := $(shell cat $(OBFUSCATOR_FILES) | sha256sum | cut -c1-16)
export CGO_CFLAGS := -O2 -g -DPHOBOS_SOURCE_ID_$(OBFUSCATOR_ID)
RESOURCE_FILES := resources.rc version/version.go manifest.xml $(wildcard ui/icon/*.ico) .deps/wireguard-nt/prepared .deps/wintun/prepared

DEPLOYMENT_HOST ?= winvm
DEPLOYMENT_ARCH ?= amd64
DEPLOYMENT_PATH ?= Desktop

all: amd64/phobos.exe x86/phobos.exe arm64/phobos.exe

define download =
.distfiles/$(1):
	mkdir -p .distfiles
	if ! curl -L#o $$@.unverified $(2); then rm -f $$@.unverified; exit 1; fi
	if ! echo "$(3)  $$@.unverified" | sha256sum -c; then rm -f $$@.unverified; exit 1; fi
	if ! mv $$@.unverified $$@; then rm -f $$@.unverified; exit 1; fi
endef

$(eval $(call download,go.tar.gz,https://download.wireguard.com/windows-toolchain/distfiles/go1.26.2-linux_amd64_2026-04-20.tar.gz,57e21e3a07a07adcffc460ab2d4983ba3272b43d4b9f218eb4c9e98d88ef7f9f))
$(eval $(call download,wireguard-nt.zip,https://download.wireguard.com/wireguard-nt/wireguard-nt-1.1.zip,dceb30a9bc4be48cce0f74160fc88a585a2c2627366e8f846fc6658f9038dace))
$(eval $(call download,wintun.zip,https://www.wintun.net/builds/wintun-0.14.1.zip,07c256185d6ee3652e09fa55c0b673e2624b565e02c4b9091c79ca7d2f24ef51))

.deps/go/prepared: .distfiles/go.tar.gz
	mkdir -p .deps
	rm -rf .deps/go
	bsdtar -C .deps -xf .distfiles/go.tar.gz
	chmod -R +w .deps/go
	touch $@

.deps/wireguard-nt/prepared: .distfiles/wireguard-nt.zip
	mkdir -p .deps
	rm -rf .deps/wireguard-nt
	bsdtar -C .deps -xf .distfiles/wireguard-nt.zip
	touch $@

.deps/wintun/prepared: .distfiles/wintun.zip
	mkdir -p .deps
	rm -rf .deps/wintun
	bsdtar -C .deps -xf .distfiles/wintun.zip
	touch $@

resources_amd64.syso: $(RESOURCE_FILES)
	x86_64-w64-mingw32-windres $(RCFLAGS) -I .deps/wireguard-nt/bin/amd64 -I .deps/wintun/bin/amd64 -i $< -o $@

resources_386.syso: $(RESOURCE_FILES)
	i686-w64-mingw32-windres $(RCFLAGS) -I .deps/wireguard-nt/bin/x86 -I .deps/wintun/bin/x86 -i $< -o $@

resources_arm64.syso: $(RESOURCE_FILES)
	aarch64-w64-mingw32-windres $(RCFLAGS) -I .deps/wireguard-nt/bin/arm64 -I .deps/wintun/bin/arm64 -i $< -o $@

amd64/phobos.exe: export GOARCH := amd64
amd64/phobos.exe: export CC := x86_64-w64-mingw32-gcc
amd64/phobos.exe: resources_amd64.syso $(SOURCE_FILES) $(OBFUSCATOR_FILES)
	go build $(GOFLAGS) -o $@

x86/phobos.exe: export GOARCH := 386
x86/phobos.exe: export CC := i686-w64-mingw32-gcc
x86/phobos.exe: resources_386.syso $(SOURCE_FILES) $(OBFUSCATOR_FILES)
	go build $(GOFLAGS) -o $@

arm64/phobos.exe: export GOARCH := arm64
arm64/phobos.exe: export CC := aarch64-w64-mingw32-gcc
arm64/phobos.exe: resources_arm64.syso $(SOURCE_FILES) $(OBFUSCATOR_FILES)
	go build $(GOFLAGS) -o $@

remaster: export GOARCH := amd64
remaster: export GOPROXY := direct
remaster: .deps/go/prepared
	rm -f go.sum go.mod
	cp go.mod.master go.mod
	go get
	sed -i $(shell curl -L 'https://go.dev/dl/?mode=json&include=all' | jq -r '(".windows-amd64.zip",".linux-amd64.tar.gz") as $$suffix | .[0].files[] | select(.filename|endswith($$suffix)) | ("-e", "s/go[0-9][^ ]*\\\($$suffix)\\([ ,]\\)[a-f0-9]\\+/\(.filename)\\1\(.sha256)/") | @sh') Makefile build.bat

fmt: export GOARCH := amd64
fmt: .deps/go/prepared
	go fmt ./...

generate: export GOOS :=
generate: .deps/go/prepared
	go generate -mod=mod ./...

deploy: $(DEPLOYMENT_ARCH)/phobos.exe
	-ssh $(DEPLOYMENT_HOST) -- 'taskkill /im phobos.exe /f'
	scp $< $(DEPLOYMENT_HOST):$(DEPLOYMENT_PATH)

clean:
	rm -rf *.syso x86/ amd64/ arm64/ .deps

distclean: clean
	rm -rf .distfiles

.PHONY: deploy clean distclean fmt remaster generate all
