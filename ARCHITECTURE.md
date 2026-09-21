# BREBO Scan Architecture

The Sparingsmeter is the first product built on a reusable scan kernel.

## Shared scan kernel

- ARKit camera pose / tracking
- LiDAR scene depth
- Vision-based feature detection
- multi-frame fusion
- world-space point clouds
- robust line / plane fitting
- uncertainty estimation
- source provenance: measured / detected / calculated / user

## Core scanning rule

The complete opening must never be required to fit in the camera image.

The operator must be able to start at any visible part of the opening and move along local edges, corners and reveals. Every accepted local observation is transformed into the shared ARKit world coordinate system and fused there.

Vision rectangle detection is an optional accelerator only. It may seed or label candidate edges when the complete opening is visible, but it must not gate the scan.

The scan kernel must support:

- partial opening observations
- local left/right/top/bottom edge segments
- corners observed at different times
- stitching multiple sweeps into one opening model
- large and coupled frames that never fit in one image
- temporary occlusion by scaffolding, furniture or occupants
- measuring from inside where the outside is inaccessible

Missing edges may be completed later in the same scan. Final dimensions are calculated only after the world-space geometry has sufficient support and meets the metrology gate.

## Product 1: Sparingsmeter

Output:
- opening width / height
- minimum governing free size
- out-of-plumb / skew / depth
- opening geometry
- proposed frame size with 5 mm clearance per side
- release only at <= +/- 2 mm uncertainty

## Future product 2: MJOP scan

The same geometric engine can later support:
- facade planes and m2
- windows / doors / frames and quantities
- dimensions and position in facade
- roof edges / gutters / balconies where visible
- component inventory
- photographic evidence tied to 3D location
- quantities for maintenance work

Condition, defect recognition and maintenance advice are separate layers on top of measured geometry.
They must never be stored as if they were directly measured sensor facts.
