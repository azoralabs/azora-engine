# Azora GPU materials

Use **Assets → New Material** in Studio to create a `.az` shader and open it in the source editor. Select the shader in Assets and a mesh or landscape in the Scene Tree, then use **Assign Selected Material**. Saving the shader cooks its Metal library and refreshes the shader on the selected scene.

A material declares `@Execution("GPU")` on its module and defines `materialVertex` and `materialFragment`. The [material template](../../materials/blank.az) uses the engine mesh layout, lighting and fog. Optional `// @Material` JSON specifies the Photon Field albedo and project-relative texture sets. Each set binds three consecutive textures starting at zero. The engine reserves slots 30 and 31.

Run `tools/shader-cook.sh PROJECT OUTPUT` to build Metal, SPIR-V and DXIL. Studio uses Metal libraries in the project's `.azora-build/shaders`. Games also look for cooked shaders in the app bundle.
