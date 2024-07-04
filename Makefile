SHELL := /bin/bash
BUILDDEPS_DIR := $(abspath ./build_deps)
LIBBPFTOOLS_SRC := $(BUILDDEPS_DIR)/src
LIBBPFTOOLS_OUTPUT := $(BUILDDEPS_DIR)/output
LIBBPF_SRC := $(LIBBPFTOOLS_SRC)/libbpf/src
LIBBPF_OUTPUT_DIR :=  $(LIBBPFTOOLS_OUTPUT)/libbpf
BPFTOOL_OUTPUT_DIR :=  $(LIBBPFTOOLS_OUTPUT)/bpf_tool
BPFTOOL := $(LIBBPFTOOLS_OUTPUT)/bpf_tool/bpftool
BPFTOOL_SRC := $(LIBBPFTOOLS_SRC)/bpftool/src
LIBBPF_OBJDIR := $(LIBBPF_OUTPUT_DIR)/obj
LIBBPF_OBJ := $(LIBBPF_OUTPUT_DIR)/libbpf.a
ARCH := $(shell uname -m | sed -e 's/x86_64/x86/' -e 's/aarch64/arm64/')

CC := $(or $(CC),gcc)
CLANG := $(or $(CLANG),clang)

.PHONY: all libbpf libbpftool

all: libbpf libbpftool

libbpftool: $(BPFTOOL)

$(BPFTOOL): | $(BPFTOOL_OUTPUT_DIR)
	@echo "Building $@"
	@if [ ! -d $(BPFTOOL_SRC) ]; then \
	echo "bpftool source directory does not exist"; \
	git submodule update --init --recursive build_deps/src/bpftool; \
	fi
	$(Q)$(MAKE) ARCH= CROSS_COMPILE=  OUTPUT=$(BPFTOOL_OUTPUT_DIR)/ -C $(BPFTOOL_SRC)

libbpf: $(LIBBPF_OBJ)

$(LIBBPF_OBJ): $(wildcard $(LIBBPF_SRC)/*.[ch] $(LIBBPF_SRC)/Makefile) | $(LIBBPF_OUTPUT) $(LIBBPF_OBJDIR)
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

$(LIBBPF_OUTPUT) $(LIBBPF_OBJDIR) $(BPFTOOL_OUTPUT_DIR): $(BUILDDEPS_DIR) $(LIBBPFTOOLS_SRC) $(LIBBPFTOOLS_OUTPUT)
	mkdir -p $@

$(BUILDDEPS_DIR):
	mkdir -p $@

$(LIBBPFTOOLS_SRC) $(LIBBPFTOOLS_OUTPUT):
	mkdir -p $@


.PHONY: clean
clean:
	rm -rf $(BUILDDEPS_DIR)

