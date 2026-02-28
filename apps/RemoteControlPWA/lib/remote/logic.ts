export type SequenceDecision = 'accepted' | 'ignored' | 'gap' | 'stale';

export function processIncomingSequence(lastIncomingSeq: number | null, seq: unknown): { decision: SequenceDecision; nextLastIncomingSeq: number | null } {
  if (typeof seq !== 'number') {
    return { decision: 'accepted', nextLastIncomingSeq: lastIncomingSeq };
  }

  if (!Number.isSafeInteger(seq) || seq < 0) {
    return { decision: 'ignored', nextLastIncomingSeq: lastIncomingSeq };
  }

  if (lastIncomingSeq === null) {
    return { decision: 'accepted', nextLastIncomingSeq: seq };
  }

  const expectedNext = lastIncomingSeq + 1;
  if (seq === expectedNext) {
    return { decision: 'accepted', nextLastIncomingSeq: seq };
  }

  if (seq > expectedNext) {
    return { decision: 'gap', nextLastIncomingSeq: lastIncomingSeq };
  }

  return { decision: 'stale', nextLastIncomingSeq: lastIncomingSeq };
}

export interface QueuedEnvelope {
  envelope: unknown;
  bytes: number;
}

export function queueEnvelopeWithLimits(
  existing: QueuedEnvelope[],
  existingBytes: number,
  incomingEnvelope: unknown,
  maxQueuedCommands: number,
  maxQueuedBytes: number
): {
  ok: boolean;
  dropped: number;
  reason: 'too_large' | null;
  queue: QueuedEnvelope[];
  bytes: number;
} {
  const encoded = JSON.stringify(incomingEnvelope);
  const bytes = new TextEncoder().encode(encoded).length;
  if (bytes > maxQueuedBytes) {
    return {
      ok: false,
      dropped: 0,
      reason: 'too_large',
      queue: existing,
      bytes: existingBytes
    };
  }

  const queue = existing.slice();
  let totalBytes = existingBytes;
  let dropped = 0;

  while (queue.length > 0 && (queue.length >= maxQueuedCommands || totalBytes + bytes > maxQueuedBytes)) {
    const evicted = queue.shift();
    if (!evicted) {
      break;
    }
    totalBytes = Math.max(0, totalBytes - evicted.bytes);
    dropped += 1;
  }

  queue.push({ envelope: incomingEnvelope, bytes });
  totalBytes += bytes;

  return {
    ok: true,
    dropped,
    reason: null,
    queue,
    bytes: totalBytes
  };
}
