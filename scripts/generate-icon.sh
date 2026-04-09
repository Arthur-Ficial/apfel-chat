#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
RESOURCES_DIR="$PROJECT_DIR/Resources"
ICON_SOURCE="$RESOURCES_DIR/icon-1024.png"
ICONSET_DIR="/tmp/AppIcon.iconset"
OUTPUT="$RESOURCES_DIR/AppIcon.icns"

# Generate source PNG if it doesn't exist
if [[ ! -f "$ICON_SOURCE" ]]; then
    echo "Generating source icon..."
    python3 -c "
import struct, zlib

def create_png(width, height, pixels):
    def chunk(ctype, data):
        c = ctype + data
        return struct.pack('>I', len(data)) + c + struct.pack('>I', zlib.crc32(c) & 0xffffffff)
    raw = b''
    for y in range(height):
        raw += b'\x00'  # filter byte
        for x in range(width):
            raw += bytes(pixels(x, y))
    return (b'\x89PNG\r\n\x1a\n' +
            chunk(b'IHDR', struct.pack('>IIBBBBB', width, height, 8, 6, 0, 0, 0)) +
            chunk(b'IDAT', zlib.compress(raw, 9)) +
            chunk(b'IEND', b''))

import math
size = 1024
cx, cy = size / 2, size / 2
r = size * 0.42

def pixel(x, y):
    dx, dy = x - cx, y - cy
    dist = math.sqrt(dx*dx + dy*dy)
    # Blue gradient circle
    if dist <= r:
        t = dist / r
        # Gradient from bright blue center to deeper blue edge
        rb = int(30 + 10 * t)
        g = int(130 + 20 * t)
        b = int(235 - 15 * t)
        # Subtle inner shadow at top
        shadow = max(0, min(1, (dy + r * 0.3) / (r * 0.6)))
        rb = int(rb * (0.85 + 0.15 * shadow))
        g = int(g * (0.85 + 0.15 * shadow))
        b = int(b * (0.85 + 0.15 * shadow))
        # Anti-alias edge
        edge = max(0, min(1, (r - dist) * 2))
        a = int(255 * edge)
        return (rb, g, b, a)
    # Chat bubble in center (simplified)
    bx, by = x - cx, y - cy + size * 0.02
    bw, bh = size * 0.22, size * 0.16
    # Rounded rect check
    rx, ry = bw - size * 0.06, bh - size * 0.06
    dx2 = max(0, abs(bx) - rx)
    dy2 = max(0, abs(by) - ry)
    bdist = math.sqrt(dx2*dx2 + dy2*dy2)
    corner_r = size * 0.06
    if bdist <= corner_r and dist <= r:
        edge = max(0, min(1, (corner_r - bdist) * 2))
        a = int(255 * edge)
        return (255, 255, 255, a)
    return (0, 0, 0, 0)

with open('$ICON_SOURCE', 'wb') as f:
    f.write(create_png(size, size, pixel))
print('Generated icon-1024.png')
"
fi

# Generate iconset
echo "Creating iconset..."
rm -rf "$ICONSET_DIR"
mkdir -p "$ICONSET_DIR"

for size in 16 32 128 256 512; do
    sips -z $size $size "$ICON_SOURCE" --out "$ICONSET_DIR/icon_${size}x${size}.png" > /dev/null 2>&1
    retina=$((size * 2))
    sips -z $retina $retina "$ICON_SOURCE" --out "$ICONSET_DIR/icon_${size}x${size}@2x.png" > /dev/null 2>&1
done
sips -z 1024 1024 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_512x512@2x.png" > /dev/null 2>&1

# Generate .icns
echo "Generating .icns..."
iconutil -c icns "$ICONSET_DIR" -o "$OUTPUT"
rm -rf "$ICONSET_DIR"

echo "Generated: $OUTPUT"
