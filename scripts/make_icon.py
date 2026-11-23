#!/usr/bin/env python3
"""Draw the Cybermove app icon and write Resources/AppIcon.icns.

The cube uses the same oblique projection as the app (SpaceProjection.swift):
depth shifts a point left and down by 86/128 and 76/128 of z. Needs Pillow and
macOS's iconutil. The generated .icns is committed, so building the app does
not need this script.
"""
import colorsys
import math
import os
import subprocess
import sys
import tempfile

from PIL import Image, ImageDraw, ImageFilter

SIZE = 1024
SCALE = 2                       # supersampling for smooth edges
SHIFT_X, SHIFT_Y = 86 / 128, 76 / 128


def project(x, y, z):
    return (x - z * SHIFT_X, y - z * SHIFT_Y)


def draw_master():
    s = SIZE * SCALE
    img = Image.new("RGBA", (s, s), (0, 0, 0, 0))

    # Big Sur style: an 824 px rounded square centred on the 1024 canvas.
    margin, radius = 100 * SCALE, 185 * SCALE
    box = (margin, margin, s - margin, s - margin)

    shadow = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle(
        (box[0], box[1] + 14 * SCALE, box[2], box[3] + 14 * SCALE), radius, fill=(0, 0, 0, 110))
    img.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(14 * SCALE)))

    gradient = Image.new("RGBA", (s, s))
    top, bottom = (54, 72, 106), (14, 22, 40)
    for y in range(s):
        t = y / (s - 1)
        row = tuple(int(top[i] + (bottom[i] - top[i]) * t) for i in range(3)) + (255,)
        ImageDraw.Draw(gradient).line([(0, y), (s, y)], fill=row)
    mask = Image.new("L", (s, s), 0)
    ImageDraw.Draw(mask).rounded_rectangle(box, radius, fill=255)
    img.paste(gradient, (0, 0), mask)

    draw = ImageDraw.Draw(img)

    # Cube, fitted into the middle of the square.
    corners = [(-1, -1, -1), (1, -1, -1), (1, -1, 1), (-1, -1, 1),
               (-1, 1, -1), (1, 1, -1), (1, 1, 1), (-1, 1, 1)]
    edges = [(0, 1), (1, 2), (2, 3), (3, 0), (4, 5), (5, 6), (6, 7), (7, 4),
             (0, 4), (1, 5), (2, 6), (3, 7)]
    plane = [project(*c) for c in corners]
    xs, ys = [p[0] for p in plane], [p[1] for p in plane]
    box_w, box_h = max(xs) - min(xs), max(ys) - min(ys)
    target = 520 * SCALE
    scale = target / max(box_w, box_h)
    cx, cy = s / 2, s / 2 + 10 * SCALE
    mid_x, mid_y = (max(xs) + min(xs)) / 2, (max(ys) + min(ys)) / 2

    def to_screen(point):
        return (cx + (point[0] - mid_x) * scale, cy - (point[1] - mid_y) * scale)

    for a, b in edges:
        draw.line([to_screen(plane[a]), to_screen(plane[b])], fill=(196, 208, 226, 235),
                  width=12 * SCALE, joint="curve")

    # A line of signal points inside the cube, like the okto view.
    points = [(-0.45, -0.4, 0.5), (-0.5, 0.35, 0.2), (0.1, 0.5, -0.1),
              (0.5, 0.1, -0.35), (0.35, -0.45, -0.6)]
    screen = [to_screen(project(*p)) for p in points]
    draw.line(screen, fill=(255, 255, 255, 240), width=9 * SCALE, joint="curve")
    for index, point in enumerate(screen):
        r, g, b = colorsys.hsv_to_rgb(index / 5, 0.7, 0.95)
        radius_dot = 24 * SCALE
        draw.ellipse((point[0] - radius_dot, point[1] - radius_dot,
                      point[0] + radius_dot, point[1] + radius_dot),
                     fill=(int(r * 255), int(g * 255), int(b * 255), 255),
                     outline=(255, 255, 255, 255), width=4 * SCALE)
    return img.resize((SIZE, SIZE), Image.Resampling.LANCZOS)


def main():
    destination = sys.argv[1] if len(sys.argv) > 1 else "Resources/AppIcon.icns"
    master = draw_master()
    with tempfile.TemporaryDirectory() as tmp:
        iconset = os.path.join(tmp, "AppIcon.iconset")
        os.makedirs(iconset)
        for base in (16, 32, 128, 256, 512):
            for factor in (1, 2):
                name = f"icon_{base}x{base}" + ("@2x" if factor == 2 else "") + ".png"
                master.resize((base * factor, base * factor), Image.Resampling.LANCZOS).save(
                    os.path.join(iconset, name))
        subprocess.run(["iconutil", "-c", "icns", iconset, "-o", destination], check=True)
        if os.environ.get("ICON_PREVIEW"):
            master.save(os.environ["ICON_PREVIEW"])
    print("wrote", destination)


if __name__ == "__main__":
    main()
