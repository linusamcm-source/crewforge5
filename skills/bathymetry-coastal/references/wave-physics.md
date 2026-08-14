# Calculation Utilities

```typescript
/**
 * Depth-induced wave breaking criterion (Battjes & Janssen).
 * Hb = γ × d, where γ ≈ 0.73 for typical conditions.
 */
export function breakingWaveHeight(
  depthM: number,
  breakerIndex: number = 0.73
): number {
  return breakerIndex * depthM;
}

/**
 * Shoaling coefficient — how wave height changes as depth decreases.
 * Ks = sqrt(Cg0 / Cg), where Cg is group velocity.
 * Uses linear wave theory.
 */
export function shoalingCoefficient(
  periodS: number,
  deepWaterDepthM: number,
  shallowDepthM: number
): number {
  const cgDeep = groupVelocity(periodS, deepWaterDepthM);
  const cgShallow = groupVelocity(periodS, shallowDepthM);
  return Math.sqrt(cgDeep / cgShallow);
}

/**
 * Group velocity for linear waves at arbitrary depth.
 * Cg = C/2 × (1 + 2kd/sinh(2kd))
 */
export function groupVelocity(periodS: number, depthM: number): number {
  const g = 9.80665;
  const omega = (2 * Math.PI) / periodS;
  const k = solveDispersionRelation(omega, depthM);
  const c = omega / k;
  const n = 0.5 * (1 + (2 * k * depthM) / Math.sinh(2 * k * depthM));
  return n * c;
}

/**
 * Solve the linear dispersion relation iteratively.
 * ω² = gk·tanh(kd)
 */
function solveDispersionRelation(omega: number, depthM: number): number {
  const g = 9.80665;
  let k = (omega * omega) / g; // Deep water initial guess
  for (let i = 0; i < 50; i++) {
    const kNew = (omega * omega) / (g * Math.tanh(k * depthM));
    if (Math.abs(kNew - k) < 1e-10) break;
    k = kNew;
  }
  return k;
}

/**
 * Snell's law for wave refraction.
 * sin(θ₂)/C₂ = sin(θ₁)/C₁
 * Returns the refracted wave angle at a new depth.
 */
export function refractedAngle(
  incidentAngleDeg: number,
  periodS: number,
  depth1M: number,
  depth2M: number
): number {
  const c1 = waveCelerity(periodS, depth1M);
  const c2 = waveCelerity(periodS, depth2M);
  const sinTheta2 = Math.sin((incidentAngleDeg * Math.PI) / 180) * (c2 / c1);
  if (Math.abs(sinTheta2) > 1) return 90; // Total refraction — wave trapped
  return (Math.asin(sinTheta2) * 180) / Math.PI;
}

/**
 * Generate depth contours from a regular bathymetric grid.
 * Uses marching squares algorithm.
 * Returns contour lines at specified depth intervals.
 */
export function generateContours(
  grid: BathymetricGrid,
  contourLevels: readonly number[]
): Map<number, DepthContour[]> {
  // Implementation would use a marching-squares library (e.g., d3-contour adapted)
  // This is the interface contract
  throw new Error('Implement with d3-contour or custom marching squares');
}
```
