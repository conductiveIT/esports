import zlib
import struct

def write_png(buf, width, height, path):
    png_sig = b'\x89PNG\r\n\x1a\n'
    ihdr_data = struct.pack("!IIBBBBB", width, height, 8, 6, 0, 0, 0)
    ihdr = b'IHDR' + ihdr_data
    ihdr_chunk = struct.pack("!I", len(ihdr_data)) + ihdr + struct.pack("!I", zlib.crc32(ihdr) & 0xFFFFFFFF)
    rows = []
    for y in range(height):
        row = b'\x00'
        for x in range(width):
            pixel = buf[y * width + x]
            row += struct.pack("BBBB", *pixel)
        rows.append(row)
    idat_data = zlib.compress(b"".join(rows))
    idat = b'IDAT' + idat_data
    idat_chunk = struct.pack("!I", len(idat_data)) + idat + struct.pack("!I", zlib.crc32(idat) & 0xFFFFFFFF)
    iend = b'IEND'
    iend_chunk = struct.pack("!I", 0) + iend + struct.pack("!I", zlib.crc32(iend) & 0xFFFFFFFF)
    with open(path, "wb") as f:
        f.write(png_sig + ihdr_chunk + idat_chunk + iend_chunk)

width, height = 1024, 200
# Create a dark charcoal bar with 200/255 opacity (~78%)
# We can also add a slight horizontal gradient for 'premium' look
buf = []
for y in range(height):
    for x in range(width):
        # Dark charcoal color
        r, g, b = 15, 15, 15
        # 180 opacity in the center, 0 at the extreme horizontal edges for a fade
        alpha = 180
        if x < 100: alpha = int(180 * (x / 100))
        if x > 924: alpha = int(180 * ((1024 - x) / 100))
        buf.append((r, g, b, alpha))

write_png(buf, width, height, "mods/tdm_core/textures/tdm_hud_bar.png")
print("High-contrast branding bar generated.")
