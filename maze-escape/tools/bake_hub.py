#!/usr/bin/env python3
"""Bake the default hub into assets/Hub/Generated for Rojo (visible in Studio without Play)."""

from __future__ import annotations

import json
import math
import shutil
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "assets" / "Hub" / "Generated"

HUB_CENTER = (0, 0, 0)
HUB_SIZE = 160
HUB_SPAWN_OFFSET = (0, 6, -50)
HUB_PAD_SPACING = 22
WORLD_COUNT = 7

WORLDS = {
    1: (180, 140, 100),
    2: (34, 100, 34),
    3: (120, 200, 255),
    4: (220, 60, 20),
    5: (30, 20, 50),
    6: (0, 180, 200),
    7: (120, 0, 180),
}


def cf(x: float, y: float, z: float) -> list[float]:
    return [x, y, z, 1, 0, 0, 0, 1, 0, 0, 0, 1]


def color3uint8(r: int, g: int, b: int) -> dict:
    # Rojo 7 requires explicit format for Color3uint8
    return {"Color3uint8": [r, g, b]}


def color3(r: int, g: int, b: int) -> dict:
    return {"Color3": [r / 255, g / 255, b / 255]}


def write_meta(folder: Path, data: dict) -> None:
    folder.mkdir(parents=True, exist_ok=True)
    (folder / "init.meta.json").write_text(
        json.dumps(data, indent=2) + "\n", encoding="utf-8"
    )


def part(
    name: str,
    size: tuple[float, float, float],
    position: tuple[float, float, float],
    color: tuple[int, int, int],
    material: str = "SmoothPlastic",
    *,
    transparency: float | None = None,
    can_collide: bool = True,
) -> dict:
    props: dict = {
        "Name": name,
        "Anchored": True,
        "Size": list(size),
        "CFrame": cf(*position),
        "Color3uint8": color3uint8(*color),
        "Material": material,
        "CanCollide": can_collide,
        "TopSurface": "Smooth",
        "BottomSurface": "Smooth",
    }
    if transparency is not None:
        props["Transparency"] = transparency
    return {"className": "Part", "properties": props}


def spawn_location(position: tuple[float, float, float]) -> dict:
    return {
        "className": "SpawnLocation",
        "properties": {
            "Name": "HubSpawn",
            "Anchored": True,
            "Size": [14, 1, 14],
            "CFrame": cf(*position),
            "Color3uint8": color3uint8(80, 160, 255),
            "Material": "Neon",
            "Neutral": True,
            "Duration": 0,
            "TopSurface": "Smooth",
            "BottomSurface": "Smooth",
        },
    }


def int_value(value: int) -> dict:
    return {"className": "IntValue", "properties": {"Name": "WorldId", "Value": value}}


def point_light(brightness: float, range_: float, color: tuple[int, int, int]) -> dict:
    return {
        "className": "PointLight",
        "properties": {
            "Brightness": brightness,
            "Range": range_,
            "Color": color3(*color),
        },
    }


def bake() -> None:
    if OUT.exists():
        shutil.rmtree(OUT)
    OUT.mkdir(parents=True)

    cx, cy, cz = HUB_CENTER
    hub_size = HUB_SIZE
    half = hub_size / 2
    wall_h = 32
    wall_t = 5
    wall_y = cy + wall_h / 2 + 1
    wall_color = (32, 35, 52)
    trim_color = (70, 85, 130)

    write_meta(OUT, {"className": "Folder", "properties": {"Name": "Generated"}})

    parts = [
        part("HubPlatform", (hub_size, 4, hub_size), (cx, cy, cz), (45, 48, 70)),
        part(
            "HubBorder",
            (hub_size + 8, 6, hub_size + 8),
            (cx, cy - 1, cz),
            (80, 90, 140),
            "Neon",
        ),
        part(
            "HubSign",
            (60, 14, 2),
            (cx, cy + 18, cz + hub_size / 2 - 6),
            (25, 28, 45),
        ),
    ]

    for item in parts:
        write_meta(OUT / item["properties"]["Name"], item)

    write_meta(
        OUT / "HubSpawn",
        spawn_location((cx + HUB_SPAWN_OFFSET[0], cy + HUB_SPAWN_OFFSET[1] - 4, cz + HUB_SPAWN_OFFSET[2])),
    )

    write_meta(
        OUT / "HubLight",
        part(
            "HubLight",
            (2, 2, 2),
            (cx, cy + 30, cz),
            (255, 255, 255),
            "Neon",
            transparency=1,
        ),
    )
    write_meta(OUT / "HubLight" / "PointLight", point_light(2, hub_size, (180, 200, 255)))

    walls = [
        ("HubWall_N", (hub_size + wall_t * 2, wall_h, wall_t), (cx, wall_y, cz - half - wall_t / 2)),
        ("HubWall_S", (hub_size + wall_t * 2, wall_h, wall_t), (cx, wall_y, cz + half + wall_t / 2)),
        ("HubWall_E", (wall_t, wall_h, hub_size + wall_t * 2), (cx + half + wall_t / 2, wall_y, cz)),
        ("HubWall_W", (wall_t, wall_h, hub_size + wall_t * 2), (cx - half - wall_t / 2, wall_y, cz)),
    ]
    for name, size, pos in walls:
        write_meta(OUT / name, part(name, size, pos, wall_color, "Concrete"))
        trim_name = f"{name}_Trim"
        trim_pos = (pos[0], pos[1] + wall_h / 2 - 0.4, pos[2])
        write_meta(
            OUT / trim_name,
            part(trim_name, (size[0], 1.2, size[2]), trim_pos, trim_color, "Neon", can_collide=False),
        )

    for ox, oz in [(-half, -half), (half, -half), (half, half), (-half, half)]:
        pillar_name = f"HubPillar_{int(ox)}_{int(oz)}"
        write_meta(
            OUT / pillar_name,
            part(
                "HubPillar",
                (6, wall_h + 4, 6),
                (cx + ox, wall_y + 2, cz + oz),
                trim_color,
                "Neon",
            ),
        )
        write_meta(
            OUT / pillar_name / "PointLight",
            point_light(1.2, 20, trim_color),
        )

    spacing = HUB_PAD_SPACING
    start_x = -((WORLD_COUNT - 1) * spacing) / 2
    pad_z = cz + 20

    for world_id in range(1, WORLD_COUNT + 1):
        px = cx + start_x + (world_id - 1) * spacing
        color = WORLDS[world_id]
        pad_name = f"WorldPad_{world_id}"
        write_meta(
            OUT / pad_name,
            part(
                pad_name,
                (14, 1.5, 14),
                (px, cy + 2.75, pad_z),
                color,
                "Neon",
            ),
        )
        write_meta(OUT / pad_name / "WorldId", int_value(world_id))
        write_meta(
            OUT / f"PadBeam_{world_id}",
            part(
                f"PadBeam_{world_id}",
                (4, 30, 4),
                (px, cy + 17, pad_z),
                color,
                "Neon",
                transparency=0.6,
                can_collide=False,
            ),
        )

    print(f"Baked hub to {OUT} ({len(list(OUT.rglob('init.meta.json')))} instances)")


if __name__ == "__main__":
    bake()
