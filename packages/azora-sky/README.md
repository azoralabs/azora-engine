# Azora Sky

Add a Sky Environment component to a Directional Light. In Studio, the viewport's Hour field sets decimal hours from 0 to 24. The component also exposes latitude, season, sun and moon intensity, haze, and the length of a full cycle in minutes. A zero cycle length keeps the scene at the chosen hour.

The sky renders a procedural gradient, sun, moon, and stars. It also supplies the scene light direction, ambient level, and haze for the material pipelines. When Photon Field is attached to the same light, its pages track the active sun or moon.
