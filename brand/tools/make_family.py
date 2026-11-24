from PIL import Image, ImageDraw, ImageFont
from pathlib import Path

W, H = 1920, 1080
BG = (11, 12, 15)
PANEL = (19, 20, 25)
LINE = (43, 46, 55)
GOLD = (230, 195, 132)
RED = (166, 58, 47)
BONE = (242, 239, 231)
INK = (17, 17, 17)
WHITE = (245, 243, 238)
MUTED = (145, 150, 160)

FONT = r'C:\Windows\Fonts\segoeui.ttf'
FONTB = r'C:\Windows\Fonts\segoeuib.ttf'


def f(size, bold=False):
    return ImageFont.truetype(FONTB if bold else FONT, size)


def fit(img, box):
    x0, y0, x1, y1 = box
    w, h = x1 - x0, y1 - y0
    s = min(w / img.width, h / img.height)
    im = img.resize((round(img.width * s), round(img.height * s)), Image.LANCZOS)
    return im, (x0 + (w - im.width) // 2, y0 + (h - im.height) // 2)


canvas = Image.new('RGB', (W, H), BG)
d = ImageDraw.Draw(canvas)

d.text((80, 56), 'RONIN  +  KENSEI', font=f(54, True), fill=GOLD)
d.text((82, 124), 'Sistema de marca  ·  A + C = Ronin   ·   B = Kensei', font=f(25), fill=MUTED)

kasa = Image.open('brand/ronin/png/ronin-kasa.png').convert('RGBA')
mon_dark = Image.open('brand/ronin/png/ronin-mon-dark.png').convert('RGBA')
mon_red = Image.open('kensei/brand/png/kensei-mon.png').convert('RGBA')

cards = [
    (80, 210, 600, 770, BONE, kasa, 'RONIN  /  KASA', 'Marca principal · fondos claros', INK),
    (640, 210, 1160, 770, PANEL, mon_dark, 'RONIN  /  MON', 'Sello · fondos oscuros', WHITE),
    (1200, 210, 1720, 770, PANEL, mon_red, 'KENSEI  /  MON', 'Sub-marca CLI · sello rojo', WHITE),
]

for x0, y0, x1, y1, tile, img, title, note, fg in cards:
    d.rounded_rectangle((x0, y0, x1, y1), radius=28, fill=tile, outline=LINE, width=2)
    im, pos = fit(img, (x0 + 55, y0 + 45, x1 - 55, y1 - 120))
    canvas.paste(im, pos, im)
    d.text((x0 + 36, y1 - 78), title, font=f(28, True), fill=fg)
    d.text((x0 + 36, y1 - 42), note, font=f(19), fill=MUTED)

# Paletas
d.text((80, 850), 'PALETA RONIN', font=f(18, True), fill=MUTED)
for i, (name, col) in enumerate([('INK', '#111111'), ('GOLD', '#E6C384'), ('BONE', '#F2EFE7')]):
    x = 80 + i * 250
    d.rounded_rectangle((x, 890, x + 54, 944), radius=10, fill=col, outline=LINE, width=1)
    d.text((x + 68, 894), name, font=f(17, True), fill=WHITE)
    d.text((x + 68, 918), col, font=f(15), fill=MUTED)

d.text((1200, 850), 'PALETA KENSEI', font=f(18, True), fill=MUTED)
for i, (name, col) in enumerate([('VERMILION', '#A63A2F'), ('GOLD', '#E6C384'), ('INK', '#111111')]):
    x = 1200 + i * 250
    d.rounded_rectangle((x, 890, x + 54, 944), radius=10, fill=col, outline=LINE, width=1)
    d.text((x + 68, 894), name, font=f(17, True), fill=WHITE)
    d.text((x + 68, 918), col, font=f(15), fill=MUTED)

d.text((80, 1015), 'SVG maestros, variantes one-color, app icons y favicons en brand/ronin/ y kensei/brand/.', font=f(17), fill=(105, 110, 120))

Path('brand').mkdir(exist_ok=True)
canvas.save('brand/brand-family.png', quality=95)
print('ok')
