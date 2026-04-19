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

def create_skin(base_color, path):
    width, height = 64, 64
    buf = [(0, 0, 0, 0)] * (width * height)
    
    def fill(x1, y1, x2, y2, color):
        for y in range(y1, y2):
            for x in range(x1, x2):
                if 0 <= x < width and 0 <= y < height:
                    buf[y * width + x] = color

    # --- BASE OVERALL COLOR (The Suit) ---
    fill(0, 16, 64, 64, base_color)
    
    # --- HEAD MAPPING (Standard 64x64) ---
    hair_color = (45, 30, 20, 255)
    skin_color = (255, 205, 160, 255)
    
    # Head Top: Hair
    fill(8, 0, 16, 8, hair_color)
    # Head Bottom: Skin (Neck/Chin)
    fill(16, 0, 24, 8, skin_color)
    
    # Face (Front): Skin + Eyes + Mouth
    fill(8, 8, 16, 16, skin_color)
    fill(10, 11, 11, 12, (0, 0, 0, 255)) # Eye L
    fill(13, 11, 14, 12, (0, 0, 0, 255)) # Eye R
    fill(11, 14, 13, 15, (160, 60, 60, 255)) # Mouth
    
    # Sides and Back of head: Hair
    fill(0, 8, 8, 16, hair_color) # Right
    fill(16, 8, 24, 16, hair_color) # Back
    fill(24, 8, 32, 16, hair_color) # Left
    
    # --- BODY DETAILS ---
    armor_color = (max(0, base_color[0]-40), max(0, base_color[1]-40), max(0, base_color[2]-40), 255)
    
    # Torso Front (Center: 20,20 to 28,32)
    fill(20, 21, 28, 26, armor_color) # Chest Plate
    fill(23, 23, 25, 25, (255, 255, 255, 255)) # Emblem

    write_png(buf, width, height, path)

create_skin((100, 100, 100, 255), "mods/tdm_core/textures/tdm_skin_neutral.png")
create_skin((220, 30, 30, 255), "mods/tdm_core/textures/tdm_skin_red.png")
create_skin((30, 30, 220, 255), "mods/tdm_core/textures/tdm_skin_blue.png")
print("Full 64x64 head mappings generated.")
