#!/bin/bash
# Patches ZeticMLange .swiftinterface files to remove $NonescapableTypes
# feature gates for Xcode 16.0 / Swift 6.0 compatibility.
# Run this AFTER Xcode resolves packages (first build attempt will fail).
# Not needed if using Xcode 16.3+.

set -e

DERIVED_DATA="$HOME/Library/Developer/Xcode/DerivedData"
IFACE_DIR=$(find "$DERIVED_DATA" -path "*/zeticmlangeios/*/ZeticMLange.xcframework/ios-arm64/ZeticMLange.framework/Modules/ZeticMLange.swiftmodule" -type d 2>/dev/null | head -1)

if [ -z "$IFACE_DIR" ]; then
    echo "ERROR: Could not find ZeticMLange.swiftmodule. Make sure Xcode has resolved packages first."
    exit 1
fi

python3 -c "
import sys, os

target_dir = '$IFACE_DIR'
for fname in ['arm64-apple-ios.swiftinterface', 'arm64-apple-ios.private.swiftinterface']:
    path = os.path.join(target_dir, fname)
    if not os.path.exists(path):
        continue
    with open(path) as f:
        lines = f.read().split('\n')
    result, count = [], 0
    i = 0
    while i < len(lines):
        if lines[i].strip() == '#if compiler(>=5.3) && \$NonescapableTypes':
            count += 1
            i += 1
            depth = 1
            while i < len(lines) and depth > 0:
                s = lines[i].strip()
                if s.startswith('#if '):
                    depth += 1
                    result.append(lines[i])
                elif s == '#endif' and depth == 1:
                    depth -= 1
                else:
                    if s == '#endif':
                        depth -= 1
                    result.append(lines[i])
                i += 1
        else:
            result.append(lines[i])
            i += 1
    with open(path, 'w') as f:
        f.write('\n'.join(result))
    print(f'Patched {fname}: removed {count} guards')
"

# Clear module cache so compiler re-reads the patched interface
find "$DERIVED_DATA" -name "Flow Pad-*" -path "*/Intermediates.noindex" -type d -exec rm -rf {} + 2>/dev/null || true
rm -rf "$DERIVED_DATA/ModuleCache.noindex" 2>/dev/null || true

echo "Done. Clean build folder in Xcode (Shift+Cmd+K) and rebuild."
