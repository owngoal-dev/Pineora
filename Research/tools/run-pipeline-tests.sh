#!/bin/sh
# Run from the project root in Apelin's prepared toolchain environment.
set -eu
: "${APELIN_PROJECT_ROOT:?}"
prefix="${APELIN_TOOLCHAIN_BIN:?}"
prefix="${prefix%/usr/lib/apelin/toolchains/*}"
[ -n "$prefix" ] && [ "$prefix" != "$APELIN_TOOLCHAIN_BIN" ]
[ -f Sources/TEIconPipeline.m ]
mkdir -p build
clang -fobjc-arc -arch arm64e -ISources \
  -I"$prefix/usr/share/apelin/development/wiki.qaq.apelin.dev.tweak/support/include" \
  -DAPELIN_BOOTSTRAP_ROOTHIDE=1 \
  '-DAPELIN_PACKAGE_ID="wiki.qaq.pineora"' '-DAPELIN_BUILD_ID="pipeline-regression"' \
  -framework Foundation -framework UIKit -framework QuartzCore -framework CoreGraphics \
  Research/tools/TEIconPipelineTests.m Sources/TECompat.m Sources/TETheme.m \
  Sources/TEIconStore.m Sources/TERenderer.m Sources/TEExtensions.m Sources/TEIconRefresh.m \
  -o build/te-pipeline-tests
ldid -SResearch/tools/Tool.entitlements build/te-pipeline-tests
./build/te-pipeline-tests
