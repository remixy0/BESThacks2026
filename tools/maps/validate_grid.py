"""Validate the exported JSON independently and compute reference four-way routes."""
from collections import deque
import json
import math
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[2]
MAP = ROOT / "backend/java-backend/src/main/resources/maps/field-museum-main-level.grid.json"
OUT = ROOT / "docs/maps"


def validate():
    data = json.loads(MAP.read_text(encoding="utf-8"))
    w, h, step = data["width"], data["height"], data["cellSizeM"]
    ox, oy = data["origin"]["x"], data["origin"]["y"]
    assert step == 0.2 and len(data["cells"]) == h
    assert all(len(row) == w and set(row) <= set(data["legend"]) for row in data["cells"])
    assert len({p["id"] for p in data["pointsOfInterest"]}) == len(data["pointsOfInterest"])
    assert len({r["id"] for r in data["rooms"]}) == len(data["rooms"])
    cells = np.array([list(row) for row in data["cells"]])
    walkable = cells == "1"
    distances = np.full((h, w), -1, dtype=np.int32)
    parent = np.full((h, w), -1, dtype=np.int8)
    start = data["navigation"]["start"]
    sr, sc = start["row"], start["column"]
    assert walkable[sr, sc]
    queue = deque([(sr, sc)])
    distances[sr, sc] = 0
    directions = ((-1, 0), (1, 0), (0, -1), (0, 1))
    while queue:
        r, c = queue.popleft()
        for direction, (dr, dc) in enumerate(directions):
            nr, nc = r + dr, c + dc
            if 0 <= nr < h and 0 <= nc < w and walkable[nr, nc] and distances[nr, nc] < 0:
                distances[nr, nc] = distances[r, c] + 1
                parent[nr, nc] = direction
                queue.append((nr, nc))
    assert np.array_equal(distances >= 0, walkable), "Disconnected cells marked walkable"

    def world(r, c):
        return {"x": round(ox + (c+.5)*step, 3), "y": round(oy + (r+.5)*step, 3)}

    for r in range(h):
        for c in (0, w//2, w-1):
            p = world(r, c)
            assert math.floor((p["x"]-ox)/step) == c
            assert math.floor((p["y"]-oy)/step) == r

    results, example = [], None
    for poi in data["pointsOfInterest"]:
        goal = poi["approach"]
        if goal is None:
            assert poi["unavailableReason"]
            continue
        r, c = goal["row"], goal["column"]
        assert distances[r, c] >= 0
        assert world(r, c) == {"x": goal["x"], "y": goal["y"]}
        path = [(r, c)]
        while (r, c) != (sr, sc):
            dr, dc = directions[parent[r, c]]
            r, c = r-dr, c-dc
            path.append((r, c))
        path.reverse()
        assert all(walkable[r, c] for r, c in path)
        assert all(abs(a[0]-b[0])+abs(a[1]-b[1]) == 1 for a, b in zip(path, path[1:]))
        length = round((len(path)-1)*step, 3)
        results.append({"poiId": poi["id"], "lengthM": length, "steps": len(path)-1})
        if poi["sourceId"] == "tsavo_lions":
            example = {"mapId": data["id"], "purpose": "validation example, not a live API response",
                       "targetPoiId": poi["id"], "lengthM": length,
                       "points": [world(r, c) for r, c in path]}
    assert example is not None
    (OUT / "example-route.json").write_text(json.dumps(example, indent=2), encoding="utf-8")
    summary = {"passed": True, "allWalkableCellsConnected": True,
               "coordinateRoundTrips": h*3, "verifiedRoutes": results,
               "reachablePoiCount": len(results), "unavailablePoiCount": len(data["pointsOfInterest"])-len(results)}
    (OUT / "validation-report.json").write_text(json.dumps(summary, indent=2), encoding="utf-8")

    image = Image.open(OUT / "field-museum-grid.png").convert("RGB")
    draw = ImageDraw.Draw(image)
    points = [(60 + (p["x"]-ox)/step*2, 100 + (p["y"]-oy)/step*2) for p in example["points"]]
    draw.line(points, fill="#e55d3a", width=4)
    image.save(OUT / "field-museum-route-preview.png")

    # A magnified section exposes individual 20 cm squares instead of a solid overview.
    c0, c1 = [math.floor((x-ox)/step) for x in (-15, 15)]
    r0, r1 = [math.floor((y-oy)/step) for y in (-9, 10)]
    section = Image.open(OUT / "field-museum-grid.png").crop((60+c0*2, 100+r0*2, 60+c1*2, 100+r1*2))
    section = section.resize(((c1-c0)*8, (r1-r0)*8), Image.Resampling.NEAREST)
    detail = Image.new("RGB", (section.width+80, section.height+100), "white")
    detail.paste(section, (40, 60))
    draw = ImageDraw.Draw(detail)
    for c in range(c1-c0+1):
        x = 40+c*8
        draw.line((x, 60, x, 60+section.height), fill="#b7c6bb", width=1)
    for r in range(r1-r0+1):
        y = 60+r*8
        draw.line((40, y, 40+section.width, y), fill="#b7c6bb", width=1)
    font_path = Path("C:/Windows/Fonts/arial.ttf")
    font = ImageFont.truetype(str(font_path), 20) if font_path.exists() else ImageFont.load_default()
    draw.text((40, 20), "DETAIL: EVERY SQUARE = 20 x 20 cm  |  Central hall / elephants", fill="#253240", font=font)
    detail.save(OUT / "field-museum-grid-detail.png")
    print(json.dumps(summary))


if __name__ == "__main__":
    validate()
