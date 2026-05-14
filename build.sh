#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
VERSION_FILE="$SCRIPT_DIR/VERSION"

if [ ! -f "$VERSION_FILE" ]; then
    echo "ERROR: VERSION file not found at $VERSION_FILE" >&2
    exit 1
fi

VERSION=$(tr -d '[:space:]' < "$VERSION_FILE")

if [ -z "$VERSION" ]; then
    echo "ERROR: VERSION file is empty" >&2
    exit 1
fi

IMAGE_NAME="iotek-hermes-agent"

echo "Building Docker image: $IMAGE_NAME:$VERSION"
docker build -t "$IMAGE_NAME:$VERSION" -t "$IMAGE_NAME:latest" "$SCRIPT_DIR"

echo "Done: $IMAGE_NAME:$VERSION"
