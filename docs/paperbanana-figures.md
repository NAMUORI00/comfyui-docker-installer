# PaperBanana-style README Figures

This note records how the README figures were prepared so future maintainers can update them without guessing.

## Workflow

The figures follow the bundled PaperBanana-style Codex workflow:

1. Planner: identify the entities, data flow, persistent stores, security boundary, and exact technical labels.
2. Stylist: apply a restrained academic diagram style with pale grouped zones, readable sans-serif labels, and semantically meaningful arrows.
3. Visualizer: generate candidate diagrams through the Codex image generation path.
4. Critic: inspect candidates for wrong labels, wrong arrows, missing mounts, and hallucinated details.
5. Finalization: keep the accepted structure, but render final README assets as SVG for exact labels and GitHub readability.

## Final assets

- `docs/assets/comfyui-deployment-flow.svg`: end-to-end LAN request path through Caddy Basic Auth into the internal ComfyUI container and GPU runtime.
- `docs/assets/comfyui-data-layout.svg`: persistent `./data` directory layout and Docker mount targets.

## Critic notes

- The generated deployment candidate had a useful composition and was used as the visual reference.
- The generated data-layout candidate contained a path-label typo, so the final asset was reconstructed as SVG instead of using the raster directly.
- Final SVG labels should be treated as the source of truth because they are directly tied to `compose.yaml`, `extra_model_paths.yaml`, and the installer behavior.
