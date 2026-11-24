"""Write Azora GPU source for the Engine material ABI."""

import json
from pathlib import Path

TEMPLATE = Path(__file__).resolve().parents[1] / "materials" / "blank.az"


def real(value):
    return str(float(value))


def material_source(module, label, albedo, textures, body):
    source = TEMPLATE.read_text(encoding="utf-8").replace("module project.materials.blank", f"module {module}", 1)
    bindings = json.dumps({"albedo": albedo, "textures": textures}, separators=(",", ":"))
    metadata = "\n".join(f"// {line}" for line in label.splitlines())
    metadata = f"{metadata}\n" if metadata else ""
    prefix, tail = source.split("// @Material ", 1)
    source = prefix + metadata + "// @Material " + bindings + "\n" + tail.split("\n", 1)[1]
    ports = "".join(
        f"    {name}{i}: @Texture({i * 3 + slot}) Texture2D\n"
        for i, _ in enumerate(textures)
        for slot, name in enumerate(("base", "normal", "surfaceMap"))
    )
    prefix, tail = source.split("    clouds: @Texture(31) Texture2D\n", 1)
    source = prefix + "    clouds: @Texture(31) Texture2D\n" + ports + tail
    prefix = source.split("    fin surface = slab(", 1)[0]
    return prefix + "".join(f"    {line}\n" for line in body) + "}\n"


def texture_material(module, label, path, tile, strength, directional):
    params = ", ".join(map(real, (tile, strength, 0, 0 if directional else 1.5, 0.6, 45,
                                  0 if directional else 1, 0)))
    return material_source(module, [0.38, 0.55, 0.72], [path], [
        "fin n = normalize(input.normal)",
        f"fin surface = textureSlab(context, input.world, n, base0, normal0, surfaceMap0, {params})",
        "return materialColor(surface, input, context, u, spots)",
    ])
