"""Télécharge les matières CC0 (Poly Haven) utilisées comme base des textures cuites (#79).

Sans Blender : python -I tools/blender/fetch_cc0.py [--force]   (depuis la racine du dépôt)
Écrit assets/textures/cc0/<id>/<id>_<carte>_1k.jpg (Git LFS) et assets/textures/cc0/sources.json (auteurs, licence,
adresse), relu par docs/assets.md. Idempotent : un fichier déjà présent n'est pas retéléchargé (--force pour forcer).
"""

import json
import os
import sys
import urllib.request

# matière -> usage ; toutes CC0 (https://polyhaven.com/license)
MATERIALS = {
    "rough_linen": "tissu (cape, capuche, manche)",
    "brown_leather": "cuir (poignée)",
    "rusty_metal_02": "métal (lame, tête, bagues)",
    "dark_wood": "bois (manche)",
}
# cartes Poly Haven -> suffixe de fichier
MAPS = {"Diffuse": "diff", "nor_gl": "nor_gl", "Rough": "rough", "Displacement": "disp"}
RES = "1k"
OUT = os.path.join("assets", "textures", "cc0")
API = "https://api.polyhaven.com"
HEADERS = {"User-Agent": "dth-asset-fetch/1.0"}


def get_json(url):
    """Cette méthode permet de lire une réponse JSON de l'API Poly Haven."""
    with urllib.request.urlopen(urllib.request.Request(url, headers=HEADERS), timeout=30) as r:
        return json.load(r)


def download(url, path):
    """Cette méthode permet d'écrire un fichier distant lorsqu'il manque : fichier temporaire renommé une fois complet
    (taille annoncée vérifiée), donc jamais de fichier tronqué pris pour bon."""
    with urllib.request.urlopen(urllib.request.Request(url, headers=HEADERS), timeout=60) as r:
        expected = int(r.headers.get("Content-Length") or 0)
        data = r.read()
    if expected and len(data) != expected:
        raise IOError(f"{url} : {len(data)} octets reçus sur {expected}")
    with open(path + ".part", "wb") as f:
        f.write(data)
    os.replace(path + ".part", path)
    return len(data)


def present(path):
    """Cette méthode permet de savoir si une carte est déjà là et lisible (pas un pointeur Git LFS ni un JPEG vide)."""
    if not os.path.isfile(path) or os.path.getsize(path) < 1024:
        return False
    with open(path, "rb") as f:
        return f.read(2) == b"\xff\xd8"


def main():
    """Cette méthode permet de télécharger chaque matière et de noter sa provenance dans sources.json."""
    if not os.path.isfile("default.project.json"):
        sys.exit("à lancer depuis la racine du dépôt")
    force = "--force" in sys.argv
    sources = {}
    for asset, usage in MATERIALS.items():
        info = get_json(f"{API}/info/{asset}")
        files = get_json(f"{API}/files/{asset}")
        folder = os.path.join(OUT, asset)
        os.makedirs(folder, exist_ok=True)
        maps = {}
        for key, suffix in MAPS.items():
            entry = files.get(key, {}).get(RES, {}).get("jpg")
            if not entry:
                continue
            name = f"{asset}_{suffix}_{RES}.jpg"
            path = os.path.join(folder, name)
            if force or not present(path):
                size = download(entry["url"], path)
                print(f"{path} ({size} octets)")
            maps[suffix] = name
        sources[asset] = {
            "name": info.get("name", asset),
            "usage": usage,
            "authors": sorted(info.get("authors", {})),
            "license": "CC0 1.0",
            "url": f"https://polyhaven.com/a/{asset}",
            "maps": maps,
        }
    with open(os.path.join(OUT, "sources.json"), "w", encoding="utf-8", newline="\n") as f:
        json.dump(sources, f, ensure_ascii=False, indent=2)
        f.write("\n")
    print(f"{len(sources)} matière(s) dans {OUT}")


if __name__ == "__main__":
    main()
