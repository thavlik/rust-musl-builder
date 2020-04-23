#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
image="${image:-thavlik/rust-musl-builder:latest}"
echo "Building $image"
docker build .
docker push $image
