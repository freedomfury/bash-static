# bash-static

This project automates the process of building a statically linked version of GNU Bash, applying official and custom patches, and testing the resulting binary in containerized environments.

## Features
- Downloads Bash source tarballs and official patches from the GNU FTP server
- Supports custom local patches
- Applies patches automatically in the correct order
- Builds Bash statically using musl-gcc
- Tests the resulting binary in Alpine (musl) and Debian (glibc) containers
- Robust static linkage check

## Requirements
- GNU Make
- Docker
- musl-gcc (for static builds)
- curl, lynx, grep, sort, xargs, tree, file, mktemp

## Usage

1. **Set the Bash version (optional):**

   By default, the version is set to `bash-5.3`. To build a different version, set the `VERSION` variable:

   ```sh
   make VERSION=bash-5.2 build-static
   ```

2. **Build static Bash:**

   ```sh
   make build-static
   ```

   This will:
   - Download the Bash source and patches
   - Extract the source
   - Download and apply all official and local patches
   - Build a statically linked Bash binary
   - Test the binary in Alpine and Debian containers

3. **Clean build and cache files:**

   ```sh
   make clean
   ```

## Directory Structure
- `cache/` — Downloaded sources, patch lists, and test results
- `build/$(VERSION)/` — Extracted source, patches, and built binaries
- `patch/$(VERSION)/` — Place your custom patches here (optional)
- `bin/` — Helper scripts (e.g., `mk-help`)

## Custom Patches
To add your own patches, place them in `patch/$(VERSION)/`. They will be copied and applied after the official patches.

## Notes
- The Makefile uses robust error handling and will stop on most errors.
- All patching and building is done in subdirectories under `build/$(VERSION)`.
- The static linkage check ensures the resulting Bash binary is truly static.

## License
This project is provided under the GNU General Public License v3.0. See the Bash source for details.
