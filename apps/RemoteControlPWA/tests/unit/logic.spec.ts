import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { getRemoteClient } from '@/lib/remote/client';
import { processIncomingSequence, queueEnvelopeWithLimits } from '@/lib/remote/logic';
import { createInitialState, remoteStoreApi } from '@/lib/remote/store';

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

describe('remote client lifecycle', () => {
  const OriginalWebSocket = globalThis.WebSocket;

  class FakeWebSocket {
    static readonly CONNECTING = 0;
    static readonly OPEN = 1;
    static readonly CLOSING = 2;
    static readonly CLOSED = 3;

    readonly url: string;
    readyState = FakeWebSocket.CONNECTING;
    onopen: ((this: WebSocket, event: Event) => unknown) | null = null;
    onclose: ((this: WebSocket, event: CloseEvent) => unknown) | null = null;
    onmessage: ((this: WebSocket, event: MessageEvent<string>) => unknown) | null = null;
    onerror: ((this: WebSocket, event: Event) => unknown) | null = null;

    constructor(url: string) {
      this.url = url;
    }

    send(_payload: string) {}

    close() {
      this.readyState = FakeWebSocket.CLOSED;
    }
  }

  beforeEach(() => {
    vi.useFakeTimers();
    remoteStoreApi.setState(createInitialState());
    (globalThis as { WebSocket: typeof WebSocket }).WebSocket = FakeWebSocket as unknown as typeof WebSocket;
  });

  afterEach(() => {
    getRemoteClient().closeSocket();
    remoteStoreApi.setState(createInitialState());
    vi.restoreAllMocks();
    vi.useRealTimers();
    (globalThis as { WebSocket: typeof WebSocket }).WebSocket = OriginalWebSocket;
  });

  it('does not fire a scheduled reconnect after resetForE2E teardown', () => {
    remoteStoreApi.setState({
      sessionID: 'session-1',
      deviceSessionToken: 'device-token',
      wsURL: 'wss://relay.example/ws'
    });

    const client = getRemoteClient();
    const connectSpy = vi.spyOn(client, 'connectSocket');
    client.connectSocket();

    const socket = remoteStoreApi.getState().socket;
    expect(socket).not.toBeNull();
    socket?.onclose?.(new CloseEvent('close'));
    expect(remoteStoreApi.getState().reconnectTimer).not.toBeNull();

    client.resetForE2E();
    expect(remoteStoreApi.getState().reconnectTimer).toBeNull();

    vi.advanceTimersByTime(1_100);
    expect(connectSpy).toHaveBeenCalledTimes(1);
  });
});
