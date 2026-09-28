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


def warp(img, amount, seed, scale=(0.004, 0.03)):
    """Domain-warp an image with smooth seamless noise (breaks up the procedural look)."""
    h, w = img.shape[:2]
    dy = (band(h, w, scale[0], scale[1], seed) - 0.5) * amount
    dx = (band(h, w, scale[0], scale[1], seed + 1) - 0.5) * amount
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    coords = [yy + dy, xx + dx]
    if img.ndim == 2:
        return ndimage.map_coordinates(img, coords, order=1, mode="grid-wrap")
    return np.dstack([ndimage.map_coordinates(img[..., c], coords, order=1, mode="grid-wrap") for c in range(img.shape[2])])


def blur(img, sigma):
    return ndimage.gaussian_filter(img, sigma, mode="wrap")


def ao_from_height(hgt, radius=6.0, strength=2.5):
    """Cavity / ambient occlusion: darken pixels lower than their surroundings."""
    h = (hgt - hgt.min()) / (np.ptp(hgt) + 1e-9)
    cav = blur(h, radius) - h
    cav2 = blur(h, radius * 3) - h
    return np.clip(1.0 - (cav * strength + cav2 * strength * 0.5), 0.35, 1.0)


def ridged(h, w, beta, seed):
    n = fnoise(h, w, beta, seed)
    return 1.0 - np.abs(n * 2.0 - 1.0)


def norm01(a):
    return (a - a.min()) / (np.ptp(a) + 1e-9)


def hue_jitter(alb, amount, seed):
    """Low-frequency colour variation so big surfaces don't look uniform."""
    h, w = alb.shape[:2]
    j = np.dstack([band(h, w, 0.002, 0.012, seed + k) - 0.5 for k in range(3)])
    return alb * (1.0 + j * amount)


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

def forest_floor():
    """Conifer forest floor: dark humus, drifts of pine needles, moss clumps, twigs, small leaves and cones."""
    soil_n = fnoise(S, S, 2.3, 1)
    fine = band(S, S, 0.08, 0.4, 2)
    moss_m = np.clip((warp(band(S, S, 0.003, 0.018, 3), 60, 300) - 0.56) * 5, 0, 1)
    drift = band(S, S, 0.002, 0.015, 7)          # where needles pile up
    soil = lerp(col(40, 30, 21), col(70, 54, 37), soil_n * 0.7 + fine * 0.3)
    alb = soil.copy()
    hgt = soil_n * 0.35 + fine * 0.15
    # moss: fuzzy, bright-ish green with dark speckle
    moss_fine = band(S, S, 0.15, 0.5, 8)
    moss_col = lerp(col(46, 60, 24), col(92, 110, 44), moss_fine * 0.7 + band(S, S, 0.01, 0.05, 9) * 0.3)
    alb = lerp(alb, moss_col, moss_m)
    hgt = hgt + moss_m * (0.35 + moss_fine * 0.25)
    # needles: two layers (old grey-brown underneath, fresher orange-brown on top)
    for layer, (count, c0, c1, seed) in enumerate([(6500, col(84, 66, 48), col(112, 90, 66), 4),
                                                   (5000, col(116, 74, 40), col(150, 100, 56), 5)]):
        nh, nc = scatter_lines(S, S, count, 24, 2, seed)
        keep = np.clip((drift - 0.2) * 2.5, 0, 1) * (1 - moss_m * 0.85)
        nh = nh * keep
        ncol = lerp(c0, c1, nc)
        alb = alb * (1 - nh[..., None] * 0.95) + ncol * nh[..., None] * 0.95
        hgt = np.maximum(hgt, hgt * 0.6 + nh * (0.45 + layer * 0.15))
    # twigs
    th, tc = scatter_lines(S, S, 140, 90, 3, 6, color_var=0.35)
    alb = lerp(alb, lerp(col(52, 38, 28), col(92, 72, 52), tc), th * 0.9)
    hgt = np.maximum(hgt, th * 0.9)
    # small dead leaves / bark flakes (Voronoi cells, sparse)
    f1, edge, cid = voronoi(S, S, 900, 10)
    pick = ((cid * 2654435761) % 100) < 4
    leaf = np.clip(edge / 5.0, 0, 1) * pick
    leaf_col = lerp(col(70, 50, 32), col(110, 80, 50), (cid * 7919 % 31) / 31.0)
    alb = lerp(alb, leaf_col, np.clip(leaf * 3, 0, 1) * 0.7)
    hgt = hgt + np.clip(leaf * 3, 0, 1) * 0.25
    ao = ao_from_height(hgt, 4.0, 3.0)
    alb = hue_jitter(alb * ao[..., None], 0.18, 11)
    rough = np.clip(0.82 - moss_m * 0.08 + fine * 0.08 - np.clip(leaf * 3, 0, 1) * 0.15, 0, 1)
    save("forest_floor", alb, hgt, rough, 7.0)


def mud():
    """Churned wet mud: tyre ruts, clumps, embedded stones, glossy puddles in the low spots."""
    base = fnoise(S, S, 2.4, 11)
    clumps = warp(band(S, S, 0.02, 0.12, 12), 25, 310) ** 1.5
    ruts = warp(band(S, S, 0.002, 0.02, 13, aniso=(0.12, 1.0)), 40, 320)
    tread = (np.sin(np.arange(S)[:, None] * 0.55 + band(S, S, 0.01, 0.05, 16) * 6) * 0.5 + 0.5)
    rut_mask = np.clip((0.42 - ruts) * 6, 0, 1)
    hgt = base * 0.45 + clumps * 0.35 - rut_mask * 0.5 + rut_mask * tread * 0.08
    f1, edge, cid = voronoi(S, S, 2600, 14)
    tt = f1 / (f1 + edge * 0.5 + 1e-6)
    stone_pick = ((cid * 2654435761) % 100) < 14
    stone = np.sqrt(np.clip(1 - tt ** 2, 0, 1)) * (tt < 0.85) * stone_pick
    hgt = hgt + stone * 0.4
    water_level = np.percentile(hgt, 18)
    puddle = np.clip((water_level - hgt) * 25, 0, 1)
    wet = np.clip(1 - (hgt - water_level) * 3.0, 0, 1)            # damp near the water
    dry = lerp(col(70, 54, 38), col(122, 98, 70), norm01(base * 0.5 + clumps * 0.5))
    alb = lerp(dry, col(42, 32, 23), wet * 0.75)
    stone_col = lerp(col(92, 88, 80), col(140, 132, 118), (cid * 7919 % 41) / 41.0)
    alb = lerp(alb, stone_col * (0.7 + 0.3 * stone[..., None]), np.clip(stone * 2.5, 0, 1))
    alb = lerp(alb, col(34, 28, 22), puddle * 0.85)
    alb = alb * ao_from_height(hgt, 5.0, 2.0)[..., None]
    alb = hue_jitter(alb, 0.12, 17)
    hgt = np.maximum(hgt, water_level)                              # puddle surface is flat
    rough = np.clip(0.78 - wet * 0.4 - puddle * 0.4 + np.clip(stone * 2.5, 0, 1) * 0.1, 0.03, 1)
    save("mud", alb, hgt, rough, 6.0)


def gravel():
    """Road gravel: rounded, individually coloured stones with fine dust packed between them."""
    alb = np.zeros((S, S, 3), np.float32)
    hgt = np.zeros((S, S), np.float32)
    # two sizes of stones layered: big ones sit on top of smaller ones
    for layer, (n, rad, seed) in enumerate([(5200, 9.0, 21), (1700, 16.0, 24)]):
        f1, edge, cid = voronoi(S, S, n, seed)
        f1 = warp(f1, 4, seed + 400, (0.02, 0.1)); edge = warp(edge, 4, seed + 400, (0.02, 0.1))
        t = f1 / (f1 + edge * 0.5 + 1e-6)                          # 0 at stone centre, 1 at its edge
        dome = np.sqrt(np.clip(1 - t ** 2.2, 0, 1)) * (t < 0.92)    # rounded pebble, with a gap between
        rough_st = band(S, S, 0.15, 0.45, seed + 1)
        shade = (cid * 7919 % 97) / 97.0
        hue = (cid * 104729 % 13) / 13.0
        c = lerp(col(88, 84, 78), col(142, 136, 126), shade)
        c = lerp(c, col(128, 104, 82), (hue > 0.75) * 0.6)          # some warm stones
        c = lerp(c, col(70, 72, 74), (hue < 0.15) * 0.6)            # some dark basalt
        c = c * (0.85 + rough_st[..., None] * 0.3) * (0.55 + 0.45 * dome[..., None])
        h_layer = dome * (0.6 + layer * 0.5) + rough_st * 0.05
        on_top = h_layer > hgt
        alb = np.where(on_top[..., None], c, alb)
        hgt = np.maximum(hgt, h_layer)
    dust = lerp(col(96, 88, 76), col(120, 110, 96), band(S, S, 0.05, 0.3, 26))
    low = np.clip((0.3 - hgt) * 6, 0, 1)
    dusty = np.clip((band(S, S, 0.003, 0.02, 28) - 0.45) * 3, 0, 1)      # patches where dust covers stones
    low = np.maximum(low, dusty * 0.6)
    alb = lerp(alb, dust, low)
    alb = alb * ao_from_height(hgt, 3.0, 3.5)[..., None]
    alb = hue_jitter(alb, 0.1, 27)
    rough = np.clip(0.72 + low * 0.18 - hgt * 0.1, 0, 1)
    save("gravel", alb, hgt, rough, 9.0)


def bark():
    """Mature pine bark: grey-brown flaky plates split by deep dark furrows, reddish where flakes peeled."""
    h, w = 1024, 512
    f1, edge, cid = voronoi(h, w, 220, 31, stretch=(0.18, 1.0))
    edge = blur(warp(edge, 10, 330), 1.2)
    plates = np.clip(edge / 7.0, 0, 1)
    plate_h = plates ** 0.45
    layers = warp(band(h, w, 0.02, 0.12, 32, aniso=(0.25, 1.0)), 10, 332)
    flakes = np.floor(layers * 5) / 5.0                             # stepped flaky layers
    tint = (cid * 7919 % 53) / 53.0
    peeled = np.clip((band(h, w, 0.01, 0.05, 34) - 0.58) * 4, 0, 1) * (plates > 0.4)
    alb = lerp(col(84, 62, 50), col(134, 104, 84), flakes * 0.6 + tint * 0.4)     # weathered grey-brown
    alb = lerp(alb, col(142, 82, 52), peeled * 0.8)                               # fresh red-orange under flakes
    alb = lerp(alb, col(40, 28, 22), np.clip(1 - plates * 1.8, 0, 1) * 0.85)       # furrows
    lichen = np.clip((band(h, w, 0.004, 0.03, 33) - 0.66) * 5, 0, 1) * (plates > 0.3)
    alb = lerp(alb, col(120, 132, 100), lichen * 0.6)
    hgt = plate_h * 0.8 + flakes * 0.25 * plates - peeled * 0.08
    alb = alb * ao_from_height(hgt, 4.0, 2.5)[..., None]
    alb = hue_jitter(alb, 0.1, 35)
    rough = 0.88 + (1 - plates) * 0.1 - peeled * 0.1
    Image.fromarray((np.clip(alb, 0, 1) * 255).astype(np.uint8)).save(os.path.join(OUT, "bark_albedo.jpg"), quality=92)
    Image.fromarray(normal_from_height(hgt, 8.0)).save(os.path.join(OUT, "bark_normal.png"))
    Image.fromarray((np.clip(rough, 0, 1) * 255).astype(np.uint8), "L").save(os.path.join(OUT, "bark_rough.png"))
    print("wrote bark")


def log_side():
    """Debarked, weathered pine log: pale grey-tan wood, long drying cracks, knots and bark scraps."""
    h, w = 1024, 512
    grain = warp(band(h, w, 0.01, 0.2, 41, aniso=(25.0, 1.0)), 5, 340, (0.002, 0.01))
    rings = np.sin(warp(np.tile(np.arange(w, dtype=np.float32)[None, :] * 0.35, (h, 1)), 30, 342) + grain * 4) * 0.5 + 0.5
    knots_d, _, kid = voronoi(h, w, 14, 42)
    knot = np.clip(1 - knots_d / 12.0, 0, 1) ** 1.5
    weather = band(h, w, 0.003, 0.02, 44)
    fresh = lerp(col(150, 118, 84), col(186, 156, 118), grain * 0.7 + rings * 0.15 + 0.15)
    grey = lerp(col(118, 110, 98), col(152, 144, 130), grain)
    alb = lerp(fresh, grey, np.clip(weather * 1.4 - 0.1, 0, 1) * 0.85)                   # sun-bleached patches
    alb = lerp(alb, col(84, 56, 36), knot)
    # long checks (drying cracks) running along the log
    cracks = np.zeros((h, w), np.float32)
    r = np.random.default_rng(45)
    for _ in range(9):
        x0 = r.uniform(0, w); y0 = r.uniform(0, h); L = r.uniform(200, 600)
        for t in range(int(L)):
            y = int(y0 + t) % h
            x = int(x0 + np.sin(t * 0.02 + x0) * 6) % w
            width = 1.5 * np.sin(np.pi * t / L)
            for k in range(-2, 3):
                cracks[y, (x + k) % w] = max(cracks[y, (x + k) % w], np.clip(width - abs(k), 0, 1))
    alb = lerp(alb, col(40, 30, 22), cracks)
    bark_scrap = np.clip((band(h, w, 0.004, 0.03, 43) - 0.74) * 6, 0, 1)
    alb = lerp(alb, col(70, 54, 42), bark_scrap)
    hgt = grain * 0.35 + rings * 0.1 - cracks * 0.8 - knot * 0.2 + bark_scrap * 0.5
    alb = alb * ao_from_height(hgt, 3.0, 2.0)[..., None]
    rough = 0.72 + bark_scrap * 0.2 + np.clip(weather - 0.5, 0, 0.5) * 0.2
    Image.fromarray((np.clip(alb, 0, 1) * 255).astype(np.uint8)).save(os.path.join(OUT, "log_albedo.jpg"), quality=92)
    Image.fromarray(normal_from_height(hgt, 6.0)).save(os.path.join(OUT, "log_normal.png"))
    Image.fromarray((np.clip(rough, 0, 1) * 255).astype(np.uint8), "L").save(os.path.join(OUT, "log_rough.png"))
    print("wrote log")


def concrete():
    """Cast concrete: exposed aggregate, air pores, formwork seams, rain streaks, grime and hairline cracks."""
    base = fnoise(S, S, 2.0, 51)
    fine = band(S, S, 0.1, 0.45, 52)
    f1, edge, cid = voronoi(S, S, 9000, 58)
    agg = np.clip(edge / 2.2, 0, 1) * (((cid * 2654435761) % 100) < 35)
    agg_col = lerp(col(120, 116, 108), col(176, 170, 160), (cid * 7919 % 29) / 29.0)
    stains = warp(band(S, S, 0.002, 0.015, 53), 50, 350)
    streaks = band(S, S, 0.004, 0.05, 54, aniso=(1.0, 0.06))
    alb = lerp(col(126, 124, 118), col(168, 165, 156), base * 0.5 + fine * 0.3 + 0.2)
    alb = lerp(alb, agg_col, agg * 0.35)
    alb = lerp(alb, col(94, 92, 86), np.clip((stains - 0.55) * 3, 0, 1) * 0.55)
    alb = lerp(alb, col(82, 80, 76), np.clip((streaks - 0.58) * 3, 0, 1) * 0.5)
    pores = (np.random.default_rng(55).random((S, S)) > 0.996).astype(np.float32)
    pores = np.clip(blur(pores, 0.8) * 4, 0, 1) * 0.5
    seams = np.zeros((S, S), np.float32)
    seams[:, :3] = 1.0                                                            # formwork panel joint
    seams[S // 2 - 1:S // 2 + 2, :] = 0.6
    zc = np.abs(band(S, S, 0.004, 0.02, 56) - 0.5)                     # zero-crossings of noise = crack lines
    crack = np.clip(1 - zc / 0.006, 0, 1) * 0.8 * (band(S, S, 0.005, 0.03, 57) > 0.62)
    hgt = base * 0.2 + fine * 0.15 + agg * 0.1 - pores * 0.4 - crack * 0.7 - seams * 0.3
    alb = lerp(alb, col(60, 58, 54), crack * 0.8)
    alb = alb * ao_from_height(hgt, 3.0, 2.0)[..., None]
    alb = hue_jitter(alb, 0.08, 59)
    rough = np.clip(0.88 - np.clip((stains - 0.6) * 2, 0, 0.3) - np.clip((streaks - 0.6) * 2, 0, 0.2), 0, 1)
    save("concrete", alb, hgt, rough, 3.5)


def asphalt():
    """Worn road asphalt: exposed stone aggregate in black binder, cracks sealed with tar, wet patches."""
    f1, edge, cid = voronoi(S, S, 26000, 61)
    agg = np.clip(edge / 2.0, 0, 1)
    dome = np.sqrt(np.clip(agg * (2 - agg), 0, 1)) * (((cid * 2654435761) % 100) < 55)
    shade = (cid * 7919 % 89) / 89.0
    binder = lerp(col(24, 24, 26), col(40, 40, 42), band(S, S, 0.05, 0.3, 64))
    stone = lerp(col(56, 55, 54), col(104, 100, 96), shade)
    alb = lerp(binder, stone, dome * 0.6)
    wear = band(S, S, 0.002, 0.012, 62)
    alb = alb * (0.8 + wear * 0.35)[..., None]
    zc = np.abs(band(S, S, 0.003, 0.015, 65) - 0.5)
    gate = band(S, S, 0.004, 0.02, 66) > 0.55
    crack = np.clip(1 - zc / 0.005, 0, 1) * gate
    sealant = np.clip(1 - zc / 0.016, 0, 1) * gate
    alb = lerp(alb, col(14, 14, 15), sealant * 0.85)
    wet = np.clip((band(S, S, 0.002, 0.01, 63) - 0.55) * 4, 0, 1)
    alb = alb * (1 - wet[..., None] * 0.35)
    hgt = dome * 0.6 - crack * 0.6 + sealant * 0.1
    alb = alb * ao_from_height(hgt, 2.0, 2.0)[..., None]
    rough = np.clip(0.85 - wet * 0.7 - sealant * 0.3, 0.06, 1)
    save("asphalt", alb, hgt, rough, 5.0)


def painted_metal():
    """Light grey painted steel (tinted per object): subtle orange-peel, chipped edges, faint rust runs."""
    base = fnoise(S, S, 2.2, 71)
    peel = band(S, S, 0.15, 0.45, 78)
    chips = np.clip((band(S, S, 0.01, 0.06, 72) * 0.6 + band(S, S, 0.05, 0.25, 73) * 0.4 - 0.72) * 8, 0, 1)
    runs = np.clip((band(S, S, 0.006, 0.05, 74, aniso=(1.0, 0.05)) - 0.62) * 3, 0, 1) * 0.5
    paint = lerp(col(212, 212, 207), col(236, 236, 232), base * 0.7 + peel * 0.3)
    rust = lerp(col(120, 72, 44), col(168, 106, 66), band(S, S, 0.05, 0.3, 75))
    alb = lerp(paint, rust, chips * 0.8)
    alb = lerp(alb, col(180, 150, 124), runs * 0.4)
    scratches, _ = scatter_lines(S, S, 60, 26, 1, 76, color_var=0)
    alb = lerp(alb, col(185, 185, 185), scratches * 0.35)
    hgt = peel * 0.08 - chips * 0.3 + base * 0.05
    rough = 0.5 + chips * 0.35 + runs * 0.1 - peel * 0.05
    save("painted_metal", alb, hgt, rough, 2.5)


def rock():
    """Mountain granite: layered strata, sharp fracture planes, lichen and moss in the cracks."""
    base = fnoise(S, S, 1.9, 81)
    rid = warp(ridged(S, S, 2.1, 85), 60, 370)
    strata = np.sin(warp(np.tile(np.arange(S, dtype=np.float32)[:, None] * 0.045, (1, S)), 90, 372) * 1.0 + base * 3) * 0.5 + 0.5
    facets = np.floor(warp(fnoise(S, S, 2.4, 86), 40, 374) * 7) / 7.0              # terraced fracture planes
    _, edge, _ = voronoi(S, S, 16, 82)
    edge = warp(edge, 40, 376)
    cracks = np.clip(1 - edge / 2.5, 0, 1) * (band(S, S, 0.004, 0.03, 89) > 0.5)
    hgt = blur(base, 2.5) * 0.4 + blur(rid, 2.0) * 0.3 + facets * 0.3 + strata * 0.1 - cracks * 0.3 + band(S, S, 0.2, 0.5, 91) * 0.03
    speck = band(S, S, 0.3, 0.5, 83)
    alb = lerp(col(84, 82, 80), col(160, 156, 150), norm01(base * 0.35 + facets * 0.35 + rid * 0.15 + speck * 0.15))
    alb = lerp(alb, col(120, 104, 90), np.clip(strata - 0.7, 0, 1) * 0.6)          # iron-stained bands
    alb = alb * (0.9 + speck[..., None] * 0.18)
    ao = ao_from_height(hgt, 5.0, 2.5)
    lichen = np.clip((band(S, S, 0.006, 0.04, 87) - 0.62) * 5, 0, 1) * (1 - cracks)
    alb = lerp(alb, col(150, 152, 118), lichen * 0.45)
    moss = np.clip((band(S, S, 0.003, 0.02, 84) - 0.62) * 4, 0, 1) * np.clip(1.1 - ao, 0, 1) * 3
    alb = lerp(alb, col(62, 80, 38), np.clip(moss, 0, 1) * 0.8)
    hb = blur(hgt, 2.0)
    light = np.clip(1.0 + (np.roll(hb, 3, 0) - np.roll(hb, -3, 0)) * 3.0 + (np.roll(hb, 3, 1) - np.roll(hb, -3, 1)) * 1.5, 0.75, 1.2)
    zones = band(S, S, 0.0015, 0.008, 90)
    alb = alb * light[..., None] * (0.8 + zones[..., None] * 0.35)
    alb = hue_jitter(alb * ao[..., None], 0.08, 88)
    rough = np.clip(0.78 - speck * 0.08 + np.clip(moss, 0, 1) * 0.1, 0, 1)
    save("rock", alb, hgt, rough, 8.0)


def planks():
    """Weathered wooden boards: uneven widths, warped grain, knots, nail heads, grey sun-bleaching."""
    widths = [150, 118, 136, 124, 160, 140, 96]
    widths = [int(v * S / sum(widths)) for v in widths]
    widths[-1] += S - sum(widths)
    edges = np.cumsum([0] + widths)
    plank_id = np.zeros((S, S), np.int32)
    xs = np.arange(S)
    for i in range(len(widths)):
        plank_id[:, (xs >= edges[i]) & (xs < edges[i + 1])] = i
    grain = np.zeros((S, S), np.float32)
    for i in range(len(widths)):
        g = warp(band(S, S, 0.01, 0.2, 91 + i, aniso=(25.0, 1.0)), 5, 380 + i, (0.002, 0.01))
        grain = np.where(plank_id == i, g, grain)
    tone = (plank_id * 37 % 11) / 11.0
    pos_in = xs[None, :] - edges[plank_id]
    wid = np.array(widths)[plank_id]
    gap = np.clip(3.5 - np.minimum(pos_in, wid - pos_in), 0, 1)
    # butt joints across some boards
    joint = np.zeros((S, S), np.float32)
    for i in range(len(widths)):
        y = (i * 389 + 170) % S
        joint[max(0, y - 2):y + 2, edges[i]:edges[i + 1]] = 1.0
    knots_d, _, _ = voronoi(S, S, 16, 93)
    knot = np.clip(1 - knots_d / 10.0, 0, 1) ** 1.3
    weather = np.clip(band(S, S, 0.003, 0.02, 94) * 1.4 - 0.3, 0, 1)
    fresh = lerp(col(92, 64, 40), col(166, 124, 84), np.clip((grain - 0.5) * 1.8 + 0.5, 0, 1) * 0.7 + tone * 0.3)
    grey = lerp(col(92, 86, 78), col(150, 142, 130), np.clip((grain - 0.5) * 1.8 + 0.5, 0, 1))
    alb = lerp(fresh, grey, weather * 0.7)
    alb = lerp(alb, col(62, 42, 28), knot)
    # nail heads near each board end
    nails = np.zeros((S, S), np.float32)
    yy, xx = np.mgrid[0:S, 0:S]
    for i in range(len(widths)):
        for yn in ((i * 389 + 150) % S, (i * 389 + 190) % S):
            for xn in (edges[i] + widths[i] * 0.25, edges[i] + widths[i] * 0.75):
                d = np.hypot(yy - yn, xx - xn)
                nails = np.maximum(nails, np.clip(5 - d, 0, 1))
    alb = lerp(alb, col(60, 52, 46), nails * 0.9)
    dark = np.clip(gap + joint, 0, 1)
    alb = lerp(alb, col(22, 16, 12), dark)
    hgt = grain * 0.3 - dark * 0.9 - knot * 0.1 + nails * 0.15 + tone * 0.1
    alb = alb * ao_from_height(hgt, 3.0, 2.0)[..., None]
    rough = np.clip(0.72 + weather * 0.15 - nails * 0.3, 0, 1)
    save("planks", alb, hgt, rough, 5.0)


def camo():
    """Woodland camouflage printed on rip-stop fabric: four colour blobs, twill weave and grid threads."""
    s = 1024
    alb = np.zeros((s, s, 3), np.float32) + col(84, 86, 66)
    for i, c in enumerate([col(58, 64, 44), col(104, 92, 66), col(36, 38, 30)]):
        m = warp(band(s, s, 0.003, 0.016, 101 + i), 50, 390 + i) > (0.57 + i * 0.01)
        alb[m] = c
    alb = blur(alb, (0.8, 0.8, 0))                                                # soft printed edges
    yy, xx = np.mgrid[0:s, 0:s]
    twill = ((xx + yy) % 4 < 2).astype(np.float32)
    ripstop = (((xx % 24) < 2) | ((yy % 24) < 2)).astype(np.float32)
    fade = band(s, s, 0.002, 0.01, 106)
    alb = alb * (0.92 + twill[..., None] * 0.08) * (1 - ripstop[..., None] * 0.08)
    alb = lerp(alb, col(120, 118, 100), np.clip(fade - 0.6, 0, 1) * 0.6)          # faded / worn areas
    hgt = twill * 0.2 + ripstop * 0.4
    save("camo", alb, hgt, np.full((s, s), 0.92), 1.5)


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
    for i in range(56):
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
            g = r.uniform(0.7, 1.1) * (0.8 + 0.3 * tt)             # shaded near the twig, lighter toward the tip
            blue = r.uniform(0.9, 1.1)
            mx, my = nx + np.cos(ang) * L * 0.5, ny + np.sin(ang) * L * 0.5
            draw_line(ny, nx, my, mx, 1.3, col(30 * g, 56 * g, 34 * g * blue))
            draw_line(my, mx, ny + np.sin(ang) * L, nx + np.cos(ang) * L, 1.0, col(46 * g, 84 * g, 44 * g * blue))
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


def meadow():
    """Short airfield grass seen from above: dense blades in several greens, dry straw, clover, dirt patches."""
    soil_n = fnoise(S, S, 2.2, 201)
    soil = lerp(col(46, 44, 26), col(78, 70, 44), soil_n)
    patches = np.clip((warp(band(S, S, 0.002, 0.012, 202), 80, 500) - 0.62) * 4, 0, 1)   # worn bare dirt
    dry = np.clip((warp(band(S, S, 0.003, 0.02, 203), 60, 502) - 0.5) * 3, 0, 1)
    alb = soil.copy()
    hgt = soil_n * 0.2
    for layer, (count, c0, c1, seed, L) in enumerate([(26000, col(48, 68, 26), col(80, 106, 40), 204, 16),
                                                      (20000, col(70, 96, 36), col(114, 138, 58), 205, 13),
                                                      (6000, col(140, 128, 74), col(176, 160, 98), 206, 14)]):
        nh, nc = scatter_lines(S, S, count, L, 2, seed, angle_range=(1.2, 1.95))   # mostly upright-ish blades
        keep = (1 - patches * 0.9)
        if layer == 2:
            keep = keep * dry          # straw only in the dry zones
        nh = nh * keep
        ncol = lerp(c0, c1, nc)
        alb = alb * (1 - nh[..., None] * 0.92) + ncol * nh[..., None] * 0.92
        hgt = np.maximum(hgt, hgt * 0.5 + nh * (0.5 + layer * 0.1))
    # clover leaves
    f1, edge, cid = voronoi(S, S, 2500, 207)
    pick = ((cid * 2654435761) % 100) < 6
    clover = np.clip(edge / 4.0, 0, 1) * pick * (1 - patches)
    alb = lerp(alb, col(60, 96, 40), np.clip(clover * 3, 0, 1) * 0.8)
    hgt = hgt + np.clip(clover * 3, 0, 1) * 0.2
    ao = ao_from_height(hgt, 3.0, 2.5)
    alb = hue_jitter(alb * ao[..., None], 0.16, 208)
    rough = np.clip(0.86 - np.clip(clover * 3, 0, 1) * 0.2, 0, 1)
    save("meadow", alb, hgt, rough, 5.0)


def corrugated():
    """Galvanised corrugated sheet: vertical ribs, zinc sheen, rust bleeding from the fixings, grime."""
    yy, xx = np.mgrid[0:S, 0:S].astype(np.float32)
    ribs = np.sin(xx / S * np.pi * 2 * 16) * 0.5 + 0.5                      # 16 ribs per tile
    zinc = lerp(col(150, 156, 158), col(196, 200, 200), fnoise(S, S, 2.4, 211) * 0.6 + ribs * 0.4)
    spangle = voronoi(S, S, 1400, 212)[2]
    zinc = zinc * (0.93 + ((spangle * 7919 % 17) / 17.0)[..., None] * 0.1)
    streaks = band(S, S, 0.005, 0.06, 213, aniso=(1.0, 0.04))
    rust_zone = np.clip((warp(band(S, S, 0.002, 0.015, 214), 50, 510) - 0.52) * 3.5, 0, 1)
    rust = lerp(col(98, 52, 28), col(160, 92, 48), band(S, S, 0.05, 0.3, 215))
    run = np.clip((streaks - 0.55) * 3, 0, 1) * (0.4 + rust_zone * 0.6)
    alb = lerp(zinc, rust, np.clip(rust_zone * 0.55 + run * 0.6, 0, 1))
    grime = np.clip((band(S, S, 0.003, 0.03, 216, aniso=(1.0, 0.15)) - 0.5) * 2, 0, 1)
    alb = lerp(alb, col(70, 68, 62), grime * 0.35)
    # screw heads in rows (rust halo around each)
    holes = np.zeros((S, S), np.float32)
    for yrow in (S // 8, S // 2 + S // 8):
        for k in range(16):
            cx = int((k + 0.5) / 16 * S)
            holes[yrow - 3:yrow + 3, cx - 3:cx + 3] = 1.0
    halo = np.clip(blur(holes, 5) * 14, 0, 1)
    alb = lerp(alb, rust, halo * 0.45)
    alb = lerp(alb, col(40, 40, 40), holes)
    alb = hue_jitter(alb, 0.06, 217)
    hgt = ribs * 0.5 - holes * 0.2 + rust_zone * 0.05
    rough = np.clip(0.45 + rust_zone * 0.4 + grime * 0.1, 0, 1)
    save("corrugated", alb, hgt, rough, 3.0)


def runway():
    """Runway / apron asphalt: lighter, sun-bleached, rubber skid marks, patched squares, oil stains."""
    f1, edge, cid = voronoi(S, S, 26000, 221)
    agg = np.clip(edge / 2.0, 0, 1)
    dome = np.sqrt(np.clip(agg * (2 - agg), 0, 1)) * (((cid * 2654435761) % 100) < 55)
    shade = (cid * 7919 % 89) / 89.0
    binder = lerp(col(52, 52, 54), col(74, 74, 76), band(S, S, 0.05, 0.3, 222))
    stone = lerp(col(90, 88, 86), col(140, 136, 130), shade)
    alb = lerp(binder, stone, dome * 0.3)
    alb = alb * (0.85 + band(S, S, 0.002, 0.012, 223)[..., None] * 0.3)
    skid = np.clip((band(S, S, 0.003, 0.03, 224, aniso=(0.03, 1.0)) - 0.56) * 4, 0, 1)   # long rubber streaks
    alb = lerp(alb, col(22, 22, 23), skid * 0.6)
    oil = np.clip((warp(band(S, S, 0.004, 0.03, 225), 40, 520) - 0.72) * 5, 0, 1)
    alb = lerp(alb, col(28, 27, 26), oil * 0.7)
    patch = np.zeros((S, S), np.float32)
    patch[300:520, 610:880] = 1.0
    patch = blur(warp(patch, 6, 526), 3) * 0.6
    alb = lerp(alb, alb * 0.72, patch)
    hgt = dome * 0.5 - patch * 0.05
    alb = alb * ao_from_height(hgt, 2.0, 1.6)[..., None]
    rough = np.clip(0.82 - oil * 0.5 - skid * 0.1, 0.1, 1)
    save("runway", alb, hgt, rough, 4.0)


if __name__ == "__main__":
    import sys
    todo = sys.argv[1:] or ["forest_floor", "mud", "gravel", "bark", "log_side", "concrete", "asphalt", "painted_metal", "rock", "planks", "camo", "pine_card", "fern_card", "clouds", "meadow", "corrugated", "runway"]
    for name in todo:
        globals()[name]()

