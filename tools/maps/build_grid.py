"""Convert the supplied, triangulated ASCII-USD museum into a 20 cm navigation grid.

Reads data only; never imports or executes Python supplied with the model.
Dependencies: numpy, Pillow. See docs/maps/README.md for the collision policy.
"""
from __future__ import annotations

import argparse
from collections import deque
import hashlib
import json
import math
from pathlib import Path
import re
import zipfile

import numpy as np
from PIL import Image, ImageDraw, ImageFont

CELL = 0.2
SUB = 4
LOW, HIGH = 0.02, 1.9
RADIUS = 0.3
ROOT = Path(__file__).resolve().parents[2]
LEGEND = {"0": "outside", "1": "walkable", "2": "geometry_obstacle",
          "3": "closed_or_staff_only", "4": "clearance_buffer", "5": "disconnected"}


def numbers(line, dtype=float):
    text = line.split("=", 1)[1].strip().strip("[]()").replace("(", "").replace(")", "")
    return np.fromstring(text, sep=",", dtype=dtype)


def read_meshes(path):
    """Strict reader for the subset emitted by the supplied mlib/usd.py writer."""
    with zipfile.ZipFile(path) as archive:
        names = [n for n in archive.namelist() if n.endswith(".usda")]
        if len(names) != 1:
            raise ValueError("Expected one ASCII USDA scene in the supplied USDZ")
        text = archive.read(names[0]).decode("utf-8")
    if not re.search(r"metersPerUnit\s*=\s*1\s", text) or 'upAxis = "Y"' not in text:
        raise ValueError("Expected metres and Y-up")
    if any(word in text for word in ("references =", "payload =", "timeSamples", "xformOp:transform")):
        raise ValueError("Unsupported USD composition/animation/matrix transform")
    stack, pending, meshes = [], None, []
    for line in text.splitlines():
        line = line.strip()
        definition = re.match(r'def (\w+) "([^"]+)"', line)
        if definition:
            pending = definition.groups()
        elif line == "{":
            if pending is None:
                raise ValueError("Unsupported USDA block")
            kind, name = pending
            stack.append(dict(kind=kind, name=name, path="/".join([n["name"] for n in stack] + [name]),
                              matrix=stack[-1]["matrix"].copy() if stack else np.eye(4)))
            pending = None
        elif line == "}":
            node = stack.pop()
            if node["kind"] == "Mesh":
                if not np.all(node["counts"] == 3):
                    raise ValueError("Only triangulated meshes are supported")
                points = node["points"]
                world = points @ node["matrix"][:3, :3].T + node["matrix"][:3, 3]
                triangles = node["indices"].reshape(-1, 3)
                if len(triangles) != len(node["counts"]) or triangles.max() >= len(points):
                    raise ValueError("Invalid triangle indices")
                meshes.append((node["path"], world, triangles))
        elif stack and "xformOp:" in line and "xformOpOrder" not in line:
            transform = np.eye(4)
            values = numbers(line)
            if "xformOp:translate" in line:
                transform[:3, 3] = values
            elif "xformOp:scale" in line:
                transform[:3, :3] = np.diag(values)
            elif "xformOp:rotateY" in line:
                angle = math.radians(values[0])
                c, s = math.cos(angle), math.sin(angle)
                transform[:3, :3] = [[c, 0, s], [0, 1, 0], [-s, 0, c]]
            else:
                raise ValueError("Unsupported transform: " + line)
            stack[-1]["matrix"] = stack[-1]["matrix"] @ transform
        elif stack and stack[-1]["kind"] == "Mesh":
            for prefix, key, dtype in (("point3f[] points", "points", float),
                                       ("int[] faceVertexIndices", "indices", int),
                                       ("int[] faceVertexCounts", "counts", int)):
                if line.startswith(prefix):
                    value = numbers(line, dtype)
                    stack[-1][key] = value.reshape(-1, 3) if key == "points" else value
    if stack or not meshes:
        raise ValueError("Incomplete scene")
    return meshes


def clip_height(polygon, height, above):
    result = []
    for previous, current in zip(polygon[-1:] + polygon[:-1], polygon):
        pin = previous[1] >= height if above else previous[1] <= height
        cin = current[1] >= height if above else current[1] <= height
        if pin != cin:
            t = (height - previous[1]) / (current[1] - previous[1])
            result.append(previous + t * (current - previous))
        if cin:
            result.append(current)
    return result


def inside(xx, yy, polygon):
    result = np.zeros(np.broadcast_shapes(xx.shape, yy.shape), dtype=bool)
    for (ax, ay), (bx, by) in zip(polygon, polygon[1:] + polygon[:1]):
        if ay != by:
            result ^= ((ay > yy) != (by > yy)) & (xx < (bx - ax) * (yy - ay) / (by - ay) + ax)
    return result


def components(walkable):
    labels = np.zeros(walkable.shape, dtype=np.int32)
    sizes = []
    height, width = walkable.shape
    for start_r, start_c in zip(*np.where(walkable)):
        if labels[start_r, start_c]:
            continue
        label = len(sizes) + 1
        queue = deque([(int(start_r), int(start_c))])
        labels[start_r, start_c] = label
        size = 0
        while queue:
            r, c = queue.popleft()
            size += 1
            for nr, nc in ((r - 1, c), (r + 1, c), (r, c - 1), (r, c + 1)):
                if 0 <= nr < height and 0 <= nc < width and walkable[nr, nc] and not labels[nr, nc]:
                    labels[nr, nc] = label
                    queue.append((nr, nc))
        sizes.append(size)
    return labels, sizes


def dilate(mask, radius):
    # Cells are area obstacles. Account for up to one full cell diagonal between
    # occupied and candidate cell centres, then add the pedestrian radius.
    distance = radius + CELL * math.sqrt(2)
    steps = math.ceil(distance / CELL)
    height, width = mask.shape
    padded = np.pad(mask, steps, constant_values=True)
    result = np.zeros_like(mask)
    for dr in range(-steps, steps + 1):
        for dc in range(-steps, steps + 1):
            if math.hypot(dr, dc) * CELL <= distance + 1e-9:
                result |= padded[steps + dr:steps + dr + height, steps + dc:steps + dc + width]
    return result


def build(source, output, artifacts):
    info_path = source / "FieldMuseum_MainLevel_info.json"
    model_path = source / "FieldMuseum_MainLevel.usdz"
    info = json.loads(info_path.read_text(encoding="utf-8"))
    meshes = read_meshes(model_path)
    floor = [m for m in meshes if "/Architecture/Floor/" in m[0]]
    if not floor:
        raise ValueError("No architecture floor mesh")
    floor_points = np.concatenate([p[:, [0, 2]] for _, p, _ in floor])
    origin = np.floor((floor_points.min(axis=0) - 1) / CELL) * CELL
    end = np.ceil((floor_points.max(axis=0) + 1) / CELL) * CELL
    width, height = np.rint((end - origin) / CELL).astype(int)
    scale = SUB / CELL
    size = (width * SUB, height * SUB)
    floor_image = Image.new("1", size)
    obstacle_image = Image.new("1", size)
    floor_draw, obstacle_draw = ImageDraw.Draw(floor_image), ImageDraw.Draw(obstacle_image)

    def paint(draw, points):
        projected = (np.asarray(points)[:, [0, 2]] - origin) * scale
        coords = [tuple(p) for p in projected]
        if len(coords) >= 3:
            draw.polygon(coords, fill=1)
        elif len(coords) == 2:
            draw.line(coords, fill=1, width=1)

    audit = []
    for path, points, indices in meshes:
        triangles = points[indices]
        is_floor = "/Architecture/Floor/" in path or "/Rooms/" in path
        if is_floor:
            if "/Architecture/Floor/" in path:
                for triangle in triangles:
                    paint(floor_draw, triangle)
            continue
        intersecting = triangles[(triangles[:, :, 1].max(axis=1) >= LOW)
                                 & (triangles[:, :, 1].min(axis=1) <= HIGH)]
        for triangle in intersecting:
            polygon = clip_height(list(triangle), LOW, True)
            if polygon:
                polygon = clip_height(polygon, HIGH, False)
            if polygon:
                paint(obstacle_draw, polygon)
        audit.append({"path": path, "triangles": len(indices), "collisionTriangles": len(intersecting)})
    print(f"Read {len(meshes)} meshes; rasterized {sum(m['collisionTriangles'] for m in audit)} collision triangles", flush=True)

    def downsample(image, all_pixels=False):
        array = np.asarray(image, dtype=bool).reshape(height, SUB, width, SUB)
        return array.all(axis=(1, 3)) if all_pixels else array.any(axis=(1, 3))

    floor_mask = downsample(floor_image, True)
    obstacles = downsample(obstacle_image)
    restricted_image = Image.new("1", size)
    draw = ImageDraw.Draw(restricted_image)
    for room in info["rooms"]:
        if room["status"] != "open":
            draw.polygon([tuple((np.asarray(p) - origin) * scale) for p in room["outline"]], fill=1)
    restricted = downsample(restricted_image)
    cells = np.zeros((height, width), dtype=np.uint8)
    cells[floor_mask] = 1
    cells[floor_mask & restricted] = 3
    cells[floor_mask & obstacles] = 2
    cells[(cells == 1) & dilate(cells != 1, RADIUS)] = 4
    labels, sizes = components(cells == 1)
    if not sizes:
        raise ValueError("No walkable space remains")
    primary = int(np.argmax(sizes)) + 1
    cells[(cells == 1) & (labels != primary)] = 5
    yy, xx = np.meshgrid(origin[1] + (np.arange(height) + .5) * CELL,
                         origin[0] + (np.arange(width) + .5) * CELL, indexing="ij")
    room_ids = np.full(cells.shape, -1, dtype=int)
    # Preserve the source's smallest-containing-room convention for overlaps.
    for index in sorted(range(len(info["rooms"])), key=lambda i: info["rooms"][i]["area_m2"], reverse=True):
        room_ids[inside(xx, yy, info["rooms"][index]["outline"])] = index

    def cell_at(x, y):
        c, r = np.floor((np.array([x, y]) - origin) / CELL).astype(int)
        return int(c), int(r)

    def room_at(x, y):
        c, r = cell_at(x, y)
        return int(room_ids[r, c]) if 0 <= c < width and 0 <= r < height else -1

    def target(x, y, max_distance):
        room_id = room_at(x, y)
        if room_id >= 0 and info["rooms"][room_id]["status"] != "open":
            return None, "closed_or_staff_only"
        candidates = (cells == 1) & (room_ids == room_id)
        distances = np.where(candidates, (xx - x) ** 2 + (yy - y) ** 2, np.inf)
        r, c = np.unravel_index(np.argmin(distances), distances.shape)
        distance = math.sqrt(float(distances[r, c]))
        if distance > max_distance:
            return None, "no_reachable_approach_within_limit"
        return {"column": int(c), "row": int(r), "x": round(float(xx[r, c]), 3),
                "y": round(float(yy[r, c]), 3), "distanceToAnchorM": round(distance, 3)}, None

    pois = []
    for poi in info["points_of_interest"]:
        x, _, y = poi["position"]
        approach, reason = target(x, y, 6.0)
        pois.append({"id": poi["node"], "sourceId": poi["id"], "kind": poi["kind"], "name": poi["label"],
                     "position": {"x": x, "y": y}, "approach": approach, "unavailableReason": reason})
    start, reason = target(-0.6, 52.0, 3.0)
    if start is None:
        raise ValueError("Source walk-view start is unreachable: " + str(reason))
    metadata = {
        "schemaVersion": 1, "id": "field-museum-main-level", "name": "Field Museum — Main Level",
        "units": "metres", "cellSizeM": CELL, "width": int(width), "height": int(height),
        "origin": {"x": round(float(origin[0]), 3), "y": round(float(origin[1]), 3)},
        "coordinates": {"xAxis": "model +X (approximately east)", "yAxis": "model +Z (approximately south)",
                        "modelToMap": {"x": "X", "y": "Z"}, "rowDirection": "increasing y",
                        "worldOrigin": "same as model; building centre", "gridOrigin": "minimum corner of cell [0,0]",
                        "worldToCell": "column=floor((x-origin.x)/cellSizeM); row=floor((y-origin.y)/cellSizeM)",
                        "cellToWorld": "x=origin.x+(column+0.5)*cellSizeM; y=origin.y+(row+0.5)*cellSizeM",
                        "bounds": "minimum inclusive, maximum exclusive; reject out-of-range indices"},
        "encoding": "rows of single-character cell codes; cells[row][column]", "legend": LEGEND,
        "navigation": {"walkableCode": "1", "neighbors": 4, "stepCostM": CELL,
                       "diagonalMoves": False, "pedestrianRadiusM": RADIUS,
                       "collisionHeightM": [LOW, HIGH], "rasterSubcellM": CELL / SUB,
                       "clearancePolicy": "conservative cell dilation: radius + full cell diagonal",
                       "componentPolicy": "largest connected component only; other free cells code 5",
                       "mapAlignmentRequired": True, "start": start},
        "source": {"model": model_path.name, "modelSha256": hashlib.sha256(model_path.read_bytes()).hexdigest(),
                   "info": info_path.name, "infoSha256": hashlib.sha256(info_path.read_bytes()).hexdigest(),
                   "credit": "Floor-plan data © 2020 Field Museum of Natural History, CC BY 4.0",
                   "url": "https://github.com/arcataroger/openlayers_indoor_map",
                   "limitation": "Procedural reconstruction; walls, doors and furniture approximate reality."},
        "rooms": [{"id": r["node"], "name": r["name"], "status": r["status"], "outline": r["outline"]}
                  for r in info["rooms"]],
        "doors": [{"id": f"door_{i+1}", "position": {"x": d["center"][0], "y": d["center"][2]},
                   "widthM": d["width"], "sourceConnects": d["connects"]} for i, d in enumerate(info["doors"])],
        "pointsOfInterest": pois,
        "cells": ["".join(map(str, row)) for row in cells.tolist()]
    }
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(metadata, ensure_ascii=False, indent=2), encoding="utf-8")
    artifacts.mkdir(parents=True, exist_ok=True)
    report = {"grid": [int(width), int(height)], "cellCount": int(cells.size),
              "counts": {LEGEND[str(k)]: int((cells == k).sum()) for k in range(6)},
              "connectedComponentSizes": sorted(sizes, reverse=True), "meshCount": len(meshes),
              "triangleCount": sum(len(t) for _, _, t in meshes),
              "reachablePois": sum(p["approach"] is not None for p in pois), "totalPois": len(pois),
              "unavailablePois": [{"id": p["id"], "reason": p["unavailableReason"]} for p in pois if p["approach"] is None],
              "meshAudit": audit}
    (artifacts / "generation-report.json").write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    render_preview(cells, metadata, artifacts / "field-museum-grid.png")
    print(json.dumps({k: v for k, v in report.items() if k not in ("meshAudit", "connectedComponentSizes")}, ensure_ascii=True), flush=True)
    return metadata


def render_preview(cells, metadata, path):
    palette = np.array([[233, 238, 244], [242, 249, 241], [37, 50, 64],
                        [186, 191, 202], [218, 227, 212], [235, 194, 153]], dtype=np.uint8)
    floor = Image.fromarray(palette[cells]).resize((cells.shape[1] * 2, cells.shape[0] * 2), Image.Resampling.NEAREST)
    image = Image.new("RGB", (floor.width + 120, floor.height + 230), "white")
    image.paste(floor, (60, 100))
    draw = ImageDraw.Draw(image)
    font_path = "C:/Windows/Fonts/arial.ttf"
    font = ImageFont.truetype(font_path, 22) if Path(font_path).exists() else ImageFont.load_default()
    small = ImageFont.truetype(font_path, 16) if Path(font_path).exists() else font
    draw.text((60, 25), "FIELD MUSEUM  /  MAIN LEVEL  /  NAVIGATION GRID", font=font, fill="#253240")
    draw.text((60, 58), f"Cell 0.20 m | {metadata['width']} x {metadata['height']} | X = model X, Y = model Z | North up", font=small, fill="#536478")
    for i, poi in enumerate(metadata["pointsOfInterest"], 1):
        p = poi["approach"]
        if p is None:
            continue
        x, y = 60 + (p["column"] + .5) * 2, 100 + (p["row"] + .5) * 2
        draw.ellipse((x-7, y-7, x+7, y+7), fill="#167c92", outline="white", width=2)
        draw.text((x+8, y-15), str(i), font=small, fill="#14596b")
    start = metadata["navigation"]["start"]
    x, y = 60 + (start["column"]+.5)*2, 100 + (start["row"]+.5)*2
    draw.ellipse((x-8, y-8, x+8, y+8), fill="#d44b4b", outline="white", width=2)
    draw.text((x+12, y+3), "START", font=small, fill="#b93030")
    for index, (code, label) in enumerate(LEGEND.items()):
        x, y = 60 + (index % 3)*420, floor.height + 125 + (index//3)*30
        draw.rectangle((x, y, x+18, y+18), fill=tuple(palette[int(code)]), outline="#80909e")
        draw.text((x+26, y), f"{code}: {label}", font=small, fill="#253240")
    draw.text((60, image.height-35), "Derived from supplied procedural model. Plan data: Field Museum, CC BY 4.0. Not a surveyed navigation plan.", font=small, fill="#536478")
    image.save(path)


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", type=Path, default=ROOT / "map-work/resources")
    parser.add_argument("--output", type=Path, default=ROOT / "backend/java-backend/src/main/resources/maps/field-museum-main-level.grid.json")
    parser.add_argument("--artifacts", type=Path, default=ROOT / "docs/maps")
    args = parser.parse_args()
    build(args.source, args.output, args.artifacts)
