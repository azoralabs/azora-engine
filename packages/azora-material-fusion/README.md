# Material Fusion

Material Fusion is a built-in Engine package. Studio has a Material Fusion dock tab and opens \`.azfusion\` and \`.azmaterial\` files from Assets. An asset is a versioned AZON document with typed connections and editor positions.

Create a material, add surface slabs or masks, and click an output pin followed by a compatible input pin. Right-click an input to disconnect it, right-drag to pan, and scroll to zoom. The node inspector edits selected parameters. Compile previews the graph, and Assign to Selection adds a Material Fusion component to the selected mesh. Save the scene to persist the assignment.

Surface Slab evaluates an opaque diffuse and GGX specular response with base color, metallic, roughness, and emission. Mix Surfaces blends two independently evaluated surfaces. Stack Layers approximates a coating with coverage, Fresnel reflection, and thickness-dependent transmission. Scalar, Checker Mask, Noise Mask, Altitude Mask, and Slope Mask can drive coverage. A Textured Slab uses an AZTX set with base color, normal, and packed roughness, ambient occlusion, height, and metallic data. Its world-aligned stochastic sampling uses mipmaps and blends texture offsets in world space.

On macOS, Engine build precompiles Material Fusion assets to Metal libraries when the Xcode Metal Toolchain is available. Engine validates the cache against the generated shader, prefers Metal 3, and falls back to Metal 2. Studio prepares the same pipelines on open or edit. Existing Standard Material components continue to render and provide a fallback for unresolved assets.

Engine callers can set the project root with \`app.setFusionRoot(root)\`, and prewarm pipelines with \`app.prepareFusionMaterials(world)\` before calling \`app.drawScene(world, meshes)\`.

## Standard terrain materials

The Engine bundles ready-to-use Material Fusion graphs for Grass, Rock, Snow,
Asphalt, Meadow Grass, Dry Grass, Mossy Grass, Beach Sand, Dune Sand, Forest
Soil, and Gravel in `materials/standard`. Each graph references a 512 × 512
`.aztexture` set with base color, normals, and packed surface properties.
Existing `.aztex` paths are supported and both extensions use the AZTX format.

From the Engine directory, run `bash tools/import-standard-materials.sh /path/to/project`.
The import adds missing files under `Materials/Standard` and `Textures/Standard`
and preserves files already present in the project. Assign a graph to a
Material Fusion surface or use its AZTX set in a Textured Slab node. Studio's
development demo imports the library when it opens.

From the source checkout, rebuild the bundled assets with
`python3 tools/generate-standard-materials.py`.
