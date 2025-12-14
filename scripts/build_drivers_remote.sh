#!/usr/bin/env bash
set -euo pipefail

cd /tmp/uconsole-drivers

KVER=$(uname -r)
if [ ! -d /lib/modules/$KVER/build ]; then
  echo "Kernel build symlink not present at /lib/modules/$KVER/build. Building will likely fail unless kernel-devel is installed." >&2
fi

for d in extracted-drivers/*; do
  if [ -d "$d" ]; then
    if [ -f "$d/Makefile" ]; then
      echo "Building driver in $d"
      pushd "$d" >/dev/null
      make -C /lib/modules/$KVER/build M=$(pwd) modules
      if ls *.ko >/dev/null 2>&1; then
        mkdir -p /lib/modules/$KVER/extra
        cp -v *.ko /lib/modules/$KVER/extra
      fi
      popd >/dev/null
    fi
  fi
done

echo "Running depmod"
depmod -a
