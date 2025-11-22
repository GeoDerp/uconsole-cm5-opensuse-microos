Scripts for running tests under aarch64 emulation and preparing the MicroOS image

run_aarch64_tests.sh
---------------------
Runs the repository tests inside an aarch64 container (podman/docker). It copies
the workspace into the container to avoid permission problems with rootless containers
and uses qemu (via the container runtime) if required to emulate arm64.

Usage examples:

```bash
# pull the image and run with dtc installed (best effort inside container)
./scripts/run_aarch64_tests.sh --pull --with-dtc

# specify podman explicitly
./scripts/run_aarch64_tests.sh --engine podman
```

create_image_for_flashing.sh
----------------------------
Downloads and prepares the openSUSE MicroOS raw.xz image. By default it will
download and decompress the image and then run `flash_and_apply_overlays.sh` in
`EXTRACT_ONLY` mode to extract overlays. You can run these steps inside a container
if you prefer.

Usage examples:

```bash
# download and decompress and run extract-only on host
./scripts/create_image_for_flashing.sh

# run the extraction inside an aarch64 container (requires podman/docker)
./scripts/create_image_for_flashing.sh --container --engine podman
```

Notes
-----
- The scripts try to be conservative. Installing `dtc` inside a container is attempted
  using the image's package manager (apt/dnf/zypper) and may fail depending on image.
- The test-runner uses `pytest` inside a venv in the container; it does not modify
  files on the host repository.
