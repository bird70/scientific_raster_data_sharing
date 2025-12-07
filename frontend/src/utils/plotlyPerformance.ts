/**
 * Plotly performance utilities
 * Implements data decimation and rendering thresholds to prevent UI freezing
 */

/**
 * Decimate timeseries data when it exceeds threshold
 * Uses Largest Triangle Three Buckets (LTTB) algorithm
 */
export function decimateTimeseries(
  times: string[],
  values: number[],
  targetPoints = 1000
): { times: string[]; values: number[] } {
  if (times.length <= targetPoints) {
    return { times, values };
  }

  const decimated = lttb(times, values, targetPoints);
  return {
    times: decimated.map((d) => d.time),
    values: decimated.map((d) => d.value),
  };
}

interface DataPoint {
  time: string;
  value: number;
}

/**
 * Largest Triangle Three Buckets (LTTB) algorithm
 * Downsamples data while preserving visual fidelity
 * Based on: https://github.com/sveinn-steinarsson/flot-downsample
 */
function lttb(times: string[], values: number[], threshold: number): DataPoint[] {
  if (times.length !== values.length) {
    throw new Error('Times and values arrays must have equal length');
  }

  const data: DataPoint[] = times.map((time, i) => ({ time, value: values[i] }));
  const dataLength = data.length;

  if (threshold >= dataLength || threshold === 0) {
    return data;
  }

  const sampled: DataPoint[] = [];
  sampled[0] = data[0]; // Always keep first point

  const bucketSize = (dataLength - 2) / (threshold - 2);

  let a = 0;
  let maxAreaPoint: DataPoint;
  let maxArea: number;
  let area: number;
  let nextA: number;

  for (let i = 0; i < threshold - 2; i++) {
    // Calculate point average for next bucket
    let avgX = 0;
    let avgY = 0;
    let avgRangeStart = Math.floor((i + 1) * bucketSize) + 1;
    let avgRangeEnd = Math.floor((i + 2) * bucketSize) + 1;
    avgRangeEnd = avgRangeEnd < dataLength ? avgRangeEnd : dataLength;

    const avgRangeLength = avgRangeEnd - avgRangeStart;

    for (; avgRangeStart < avgRangeEnd; avgRangeStart++) {
      avgX += avgRangeStart;
      avgY += data[avgRangeStart].value;
    }
    avgX /= avgRangeLength;
    avgY /= avgRangeLength;

    // Get the range for this bucket
    let rangeOffs = Math.floor(i * bucketSize) + 1;
    const rangeTo = Math.floor((i + 1) * bucketSize) + 1;

    // Point a
    const pointAX = a;
    const pointAY = data[a].value;

    maxArea = -1;

    for (; rangeOffs < rangeTo; rangeOffs++) {
      // Calculate triangle area over three buckets
      area =
        Math.abs(
          (pointAX - avgX) * (data[rangeOffs].value - pointAY) -
            (pointAX - rangeOffs) * (avgY - pointAY)
        ) * 0.5;

      if (area > maxArea) {
        maxArea = area;
        maxAreaPoint = data[rangeOffs];
        nextA = rangeOffs;
      }
    }

    sampled[i + 1] = maxAreaPoint!;
    a = nextA!;
  }

  sampled[threshold - 1] = data[dataLength - 1]; // Always keep last point

  return sampled;
}

/**
 * Performance thresholds for Plotly charts
 */
export const PLOTLY_THRESHOLDS = {
  // Maximum points before decimation is applied
  MAX_POINTS: 5000,
  // Target points after decimation
  TARGET_POINTS: 1000,
  // Warn user if data exceeds this threshold
  WARN_THRESHOLD: 10000,
  // Maximum points to render (hard limit)
  ABSOLUTE_MAX: 50000,
};

/**
 * Check if data should be decimated and return appropriate message
 */
export function checkRenderThreshold(
  dataPoints: number
): { shouldDecimate: boolean; shouldWarn: boolean; message?: string } {
  if (dataPoints > PLOTLY_THRESHOLDS.ABSOLUTE_MAX) {
    return {
      shouldDecimate: true,
      shouldWarn: true,
      message: `Dataset too large (${dataPoints.toLocaleString()} points). Displaying first ${PLOTLY_THRESHOLDS.ABSOLUTE_MAX.toLocaleString()} points only.`,
    };
  }

  if (dataPoints > PLOTLY_THRESHOLDS.WARN_THRESHOLD) {
    return {
      shouldDecimate: true,
      shouldWarn: true,
      message: `Large dataset (${dataPoints.toLocaleString()} points). Downsampling to ${PLOTLY_THRESHOLDS.TARGET_POINTS.toLocaleString()} points for better performance.`,
    };
  }

  if (dataPoints > PLOTLY_THRESHOLDS.MAX_POINTS) {
    return {
      shouldDecimate: true,
      shouldWarn: false,
    };
  }

  return {
    shouldDecimate: false,
    shouldWarn: false,
  };
}

/**
 * Truncate data to absolute maximum
 */
export function truncateToMax<T>(data: T[], max = PLOTLY_THRESHOLDS.ABSOLUTE_MAX): T[] {
  if (data.length <= max) return data;
  return data.slice(0, max);
}
