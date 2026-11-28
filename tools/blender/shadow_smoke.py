"""Texture de fumée de l'ombre de la Mort (#98) : bouffée dense au cœur, bords effilochés en langues.

Blanche (la couleur vient de l'émetteur, Client.DeathView), l'alpha porte la forme. Graine fixe, rejouable :
    blender -b --factory-startup --python tools/blender/shadow_smoke.py -- <sortie.png> [taille] [aperçu.png]
Source versionnée : assets/textures/death/shadow_smoke.png (envoyée par Open Cloud, type Image, docs/assets.md).
"""

import sys

import bpy
import numpy as np

SEED = 98


def value_noise(size, cells, rng):
    """Cette méthode permet de tirer un bruit lisse et périodique de `cells` cases lorsque la texture est composée."""
    grid = rng.random((cells, cells))
    coords = np.arange(size) * cells / size
    i0 = np.floor(coords).astype(int) % cells
    i1 = (i0 + 1) % cells
    f = coords - np.floor(coords)
    f = f * f * (3 - 2 * f)
    top = grid[i0][:, i0] * (1 - f)[None, :] + grid[i0][:, i1] * f[None, :]
    bottom = grid[i1][:, i0] * (1 - f)[None, :] + grid[i1][:, i1] * f[None, :]
    return top * (1 - f)[:, None] + bottom * f[:, None]


def fbm(size, rng, octaves=5, base=4):
    """Cette méthode permet de sommer plusieurs octaves de bruit lorsque la texture a besoin de détail à toutes les
    échelles (valeur entre 0 et 1)."""
    total, amplitude, norm = np.zeros((size, size)), 1.0, 0.0
    for o in range(octaves):
        total += value_noise(size, base * 2**o, rng) * amplitude
        norm += amplitude
        amplitude *= 0.5
    return total / norm


def smoke(size):
    """Cette méthode permet de composer l'alpha et la teinte de la bouffée lorsque le script tourne : rayon déformé par
    un bruit (langues qui s'échappent), cœur plein, voile intérieur léger."""
    rng = np.random.default_rng(SEED)
    y, x = np.mgrid[0:size, 0:size]
    u = (x + 0.5) / size * 2 - 1
    v = (y + 0.5) / size * 2 - 1
    r = np.sqrt(u * u + v * v)
    angle = np.arctan2(v, u)
    warp = fbm(size, rng, octaves=5, base=3)
    # bord : lobes angulaires inégaux et doux (deux fréquences, phases tordues par le bruit), vaporeux, sans lames
    tongues = 0.5 + 0.25 * np.sin(3 * angle + 7 * warp + 1.3) + 0.25 * np.sin(7 * angle - 5 * warp)
    wisp = fbm(size, rng, octaves=6, base=6)
    edge = 0.62 + 0.12 * tongues ** 2 + 0.22 * (wisp - 0.5)
    alpha = np.clip((edge - r) / 0.4, 0, 1)
    alpha = alpha * alpha * (3 - 2 * alpha)
    detail = fbm(size, rng, octaves=4, base=8)
    alpha *= 0.85 + 0.15 * detail
    # bord du carré toujours vide : pas de coupure nette sur la particule
    border = np.clip((1 - np.maximum(np.abs(u), np.abs(v))) / 0.06, 0, 1)
    alpha *= border
    shade = 0.8 + 0.2 * detail
    return shade, alpha


def main():
    args = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    out = args[0] if args else "shadow_smoke.png"
    size = int(args[1]) if len(args) > 1 else 256
    shade, alpha = smoke(size)
    rgba = np.zeros((size, size, 4), dtype=np.float32)
    rgba[..., 0] = shade
    rgba[..., 1] = shade
    rgba[..., 2] = shade
    rgba[..., 3] = alpha
    image = bpy.data.images.new("shadow_smoke", size, size, alpha=True)
    image.alpha_mode = "STRAIGHT"
    image.pixels.foreach_set(rgba.ravel())
    image.filepath_raw = out
    image.file_format = "PNG"
    image.save()
    if len(args) > 2:
        # aperçu : la bouffée en noir bleuté sur le beige du salon, pour juger la forme à l'oeil
        bg = np.array([0.78, 0.72, 0.62])
        ink = np.array([0.035, 0.03, 0.05])
        view = np.ones((size, size, 4), dtype=np.float32)
        for c in range(3):
            view[..., c] = bg[c] * (1 - alpha) + ink[c] * shade * alpha
        preview = bpy.data.images.new("shadow_smoke_preview", size, size, alpha=True)
        preview.pixels.foreach_set(view.ravel())
        preview.filepath_raw = args[2]
        preview.file_format = "PNG"
        preview.save()
    print(f"shadow_smoke : {out} ({size} px), alpha moyen {alpha.mean():.3f}, cœur {alpha[size // 2, size // 2]:.2f}")


main()
