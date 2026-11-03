from PIL import Image
import os

S = 1024
img = Image.new('RGBA', (S, S), (0, 0, 0, 0))
from PIL import ImageDraw
d = ImageDraw.Draw(img)

m = int(S * 0.075)
d.rounded_rectangle((m, m, S - m, S - m), radius=int(S * 0.18), fill=(242, 239, 232, 255))

pm = int(S * 0.20)
d.rounded_rectangle((pm, pm, S - pm, S - pm), radius=int(S * 0.09), fill=(255, 255, 254, 255))

# 橄榄绿进度条（呼应应用内的目标进度条）
d.rounded_rectangle((S * 0.28, S * 0.24, S * 0.52, S * 0.29), radius=S * 0.025, fill=(107, 127, 94, 255))

# 三行正文灰线
for i, (x0, x1) in enumerate([(0.28, 0.72), (0.28, 0.72), (0.28, 0.60)]):
    y = S * (0.36 + 0.11 * i)
    d.rounded_rectangle((S * x0, y, S * x1, y + S * 0.045), radius=S * 0.02, fill=(216, 209, 190, 255))

img.save('icon_source.png')

os.makedirs('icon.iconset', exist_ok=True)
spec = {
    16: ['icon_16x16.png'],
    32: ['icon_16x16@2x.png', 'icon_32x32.png'],
    64: ['icon_32x32@2x.png'],
    128: ['icon_128x128.png'],
    256: ['icon_128x128@2x.png', 'icon_256x256.png'],
    512: ['icon_256x256@2x.png', 'icon_512x512.png'],
    1024: ['icon_512x512@2x.png'],
}
for size, names in spec.items():
    im = img.resize((size, size), Image.LANCZOS)
    for n in names:
        im.save(os.path.join('icon.iconset', n))
print('iconset ok')
