#!/bin/bash
# Assemble dist/Doom2016GOG.app. Wine is downloaded on first launch.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
APP="$ROOT/dist/Doom2016GOG.app"
KOSMIC_SRC="$ROOT/dist/upstream/kosmickrisp"
PYTHON_DIR="$ROOT/dist/python-standalone"
VERSION="${VERSION:-1.3.1}"
BUILD="${BUILD:-131}"
UPDATE_REPOSITORY="${UPDATE_REPOSITORY-filio-ink/doom2016-launcher}"
if [[ ! "$VERSION" =~ ^[0-9]+([.][0-9]+){1,2}(-[0-9A-Za-z.-]+)?([+][0-9A-Za-z.-]+)?$ || ! "$BUILD" =~ ^[0-9]+([.][0-9]+){0,2}$ ]]; then
    echo "Invalid app version or build number." >&2
    exit 1
fi
if [[ -n "$UPDATE_REPOSITORY" && ! "$UPDATE_REPOSITORY" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]]; then
    echo "Invalid update repository." >&2
    exit 1
fi

mkdir -p "$ROOT/dist/upstream"
# Both the source ZIP and the extracted library have checked-in SHA-256 pins.
python3 -B "$ROOT/dependencies.py" kosmic "$ROOT/dist/upstream/launcher-1.3.zip" \
    --extract "$KOSMIC_SRC"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" \
    "$APP/Contents/Resources/engine" \
    "$APP/Contents/Resources/vulkan/icd.d" \
    "$APP/Contents/Frameworks"

cp "$KOSMIC_SRC/libvulkan_kosmickrisp.dylib" "$APP/Contents/Frameworks/"
cp "$ROOT/vulkan/kosmickrisp_icd.json" "$APP/Contents/Resources/vulkan/icd.d/"
cp "$ROOT/launch.py" "$ROOT/dependencies.py" "$ROOT/dependencies.json" "$ROOT/NOTICES.txt" "$APP/Contents/Resources/engine/"
cp "$ROOT/NOTICES.txt" "$APP/Contents/Resources/NOTICES.txt"
mkdir -p "$APP/Contents/Resources/licenses"
cp "$ROOT/licenses/"* "$APP/Contents/Resources/licenses/"
cp "$ROOT/macos/cover.jpg" "$APP/Contents/Resources/cover.jpg"
# Dock icon: the DOOM title from the cover, on the red field. macOS rounds the corners.
ICONSET="$ROOT/dist/AppIcon.iconset"
SOURCE="$ROOT/dist/AppIcon-source.png"
rm -rf "$ICONSET"
mkdir -p "$ICONSET"
swift - "$ROOT/macos/cover.jpg" "$SOURCE" << 'EOF'
import AppKit
let cover = NSImage(contentsOfFile: CommandLine.arguments[1])!
let src = NSBitmapImageRep(data: cover.tiffRepresentation!)!
let x0 = 28, y0 = 18, lw = 292, lh = 146
let logoRep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: lw, pixelsHigh: lh,
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: lw * 4, bitsPerPixel: 32)!
for y in 0..<lh {
    for x in 0..<lw {
        let c = src.colorAt(x: x0 + x, y: y0 + y)!
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        c.usingColorSpace(.deviceRGB)!.getRed(&r, green: &g, blue: &b, alpha: &a)
        var alpha = (min(g, b) - 0.28) / 0.42
        if alpha < 0 { alpha = 0 }
        if alpha > 1 { alpha = 1 }
        logoRep.setColor(NSColor(calibratedRed: min(1, r + 0.04), green: min(1, g + 0.02), blue: min(1, b), alpha: alpha), atX: x, y: y)
    }
}
let logo = NSImage(size: NSSize(width: lw, height: lh))
logo.addRepresentation(logoRep)
let s: CGFloat = 1024
let image = NSImage(size: NSSize(width: s, height: s))
image.lockFocus()
let ctx = NSGraphicsContext.current!.cgContext
let top = NSColor(calibratedRed: 0.62, green: 0.08, blue: 0.05, alpha: 1)
let mid = NSColor(calibratedRed: 0.45, green: 0.04, blue: 0.03, alpha: 1)
let bot = NSColor(calibratedRed: 0.22, green: 0.02, blue: 0.015, alpha: 1)
let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [bot.cgColor, mid.cgColor, top.cgColor] as CFArray, locations: [0, 0.55, 1])!
ctx.drawLinearGradient(grad, start: CGPoint(x: s / 2, y: 0), end: CGPoint(x: s / 2, y: s), options: [])
let targetW = s * 0.78
let scale = targetW / CGFloat(lw)
let targetH = CGFloat(lh) * scale
logo.draw(in: NSRect(x: (s - targetW) / 2, y: (s - targetH) / 2, width: targetW, height: targetH), from: NSRect(x: 0, y: 0, width: lw, height: lh), operation: .sourceOver, fraction: 1)
image.unlockFocus()
try! NSBitmapImageRep(data: image.tiffRepresentation!)!.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[2]))
EOF
for size in 16 32 128 256 512; do
    sips -s format png -z "$size" "$size" "$SOURCE" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
    double=$((size * 2))
    sips -s format png -z "$double" "$double" "$SOURCE" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
rm -rf "$ICONSET" "$SOURCE"
chmod 755 "$APP/Contents/Frameworks/libvulkan_kosmickrisp.dylib"

# Never re-sign Python from an unchecked extracted cache.
python3 -B "$ROOT/dependencies.py" python "$ROOT/dist/upstream/python.tar.gz" \
    --extract "$PYTHON_DIR" --prefix python
mkdir -p "$APP/Contents/Resources/python"
rsync -a "$PYTHON_DIR/" "$APP/Contents/Resources/python/"

# Without -target, the binary's minimum becomes the SDK version (27 on this Mac) and macOS 26 will not open it.
SWIFT_FLAGS=(-parse-as-library -O -target arm64-apple-macos26.0 -framework SwiftUI -framework AppKit -framework WebKit -framework Security)
if [[ "${DEBUG:-}" == "1" ]]; then
    SWIFT_FLAGS+=(-DDEBUG)
fi
swiftc "${SWIFT_FLAGS[@]}" -o "$APP/Contents/MacOS/Doom" \
    "$ROOT/macos/DoomApp.swift" \
    "$ROOT/macos/AppUpdate.swift" \
    "$ROOT/macos/SecurityPolicy.swift"

cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>Doom</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>com.doom2016.secure</string>
    <key>DOOMUpdateRepository</key>
    <string>${UPDATE_REPOSITORY:-}</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleDisplayName</key>
    <string>DOOM (2016) Secure</string>
    <key>CFBundleName</key>
    <string>DOOM (2016) Secure</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundleVersion</key>
    <string>${BUILD}</string>
    <key>LSMinimumSystemVersion</key>
    <string>26.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSDesktopFolderUsageDescription</key>
    <string>The game folder may be on the Desktop.</string>
    <key>NSDocumentsFolderUsageDescription</key>
    <string>The game folder may be in Documents.</string>
    <key>NSDownloadsFolderUsageDescription</key>
    <string>The game folder may be in Downloads.</string>
    <key>NSRemovableVolumesUsageDescription</key>
    <string>The game folder may be on an external volume.</string>
</dict>
</plist>
EOF

SIGN_ID="${SIGN_ID:--}"
ENTITLEMENTS="$ROOT/macos/entitlements.plist"
if [[ "$SIGN_ID" == "-" && "${REQUIRE_SIGN:-}" == "1" ]]; then
    echo "A release requires a Developer ID signing identity." >&2
    exit 1
fi
if [[ "$SIGN_ID" != "-" ]] && ! security find-identity -v -p codesigning | grep -Fq -- "$SIGN_ID"; then
    echo "Requested signing identity not found: $SIGN_ID" >&2
    exit 1
fi
python3 - "$APP" "$SIGN_ID" "$ENTITLEMENTS" <<'PY'
import os, subprocess, sys
root, identity, entitlements = sys.argv[1:]
main = os.path.join(root, "Contents/MacOS/Doom")
found = []
for dirpath, _, names in os.walk(root):
    for name in names:
        path = os.path.join(dirpath, name)
        if os.path.islink(path) or os.path.realpath(path) == os.path.realpath(main):
            continue
        kind = subprocess.run(["file", "-b", path], capture_output=True, text=True).stdout
        if "Mach-O" in kind:
            found.append((path.count(os.sep), path, kind))
found.sort(reverse=True)
for _, path, kind in found:
    command = [
        "codesign", "--force", "--sign", identity,
        "--options", "runtime",
    ]
    if identity != "-":
        command.append("--timestamp")
    # Entitlements apply to executables. Libraries are sealed with the hardened runtime only.
    if "executable" in kind and "shared library" not in kind and "bundle" not in kind:
        command.extend(["--entitlements", entitlements])
    command.append(path)
    subprocess.check_call(command)
command = ["codesign", "--force", "--sign", identity, "--options", "runtime",
           "--entitlements", entitlements]
if identity != "-":
    command.append("--timestamp")
subprocess.check_call(command + [root])
PY
codesign --verify --deep --strict --verbose=2 "$APP"

echo "Built $APP"
du -sh "$APP"
