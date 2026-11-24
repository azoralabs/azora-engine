#!/usr/bin/env python3
"""Embed GLSL generated from compat.az for the legacy Vulkan and WebGL host ABI."""

import argparse
from pathlib import Path
import re
import subprocess


def cross(folder, entry, web=False, interface=()):
    shader = folder / f"compat.{entry}.spv"
    args = ["spirv-cross", str(shader), "--version", "300" if web else "450"]
    if web:
        args.append("--es")
    for direction, slot, name in interface:
        args.extend(("--rename-interface-variable", direction, str(slot), name))
    return subprocess.check_output(args, text=True).strip() + "\n"


def web_glsl(source):
    # The web bridge sets individual uniforms by name. Recover those names from
    # the uniform block emitted for the shared GPU ABI.
    block = r'layout\(std140\) uniform az_ublock_0\s*\{\s*(\w+) az_value;\s*\}\s*az_uniform_0;'
    block_type = re.search(block, source)[1]
    if block_type == "int":
        source = re.sub(block, "uniform bool uUseTexture;", source)
        source = source.replace("az_uniform_0.az_value == 0", "!uUseTexture")
    else:
        struct = rf'struct {block_type}\s*\{{([^}}]*)\}};'
        fields = re.findall(r'(\w+) (az_field_\d+_(\w+));', re.search(struct, source)[1])
        declarations = []
        for kind, emitted, name in fields:
            declarations.append(f"uniform highp {kind} {name};")
            source = source.replace(f"az_uniform_0.az_value.{emitted}", name)
        source = re.sub(struct, "", source)
        source = re.sub(block, "\n".join(declarations), source)
    return source.replace("SPIRV_Cross_Combinedaz_texture_1az_sampler_0", "uTexture")


def vulkan_glsl(source):
    return source.replace("layout(binding = 0, std140)", "layout(set = 0, binding = 0, std140)").replace(
        "uniform sampler2D SPIRV_Cross_Combinedaz_texture_1az_sampler_0;",
        "layout(set = 0, binding = 1) uniform sampler2D SPIRV_Cross_Combinedaz_texture_1az_sampler_0;",
    )


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("spirv", type=Path)
    args = parser.parse_args()
    variants = (
        ("vulkan3dVertexShaderSource", "vulkanMeshVertex", ()),
        ("vulkan3dFragmentShaderSource", "vulkanMeshFragment", ()),
        ("vulkan2dVertexShaderSource", "vulkanCanvasVertex", ()),
        ("vulkan2dFragmentShaderSource", "vulkanCanvasFragment", ()),
        ("webgl3dVertexShaderSource", "webMeshVertex", (("in", 0, "position"), ("in", 1, "normal"), ("out", 0, "vNormal"))),
        ("webgl3dFragmentShaderSource", "webMeshFragment", (("in", 0, "vNormal"),)),
        ("webgl2dVertexShaderSource", "webCanvasVertex", (("in", 0, "position"), ("in", 1, "uv"), ("in", 2, "color"),
                                                          ("out", 0, "vUv"), ("out", 1, "vColor"))),
        ("webgl2dFragmentShaderSource", "webCanvasFragment", (("in", 0, "vUv"), ("in", 1, "vColor"))),
    )
    print('/* Generated from shaders/compat.az by tools/generate-compat-shaders.py. */\nmodule engine.shaders')
    for name, entry, interface in variants:
        web = name.startswith("web")
        source = cross(args.spirv, entry, web, interface)
        source = web_glsl(source) if web else vulkan_glsl(source)
        # Keep the generated shader readable in the embedded source.
        expression = source.replace(chr(92), chr(92) * 2).replace(chr(34), chr(92) + chr(34))
        print(f'\nfunc {name}(): String = "{expression}"')


if __name__ == "__main__":
    main()
