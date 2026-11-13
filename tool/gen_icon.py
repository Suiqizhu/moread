"""生成安卓启动图标（渐变底 + 墨字），无第三方依赖除了 Pillow。"""
from PIL import Image, ImageDraw, ImageFont
import os

RES = "android/app/src/main/res"
FONT = "/system/fonts/NotoSansCJK-Regular.ttc"
TOP = (47, 74, 63)
BOTTOM = (110, 143, 127)

def gradient(size):
    img = Image.new("RGB", (size, size), TOP)
    d = ImageDraw.Draw(img)
    for y in range(size):
        t = y / max(1, size - 1)
        c = tuple(int(TOP[i] + (BOTTOM[i] - TOP[i]) * t) for i in range(3))
        d.line([(0, y), (size, y)], fill=c)
    return img

def rounded(img, radius_ratio=0.22):
    size = img.size[0]
    mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, size - 1, size - 1], radius=int(size * radius_ratio), fill=255)
    out = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    out.paste(img, (0, 0), mask)
    return out

def draw_glyph(img, ratio=0.62, dy=0.0):
    size = img.size[0]
    font = ImageFont.truetype(FONT, int(size * ratio))
    d = ImageDraw.Draw(img)
    box = d.textbbox((0, 0), "墨", font=font)
    w, h = box[2] - box[0], box[3] - box[1]
    d.text(((size - w) / 2 - box[0], (size - h) / 2 - box[1] + size * dy), "墨", font=font, fill=(246, 242, 232, 255))
    return img

for folder, px in [("mipmap-mdpi", 48), ("mipmap-hdpi", 72), ("mipmap-xhdpi", 96),
                   ("mipmap-xxhdpi", 144), ("mipmap-xxxhdpi", 192)]:
    os.makedirs(f"{RES}/{folder}", exist_ok=True)
    icon = draw_glyph(rounded(gradient(px * 4)), ratio=0.60).resize((px, px), Image.LANCZOS)
    icon.save(f"{RES}/{folder}/ic_launcher.png")
    # 自适应图标前景：内容缩到安全区内
    fg = Image.new("RGBA", (px * 4, px * 4), (0, 0, 0, 0))
    draw_glyph(fg, ratio=0.42)
    fg.resize((px, px), Image.LANCZOS).save(f"{RES}/{folder}/ic_launcher_foreground.png")

os.makedirs(f"{RES}/mipmap-anydpi-v26", exist_ok=True)
with open(f"{RES}/mipmap-anydpi-v26/ic_launcher.xml", "w") as f:
    f.write("""<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@color/ic_launcher_background"/>
    <foreground android:drawable="@mipmap/ic_launcher_foreground"/>
</adaptive-icon>
""")
os.makedirs(f"{RES}/values", exist_ok=True)
with open(f"{RES}/values/colors.xml", "w") as f:
    f.write("""<?xml version="1.0" encoding="utf-8"?>
<resources>
    <color name="ic_launcher_background">#2F4A3F</color>
</resources>
""")
print("icons generated")
