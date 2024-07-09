SHELL := /bin/bash
LLVM_STRIP ?= llvm-strip

BIN_OUTPUT := $(abspath ./ebpftools)
BUILDDEPS_DIR := $(abspath ./build_deps)
LIBBPFTOOLS_SRC := $(BUILDDEPS_DIR)/src
LIBBPFTOOLS_OUTPUT := $(BUILDDEPS_DIR)/output
LIBBPF_SRCDIR := $(LIBBPFTOOLS_SRC)/libbpf
LIBBPF_SRC := $(LIBBPFTOOLS_SRC)/libbpf/src
LIBBPF_OUTPUT_DIR :=  $(LIBBPFTOOLS_OUTPUT)/libbpf
BPFTOOL_OUTPUT_DIR :=  $(LIBBPFTOOLS_OUTPUT)/bpf_tool
BPFTOOL := $(LIBBPFTOOLS_OUTPUT)/bpf_tool/bootstrap/bpftool
BPFTOOL_SRC := $(LIBBPFTOOLS_SRC)/bpftool/src
LIBBPF_OBJDIR := $(LIBBPF_OUTPUT_DIR)/obj
LIBBPF_OBJ := $(LIBBPF_OUTPUT_DIR)/libbpf.a
VMLINUX_DIR := $(abspath ./vmlinux)

CFLAGS := -g -O2 -Wall -Wmissing-field-initializers -Werror
BPFCFLAGS := -g -O2 -Wall

INCLUDES := -I$(LIBBPF_OUTPUT_DIR) -I$(LIBBPFTOOLS_OUTPUT) -I$(LIBBPF_SRCDIR)/include/uapi

ARCH := $(shell uname -m | sed -e 's/x86_64/x86/' -e 's/aarch64/arm64/')

CC := $(or $(CC),gcc)
CLANG := $(or $(CLANG),clang)

APPS = \
	hello \
	#

.PHONY: all

all: $(APPS)

$(APPS): %: $(LIBBPFTOOLS_OUTPUT)/%.o $(LIBBPF_OBJ) | $(BIN_OUTPUT)
	$(Q)$(CC) $(CFLAGS) $^ $(LDFLAGS) -lelf -lz -o $(BIN_OUTPUT)/$@

$(patsubst %,$(LIBBPFTOOLS_OUTPUT)/%.o,$(APPS)): %.o: %.skel.h

$(LIBBPFTOOLS_OUTPUT)/%.o: %.c $(wildcard %.h) $(LIBBPF_OBJ) | $(LIBBPFTOOLS_OUTPUT)
	$(Q)$(CC) $(CFLAGS) $(INCLUDES) -c $(filter %.c,$^) -o $@

$(LIBBPFTOOLS_OUTPUT)/%.skel.h: $(LIBBPFTOOLS_OUTPUT)/%.bpf.o | $(LIBBPFTOOLS_OUTPUT) $(BPFTOOL)
	$(Q)$(BPFTOOL) gen skeleton $< > $@

$(LIBBPFTOOLS_OUTPUT)/%.bpf.o: %.bpf.c $(LIBBPF_OBJ) $(wildcard %.h) $(VMLINUX_DIR)/$(ARCH)/vmlinux.h | $(LIBBPFTOOLS_OUTPUT)
	$(Q)$(CLANG) $(BPFCFLAGS) -target bpf -D__TARGET_ARCH_$(ARCH)	      \
		     -I$(VMLINUX_DIR)/$(ARCH)/ $(INCLUDES) -c $(filter %.c,$^) -o $@
#	$(LLVM_STRIP) -g $@

$(VMLINUX_DIR)/$(ARCH)/vmlinux.h: $(BPFTOOL) | $(VMLINUX_DIR)
	@if [ -f $@ ]; then \
	    echo "vmlinux.h exists"; \
	else \
	    echo "vmlinux.h does not exist create one"; \
	    $(BPFTOOL) btf dump file /sys/kernel/btf/vmlinux  format c > $@; \
	fi

$(BPFTOOL): | $(BPFTOOL_OUTPUT_DIR)
	@echo "Building $@"
	@if [ ! -d $(BPFTOOL_SRC) ]; then \
	echo "bpftool source directory does not exist"; \
	git submodule update --init --recursive build_deps/src/bpftool; \
	fi
	$(Q)$(MAKE) ARCH= CROSS_COMPILE=  OUTPUT=$(BPFTOOL_OUTPUT_DIR)/ -C $(BPFTOOL_SRC) bootstrap

$(LIBBPF_OBJ): $(wildcard $(LIBBPF_SRC)/*.[ch] $(LIBBPF_SRC)/Makefile) | $(LIBBPF_OUTPUT_DIR) $(LIBBPF_OBJDIR)
	@echo "Building $@"
	@if [ ! -d $(LIBBPF_SRC) ]; then \
        echo "libbpf source directory does not exist"; \
        git submodule update --init --recursive build_deps/src/libbpf; \
	fi
	$(MAKE) -C $(LIBBPF_SRC) \
		CFLAGS="-fPIC" \
		BUILD_STATIC_ONLY=1 \
		OBJDIR=$(abspath $(LIBBPF_OBJDIR)) \
		DESTDIR=$(abspath $(LIBBPF_OUTPUT_DIR)) \
		INCLUDEDIR= LIBDIR= UAPIDIR= prefix= libdir= \
		install install_uapi_headers

$(LIBBPF_OUTPUT_DIR) $(LIBBPF_OBJDIR) $(BPFTOOL_OUTPUT_DIR): $(BUILDDEPS_DIR) $(LIBBPFTOOLS_SRC) $(LIBBPFTOOLS_OUTPUT)
	mkdir -p $@

$(BUILDDEPS_DIR) $(BIN_OUTPUT):
	mkdir -p $@

$(LIBBPFTOOLS_SRC) $(LIBBPFTOOLS_OUTPUT):
	mkdir -p $@

$(VMLINUX_DIR):
	mkdir -p $@
	mkdir -p $@/$(ARCH)


.PHONY: clean
clean:
	@echo "Cleaning up all build files and directories except '$(LIBBPFTOOLS_OUTPUT)/$(LIBBPFTOOLS_SRC)'..."
	@find $(LIBBPFTOOLS_OUTPUT) -mindepth 1 -maxdepth 1 ! -path '$(LIBBPFTOOLS_SRC)'  -exec rm -rf {} +
	rm -rf $(BIN_OUTPUT)
	@echo "Cleanup complete."

