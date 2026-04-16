BASH:=$(shell which bash)
SHELL:=$(BASH)
PWD:=$(shell pwd)
DOTENV:=$(PWD)/.env

.SHELLFLAGS:= -O inherit_errexit -eu -o pipefail -c
.ONESHELL:
.DELETE_ON_ERROR:
.DEFAULT_GOAL:=help
BASEURL="https://ftp.gnu.org/gnu/bash"
VERSION?=bash-5.3

define mk-parent
@folder=$(dir $(1))
if [ ! -d "$$folder" ]; then
	mkdir -p "$$folder"
fi
@echo "Creating directory: $$folder"
endef

define test-result
	if [ -z "$1" ] || [ -z "$2" ] || [ -z "$3" ]; then
		echo "Usage: test-in-container <container-name> <image> <output-file>"
		exit 1
	fi

	if ! docker image inspect $2 > /dev/null 2>&1; then
		echo "Pulling Docker image $2..."
		docker pull $2 || {
			echo "Failed to pull Docker image $2"
			exit 1
		}
	fi

	NAME=$1-$(shell date +%s)
	docker rm -f $$NAME 2>/dev/null || true
	trap 'docker rm -f $$NAME 2>/dev/null || true' EXIT
	docker create --name $$NAME $2 sh -c "while true; do sleep 1000; done"
	docker start $$NAME
	docker exec $$NAME mkdir -p /test
	docker cp build/$(VERSION)/bash $$NAME:/test/bash
	docker exec $$NAME chmod +x /test/bash
	docker exec $$NAME /test/bash --version | tee $3
	NUMERIC="$(VERSION)"
	grep "GNU bash, version $${NUMERIC/bash-/}" $3
endef

.PHONY: help build-static
help:
	@bin/mk-help $(MAKEFILE_LIST)

# Main targets
build-static: build/$(VERSION)/bash cache/test/all ## Build the static version of bash.

clean: ## Clean up the build and cache directories.
	@echo "Cleaning up..."
	rm -rfv cache/* build/*

# Cache targets
cache/unfiltered.txt:
	@echo "Creating unfiltered cache file..."
	$(call mk-parent,$@)
	lynx https://ftp.gnu.org/gnu/bash/ --dump -nonumbers -listonly > cache/unfiltered.txt

cache/versions.txt: cache/unfiltered.txt
	@echo "Fetching versions from the remote repository..."
	@$(call mk-parent,$@)
		 grep 'bash-[0-9].*\.tar\.gz$$' "cache/unfiltered.txt" |\
				 sort --version-sort -r | xargs -n 1 basename  > "$@"

cache/available.txt: cache/unfiltered.txt
	@echo "Generating patches list from unfiltered cache..."
	$(call mk-parent,$@)
		 grep 'patches/$$' "cache/unfiltered.txt" | sort --version-sort -r |\
				 xargs -n 1 basename  > "$@"

cache/$(VERSION).tar.gz: cache/versions.txt
	@echo "Fetching source code $(VERSION) from the remote repository..."
	$(call mk-parent,$@)
		 if grep -qx "$(VERSION).tar.gz" "cache/versions.txt"; then
				 echo "Downloading $(VERSION)...";
				 curl -Ss "$(BASEURL)/$(VERSION).tar.gz" -o "$@" || {
						 echo "Failed to download $(VERSION)"
						 exit 1
				 }
		 else
				 echo "Version $(VERSION) not found in versions.txt";
				 exit 1;
		 fi

cache/$(VERSION)-patches.txt: cache/available.txt
	@echo "Fetching patch list for $(VERSION)..."
	$(call mk-parent,$@)
		 if grep -qx "$(VERSION)-patches" "cache/available.txt"; then
				 echo "Found patches for $(VERSION), downloading list..."
				 PATCH=$$(echo "$(VERSION)" | tr -d '.-')
				 lynx "https://ftp.gnu.org/gnu/bash/$(VERSION)-patches/" --dump -nonumbers -listonly | \
						 grep -E "$$PATCH-[0-9]{3}$$" > "$@"
		 else
				 echo "No patch directory for $(VERSION)"
				 touch "$@"
		 fi

cache/test/all: cache/test/musl cache/test/glibc
	@echo "All tests completed successfully."
	touch $@

cache/test/musl: build/$(VERSION)/bash
	$(call mk-parent,$@)
	$(call test-result,bash-test,alpine:latest,$@)

cache/test/glibc: build/$(VERSION)/bash
	$(call mk-parent,$@)
	$(call test-result,bash-test,debian:bookworm-slim,$@)

# Build targets
build/$(VERSION)/$(VERSION)-patches/patch: build/$(VERSION)/extract cache/$(VERSION)-patches.txt
	@echo "Processing patches for $(VERSION)..."
	$(call mk-parent,$@)
	FOLDER="build/$(VERSION)/$(VERSION)-patches"
	mkdir -p "$$FOLDER"
	if [ ! -s "cache/$(VERSION)-patches.txt" ]; then
			echo "No patches found for $(VERSION)"
			exit 0
	fi

	echo "Downloading all patches for $(VERSION)..."
	for patch in $$(cat "cache/$(VERSION)-patches.txt"); do
			echo "Downloading $$patch..."
			NAME=$$(basename "$$patch")
			echo "$$NAME"
			curl -Ss -o "$$FOLDER/$$NAME" "$$patch" || {
					echo "Failed to download $$patch"
					exit 1
			}
	done
	tree "$$FOLDER"

	if [ -d "patch/$(VERSION)" ]; then
		echo "Copying local patches for $(VERSION)..."
		tree "patch/$(VERSION)"
		cp -vr "patch/$(VERSION)/." "$$FOLDER/"
	fi

	cd "build/$(VERSION)" || {
			echo "Failed to change directory to build/$(VERSION)"
			exit 1
	}

	for patch in $$(ls "$(VERSION)-patches" | grep -v .lock); do
		if [ -f "$(VERSION)-patches/$$patch.lock" ]; then
				echo "Patch $$patch already applied, skipping..."
				continue
		fi
		echo "Applying $$patch..."
		patch -p0 < "$(VERSION)-patches/$$patch" || {
				echo "Failed to apply $$patch"
				exit 1
		}
		touch "$(VERSION)-patches/$$patch.lock"
	done

	echo "All patches applied successfully."
	touch "$(VERSION)-patches/patch"

build/$(VERSION)/extract: cache/$(VERSION).tar.gz
		 mkdir -p "build/$(VERSION)"
		 @echo "Extracting $(VERSION) to build directory..."
		 tar -xzf "cache/$(VERSION).tar.gz" -C "build/"
		 touch "build/$(VERSION)/extract"
		 echo "Extraction complete."

build/$(VERSION)/bash: build/$(VERSION)/$(VERSION)-patches/patch
	@echo "Creating bash (static) in build directory..."
	$(call mk-parent,$@)
	pushd "build/$(VERSION)" || {
		echo "Failed to change directory to build/$(VERSION)"; exit 1;
	}
	CC=musl-gcc ./configure --enable-static-link --without-bash-malloc --host=x86_64-linux-musl LDFLAGS="-static" || {
		echo "Configure failed"; exit 1;
	}
	make CC=musl-gcc LDFLAGS="-static" bash || {
		echo "Build failed"; exit 1;
	}
	popd || {
		echo "Failed to change directory back to previous"
		exit 1
	}
	file $@
	$@ --version
	TMP_LLD=$(shell mktemp /tmp/ldd-check.XXXXXX)
	trap 'rm -f "$$TMP_LLD"' EXIT

	ldd $@ 2>&1 | tee "$$TMP_LLD" || true
	if [[ ! -f "$$TMP_LLD" ]] ; then
		echo "No output from ldd, exiting..."
		exit 1
	else
		cat "$$TMP_LLD"
		echo "Checking if bash is statically linked..."
		if ! grep -q "not a dynamic executable" "$$TMP_LLD"; then
			echo "Bash is not statically linked"
			exit 1
		fi
	fi
	echo "Static bash built at build/$(VERSION)/bash"
