#!/usr/bin/env python3
"""Genera los iconos de Nexo: una N hecha de nodos conectados sobre degradado azul."""
import json, os
from PIL import Image, ImageDraw, ImageFilter

S = 4096

def glyph(size):
    from PIL import ImageFont
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    f = ImageFont.truetype("/System/Library/Fonts/HelveticaNeue.ttc", int(size * 0.62), index=1)
    bb = d.textbbox((0, 0), "N", font=f)
    w, h = bb[2] - bb[0], bb[3] - bb[1]
    d.text(((size - w) / 2 - bb[0], (size - h) / 2 - bb[1]), "N", font=f, fill=(255, 255, 255, 255))
    return img

def gradient(size):
    g = Image.new("RGB", (size, size), (18, 20, 26))
    glow = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    ImageDraw.Draw(glow).ellipse([size * .05, size * .3, size * 1.4, size * 1.6], fill=(41, 102, 237, 255))
    glow = glow.filter(ImageFilter.GaussianBlur(size // 4))
    return Image.alpha_composite(g.convert("RGBA"), glow).convert("RGB")

def render(size, mac=False):
    bg = gradient(S // 4).resize((S, S))
    # brillo suave arriba, como los iconos de Apple
    glow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ImageDraw.Draw(glow).ellipse([-S * .2, -S * .7, S * 1.2, S * .5], fill=(255, 255, 255, 0))
    bg = Image.alpha_composite(bg.convert("RGBA"), glow.filter(ImageFilter.GaussianBlur(S // 40)))
    shadow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    g = glyph(S)
    sh = g.copy(); sh.putalpha(g.getchannel("A").point(lambda v: int(v * .28)))
    shadow.paste(sh, (0, int(S * .012)), sh)
    bg = Image.alpha_composite(bg, shadow.filter(ImageFilter.GaussianBlur(S // 120)))
    bg = Image.alpha_composite(bg, g)
    if mac:  # macOS: cuadrado redondeado con margen y sombra
        inner = int(S * 824 / 1024)
        mask = Image.new("L", (inner, inner), 0)
        ImageDraw.Draw(mask).rounded_rectangle([0, 0, inner - 1, inner - 1], radius=int(inner * .225), fill=255)
        tile = bg.resize((inner, inner), Image.LANCZOS); tile.putalpha(mask)
        canvas = Image.new("RGBA", (S, S), (0, 0, 0, 0))
        off = (S - inner) // 2
        sh = Image.new("RGBA", (S, S), (0, 0, 0, 0)); sh.paste((0, 0, 0, 90), (off, off + S // 60), mask)
        canvas = Image.alpha_composite(canvas, sh.filter(ImageFilter.GaussianBlur(S // 80)))
        canvas.paste(tile, (off, off), tile)
        bg = canvas
    else:
        bg = bg.convert("RGB")
    return bg.resize((size, size), Image.LANCZOS)

def write(path, contents):
    os.makedirs(path, exist_ok=True)
    json.dump(contents, open(os.path.join(path, "Contents.json"), "w"), indent=2)

root = os.path.join(os.path.dirname(__file__), "..")
single = lambda platform: {"images": [{"filename": "icon.png", "idiom": "universal", "platform": platform, "size": "1024x1024"}],
                           "info": {"author": "xcode", "version": 1}}
for name, plat in [("Phone", "ios"), ("Watch", "watchos")]:
    d = f"{root}/{name}/Assets.xcassets"
    write(d, {"info": {"author": "xcode", "version": 1}})
    write(f"{d}/AppIcon.appiconset", single(plat))
    render(1024).save(f"{d}/AppIcon.appiconset/icon.png")

d = f"{root}/Mac/Assets.xcassets"
write(d, {"info": {"author": "xcode", "version": 1}})
images = []
for pt in (16, 32, 128, 256, 512):
    for sc in (1, 2):
        fn = f"icon_{pt}@{sc}x.png"
        render(pt * sc, mac=True).save(f"{d}/AppIcon.appiconset/{fn}") if os.makedirs(f"{d}/AppIcon.appiconset", exist_ok=True) is None else None
        images.append({"filename": fn, "idiom": "mac", "scale": f"{sc}x", "size": f"{pt}x{pt}"})
write(f"{d}/AppIcon.appiconset", {"images": images, "info": {"author": "xcode", "version": 1}})
render(1024).save(f"{root}/icon-preview.png")
print("ok")
