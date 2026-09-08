#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
HARNESS="$ROOT/.build/source-microphone-verification"
mkdir -p "$HARNESS/Sources/RemoteMic" "$HARNESS/Tests/RemoteMicTests"
cp "$ROOT/Tests/SourceMicrophone/Package.swift" "$HARNESS/Package.swift"
for name in SourceMicrophoneSessionController SourceMicrophoneFnMonitor AudioRouteWaiter; do
  ln -sfn "$ROOT/Sources/RemoteMic/$name.swift" "$HARNESS/Sources/RemoteMic/$name.swift"
done
ln -sfn "$ROOT/Tests/RemoteMicTests/SourceMicrophoneSessionTests.swift" "$HARNESS/Tests/RemoteMicTests/SourceMicrophoneSessionTests.swift"
ln -sfn "$ROOT/Tests/RemoteMicTests/AudioRouteWaiterTests.swift" "$HARNESS/Tests/RemoteMicTests/AudioRouteWaiterTests.swift"
swift test --package-path "$HARNESS"
