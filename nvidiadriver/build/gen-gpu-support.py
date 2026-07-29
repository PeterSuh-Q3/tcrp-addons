#!/usr/bin/env python3
"""
gen-gpu-support.py - regenerate nvidiadriver/src/nvidia-gpu-support.json.

The old file was hand-maintained and held 7 PCI ids, so every other GPU fell
through to `default_branch` (535) - e.g. a Quadro P1000 (10de:1cb1, Pascal)
was told to install 535 even though Pascal is supported all the way up to 580.

NVIDIA publishes, per driver release, the exact device-id list that release
supports:

  https://download.nvidia.com/XFree86/Linux-x86_64/<ver>/README/supportedchips.html

That page has one "Current NVIDIA GPUs" table (what THIS release drives) plus
`legacy_<branch>` tables (what the older legacy branches drive - those rows are
NOT supported by the release you fetched, which is the trap the first version
of this parser fell into: GTX 650 appears in 580's page, but only inside the
`legacy_470.xx` table).

Fetching all four branches we ship and intersecting the "current" tables gives
per-GPU branch support as a fact instead of a guess.

Usage:
  ./gen-gpu-support.py > nvidiadriver/src/nvidia-gpu-support.json
Re-run whenever a driver branch in BRANCHES changes version.
"""
import html
import json
import re
import subprocess
import sys

# Branch -> exact driver version we publish (must match nvidia-index.json).
BRANCHES = {
    "470": "470.256.02",
    "535": "535.230.02",
    "550": "550.163.01",
    "580": "580.173.02",
}
# Newest-first preference order used to build each GPU's `branches` list.
PREF = ["580", "550", "535", "470"]

URL = "https://download.nvidia.com/XFree86/Linux-x86_64/{v}/README/supportedchips.html"

# Prose, carried through unchanged - the only hand-written part of the output.
BRANCH_NOTES = {
    "470": "Legacy LTSB. Kepler..Ampere (no Ada). The ONLY branch here that "
           "drives Kepler - 535 dropped it. Builds clean on kver5. NVENC/NVDEC "
           "present (H.264/HEVC); no AV1. ffmpeg layer is pinned to "
           "jellyfin-ffmpeg 5.1.2-9 (NVENC API 11.1) - never pair with the "
           "535/550 ffmpeg (API 12.x, will fail to load). Kepler GPUs: H.264 "
           "encode only, no HEVC encode (HEVC encode needs Maxwell 2nd-gen "
           "GM206+).",
    "535": "Production Branch. Maxwell..Ada. Verified on P620.",
    "550": "Maxwell..Ada. ffmpeg layer jellyfin-ffmpeg 7.0.2-9 (NVENC SDK 12.0, "
           "same pin as 535 - not 12.1). Superseded by 580, but still the "
           "recommended branch for Ada (RTX 40) because 580 has no GSP firmware "
           "for those chips yet.",
    "580": "Default on kver5. Last branch supporting Maxwell/Pascal/Volta (per "
           "NVIDIA), and the only one that knows Blackwell (RTX 50). Native CUDA "
           "13.0. Raises the usable CUDA ceiling on Pascal from 12.4 (550) to "
           "12.9 - CUDA 13.0 itself needs compute capability >= 7.5 (Turing), so "
           "Pascal/Maxwell/Volta stay at 12.9. Turing/Ampere(GA10x) REQUIRE GSP "
           "firmware, shipped as nv-gsp-580.173.02.tgz (gsp_tu10x.bin + "
           "gsp_ga10x.bin, extracted from the official .run) and auto-deployed by "
           "install.sh to /lib/firmware/nvidia/<ver>/. Ada(RTX 40), "
           "Blackwell(RTX 50) and GA100 also need GSP but that .run bundles no "
           "blob for them - those chips carry needs_gsp with no gsp_fw, which "
           "makes install.sh skip 580 as a recommendation and gate it behind a "
           "warning. ffmpeg layer: jellyfin-ffmpeg 7.1.4-3 (NVENC SDK 12.0, needs "
           "driver >= 530).",
}


def fetch(ver):
    # curl, not urllib: a stock python.org build has no CA bundle wired up and
    # dies with CERTIFICATE_VERIFY_FAILED, while curl uses the system trust store.
    out = subprocess.run(["curl", "-fsSL", URL.format(v=ver)],
                         capture_output=True, check=True).stdout
    return out.decode("utf-8", "replace")


def parse(page):
    """-> (current: {devid: name}, legacy: {devid: (branch, name)})"""
    # Everything before the first legacy anchor is the current-release table.
    anchors = [(m.start(), m.group(1))
               for m in re.finditer(r'<a name="legacy_([0-9.]+xx)"', page)]
    bounds = [(0, "current")] + anchors + [(len(page), None)]
    current, legacy = {}, {}
    for i in range(len(bounds) - 1):
        start, label = bounds[i]
        if label is None:
            break
        chunk = page[start:bounds[i + 1][0]]
        for devid, body in re.findall(
                r'<tr id="devid([0-9A-Fa-f]{4})"[^>]*>(.*?)</tr>', chunk, re.S | re.I):
            cells = [html.unescape(re.sub(r"<[^>]+>", "", c)).strip()
                     for c in re.findall(r"<td[^>]*>(.*?)</td>", body, re.S | re.I)]
            name = cells[0] if cells else ""
            devid = devid.lower()
            if label == "current":
                current.setdefault(devid, name)
            else:
                legacy.setdefault(devid, (label, name))
    return current, legacy


# --- architecture ------------------------------------------------------------
# Device-id ranges, Maxwell and newer. Older chips are classified by branch
# membership instead (a devid that only 470 still drives IS Kepler - that is
# exactly the cut 535 made), because the Fermi/Kepler id space is interleaved
# and not worth encoding by hand.
ARCH_RANGES = [
    (0x1340, 0x143F, "Maxwell"),   # GM107/GM108/GM204/GM206
    (0x1617, 0x161A, "Maxwell"),   # GM204M
    (0x1667, 0x1667, "Maxwell"),
    (0x174D, 0x179C, "Maxwell"),   # GM108M/GM204M
    (0x17C2, 0x17FF, "Maxwell"),   # GM200
    (0x15F0, 0x15FF, "Pascal"),    # GP100
    (0x1B00, 0x1D7F, "Pascal"),    # GP102/104/106/107/108
    (0x1D80, 0x1DFF, "Volta"),     # GV100
    (0x1E00, 0x1FFF, "Turing"),    # TU102/104/106/117
    (0x2080, 0x20FF, "Ampere"),    # GA100 (datacenter)
    (0x2182, 0x21FF, "Turing"),    # TU116/TU117
    (0x2200, 0x22FF, "Ampere"),    # GA102
    (0x2300, 0x237F, "Hopper"),    # GH100
    (0x2400, 0x25FF, "Ampere"),    # GA103/104/106/107
    (0x2600, 0x28FF, "Ada"),       # AD102/103/104/106/107
    (0x2900, 0x2FFF, "Blackwell"),  # GB1xx/GB2xx
]

# GSP firmware blob per architecture, for the 580 open kernel module. Only the
# blobs the 580.173.02 .run actually bundles are named here; an arch that needs
# GSP but has no entry keeps needs_gsp=true with no gsp_fw, which is install.sh's
# signal to warn instead of silently installing something that cannot initialise.
GSP_FW = {
    "Turing": "gsp_tu10x.bin",
    "Ampere": "gsp_ga10x.bin",
}
# Compute capability caps the CUDA toolkit, independent of driver branch.
CUDA_MAX = {
    "Kepler": "11.8", "Maxwell": "12.9", "Pascal": "12.9", "Volta": "12.9",
    "Turing": "13.0", "Ampere": "13.0", "Hopper": "13.0", "Ada": "13.0",
    "Blackwell": "13.0",
}


def arch_of(devid_hex, branches):
    n = int(devid_hex, 16)
    for lo, hi, name in ARCH_RANGES:
        if lo <= n <= hi:
            # GA100 has no display engine / no consumer GSP blob; keep it apart
            # from GA10x so it does not claim gsp_ga10x.bin.
            if name == "Ampere" and 0x2080 <= n <= 0x20FF:
                return "Ampere GA100"
            return name
    if branches == ["470"]:
        return "Kepler"
    return ""


def main():
    pages = {b: parse(fetch(v)) for b, v in BRANCHES.items()}
    current = {b: c for b, (c, _) in pages.items()}
    # Legacy tables are identical across releases; take the newest branch's.
    legacy = pages["580"][1]

    gpus = {}
    for b in PREF:
        for devid, name in current[b].items():
            gpus.setdefault(devid, {"name": name, "branches": []})
            gpus[devid]["branches"].append(b)
            # Newer releases carry the tidier "NVIDIA GeForce ..." spelling.
            if len(name) > len(gpus[devid]["name"]):
                gpus[devid]["name"] = name

    out = {}
    for devid, g in sorted(gpus.items()):
        arch = arch_of(devid, g["branches"])
        e = {"name": g["name"]}
        if arch:
            e["arch"] = arch
        e["branches"] = g["branches"]
        # 580 uses the open kernel module, which needs GSP firmware on every
        # chip with compute capability >= 7.5 (Turing and newer). Maxwell,
        # Pascal and Volta stay on the legacy path and need nothing.
        if "580" in g["branches"] and arch in (
                "Turing", "Ampere", "Ampere GA100", "Hopper", "Ada", "Blackwell"):
            e["needs_gsp"] = True
            fw = GSP_FW.get(arch)
            if fw:
                e["gsp_fw"] = fw
        cm = CUDA_MAX.get(arch.split()[0] if arch else "")
        if cm:
            e["cuda_max"] = cm
        out["10de:" + devid] = e

    # GPUs no legacy-aware branch of ours drives: record why, so install.sh can
    # say "needs the 390.xx legacy driver" instead of recommending a branch that
    # will load and then bind to nothing.
    for devid, (br, name) in sorted(legacy.items()):
        key = "10de:" + devid
        if key in out:
            continue
        out[key] = {"name": name, "branches": [], "legacy_driver": br}

    # Hand-curated install reports, merged over the generated rows.
    verified = {"10de:1cb6": ["535.230.02"]}
    build_ok = {"10de:1cb6": ["550.163.01"]}
    for k, v in verified.items():
        if k in out:
            out[k]["verified"] = v
    for k, v in build_ok.items():
        if k in out:
            out[k]["build_ok"] = v

    doc = {
        "_comment": (
            "GENERATED by tools/gen-gpu-support.py - do not hand-edit; re-run it "
            "when a driver branch changes version. Source of truth is NVIDIA's own "
            "per-release supportedchips.html, so 'branches' is the exact set of the "
            "branches we publish that actually drive this PCI id, newest-preferred "
            "first. 'legacy_driver' marks a GPU only an even older NVIDIA legacy "
            "branch drives - we build none of those, so it cannot be used here. "
            "'cuda_max' is the highest CUDA toolkit the chip's compute capability "
            "can target (driver-independent). 'needs_gsp' marks chips that require "
            "GSP firmware under 580's open kernel module; 'gsp_fw' names the blob "
            "(see nvidia-index.json's gsp_firmware layer). needs_gsp without gsp_fw "
            "= no firmware shipped for that chip yet, and install.sh gates on it."),
        "default_branch": "535",
        "default_branch_by_kernel": {
            "_comment": (
                "Fallback when the GPU is unknown or absent, keyed by the running "
                "kernel's major version. kver5 platforms publish 470/535/550/580 so "
                "the newest (580) is preferred; kver4 platforms publish only 550. "
                "install.sh intersects this with what nvidia-index.json actually has "
                "for the platform+kernel, so a stale entry cannot pick a missing "
                "driver."),
            "5": "580",
            "4": "550",
        },
        "branch_notes": BRANCH_NOTES,
        "gpus": out,
    }
    json.dump(doc, sys.stdout, indent=2, ensure_ascii=False)
    sys.stdout.write("\n")


if __name__ == "__main__":
    main()
