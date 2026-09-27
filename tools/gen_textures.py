"""Generate tileable, photo-style PBR textures for The Horizon Protocol.
Outputs albedo (jpg), normal (png) and roughness (png) maps into assets/textures/.
Everything is procedural (numpy), so there are no licensing worries.
"""
import os
import numpy as np
from PIL import Image
from scipy import ndimage

OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "textures")
os.makedirs(OUT, exist_ok=True)
rng = np.random.default_rng(1983)


# ---------------------------------------------------------------- noise helpers

def fnoise(h, w, beta=2.0, seed=None, aniso=(1.0, 1.0)):
    """Seamless fractal noise via spectral synthesis (1/f^beta). aniso stretches frequencies."""
    r = np.random.default_rng(seed) if seed is not None else rng
    fy = np.fft.fftfreq(h)[:, None] * aniso[0]
    fx = np.fft.fftfreq(w)[None, :] * aniso[1]
    f = np.sqrt(fx * fx + fy * fy)
    f[0, 0] = 1.0
    spec = (r.normal(size=(h, w)) + 1j * r.normal(size=(h, w))) / f ** (beta / 2.0)
    spec[0, 0] = 0
    n = np.real(np.fft.ifft2(spec))
    n -= n.min()
    return n / (n.max() + 1e-9)


def band(h, w, lo, hi, seed=None, aniso=(1.0, 1.0)):
    """Band-limited seamless noise between frequencies lo..hi (cycles per pixel)."""
    r = np.random.default_rng(seed) if seed is not None else rng
    fy = np.fft.fftfreq(h)[:, None] * aniso[0]
    fx = np.fft.fftfreq(w)[None, :] * aniso[1]
    f = np.sqrt(fx * fx + fy * fy)
    mask = np.exp(-((np.log(f + 1e-9) - np.log((lo * hi) ** 0.5)) ** 2) / (2 * (np.log(hi / lo) / 2) ** 2))
    spec = (r.normal(size=(h, w)) + 1j * r.normal(size=(h, w))) * mask
    n = np.real(np.fft.ifft2(spec))
    n -= n.min()
    return n / (n.max() + 1e-9)


def voronoi(h, w, n_points, seed=None, stretch=(1.0, 1.0)):
    """Seamless Voronoi via KD-tree on tiled points: returns (F1, F2-F1 edge distance, cell id)."""
    from scipy.spatial import cKDTree
    r = np.random.default_rng(seed) if seed is not None else rng
    pts = r.random((n_points, 2)) * [h, w]
    tiles, ids = [], []
    for dy in (-h, 0, h):
        for dx in (-w, 0, w):
            tiles.append(pts + [dy, dx])
            ids.append(np.arange(n_points))
    allp = np.concatenate(tiles) * stretch
    allid = np.concatenate(ids)
    tree = cKDTree(allp)
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    q = np.stack([yy.ravel(), xx.ravel()], 1) * stretch
    d, idx = tree.query(q, k=2)
    f1 = d[:, 0].reshape(h, w)
    f2 = d[:, 1].reshape(h, w)
    cid = allid[idx[:, 0]].reshape(h, w)
    return f1.astype(np.float32), (f2 - f1).astype(np.float32), cid


def normal_from_height(hgt, strength):
    gx = (np.roll(hgt, -1, 1) - np.roll(hgt, 1, 1)) * strength
    gy = (np.roll(hgt, -1, 0) - np.roll(hgt, 1, 0)) * strength
    n = np.dstack([-gx, gy, np.ones_like(hgt)])
    n /= np.linalg.norm(n, axis=2, keepdims=True)
    return ((n * 0.5 + 0.5) * 255).astype(np.uint8)


def lerp(a, b, t):
    t = np.clip(t, 0, 1)[..., None] if np.ndim(t) == 2 else t
    return a + (b - a) * t


def col(*rgb):
    return np.array(rgb, np.float32) / 255.0


def save(name, albedo, height, rough, nstrength=4.0, albedo_alpha=None):
    a = np.clip(albedo * 255, 0, 255).astype(np.uint8)
    if albedo_alpha is not None:
        Image.fromarray(np.dstack([a, (np.clip(albedo_alpha, 0, 1) * 255).astype(np.uint8)]), "RGBA").save(os.path.join(OUT, name + "_albedo.png"))
    else:
        Image.fromarray(a, "RGB").save(os.path.join(OUT, name + "_albedo.jpg"), quality=90)
    if height is not None:
        Image.fromarray(normal_from_height(height, nstrength), "RGB").save(os.path.join(OUT, name + "_normal.png"))
    if rough is not None:
        Image.fromarray((np.clip(rough, 0, 1) * 255).astype(np.uint8), "L").save(os.path.join(OUT, name + "_rough.png"))
    print("wrote", name)


def scatter_lines(h, w, count, length, width, seed, angle_range=(0, np.pi), color_var=0.2):
    """Draw many short thin lines (pine needles, twigs) into a height/colour layer, wrapping at edges."""
    r = np.random.default_rng(seed)
    hl = np.zeros((h, w), np.float32)
    cv = np.zeros((h, w), np.float32)
    for _ in range(count):
        y0, x0 = r.random() * h, r.random() * w
        a = r.uniform(*angle_range)
        L = length * r.uniform(0.6, 1.3)
        steps = int(L * 1.5)
        v = r.uniform(1 - color_var, 1.0)
        for s in range(steps):
            t = s / steps
            y = int(y0 + np.sin(a) * L * t) % h
            x = int(x0 + np.cos(a) * L * t) % w
            for k in range(-width + 1, width):
                hl[(y + k) % h, x] = max(hl[(y + k) % h, x], 1.0 - abs(k) / width)
                cv[(y + k) % h, x] = v
    return hl, cv


S = 1024

# ---------------------------------------------------------------- forest floor

def forest_floor():
    base = fnoise(S, S, 2.2, 1)
    fine = band(S, S, 0.05, 0.3, 2)
    moss = band(S, S, 0.003, 0.02, 3)
    dirt = lerp(col(58, 44, 30), col(86, 66, 44), base)
    alb = lerp(dirt, col(62, 78, 38), np.clip((moss - 0.55) * 4, 0, 1) * 0.8)
    needles_h, needles_c = scatter_lines(S, S, 5500, 26, 2, 4)
    needle_col = lerp(col(118, 78, 42), col(150, 104, 58), needles_c)
    alb = alb * (1 - needles_h[..., None] * 0.9) + needle_col * needles_h[..., None] * 0.9
    twig_h, _ = scatter_lines(S, S, 180, 70, 3, 5)
    alb = alb * (1 - twig_h[..., None] * 0.8) + col(70, 50, 34) * twig_h[..., None] * 0.8
    alb *= (0.85 + fine * 0.3)[..., None]
    hgt = base * 0.6 + fine * 0.3 + needles_h * 0.5 + twig_h * 0.8
    rough = 0.75 - needles_h * 0.1 + fine * 0.1
    save("forest_floor", alb, hgt, rough, 6.0)


# ---------------------------------------------------------------- mud

def mud():
    base = fnoise(S, S, 2.4, 11)
    fine = band(S, S, 0.04, 0.25, 12)
    ruts = band(S, S, 0.002, 0.02, 13, aniso=(0.15, 1.0))   # stretched along one axis: tyre ruts
    puddle = np.clip((ruts - 0.58) * 6, 0, 1)
    alb = lerp(col(44, 32, 22), col(98, 76, 52), base * 0.7 + fine * 0.3)
    alb = lerp(alb, col(30, 24, 18), puddle * 0.9)
    stones, _, _ = voronoi(S, S, 900, 14)
    pebble = np.clip(1 - stones / 6.0, 0, 1) * (band(S, S, 0.1, 0.4, 15) > 0.55)
    alb = lerp(alb, col(110, 100, 88), pebble * 0.6)
    hgt = base * 0.5 + fine * 0.4 + pebble * 0.8 - puddle * 0.8
    hgt = np.where(puddle > 0.5, hgt.min(), hgt)
    rough = np.clip(0.55 - puddle * 0.5 + fine * 0.1, 0.03, 1)
    save("mud", alb, hgt, rough, 5.0)


# ---------------------------------------------------------------- gravel

def gravel():
    f1, edge, cid = voronoi(S, S, 3000, 21)
    shade = (cid * 7919 % 97) / 97.0
    stone = np.clip(edge / 5.0, 0, 1)
    alb = lerp(col(88, 84, 78), col(150, 144, 134), shade)
    alb = alb * (0.55 + stone * 0.45)[..., None]
    alb *= (0.85 + band(S, S, 0.02, 0.1, 22) * 0.3)[..., None]
    hgt = stone ** 0.6
    rough = 0.8 - stone * 0.15
    save("gravel", alb, hgt, rough, 8.0)


# ---------------------------------------------------------------- pine bark

def bark():
    h, w = 1024, 512
    f1, edge, cid = voronoi(h, w, 520, 31, stretch=(0.2, 1.0))   # tall vertical plates
    plates = np.clip(edge / 6.0, 0, 1)
    tint = (cid * 7919 % 53) / 53.0
    grain = band(h, w, 0.02, 0.2, 32, aniso=(0.1, 1.0))
    alb = lerp(col(52, 34, 24), col(128, 84, 58), plates * 0.7 + tint * 0.3)
    alb = lerp(alb, col(30, 22, 16), (1 - plates) ** 3)
    alb *= (0.8 + grain * 0.4)[..., None]
    lichen = np.clip((band(h, w, 0.004, 0.03, 33) - 0.7) * 5, 0, 1)
    alb = lerp(alb, col(110, 120, 90), lichen * 0.5)
    hgt = plates ** 0.5 + grain * 0.3
    rough = 0.85 + (1 - plates) * 0.1
    Image.fromarray((np.clip(alb, 0, 1) * 255).astype(np.uint8)).save(os.path.join(OUT, "bark_albedo.jpg"), quality=90)
    Image.fromarray(normal_from_height(hgt, 7.0)).save(os.path.join(OUT, "bark_normal.png"))
    Image.fromarray((np.clip(rough, 0, 1) * 255).astype(np.uint8), "L").save(os.path.join(OUT, "bark_rough.png"))
    print("wrote bark")


# ---------------------------------------------------------------- log (debarked pine, lighter)

def log_side():
    h, w = 1024, 512
    grain = band(h, w, 0.01, 0.15, 41, aniso=(0.06, 1.0))
    knots, _, _ = voronoi(h, w, 18, 42)
    knot = np.clip(1 - knots / 14.0, 0, 1)
    bark_patches = np.clip((band(h, w, 0.003, 0.03, 43) - 0.55) * 5, 0, 1)
    alb = lerp(col(120, 82, 50), col(176, 132, 86), grain)
    lines = np.clip((band(h, w, 0.03, 0.12, 45, aniso=(0.03, 1.0)) - 0.6) * 5, 0, 1)
    alb = lerp(alb, col(96, 64, 40), lines * 0.6)
    alb = lerp(alb, col(90, 60, 38), knot)
    alb = lerp(alb, col(78, 54, 38), bark_patches)
    alb *= (0.85 + fnoise(h, w, 2.0, 44) * 0.25)[..., None]
    hgt = grain * 0.5 + bark_patches * 0.6 - knot * 0.3
    rough = 0.7 + bark_patches * 0.2
    Image.fromarray((np.clip(alb, 0, 1) * 255).astype(np.uint8)).save(os.path.join(OUT, "log_albedo.jpg"), quality=90)
    Image.fromarray(normal_from_height(hgt, 5.0)).save(os.path.join(OUT, "log_normal.png"))
    Image.fromarray((np.clip(rough, 0, 1) * 255).astype(np.uint8), "L").save(os.path.join(OUT, "log_rough.png"))
    print("wrote log")


# ---------------------------------------------------------------- concrete

def concrete():
    base = fnoise(S, S, 2.0, 51)
    fine = band(S, S, 0.1, 0.45, 52)
    stains = band(S, S, 0.002, 0.015, 53)
    streaks = band(S, S, 0.004, 0.05, 54, aniso=(1.0, 0.08))   # vertical rain streaks
    alb = lerp(col(118, 116, 110), col(160, 158, 150), base * 0.5 + fine * 0.3 + 0.2)
    alb = lerp(alb, col(90, 88, 82), np.clip((stains - 0.55) * 3, 0, 1) * 0.6)
    alb = lerp(alb, col(80, 78, 74), np.clip((streaks - 0.6) * 3, 0, 1) * 0.5)
    pores = (band(S, S, 0.3, 0.5, 55) > 0.78).astype(np.float32)
    alb *= (1 - pores * 0.25)[..., None]
    # Hairline cracks from Voronoi edges
    _, edge, _ = voronoi(S, S, 40, 56)
    crack = (edge < 1.2) & (band(S, S, 0.005, 0.03, 57) > 0.58)
    alb = np.where(crack[..., None], alb * 0.55, alb)
    hgt = base * 0.2 + fine * 0.2 - pores * 0.3 - crack * 0.6
    rough = 0.85 - np.clip((stains - 0.6) * 2, 0, 0.3)
    save("concrete", alb, hgt, rough, 3.0)


# ---------------------------------------------------------------- asphalt

def asphalt():
    f1, edge, cid = voronoi(S, S, 6000, 61)
    agg = np.clip(edge / 2.5, 0, 1)
    shade = (cid * 7919 % 89) / 89.0
    alb = lerp(col(32, 32, 34), col(70, 70, 72), shade * agg)
    alb *= (0.85 + band(S, S, 0.003, 0.02, 62) * 0.3)[..., None]
    wet = np.clip((band(S, S, 0.002, 0.01, 63) - 0.55) * 4, 0, 1)
    alb = alb * (1 - wet[..., None] * 0.3)
    hgt = agg * 0.6
    rough = np.clip(0.8 - wet * 0.65, 0.08, 1)
    save("asphalt", alb, hgt, rough, 4.0)


# ---------------------------------------------------------------- rusty painted metal (tintable)

def painted_metal():
    base = fnoise(S, S, 2.2, 71)
    rust_mask = np.clip((band(S, S, 0.002, 0.015, 72) * 0.65 + band(S, S, 0.02, 0.1, 73) * 0.35 - 0.56) * 6, 0, 1)
    streaks = np.clip((band(S, S, 0.006, 0.05, 74, aniso=(1.0, 0.06)) - 0.5) * 3, 0, 1)
    paint = lerp(col(205, 205, 200), col(235, 235, 230), base)        # light grey: tinted per object
    rust = lerp(col(90, 48, 26), col(150, 80, 40), band(S, S, 0.05, 0.3, 75))
    alb = lerp(paint, rust, rust_mask)
    alb = lerp(alb, col(120, 70, 40), streaks * 0.5)
    scratches, _ = scatter_lines(S, S, 400, 30, 1, 76, color_var=0)
    alb = lerp(alb, col(170, 170, 170), scratches * 0.5)
    hgt = rust_mask * 0.5 + band(S, S, 0.1, 0.4, 77) * rust_mask * 0.4
    rough = 0.45 + rust_mask * 0.45
    save("painted_metal", alb, hgt, rough, 3.0)


# ---------------------------------------------------------------- rock

def rock():
    base = fnoise(S, S, 1.8, 81)
    f1, edge, _ = voronoi(S, S, 70, 82)
    cracks = np.clip(edge / 6.0, 0, 1)
    speck = band(S, S, 0.25, 0.5, 83)
    alb = lerp(col(88, 88, 86), col(150, 148, 142), base * 0.6 + speck * 0.4)
    alb *= (0.6 + cracks * 0.4)[..., None]
    moss = np.clip((band(S, S, 0.003, 0.02, 84) - 0.6) * 4, 0, 1)
    alb = lerp(alb, col(70, 86, 46), moss * 0.7)
    hgt = base * 0.7 + cracks * 0.3 + speck * 0.1
    rough = 0.8 - moss * 0.1
    save("rock", alb, hgt, rough, 7.0)


# ---------------------------------------------------------------- wood planks

def planks():
    grain = band(S, S, 0.01, 0.12, 91, aniso=(0.05, 1.0))
    rows = 8
    plank_id = (np.arange(S) * rows // S)[None, :].repeat(S, 0)
    tone = (plank_id * 37 % 11) / 11.0
    gap = ((np.arange(S) % (S // rows)) < 4)[None, :].repeat(S, 0)
    alb = lerp(col(92, 66, 44), col(140, 104, 70), grain * 0.6 + tone * 0.4)
    alb = np.where(gap[..., None], alb * 0.35, alb)
    alb *= (0.85 + fnoise(S, S, 2.0, 92) * 0.25)[..., None]
    hgt = grain * 0.4 - gap * 0.8
    rough = 0.75
    save("planks", alb, hgt, np.full((S, S), rough), 4.0)


# ---------------------------------------------------------------- uniform camo (woodland, muted)

def camo():
    s = 512
    layers = [(col(62, 66, 52), None)]
    alb = np.zeros((s, s, 3), np.float32) + layers[0][0]
    for i, c in enumerate([col(88, 84, 62), col(40, 44, 34), col(104, 96, 74)]):
        m = band(s, s, 0.004, 0.02, 101 + i) > 0.58
        alb[m] = c
    weave = band(s, s, 0.3, 0.5, 105)
    alb *= (0.9 + weave * 0.15)[..., None]
    hgt = weave * 0.3
    save("camo", alb, hgt, np.full((s, s), 0.9), 2.0)


# ---------------------------------------------------------------- pine branch card (alpha)

def pine_card():
    h, w = 512, 512
    alb = np.zeros((h, w, 3), np.float32)
    alpha = np.zeros((h, w), np.float32)
    r = np.random.default_rng(111)
    # A drooping branch from the left edge to the right, with side twigs covered in needles
    def draw_line(y0, x0, y1, x1, width, c):
        n = int(max(abs(y1 - y0), abs(x1 - x0)) * 1.5) + 1
        for t in np.linspace(0, 1, n):
            y, x = y0 + (y1 - y0) * t, x0 + (x1 - x0) * t
            wv = width * (1 - t * 0.6)
            yi0, yi1 = int(max(0, y - wv - 1)), int(min(h, y + wv + 2))
            xi0, xi1 = int(max(0, x - wv - 1)), int(min(w, x + wv + 2))
            for yy in range(yi0, yi1):
                for xx in range(xi0, xi1):
                    d = np.hypot(yy - y, xx - x)
                    a = np.clip(wv + 0.5 - d, 0, 1)
                    if a > alpha[yy, xx]:
                        alpha[yy, xx] = a
                        alb[yy, xx] = c
    main_y = h * 0.45
    draw_line(main_y, 0, main_y + 60, w * 0.98, 5, col(70, 48, 32))
    for i in range(44):
        t = r.uniform(0.02, 0.98)
        by, bx = main_y + 60 * t, w * 0.98 * t
        side = 1 if i % 2 else -1
        ey = by + side * r.uniform(80, 190)
        ex = bx + r.uniform(20, 110)
        draw_line(by, bx, ey, ex, 2, col(80, 56, 36))
        # Needles along the twig
        for k in range(120):
            tt = r.uniform(0, 1)
            ny, nx = by + (ey - by) * tt, bx + (ex - bx) * tt
            ang = np.arctan2(ey - by, ex - bx) + side * r.uniform(0.4, 1.2) * r.choice([-1, 1])
            L = r.uniform(18, 30)
            g = r.uniform(0.75, 1.1)
            draw_line(ny, nx, ny + np.sin(ang) * L, nx + np.cos(ang) * L, 1.2, col(38 * g, 70 * g, 40 * g))
    Image.fromarray(np.dstack([(np.clip(alb, 0, 1) * 255).astype(np.uint8), (alpha * 255).astype(np.uint8)]), "RGBA").save(os.path.join(OUT, "pine_card_albedo.png"))
    print("wrote pine card")


def fern_card():
    """Fern/undergrowth sprite: several arching fronds with leaflets (RGBA)."""
    h, w = 512, 512
    alb = np.zeros((h, w, 3), np.float32)
    alpha = np.zeros((h, w), np.float32)
    r = np.random.default_rng(222)

    def dot(y, x, rad, c):
        yi0, yi1 = int(max(0, y - rad - 1)), int(min(h, y + rad + 2))
        xi0, xi1 = int(max(0, x - rad - 1)), int(min(w, x + rad + 2))
        for yy in range(yi0, yi1):
            for xx in range(xi0, xi1):
                a = np.clip(rad + 0.5 - np.hypot(yy - y, xx - x), 0, 1)
                if a > alpha[yy, xx]:
                    alpha[yy, xx] = a
                    alb[yy, xx] = c

    for f in range(9):
        ang = np.radians(r.uniform(-65, 65))
        L = r.uniform(260, 420)
        bend = r.uniform(0.6, 1.2)
        g = r.uniform(0.8, 1.15)
        base = col(52 * g, 88 * g, 36 * g)
        for k in range(160):
            t = k / 160
            x = w / 2 + np.sin(ang) * L * t
            y = h - 4 - np.cos(ang) * L * t + (t * t) * L * 0.35 * bend
            dot(y, x, 1.6, col(60, 70, 34))
            if k % 6 == 0 and t > 0.08:
                lf = (1 - t) * 38 + 6
                for side in (-1, 1):
                    pa = ang + side * np.radians(75)
                    for j in range(int(lf)):
                        tt = j / lf
                        dot(y - np.cos(pa) * j * 0.9 + tt * 4, x + np.sin(pa) * j * 0.9, 2.6 * (1 - tt) + 0.6, base * (0.8 + 0.3 * tt))
    Image.fromarray(np.dstack([(np.clip(alb, 0, 1) * 255).astype(np.uint8), (alpha * 255).astype(np.uint8)]), "RGBA").save(os.path.join(OUT, "fern_card_albedo.png"))
    print("wrote fern card")


def clouds():
    """Tileable overcast cloud layer (greyscale in RGB, density in alpha)."""
    s = 1024
    n = fnoise(s, s, 2.6, 301) * 0.65 + band(s, s, 0.004, 0.03, 302) * 0.35
    dens = np.clip((n - 0.35) * 2.2, 0, 1)
    shade = 0.55 + 0.45 * (1 - band(s, s, 0.01, 0.06, 303))
    rgb = np.dstack([shade, shade * 1.01, shade * 1.03])
    Image.fromarray(np.dstack([(np.clip(rgb, 0, 1) * 255).astype(np.uint8), (dens * 255).astype(np.uint8)]), "RGBA").save(os.path.join(OUT, "clouds_albedo.png"))
    print("wrote clouds")


if __name__ == "__main__":
    import sys
    todo = sys.argv[1:] or ["forest_floor", "mud", "gravel", "bark", "log_side", "concrete", "asphalt", "painted_metal", "rock", "planks", "camo", "pine_card", "fern_card", "clouds"]
    for name in todo:
        globals()[name]()

