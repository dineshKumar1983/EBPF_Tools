SHELL := /bin/bash
LIBBPF_SRC := $(abspath ./libbpf/src)
LIBBPF_OUTPUT := $(abspath ./output/libbpf)
LIBBPF_OBJDIR := $(LIBBPF_OUTPUT)/obj
LIBBPF_OBJ := $(LIBBPF_OUTPUT)/libbpf.a
ARCH := $(shell uname -m | sed -e 's/x86_64/x86/' -e 's/aarch64/arm64/')

CC := $(or $(CC),gcc)
CLANG := $(or $(CLANG),clang)

.PHONY: all libbpf

all: libbpf

libbpf: $(LIBBPF_OBJ)

$(LIBBPF_OBJ): $(wildcard $(LIBBPF_SRC)/*.[ch] $(LIBBPF_SRC)/Makefile) | $(LIBBPF_OUTPUT) $(LIBBPF_OBJDIR)
	@echo "Building $@"
	@if [ ! -d $(LIBBPF_SRC) ]; then \
        echo "libbpf source directory does not exist"; \
        git submodule update --init --recursive; \
    fi
	$(MAKE) -C $(LIBBPF_SRC) \
		CFLAGS="-fPIC" \
		BUILD_STATIC_ONLY=1 \
		OBJDIR=$(abspath $(LIBBPF_OBJDIR)) \
		DESTDIR=$(abspath $(LIBBPF_OUTPUT)) \
		INCLUDEDIR= LIBDIR= UAPIDIR= prefix= libdir= \
		install install_uapi_headers

$(LIBBPF_OUTPUT) $(LIBBPF_OBJDIR):
	mkdir -p $@

.PHONY: clean
clean:
	rm -rf $(abspath ./output)

