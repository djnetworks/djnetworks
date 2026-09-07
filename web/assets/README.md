# web/assets

Only the DJ Network's app icons live here, and only because a browser and an Android launcher need
raster files — the mark itself is typographic and is drawn in CSS (`.wordmark` in `style.css`).

`djn-icon-{32,64,192,512}.png` and `djn-apple-touch-icon.png` are all rendered from one 1024px
source: a teal `#2B7379` ground, an orange `#FF9700` dot, and `DJ` in white. Content sits inside
the centred 80% circle so a launcher that crops to a circle or a squircle cannot clip the letters.
`manifest.webmanifest` declares 192 and 512, and 512 again as `maskable`.

**The EKUM icon is deliberately NOT here.** It lives in `reference/design/ekum-icon-1024.png`, which
is repo-only — Cloudflare Pages publishes `web/` and nothing above it. It was a colour reference for
`tokens.css` and nothing more: the app icons come from the DJ wordmark, and EKUM appears exactly
once in the whole product, as the words "Built by EKUM" under the operator sign-in button. Putting
the icon in the deploy root would publish an EKUM mark at a guessable URL on chachu's own site.

To regenerate after a change to the mark:

```bash
python3 - <<'PY'
from PIL import Image, ImageDraw, ImageFont
TEAL, WHITE, ORANGE = (0x2B,0x73,0x79), (255,255,255), (0xFF,0x97,0x00)
F = '/System/Library/Fonts/Supplemental/Arial Bold.ttf'
S = 1024
im = Image.new('RGB', (S, S), TEAL); d = ImageDraw.Draw(im)
f = ImageFont.truetype(F, int(S * 0.36))
l, t, r, b = d.textbbox((0, 0), 'DJ', font=f); tw, th = r - l, b - t
dot, gap = int(S * 0.072), int(S * 0.05)
x0, cy = (S - (dot + gap + tw)) // 2, S // 2
d.ellipse([x0, cy - dot // 2, x0 + dot, cy + dot // 2], fill=ORANGE)
d.text((x0 + dot + gap - l, cy - th // 2 - t), 'DJ', font=f, fill=WHITE)
for n, name in [(512, 'djn-icon-512.png'), (192, 'djn-icon-192.png'),
                (180, 'djn-apple-touch-icon.png'), (64, 'djn-icon-64.png'), (32, 'djn-icon-32.png')]:
    im.resize((n, n), Image.LANCZOS).save('web/assets/' + name)
PY
```

Bump the `?v=` on the `<link rel="icon">` tags if you do — a favicon is one of the most aggressively
cached things a browser holds.
