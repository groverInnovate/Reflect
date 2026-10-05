#!/bin/bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_DIR="$ROOT_DIR/.build/portable-tests"
mkdir -p "$TEST_DIR"
export CLANG_MODULE_CACHE_PATH="$ROOT_DIR/.build/ModuleCache"
# Isolate the pure package so testing never builds the macOS executable.
swift build --package-path "$ROOT_DIR/LifeReplayCore" --disable-sandbox --build-tests > "$TEST_DIR/swift-test-build.log" 2>&1 && {
    swift test --package-path "$ROOT_DIR/LifeReplayCore" --disable-sandbox --skip-build
    exit 0
}
# A broken test must not be hidden by fallback. Use this only when the test
# frameworks themselves are absent from the selected Apple toolchain.
if ! rg -q "no such module '(XCTest|Testing)'" "$TEST_DIR/swift-test-build.log"; then
    cat "$TEST_DIR/swift-test-build.log"
    exit 1
fi
swift build --package-path "$ROOT_DIR/LifeReplayCore" --disable-sandbox
BIN_DIR="$(swift build --package-path "$ROOT_DIR/LifeReplayCore" --disable-sandbox --show-bin-path)"
python3 - "$ROOT_DIR" "$TEST_DIR" <<'PY'
import re, sys
from pathlib import Path
root, destination = map(Path, sys.argv[1:])
for old in destination.glob("*Tests.swift"): old.unlink()
calls=[]
for source in sorted((root/'LifeReplayCore/Tests/LifeReplayCoreTests').glob('*.swift')):
    text=source.read_text()
    (destination/source.name).write_text(text.replace('import XCTest', ''))
    name=re.search(r'final class (\w+): XCTestCase',text)[1]
    for method, throwing in re.findall(r'func (test\w+)\(\)( throws)?',text):
        calls.append(f'        {"try " if throwing else ""}{name}().{method}()\n        print("PASS {name}.{method}")')
(destination/'Runner.swift').write_text('import Foundation\n@main struct Runner {\n    static func main() throws {\n'+ '\n'.join(calls)+f'\n        print("{len(calls)} core tests passed")\n    }}\n}}\n')
PY
swiftc -swift-version 6 -I "$BIN_DIR/Modules" "$BIN_DIR"/LifeReplayCore.build/*.swift.o \
    "$ROOT_DIR/scripts/PortableTestSupport.swift" "$TEST_DIR"/*Tests.swift \
    "$TEST_DIR/Runner.swift" -o "$TEST_DIR/run"
"$TEST_DIR/run"
