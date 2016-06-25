SHELL := /bin/bash

ifneq ($(strip $(V)),)
  hide :=
else
  hide := @
endif

DQUOTE := "
# vim syntax highligh go crazy with a signal double quote above "

LATEST := $(shell cat latest)

BASE_URL := https://partner-images.canonical.com/core
WGET_FILES := \
  MD5SUMS \
  MD5SUMS.gpg \
  SHA1SUMS \
  SHA1SUMS.gpg \
  SHA256SUMS \
  SHA256SUMS.gpg \
  unpacked/build-info.txt

DEFAULT_ARCH := amd64
HOST_ARCH := $(shell dpkg --print-architecture)
SUPPORTED_ARCH_PAIRS := \
  amd64-i386 \
  arm-armel \
  armel-arm \
  arm-armhf \
  armhf-arm \
  armel-armhf \
  armhf-armel \
  i386-amd64 \
  powerpc-ppc64 \
  ppc64-powerpc \
  sparc-sparc64 \
  sparc64-sparc \
  s390-s390x \
  s390x-s390

DOCKER ?= docker
DOCKER_REPO := $(shell cat repo 2>/dev/null)
$(if $(DOCKER_REPO),, \
  $(eval DOCKER_USER := $(shell $(DOCKER) info | awk -F ': ' '$$1 == "Username" { print $$2; exit }')) \
  $(eval DOCKER_REPO := $(if $(DOCKER_USER),$(DOCKER_USER)/)ubuntu) \
)
SHA256SUM ?= $(shell which sha256sum)

ALL_TARGETS :=

# $(1): relative directory path, e.g. "jessie/amd64"
define target-name-from-path
$(subst /,-,$(1))
endef

# $(1): relative directory path, e.g. "jessie/amd64"
define suite-name-from-path
$(word 1,$(subst /, ,$(1)))
endef

# $(1): relative directory path, e.g. "jessie/amd64"
define arch-name-from-path
$(word 2,$(subst /, ,$(1)))
endef

# $(1): suite name, e.g. jessie
# $(2): arch name, e.g. amd64
define roottar-prefix
ubuntu-$(1)-core-cloudimg-$(2)
endef

# $(1): suite name, e.g. jessie
# $(2): arch name, e.g. amd64
define roottar-filename
$(call roottar-prefix,$(1),$(2))-root.tar.gz
endef

# $(1): relative directory path, e.g. "jessie/amd64", "jessie/amd64/scm"
define enumerate-build-dep-for-docker-build
$(foreach wf,$(WGET_FILES))
endef

# $(1): suite name, e.g. jessie
# $(2): arch name, e.g. amd64
define enumerate-additional-tags-for
$(if $(filter $(DEFAULT_ARCH),$(2)),$(1)) \
$(if $(filter $(LATEST),$(1)),latest-$(2) $(if $(filter $(DEFAULT_ARCH),$(2)),latest)) \
\
$(eval roottar := $(1)/$(2)/$(call roottar-filename,$(1),$(2))) \
$(if $(wildcard $(roottar)), \
  $(eval fullver := $(shell tar -xvf "$(roottar)" etc/debian_version --to-stdout 2>/dev/null)) \
  $(if $(filter %/sid,$(fullver) $(if $(fullver),,/sid)), \
    $(eval fullver := $(word 2,$(subst $(DQUOTE), ,$(filter VERSION_ID=%,$(shell tar -xvf $(roottar) etc/os-release --to-stdout 2>/dev/null))))) \
  ), \
  $(eval fullver :=) \
) \
$(if $(fullver), \
  $(fullver)-$(2) $(if $(filter $(DEFAULT_ARCH),$(2)),$(fullver)) \
  $(eval fullvers := $(subst ., ,$(fullver))) \
  $(if $(filter 3,$(words $(fullvers))), \
    $(word 1,$(fullvers)).$(word 2,$(fullvers))-$(2) $(if $(filter $(DEFAULT_ARCH),$(2)),$(word 1,$(fullvers)).$(word 2,$(fullvers))) \
  ) \
) \
\
$(if $(wildcard $(1)/build-info.txt), \
  $(eval serial := $(shell awk -F '=' '$$1 == "SERIAL" { print $$2; exit }' "$(1)/build-info.txt")) \
  $(eval $(1)-$(2)_SERIAL := $(serial)) \
  $(1)-$(2)-$(serial) $(if $(filter $(DEFAULT_ARCH),$(2)),$(1)-$(serial)) \
)
endef

# $(1): target arch, e.g. amd64
define qemu-arch-for-target-arch
$(strip $(if $(filter $(HOST_ARCH),$(1)),, \
  $(if $(filter $(HOST_ARCH)-$(1),$(SUPPORTED_ARCH_PAIRS)),, \
    $(if $(filter $(1),alpha arm armeb i386 m68k mips mipsel ppc64 sh4 sh4eb sparc sparc64 s390x), \
      $(1), \
      $(if $(filter $(1),amd64), \
        x86_64, \
        $(if $(filter $(1),armel armhf), \
          arm, \
          $(if $(filter $(1),arm64), \
            aarch64, \
            $(if $(filter $(1),lpia), \
              i386, \
              $(if $(filter $(1),powerpc powerpcspe), \
                ppc, \
                $(if $(filter $(1),ppc64el), \
                  ppc64le, \
                  $(error Sorry, I dont know how to support arch $(1)) \
                ) \
              ) \
            ) \
          ) \
        ) \
      ) \
    ) \
  ) \
))
endef

# $(1): relative directory path, e.g. "jessie/amd64", "jessie/amd64/scm"
# $(2): target name, e.g. jessie-amd64-scm
# $(3): qemu arch, e.g. x86_64
define define-qemu-static-target
$(1)/qemu-$(3)-static:
	$$(hide) cp $$$$(which $$(@F)) $$@

$(2): | $(1)/qemu-$(3)-static
endef

define do-dockerfile
$(hide) if [ -n "$$(grep '^# GENERATED' $@)" ]; then \
  echo "$@ <= $<"; \
  sed 's!@SUITE@!$(PRIVATE_SUITE)!g; s!@ARCH@!$(PRIVATE_ARCH)!g; s!@NEED_QEMU_USER_BIN@!$(if $(PRIVATE_QEMU_ARCH),ADD qemu-$(PRIVATE_QEMU_ARCH)-static /usr/bin/qemu-$(PRIVATE_QEMU_ARCH)-static)!g;' "$<" > "$@"; \
else \
  echo "$@ is not automatically generated. Skipping ..."; \
fi
endef

# $(1): relative directory path, e.g. "jessie/amd64", "jessie/amd64/scm"
# $(2): target name, e.g. jessie-amd64-scm
# $(3): suite name, e.g. jessie
# $(4): arch name, e.g. amd64
define define-dockerfile-target
$(eval dockerfile := $(1)/Dockerfile)
$(eval qemuarch := $(call qemu-arch-for-target-arch,$(4)))
dockerfiles: $(dockerfile)
$(dockerfile): PRIVATE_SUITE := $(3)
$(dockerfile): PRIVATE_ARCH := $(4)
$(dockerfile): PRIVATE_QEMU_ARCH := $(qemuarch)
$(if $(qemuarch),$(call define-qemu-static-target,$(1),$(dockerfile),$(qemuarch)))
$(dockerfile): Dockerfile.template
	$$(call do-dockerfile)

endef

define do-check-roottar
$(hide) sha256sum="$$($(SHA256SUM) "$(PRIVATE_ROOTTAR)" | cut -d' ' -f1)"; \
if ! grep -q "$$sha256sum" "$(PRIVATE_SHA256SUMS)"; then \
  echo >&2 "error: '$(PRIVATE_ROOTTAR)' has invalid SHA256"; \
  exit 1; \
fi

endef

# $(1): target name, e.g. jessie-amd64-scm
# $(2): suite name, e.g. jessie/SHA256SUMS
# $(3): roottar path, e.g. precise/i386/ubuntu-precise-core-cloudimg-i386-root.tar.gz
define define-check-roottar-target
.PHONY: check-roottar-$(1)
check-roottar-$(1): PRIVATE_SHA256SUMS := $(2)
check-roottar-$(1): PRIVATE_ROOTTAR := $(3)
check-roottar-$(1): $(2) $(3)
	$$(call do-check-roottar)

downloads: check-roottar-$(1)
endef

define do-wget
$(hide) wget -cqN "$(PRIVATE_URL)" -O $@
endef

# $(1): destination file
# $(2): source url
define define-wget-target
$(1): PRIVATE_URL := $(2)
$(1):
	$$(call do-wget)

downloads: $(1)

endef

# $(1): relative directory path, e.g. "jessie/amd64", "jessie/amd64/scm"
# $(2): target name, e.g. jessie-amd64-scm
# $(3): suite name, e.g. jessie
# $(4): arch name, e.g. amd64
define define-download-files-target
$(eval suitedurl := $(BASE_URL)/$(3)/current)
$(if $(defined_$(3)),, \
  $(eval defined_$(3) := yes) \
  $(foreach wf,$(WGET_FILES),$(call define-wget-target,$(3)/$(notdir $(wf)),$(suitedurl)/$(wf))) \
)

$(eval roottarbase := $(call roottar-prefix,$(3),$(4)))
$(eval roottar := $(call roottar-filename,$(3),$(4)))
$(call define-wget-target,$(1)/$(roottar),$(suitedurl)/$(roottar))
$(call define-wget-target,$(1)/$(roottarbase).manifest,$(suitedurl)/$(roottarbase).manifest)
$(call define-check-roottar-target,$(2),$(3)/SHA256SUMS,$(1)/$(roottar))
endef

define do-docker-build
@echo "$@ <= docker building $(PRIVATE_PATH)";
$(hide) if [ -n "$(FORCE)" -o -z "$$($(DOCKER) inspect $(DOCKER_REPO):$(PRIVATE_TARGET) 2>/dev/null | grep Created)" ]; then \
  $(DOCKER) build -t $(DOCKER_REPO):$(PRIVATE_TARGET) $(PRIVATE_PATH); \
fi

endef

# $(1): relative directory path, e.g. "jessie/amd64", "jessie/amd64/scm"
# $(2): target name, e.g. jessie-amd64-scm
# $(3): suite name, e.g. jessie
# $(4): arch name, e.g. amd64
define define-docker-build-target
$(call define-dockerfile-target,$(1),$(2),$(3),$(4))
$(call define-download-files-target,$(1),$(2),$(3),$(4))

.PHONY: docker-build-$(2)
$(2): docker-build-$(2)
docker-build-$(2): PRIVATE_TARGET := $(2)
docker-build-$(2): PRIVATE_PATH := $(1)
docker-build-$(2): $(1)/Dockerfile check-roottar-$(2)
	$$(call do-docker-build)

endef

define do-docker-tag
$(hide) if [ -n "$(PRIVATE_TAGS)" ]; then \
  echo "$@ <= docker tagging $(PRIVATE_PATH)"; \
  for tag in $(PRIVATE_TAGS); do \
    $(DOCKER) tag -f $(DOCKER_REPO):$(PRIVATE_TARGET) $(DOCKER_REPO):$${tag}; \
  done; \
fi

endef

# $(1): relative directory path, e.g. "jessie/amd64", "jessie/amd64/scm"
# $(2): target name, e.g. jessie-amd64-scm
# $(3): suite name, e.g. jessie
# $(4): arch name, e.g. amd64
define define-docker-tag-target
$(call define-docker-build-target,$(1),$(2),$(3),$(4))

.PHONY: docker-tag-$(2)
$(2): docker-tag-$(2)
docker-tag-$(2): PRIVATE_TARGET := $(2)
docker-tag-$(2): PRIVATE_PATH := $(1)
docker-tag-$(2): PRIVATE_TAGS := $(strip $(call enumerate-additional-tags-for,$(3),$(4)))
docker-tag-$(2): docker-build-$(2)
	$$(call do-docker-tag)

endef

# $(1): relative directory path, e.g. "jessie/amd64", "jessie/amd64/scm"
# $(2): target name, e.g. jessie-amd64-scm
# $(3): suite name, e.g. jessie
# $(4): arch name, e.g. amd64
define define-docker-target
$(call define-docker-tag-target,$(1),$(2),$(3),$(4))
$(eval ALL_TARGETS += $(2))

.PHONY: $(2) $(3) $(4)
all $(3) $(4): $(2)
endef

# $(1): relative directory path, e.g. "jessie/amd64", "jessie/amd64/scm"
define define-target-from-path
$(call define-docker-target,$(1),$(call target-name-from-path,$(1)),$(call suite-name-from-path,$(1)),$(call arch-name-from-path,$(1)))
endef

all:
	@echo "Build $(DOCKER_REPO) done"; \
	echo "Update tarballs"; \
	echo ; \
	$(foreach t,$(ALL_TARGETS),echo '- `$(DOCKER_REPO):$(t)`: $($(t)_SERIAL)';)

$(foreach f,$(shell find . -type f -name Dockerfile | cut -d/ -f2-), \
  $(eval path := $(patsubst %/Dockerfile,%,$(f))) \
  $(eval $(call define-target-from-path,$(path))) \
)
