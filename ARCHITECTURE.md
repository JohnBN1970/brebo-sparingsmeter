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
