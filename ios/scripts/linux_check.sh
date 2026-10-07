#!/usr/bin/env bash
# Compile et teste, SANS Mac, toute la partie de l'app qui ne dépend que de Foundation
# (modèles, règles, numérotation, client réseau, view models) avec le compilateur Swift officiel pour Linux (Docker).
#
# Les fichiers qui importent SwiftUI, UIKit, SwiftData, PDFKit, PhotosUI ou Security sont exclus :
# ils ne se vérifient qu'avec Xcode (make ios-build / make ios-test sur le Mac).
#
# Usage : ios/scripts/linux_check.sh          (image par défaut : swift:6.0-jammy)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
IMAGE="${SWIFT_IMAGE:-mirror.gcr.io/library/swift:6.0-jammy}"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

UI_IMPORTS='^import (SwiftUI|UIKit|SwiftData|PDFKit|PhotosUI|Security)'
mkdir -p "$WORK/Sources/DevisChat" "$WORK/Tests/DevisChatTests"
included=0
excluded=()
while IFS= read -r f; do
  if grep -Eq "$UI_IMPORTS" "$f"; then excluded+=("${f#$ROOT/}"); else cp "$f" "$WORK/Sources/DevisChat/"; included=$((included + 1)); fi
done < <(find "$ROOT/ios/DevisChat" -name '*.swift' | sort)
while IFS= read -r f; do
  if grep -Eq "$UI_IMPORTS" "$f"; then excluded+=("${f#$ROOT/}"); else cp "$f" "$WORK/Tests/DevisChatTests/"; fi
done < <(find "$ROOT/ios/DevisChatTests" -name '*.swift' | sort)

cat > "$WORK/Package.swift" <<'EOF'
// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "DevisChatLinuxCheck",
    targets: [
        .target(name: "DevisChat", path: "Sources/DevisChat"),
        .testTarget(name: "DevisChatTests", dependencies: ["DevisChat"], path: "Tests/DevisChatTests"),
    ]
)
EOF

echo "Fichiers app compilés sous Linux : $included"
echo "Fichiers exclus (interface iOS, à vérifier avec Xcode) : ${#excluded[@]}"
docker run --rm -v "$WORK":/pkg -v "$ROOT/shared/fixtures":/fixtures:ro \
  -e DEVISCHAT_FIXTURES=/fixtures -w /pkg "$IMAGE" \
  bash -c "swift build --build-tests 2>&1 | grep -E 'error|warning: (var|unused|immutable)|Compiling|Build' | grep -v '^\[' ; swift test 2>&1 | tail -60"
