import { describe, expect, it } from 'vitest';
import { CHAT_BOTTOM_THRESHOLD_PX, distanceFromBottom, isNearBottom } from '@/lib/remote/scroll-anchor';

describe('scroll anchoring helpers', () => {
  it('computes distance from bottom', () => {
    expect(
      distanceFromBottom({
        scrollTop: 120,
        scrollHeight: 420,
        clientHeight: 200
      })
    ).toBe(100);
  });

  it('detects near-bottom state using threshold', () => {
    const nearBottom = isNearBottom({
      scrollTop: 172,
      scrollHeight: 420,
      clientHeight: 200
    });

    const farFromBottom = isNearBottom(
      {
        scrollTop: 80,
        scrollHeight: 420,
        clientHeight: 200
      },
      CHAT_BOTTOM_THRESHOLD_PX
    );

    expect(nearBottom).toBe(true);
    expect(farFromBottom).toBe(false);
  });
});
