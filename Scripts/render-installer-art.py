#!/usr/bin/env python3
"""Render the disk-image background and the app icon.

Finder draws Brian.app and the Applications folder on top of the background.
The light pools sit on the same centers as the icon positions in package-dmg.sh.
"""

import io
import struct
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent
WIDTH = 660
HEIGHT = 400
APP_X = 180
APP_Y = 170
APPS_X = 480
APPS_Y = 170
SCALE = 4

REGULAR = "/usr/share/fonts/truetype/macos/Inter-Medium.ttf"
SEMIBOLD = "/usr/share/fonts/truetype/macos/Inter-SemiBold.ttf"


def mix(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3)) + (255,)


def render_background():
    w, h = WIDTH * SCALE, HEIGHT * SCALE
    image = Image.new("RGBA", (w, h))
    pixels = image.load()
    top = (248, 248, 250)
    bottom = (228, 228, 232)
    for y in range(h):
        row = mix(top, bottom, y / (h - 1))
        for x in range(w):
            pixels[x, y] = row

    def pool(cx, cy, radius, peak):
        left = max(0, int((cx - radius) * SCALE))
        right = min(w, int((cx + radius) * SCALE))
        top_px = max(0, int((cy - radius) * SCALE))
        bottom_px = min(h, int((cy + radius) * SCALE))
        radius_px = radius * SCALE
        for y in range(top_px, bottom_px):
            for x in range(left, right):
                dx = x - cx * SCALE
                dy = y - cy * SCALE
                distance = (dx * dx + dy * dy) ** 0.5
                if distance >= radius_px:
                    continue
                strength = (1 - distance / radius_px) ** 2 * peak
                current = pixels[x, y]
                pixels[x, y] = mix(current, (255, 255, 255), strength)

    pool(APP_X, APP_Y - 8, 118, 0.85)
    pool(APPS_X, APPS_Y - 8, 118, 0.85)

    draw = ImageDraw.Draw(image)
    y = APPS_Y * SCALE
    start = (APP_X + 92) * SCALE
    end = (APPS_X - 96) * SCALE
    thickness = 3 * SCALE
    draw.line((start, y + SCALE, end, y + SCALE), fill=(0, 0, 0, 28), width=thickness)
    draw.line((start, y, end, y), fill=(255, 255, 255, 230), width=max(1, SCALE))
    draw.line((start, y, end, y), fill=(120, 120, 128, 255), width=max(2, 2 * SCALE))
    head = 11 * SCALE
    draw.polygon(
        [(end, y - head), (end + head * 1.35, y), (end, y + head)],
        fill=(120, 120, 128, 255),
    )

    font = ImageFont.truetype(REGULAR, 15 * SCALE)
    caption = "Drag Brian to the Applications folder"
    text_box = draw.textbbox((0, 0), caption, font=font)
    text_w = text_box[2] - text_box[0]
    text_x = (w - text_w) / 2
    text_y = 332 * SCALE
    draw.text((text_x, text_y + SCALE), caption, font=font, fill=(0, 0, 0, 40))
    draw.text((text_x, text_y), caption, font=font, fill=(60, 60, 67, 255))

    retina = image.resize((WIDTH * 2, HEIGHT * 2), Image.Resampling.LANCZOS)
    plain = image.resize((WIDTH, HEIGHT), Image.Resampling.LANCZOS)
    # Finder paints a transparent disk-image background as black.
    retina = flatten(retina)
    plain = flatten(plain)
    retina.save(ROOT / "installer-background@2x.png")
    plain.save(ROOT / "installer-background.png")
    return plain


def flatten(image):
    base = Image.new("RGB", image.size, (236, 236, 238))
    base.paste(image, mask=image.getchannel("A"))
    return base


def render_icon():
    size = 1024
    image = Image.new("RGBA", (size, size), (22, 22, 24, 255))
    pixels = image.load()
    for y in range(size):
        for x in range(size):
            dx = x - size * 0.28
            dy = y - size * 0.22
            distance = (dx * dx + dy * dy) ** 0.5
            radius = size * 0.72
            if distance < radius:
                strength = (1 - distance / radius) ** 2 * 0.42
                pixels[x, y] = mix(pixels[x, y], (255, 255, 255), strength)
    draw = ImageDraw.Draw(image)
    font = ImageFont.truetype(SEMIBOLD, 620)
    glyph = "B"
    box = draw.textbbox((0, 0), glyph, font=font)
    text_w = box[2] - box[0]
    text_h = box[3] - box[1]
    draw.text(
        ((size - text_w) / 2 - box[0], (size - text_h) / 2 - box[1] - 18),
        glyph,
        font=font,
        fill=(255, 255, 255, 255),
    )
    image.save(ROOT / "AppIcon-1024.png")
    write_icns(image, ROOT / "AppIcon.icns")
    return image


def write_icns(master, path):
    types = (
        (16, b"icp4"),
        (32, b"icp5"),
        (64, b"icp6"),
        (128, b"ic07"),
        (256, b"ic08"),
        (512, b"ic09"),
        (1024, b"ic10"),
    )
    chunks = []
    for side, tag in types:
        resized = master.resize((side, side), Image.Resampling.LANCZOS)
        handle = io.BytesIO()
        resized.save(handle, format="PNG")
        payload = handle.getvalue()
        chunks.append(tag + struct.pack(">I", 8 + len(payload)) + payload)
    body = b"".join(chunks)
    path.write_bytes(b"icns" + struct.pack(">I", 8 + len(body)) + body)


def render_preview(background, icon):
    """Composite what Finder shows, so the layout can be checked off a Mac."""
    frame = Image.new("RGBA", (WIDTH, HEIGHT + 28), (236, 236, 238, 255))
    frame.paste(background.convert("RGBA"), (0, 28))
    draw = ImageDraw.Draw(frame)
    for index, color in enumerate(((255, 95, 86), (255, 189, 46), (39, 201, 63))):
        draw.ellipse((14 + index * 20, 8, 26 + index * 20, 20), fill=color)
    font = ImageFont.truetype(REGULAR, 13)
    title = "Install Brian"
    box = draw.textbbox((0, 0), title, font=font)
    draw.text(((WIDTH - (box[2] - box[0])) / 2, 6), title, font=font, fill=(70, 70, 74, 255))

    def place_icon(art, center, label):
        side = 112
        art = art.resize((side, side), Image.Resampling.LANCZOS)
        mask = Image.new("L", (side, side), 0)
        ImageDraw.Draw(mask).rounded_rectangle((0, 0, side - 1, side - 1), radius=26, fill=255)
        x = int(center[0] - side / 2)
        y = int(28 + center[1] - side / 2)
        shadow = Image.new("RGBA", (side, 18), (0, 0, 0, 0))
        ImageDraw.Draw(shadow).ellipse((8, 2, side - 8, 16), fill=(0, 0, 0, 36))
        frame.alpha_composite(shadow, (x, y + side - 4))
        frame.paste(art, (x, y), mask)
        label_font = ImageFont.truetype(REGULAR, 13)
        label_box = draw.textbbox((0, 0), label, font=label_font)
        label_w = label_box[2] - label_box[0]
        draw.text((center[0] - label_w / 2, y + side + 6), label, font=label_font, fill=(30, 30, 32, 255))

    folder = Image.new("RGBA", (512, 512), (0, 0, 0, 0))
    folder_draw = ImageDraw.Draw(folder)
    folder_draw.rounded_rectangle((36, 150, 476, 450), radius=36, fill=(84, 168, 242, 255))
    folder_draw.rounded_rectangle((36, 108, 210, 176), radius=18, fill=(84, 168, 242, 255))
    folder_draw.rounded_rectangle((56, 186, 456, 430), radius=28, fill=(120, 196, 255, 255))
    place_icon(icon, (APP_X, APP_Y), "Brian")
    place_icon(folder, (APPS_X, APPS_Y), "Applications")
    preview = Path("/tmp/brian-installer-preview.png")
    frame.convert("RGB").save(preview)
    print(preview)


if __name__ == "__main__":
    background = render_background()
    icon = render_icon()
    render_preview(background, icon)
