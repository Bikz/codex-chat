import { describe, expect, it } from 'vitest';
import { processIncomingSequence, queueEnvelopeWithLimits } from '@/lib/remote/logic';

describe('remote logic', () => {
  it('processes incoming sequence transitions', () => {
    expect(processIncomingSequence(null, 3)).toEqual({ decision: 'accepted', nextLastIncomingSeq: 3 });
    expect(processIncomingSequence(3, 4)).toEqual({ decision: 'accepted', nextLastIncomingSeq: 4 });
    expect(processIncomingSequence(3, 6)).toEqual({ decision: 'gap', nextLastIncomingSeq: 3 });
    expect(processIncomingSequence(3, 2)).toEqual({ decision: 'stale', nextLastIncomingSeq: 3 });
    expect(processIncomingSequence(3, -1)).toEqual({ decision: 'ignored', nextLastIncomingSeq: 3 });
  });

  it('evicts old queued envelopes by count and bytes', () => {
    const q1 = queueEnvelopeWithLimits([], 0, { a: 'x'.repeat(50) }, 2, 400);
    const q2 = queueEnvelopeWithLimits(q1.queue, q1.bytes, { b: 'x'.repeat(50) }, 2, 400);
    const q3 = queueEnvelopeWithLimits(q2.queue, q2.bytes, { c: 'x'.repeat(50) }, 2, 400);

    expect(q3.ok).toBe(true);
    expect(q3.queue).toHaveLength(2);
    expect(q3.dropped).toBe(1);
  });

  it('rejects envelope larger than byte limit', () => {
    const result = queueEnvelopeWithLimits([], 0, { huge: 'x'.repeat(1000) }, 10, 100);
    expect(result.ok).toBe(false);
    expect(result.reason).toBe('too_large');
  });
});
