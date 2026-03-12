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
  const storageState = new Map<string, string>();

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
    if (typeof window !== 'undefined') {
      const localStorageStub = window.localStorage as Storage | undefined;
      if (!localStorageStub || typeof localStorageStub.getItem !== 'function' || typeof localStorageStub.setItem !== 'function') {
        Object.defineProperty(window, 'localStorage', {
          configurable: true,
          value: {
            getItem: (key: string) => storageState.get(key) ?? null,
            setItem: (key: string, value: string) => {
              storageState.set(key, String(value));
            },
            removeItem: (key: string) => {
              storageState.delete(key);
            },
            clear: () => {
              storageState.clear();
            }
          } satisfies Pick<Storage, 'getItem' | 'setItem' | 'removeItem' | 'clear'>
        });
      }
      window.localStorage.clear();
    }
  });

  afterEach(() => {
    getRemoteClient().closeSocket();
    remoteStoreApi.setState(createInitialState());
    vi.restoreAllMocks();
    vi.useRealTimers();
    (globalThis as { WebSocket: typeof WebSocket }).WebSocket = OriginalWebSocket;
    if (typeof window !== 'undefined' && window.localStorage && typeof window.localStorage.clear === 'function') {
      window.localStorage.clear();
    }
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

  it('does not consume outgoing sequence when non-queueable command is rejected offline', () => {
    remoteStoreApi.setState({
      sessionID: 'session-1',
      selectedProjectFilterID: 'all'
    });

    const client = getRemoteClient();
    expect(remoteStoreApi.getState().nextOutgoingSeq).toBe(1);

    client.selectProjectFilter('project-offline', true);

    const nextState = remoteStoreApi.getState();
    expect(nextState.nextOutgoingSeq).toBe(1);
    expect(nextState.queuedCommands).toHaveLength(0);
  });

  it('does not consume outgoing sequence when oversized message cannot be queued offline', () => {
    remoteStoreApi.setState({
      sessionID: 'session-1',
      selectedThreadID: 'thread-1'
    });

    const client = getRemoteClient();
    const hugeMessage = 'x'.repeat(300 * 1024);

    expect(remoteStoreApi.getState().nextOutgoingSeq).toBe(1);
    expect(client.sendComposerMessage(hugeMessage)).toBe(false);

    const nextState = remoteStoreApi.getState();
    expect(nextState.nextOutgoingSeq).toBe(1);
    expect(nextState.queuedCommands).toHaveLength(0);
    expect(nextState.queuedCommandsBytes).toBe(0);
  });

  it('queues composer message while socket is open but auth is pending', () => {
    const socket = new FakeWebSocket('wss://relay.example/ws');
    socket.readyState = FakeWebSocket.OPEN;

    remoteStoreApi.setState({
      sessionID: 'session-1',
      selectedThreadID: 'thread-1',
      wsURL: 'wss://relay.example/ws',
      deviceSessionToken: 'token-old',
      socket: socket as unknown as WebSocket,
      isAuthenticated: false
    });

    const client = getRemoteClient();
    expect(client.sendComposerMessage('queued while auth pending')).toBe(true);

    const nextState = remoteStoreApi.getState();
    expect(nextState.nextOutgoingSeq).toBe(2);
    expect(nextState.queuedCommands).toHaveLength(1);
    expect(nextState.queuedCommands[0]?.envelope).toMatchObject({
      sessionID: 'session-1',
      payload: {
        type: 'command',
        payload: {
          name: 'thread.send_message',
          threadID: 'thread-1',
          text: 'queued while auth pending'
        }
      }
    });
  });

  it('persists rotated device token on auth_ok for durable reconnect', () => {
    remoteStoreApi.setState({
      sessionID: 'session-1',
      deviceID: 'device-1',
      deviceName: 'Test iPhone',
      relayBaseURL: 'https://relay.example',
      wsURL: 'wss://relay.example/ws',
      deviceSessionToken: 'token-old'
    });

    const client = getRemoteClient();
    client.ingestServerMessageForTesting({
      type: 'auth_ok',
      role: 'mobile',
      sessionID: 'session-1',
      deviceID: 'device-1',
      nextDeviceSessionToken: 'token-new',
      desktopConnected: false
    });

    const nextState = remoteStoreApi.getState();
    expect(nextState.deviceSessionToken).toBe('token-new');
    expect(nextState.desktopConnected).toBe(false);

    const raw = window.localStorage.getItem('codexchat.remote.pairedDevice.v1');
    expect(raw).not.toBeNull();
    const persisted = JSON.parse(raw || '{}') as { deviceSessionToken?: string };
    expect(persisted.deviceSessionToken).toBe('token-new');
  });

  it('clears persisted credentials when disconnect reason requires re-pair', () => {
    const client = getRemoteClient();
    const nonReconnectableReasons = [
      'device_revoked',
      'stopped_by_desktop',
      'session_expired',
      'replaced_by_new_pair_start'
    ] as const;

    for (const reason of nonReconnectableReasons) {
      window.localStorage.setItem(
        'codexchat.remote.pairedDevice.v1',
        JSON.stringify({
          sessionID: 'session-1',
          deviceID: 'device-1',
          relayBaseURL: 'https://relay.example',
          deviceSessionToken: 'token-old',
          wsURL: 'wss://relay.example/ws',
          storedAt: new Date().toISOString()
        })
      );

      remoteStoreApi.setState({
        isAuthenticated: true,
        sessionID: 'session-1',
        deviceID: 'device-1',
        joinToken: 'join-token',
        deviceSessionToken: 'token-old',
        wsURL: 'wss://relay.example/ws',
        reconnectDisabledReason: null,
        queuedCommands: [
          {
            envelope: { schemaVersion: 2 },
            bytes: 24
          }
        ],
        queuedCommandsBytes: 24,
        pendingSnapshotReason: 'initial_sync'
      });

      client.ingestServerMessageForTesting({
        type: 'disconnect',
        reason
      });

      const nextState = remoteStoreApi.getState();
      expect(nextState.reconnectDisabledReason).toBe(reason);
      expect(nextState.isAuthenticated).toBe(false);
      expect(nextState.deviceSessionToken).toBeNull();
      expect(nextState.wsURL).toBeNull();
      expect(nextState.deviceID).toBeNull();
      expect(nextState.joinToken).toBeNull();
      expect(nextState.queuedCommands).toHaveLength(0);
      expect(nextState.queuedCommandsBytes).toBe(0);
      expect(nextState.pendingSnapshotReason).toBeNull();
      expect(window.localStorage.getItem('codexchat.remote.pairedDevice.v1')).toBeNull();
    }
  });
});
