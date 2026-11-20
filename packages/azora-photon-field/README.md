# Photon Field

Attach the Photon Field ECS component to a Directional Light in Studio, or use View → Toggle Photon Field. It is enabled on the directional light in Studio's default scene. Its component controls virtual page size, resolution, range, shadow bias, and diffuse bounce strength.

Photon Field maintains a sparse depth page table around the view target. It traces transformed cube, sphere, cylinder, and plane primitives, along with heightfield surfaces into newly needed or invalidated pages. The Metal shaders filter receiver shadows across page edges and sample the lit surface cache for approximate single-bounce diffuse color bleeding. Material Fusion supplies a representative diffuse color for that cache.

Call \`app.updateScenePhotons(world, focus)\` after applying scene lighting and before drawing. This implementation supports one enabled directional light and the built-in mesh primitives and heightfields. Plugin-owned meshes can receive the light. Their geometry is outside this caster set.
