"""Builds SunriseApp/Resources/makeup-score.database.json (and Docs/SkorPlacementShade.html to read it): what every percentage 1-100 of the Placement and Shade scores
means, per tool (blush, brow, eyeliner), with the measurement behind it. Run: python3 Tools/Feedback/make_score_database.py

-Nimah. The thresholds are the same draft values as makeup-feedback.database.json; change them here and run again.
"""
import json
import os

OUT = os.path.join(os.path.dirname(__file__), "..", "..", "SunriseApp", "Resources", "makeup-score.database.json")

# Score of one metric from its deviation: 0 -> 100, ok -> 90, slight -> 75, clear -> 55, 2 x clear -> 20, 3 x clear -> 1.
# The bands of makeup-feedback.database.json map onto it: ok 90-100, slight 75-89, clear 55-74, large 1-54.
def curve(t):
    ok, slight, clear = t
    return [(0.0, 100.0), (ok, 90.0), (slight, 75.0), (clear, 55.0), (2 * clear, 20.0), (3 * clear, 1.0)]


def deviation_for(percent, t):
    """The deviation that alone gives `percent` (inverse of the curve)."""
    points = curve(t)
    for (d0, p0), (d1, p1) in zip(points, points[1:]):
        if p1 <= percent <= p0:
            return d0 + (p0 - percent) / (p0 - p1) * (d1 - d0)
    return points[-1][0]


def band(percent):
    return "ok" if percent >= 90 else "slight" if percent >= 75 else "clear" if percent >= 55 else "large"


# Ten tiers of wording, highest first: (lowest percent, Indonesian, English).
TIERS = [
    (100, "Sama persis", "Exactly the same"),
    (95, "Hampir sama persis", "Almost exactly the same"),
    (90, "Sangat dekat", "Very close"),
    (85, "Dekat", "Close"),
    (75, "Sedikit meleset", "Slightly off"),
    (65, "Meleset", "Off"),
    (55, "Cukup jauh", "Fairly far"),
    (40, "Jauh", "Far"),
    (20, "Sangat jauh", "Very far"),
    (1, "Belum sesuai", "Not there yet"),
]

ADVICE = {
    "ok": ("Tidak perlu diperbaiki.", "Nothing to fix."),
    "slight": ("Cukup dirapikan sedikit.", "A small touch fixes it."),
    "clear": ("Perlu diperbaiki di bagian yang ditandai.", "Fix the marked part."),
    "large": ("Sebaiknya dihapus dan diulang dari langkah pertama.", "Easier to remove and redo from the first step."),
}


def tier(percent):
    return next(t for t in TIERS if percent >= t[0])


def fmt(value, unit):
    """Text for a deviation, Indonesian (decimal comma) and English. One decimal, so every percentage reads differently."""
    v = f"{value:.1f}"
    return v.replace(".", ","), v


# Each metric: id, weight, thresholds (ok, slight, clear) as a deviation, unit, whether mm thresholds scale with IPD,
# where it comes from, and how one deviation reads in a sentence (id, en) with {v} = the value.
TOOLS = {
    "blush": {
        "placement": {
            "source": {
                "id": "Koordinat target dari Try On: pusat dan elips blush yang digambar engine di wajah (titik-titik mesh ARKit, milimeter) pada foto look impian. Hasil: pusat blush asli (ditimbang dengan kenaikan warna) di titik mesh yang sama pada foto hasil.",
                "en": "Target coordinates from Try On: the centre and ellipse of the blush the engine drew on the face (ARKit mesh points, millimetres) in the desired-look photo. Result: the real blush's centre (weighted by colour rise) at the same mesh points in the result photo.",
            },
            "metrics": [
                {"id": "offset_mm", "weight": 2, "thresholds": [3, 6, 10], "unit": "mm", "ipd": True,
                 "rules": ["blush.offset.too_high", "blush.offset.too_low", "blush.offset.too_far_in", "blush.offset.too_far_out"],
                 "id_text": "pusat blush bergeser sekitar {v} mm dari pusat target",
                 "en_text": "the blush centre is about {v} mm from the target centre"},
                {"id": "size_ratio", "weight": 1, "thresholds": [0.25, 0.5, 1.0], "unit": "ratio", "ipd": False,
                 "rules": ["blush.size.too_small", "blush.size.too_large"],
                 "id_text": "area blush {v}x lebih luas dari target, atau hanya {p}% dari luas target",
                 "en_text": "the blush area is {v}x larger than the target, or only {p}% of it"},
            ],
        },
        "shade": {
            "source": {
                "id": "Warna kulit polos dan warna blush virtual di titik mesh yang sama pada foto look impian, dibandingkan dengan warna di foto hasil (CIELAB, cahaya disamakan per pipi).",
                "en": "The bare skin colour and the virtual blush colour at the same mesh points in the desired-look photo, compared with the result photo (CIELAB, light matched per cheek).",
            },
            "metrics": [
                {"id": "hue_delta_deg", "weight": 1, "thresholds": [10, 20, 35], "unit": "deg", "ipd": False,
                 "rules": ["blush.hue.warmer", "blush.hue.cooler"],
                 "id_text": "warna berbeda sekitar {v}° dari shade pilihan (lebih oranye atau lebih pink)",
                 "en_text": "the colour is about {v}° from the chosen shade (more orange or more pink)"},
                {"id": "intensity_ratio", "weight": 1, "thresholds": [0.3, 0.6, 1.0], "unit": "ratio", "ipd": False,
                 "rules": ["blush.intensity.too_heavy", "blush.intensity.too_light"],
                 "id_text": "blush {v}x lebih pekat dari blush Try On, atau hanya {p}% sepekat itu",
                 "en_text": "the blush is {v}x stronger than the Try On blush, or only {p}% as strong"},
            ],
        },
    },
    "brow": {
        "placement": {
            "source": {
                "id": "Koordinat target dari Try On: bentuk alis yang digambar engine pada foto look impian, di titik-titik mesh ARKit (milimeter), diukur sepanjang garis alis: pangkal, puncak lengkung, ekor. Hasil: titik yang sama pada alis di foto hasil.",
                "en": "Target coordinates from Try On: the brow the engine drew in the desired-look photo, on ARKit mesh points (millimetres), measured along the brow line: head, arch peak, tail. Result: the same points of the brow in the result photo.",
            },
            "metrics": [
                {"id": "key_point_offset_mm", "weight": 2, "thresholds": [1.5, 3, 5], "unit": "mm", "ipd": True,
                 "rules": ["brow.head.*", "brow.tail.*", "brow.arch.too_inner", "brow.arch.too_outer"],
                 "id_text": "pangkal, puncak, atau ekor alis bergeser sekitar {v} mm dari target",
                 "en_text": "the head, peak or tail of the brow is about {v} mm from the target"},
                {"id": "arch_height_mm", "weight": 1, "thresholds": [1, 2, 3.5], "unit": "mm", "ipd": True,
                 "rules": ["brow.arch.too_high", "brow.arch.too_flat"],
                 "id_text": "tinggi lengkung berbeda sekitar {v} mm dari target",
                 "en_text": "the arch height differs by about {v} mm from the target"},
            ],
        },
        "shade": {
            "source": {
                "id": "Warna, kepekatan, dan ketebalan alis di foto hasil dibandingkan dengan alis virtual di foto look impian (titik mesh yang sama) dan shade alis yang dipilih di Try On.",
                "en": "Colour, darkness and thickness of the brow in the result photo against the virtual brow in the desired-look photo (same mesh points) and the brow shade chosen on Try On.",
            },
            "metrics": [
                {"id": "hue_delta_deg", "weight": 0.5, "thresholds": [12, 22, 35], "unit": "deg", "ipd": False,
                 "rules": ["brow.hue.warmer", "brow.hue.cooler"],
                 "id_text": "warna berbeda sekitar {v}° dari shade pilihan (lebih kemerahan atau lebih abu-abu)",
                 "en_text": "the colour is about {v}° from the chosen shade (redder or greyer)"},
                {"id": "darkness_ratio", "weight": 1, "thresholds": [0.25, 0.5, 1.0], "unit": "ratio", "ipd": False,
                 "rules": ["brow.darkness.too_dark", "brow.darkness.too_light"],
                 "id_text": "alis {v}x lebih gelap dari alis Try On, atau hanya {p}% segelap itu",
                 "en_text": "the brow is {v}x darker than the Try On brow, or only {p}% as dark"},
                {"id": "thickness_mm", "weight": 1, "thresholds": [0.8, 1.5, 2.5], "unit": "mm", "ipd": True,
                 "rules": ["brow.thickness.too_thick", "brow.thickness.too_thin"],
                 "id_text": "ketebalan berbeda sekitar {v} mm dari target",
                 "en_text": "the thickness differs by about {v} mm from the target"},
            ],
        },
    },
    "eyeliner": {
        "placement": {
            "source": {
                "id": "Koordinat target dari Try On: garis eyeliner yang digambar di foto look impian, di titik-titik mesh ARKit sekitar mata (milimeter), diukur sepanjang garis: titik mulai, ujung wing, sudut wing. Hasil: titik yang sama pada garis di foto hasil.",
                "en": "Target coordinates from Try On: the liner drawn in the desired-look photo, on ARKit mesh points around the eye (millimetres), measured along the line: start, wing tip, wing angle. Result: the same points of the line in the result photo.",
            },
            "metrics": [
                {"id": "key_point_offset_mm", "weight": 2, "thresholds": [1, 2, 3.5], "unit": "mm", "ipd": True,
                 "rules": ["eyeliner.start.*", "eyeliner.wing.too_short", "eyeliner.wing.too_long", "eyeliner.wing_tip.*"],
                 "id_text": "titik mulai atau ujung wing bergeser sekitar {v} mm dari target",
                 "en_text": "the start or the wing tip is about {v} mm from the target"},
                {"id": "wing_angle_deg", "weight": 1, "thresholds": [3, 6, 10], "unit": "deg", "ipd": False,
                 "rules": ["eyeliner.wing.too_steep", "eyeliner.wing.too_flat"], "not_for_looks": ["natural"],
                 "id_text": "sudut wing berbeda sekitar {v}° dari target",
                 "en_text": "the wing angle differs by about {v}° from the target"},
            ],
        },
        "shade": {
            "source": {
                "id": "Kepekatan dan ketebalan garis di foto hasil dibandingkan dengan garis virtual di foto look impian (titik mesh yang sama). Warna tidak diukur: alur saat ini hanya eyeliner hitam.",
                "en": "Darkness and thickness of the line in the result photo against the virtual line in the desired-look photo (same mesh points). Colour is not measured: the current flow only has black liner.",
            },
            "metrics": [
                {"id": "darkness_ratio", "weight": 1, "thresholds": [0.25, 0.5, 1.0], "unit": "ratio", "ipd": False,
                 "rules": ["eyeliner.darkness.too_light"],
                 "id_text": "garis hanya {p}% sepekat garis Try On",
                 "en_text": "the line is only {p}% as dark as the Try On line"},
                {"id": "thickness_mm", "weight": 1, "thresholds": [0.3, 0.6, 1.0], "unit": "mm", "ipd": True,
                 "rules": ["eyeliner.thickness.too_thick", "eyeliner.thickness.too_thin"],
                 "id_text": "ketebalan garis berbeda sekitar {v} mm dari target",
                 "en_text": "the line thickness differs by about {v} mm from the target"},
            ],
        },
    },
}

PART = {"blush": ("blush", "blush"), "brow": ("alis", "brows"), "eyeliner": ("eyeliner", "eyeliner")}
CATEGORY = {"placement": ("Posisi", "Placement"), "shade": ("Shade", "Shade")}


def describe(tool, category, metrics, percent):
    t = tier(percent)
    b = band(percent)
    equivalents = {}
    parts_id, parts_en = [], []
    for m in metrics:
        dev = deviation_for(percent, m["thresholds"])
        if m["unit"] == "ratio":
            times, share = 1 + dev, 100 / (1 + dev)
            equivalents[m["id"]] = {"times": round(times, 2), "or_percent_of_target": round(share, 1)}
            v_id, v_en = f"{times:.2f}".replace(".", ","), f"{times:.2f}"
            p_id, p_en = f"{share:.1f}".replace(".", ","), f"{share:.1f}"
        else:
            equivalents[m["id"]] = {m["unit"]: round(dev, 2)}
            v_id, v_en = fmt(dev, m["unit"])
            p_id = p_en = ""
        parts_id.append(m["id_text"].replace("{v}", v_id).replace("{p}", p_id))
        parts_en.append(m["en_text"].replace("{v}", v_en).replace("{p}", p_en))
    name_id, name_en = PART[tool]
    if percent == 100:
        desc_id = f"{CATEGORY[category][0]} {name_id} sama dengan look Try On; tidak ada selisih yang terukur."
        desc_en = f"The {name_en} {CATEGORY[category][1].lower()} matches the Try On look; no measurable difference."
    else:
        desc_id = f"{t[1]}. Setara dengan: " + "; atau ".join(parts_id) + f". {ADVICE[b][0]}"
        desc_en = f"{t[2]}. Equivalent to: " + "; or ".join(parts_en) + f". {ADVICE[b][1]}"
    return {"percent": percent, "band": b, "label": {"id": t[1], "en": t[2]},
            "description": {"id": desc_id, "en": desc_en}, "equivalent_single_difference": equivalents}


def main():
    db = {
        "meta": {
            "id": "dandan.makeup-score",
            "version": "0.1.0",
            "status": "draft: the curve and thresholds are starting values from makeup-feedback.database.json; calibrate with real before/after photos.",
            "purpose": {
                "id": "Arti setiap persentase 1-100 untuk skor Posisi (placement) dan Shade di layar feedback, per alat (blush, alis, eyeliner), beserta ukuran di baliknya.",
                "en": "What every percentage 1-100 of the Placement and Shade scores on the feedback screen means, per tool (blush, brow, eyeliner), with the measurement behind it.",
            },
            "generated_by": "Tools/Feedback/make_score_database.py (edit the thresholds there, then run it again)",
            "language_note": "Indonesian is formal, like the feedback messages in makeup-feedback.database.json.",
            "owner": "Nimah (feedback)",
        },
        "how_it_is_scored": {
            "metric_score": {
                "id": "Setiap ukuran (misalnya pergeseran dalam mm) diubah menjadi 1-100 dengan kurva yang sama: selisih 0 = 100, batas 'ok' = 90, batas 'slight' = 75, batas 'clear' = 55, 2x batas 'clear' = 20, 3x batas 'clear' atau lebih = 1; di antara titik-titik itu garis lurus.",
                "en": "Each measurement (e.g. an offset in mm) becomes 1-100 on one curve: no difference = 100, the 'ok' limit = 90, 'slight' = 75, 'clear' = 55, 2x 'clear' = 20, 3x 'clear' or more = 1; straight lines in between.",
            },
            "category_score": {
                "id": "Skor Posisi atau Shade = rata-rata berbobot skor ukuran-ukurannya (bobot di 'metrics'), dibulatkan ke persen terdekat, paling kecil 1.",
                "en": "The Placement or Shade score = the weighted mean of its measurements' scores (weights under 'metrics'), rounded to a whole percent, at least 1.",
            },
            "per_side": {
                "id": "Diukur per sisi (kiri dan kanan), lalu diambil rata-ratanya. Ukuran 'mm' dengan ipd = true dikalikan (jarak pupil / 63 mm).",
                "en": "Measured per side (left and right), then averaged. 'mm' measurements with ipd = true are multiplied by (pupil distance / 63 mm).",
            },
            "curve_points": "[(0, 100), (ok, 90), (slight, 75), (clear, 55), (2 x clear, 20), (3 x clear, 1)]",
            "bands": {"ok": "90-100", "slight": "75-89", "clear": "55-74", "large": "1-54"},
            "equivalent_note": {
                "id": "Setiap deskripsi menyebut selisih yang, kalau hanya selisih itu saja, memberi persentase tersebut. Beberapa selisih kecil sekaligus bisa memberi persentase yang sama.",
                "en": "Each description names the difference that, on its own, gives that percentage. Several smaller differences together can give the same percentage.",
            },
            "ratio_note": "For ratio metrics the deviation is max(r, 1/r) - 1: 1.30x heavier and 77% (1/1.30) as strong are the same deviation.",
        },
        "tools": {},
    }
    for tool, categories in TOOLS.items():
        db["tools"][tool] = {}
        for category, spec in categories.items():
            metrics = spec["metrics"]
            db["tools"][tool][category] = {
                "source": spec["source"],
                "metrics": [{k: v for k, v in m.items() if k not in ("id_text", "en_text")} | {
                    "thresholds": dict(zip(["ok", "slight", "clear"], m["thresholds"]))} for m in metrics],
                "percent": [describe(tool, category, metrics, p) for p in range(100, 0, -1)],
            }
    with open(OUT, "w") as f:
        json.dump(db, f, ensure_ascii=False, indent=2)
        f.write("\n")
    print("wrote", os.path.relpath(OUT), "entries:", sum(len(c["percent"]) for t in db["tools"].values() for c in t.values()))
    # A page to read it: the same data inlined into Docs/SkorPlacementShade.html (opens in any browser, no server).
    here = os.path.dirname(__file__)
    page = open(os.path.join(here, "score_page_template.html")).read()
    data = json.dumps(db, ensure_ascii=False, separators=(",", ":")).replace("</", "<\\/")
    html = os.path.join(here, "..", "..", "Docs", "SkorPlacementShade.html")
    with open(html, "w") as f:
        f.write(page.replace("__DATA__", data))
    print("wrote", os.path.relpath(html))


if __name__ == "__main__":
    main()
