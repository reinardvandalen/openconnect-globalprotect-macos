#!/usr/bin/env python3

from pathlib import Path
from PIL import Image, ImageChops, ImageDraw, ImageFilter


ROOT = Path(__file__).resolve().parent.parent
ICONSET = ROOT / "Assets" / "AppIcon.iconset"
SIZE = 1024


def rounded_mask(size: int, radius: int) -> Image.Image:
    mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, size, size), radius=radius, fill=255)
    return mask


def gradient(size: int, start: tuple[int, int, int], end: tuple[int, int, int]) -> Image.Image:
    image = Image.new("RGBA", (size, size))
    pixels = image.load()
    for y in range(size):
        for x in range(size):
            amount = (x + y) / (2 * (size - 1))
            pixels[x, y] = tuple(
                round(start[channel] * (1 - amount) + end[channel] * amount)
                for channel in range(3)
            ) + (255,)
    return image


def create_master() -> Image.Image:
    canvas = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    tile_size = 880
    tile = gradient(tile_size, (10, 132, 255), (21, 184, 166))
    tile.putalpha(rounded_mask(tile_size, 214))
    canvas.alpha_composite(tile, (72, 72))

    ambient = Image.new("RGBA", (tile_size, tile_size), (0, 0, 0, 0))
    ambient_draw = ImageDraw.Draw(ambient)
    ambient_draw.ellipse((-30, -54, 374, 350), fill=(255, 255, 255, 28))
    ambient_draw.ellipse((566, 530, 996, 960), fill=(142, 247, 233, 24))
    ambient.putalpha(ImageChops.multiply(ambient.getchannel("A"), rounded_mask(tile_size, 214)))
    canvas.alpha_composite(ambient, (72, 72))

    shadow = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    shield = [(512, 216), (598, 275), (754, 312), (754, 499), (735, 622),
              (661, 731), (512, 822), (363, 731), (289, 622), (270, 499), (270, 312), (426, 275)]
    ImageDraw.Draw(shadow).polygon([(x, y + 28) for x, y in shield], fill=(0, 42, 84, 90))
    shadow = shadow.filter(ImageFilter.GaussianBlur(30))
    canvas.alpha_composite(shadow)

    shield_layer = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    shield_draw = ImageDraw.Draw(shield_layer)
    shield_draw.polygon(shield, fill=(241, 252, 255, 242))
    inner = [(512, 312), (575, 353), (678, 384), (678, 500), (660, 590),
             (608, 665), (512, 727), (416, 665), (364, 590), (346, 500), (346, 384), (449, 353)]
    shield_draw.polygon(inner, fill=(10, 132, 255, 38))
    canvas.alpha_composite(shield_layer)

    lock_layer = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    lock_draw = ImageDraw.Draw(lock_layer)
    lock_draw.arc((448, 354, 576, 482), start=180, end=360, fill=(8, 126, 229, 255), width=36)
    lock_draw.line((448, 418, 448, 474), fill=(8, 126, 229, 255), width=36)
    lock_draw.line((576, 418, 576, 474), fill=(8, 126, 229, 255), width=36)
    lock_draw.rounded_rectangle((431, 461, 593, 607), radius=38, fill=(8, 126, 229, 255))
    lock_draw.ellipse((492, 505, 532, 545), fill=(255, 255, 255, 255))
    lock_draw.rounded_rectangle((504, 524, 520, 567), radius=8, fill=(255, 255, 255, 255))
    canvas.alpha_composite(lock_layer)

    badge = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    badge_draw = ImageDraw.Draw(badge)
    badge_draw.ellipse((628, 616, 842, 830), fill=(255, 255, 255, 255))
    badge_draw.ellipse((641, 629, 829, 817), fill=(40, 205, 65, 255))
    badge_draw.line((691, 724, 723, 756, 781, 689), fill=(255, 255, 255, 255), width=25, joint="curve")
    canvas.alpha_composite(badge)

    return canvas


def main() -> None:
    ICONSET.mkdir(parents=True, exist_ok=True)
    master = create_master()
    outputs = {
        "icon_16x16.png": 16,
        "icon_16x16@2x.png": 32,
        "icon_32x32.png": 32,
        "icon_32x32@2x.png": 64,
        "icon_128x128.png": 128,
        "icon_128x128@2x.png": 256,
        "icon_256x256.png": 256,
        "icon_256x256@2x.png": 512,
        "icon_512x512.png": 512,
        "icon_512x512@2x.png": 1024,
    }
    for filename, size in outputs.items():
        master.resize((size, size), Image.Resampling.LANCZOS).save(ICONSET / filename)


if __name__ == "__main__":
    main()
