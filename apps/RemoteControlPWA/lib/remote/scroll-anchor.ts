export const CHAT_BOTTOM_THRESHOLD_PX = 48;

export interface ScrollMetrics {
  scrollTop: number;
  scrollHeight: number;
  clientHeight: number;
}

export function distanceFromBottom(metrics: ScrollMetrics): number {
  return Math.max(0, metrics.scrollHeight - metrics.scrollTop - metrics.clientHeight);
}

export function isNearBottom(metrics: ScrollMetrics, threshold = CHAT_BOTTOM_THRESHOLD_PX): boolean {
  return distanceFromBottom(metrics) <= threshold;
}
