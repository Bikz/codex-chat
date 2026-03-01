'use client';

import * as Dialog from '@radix-ui/react-dialog';
import { useMemo } from 'react';
import { getRemoteClient } from '@/lib/remote/client';
import { useRemoteStore } from '@/lib/remote/store';
import { useShallow } from 'zustand/react/shallow';

export function AccountSheet() {
  const client = getRemoteClient();
  const {
    isAccountSheetOpen,
    sessionID,
    deviceName,
    reconnectDisabledReason,
    deviceSessionToken,
    wsURL,
    lastIncomingSeq,
    statusLevel,
    connectionStatusText,
    isAuthenticated,
    isSyncStale,
    lastSyncedAt,
    showAllSystemMessages
  } = useRemoteStore(
    useShallow((state) => ({
      isAccountSheetOpen: state.isAccountSheetOpen,
      sessionID: state.sessionID,
      deviceName: state.deviceName,
      reconnectDisabledReason: state.reconnectDisabledReason,
      deviceSessionToken: state.deviceSessionToken,
      wsURL: state.wsURL,
      lastIncomingSeq: state.lastIncomingSeq,
      statusLevel: state.statusLevel,
      connectionStatusText: state.connectionStatusText,
      isAuthenticated: state.isAuthenticated,
      isSyncStale: state.isSyncStale,
      lastSyncedAt: state.lastSyncedAt,
      showAllSystemMessages: state.showAllSystemMessages
    }))
  );

  const lastSyncedLabel = useMemo(() => {
    if (!lastSyncedAt) return 'Never';
    const deltaMs = Date.now() - lastSyncedAt;
    if (deltaMs < 5_000) return 'Just now';
    const deltaSeconds = Math.floor(deltaMs / 1_000);
    if (deltaSeconds < 60) return `${deltaSeconds}s ago`;
    const deltaMinutes = Math.floor(deltaSeconds / 60);
    if (deltaMinutes < 60) return `${deltaMinutes}m ago`;
    return new Date(lastSyncedAt).toLocaleTimeString();
  }, [lastSyncedAt]);

  const reconnectDisabled = Boolean(reconnectDisabledReason);
  const hasRememberedDevice = Boolean(deviceSessionToken && wsURL);

  return (
    <Dialog.Root open={isAccountSheetOpen} onOpenChange={(open) => (open ? client.openAccountSheet() : client.closeAccountSheet())}>
      <Dialog.Portal>
        <Dialog.Overlay className="sheet-backdrop" />
        <Dialog.Content id="accountSheet" className="sheet-card" aria-labelledby="accountSheetTitle">
          <div className="sheet-head">
            <Dialog.Title asChild>
              <h2 id="accountSheetTitle">Connection</h2>
            </Dialog.Title>
            <Dialog.Close asChild>
              <button id="closeAccountSheetButton" className="ghost" type="button" aria-label="Close account and connection controls">
                Close
              </button>
            </Dialog.Close>
          </div>

          <p id="pairingHint" className="pairing-hint">
            {sessionID ? 'Session details and sync health.' : 'No active session details yet. Start from Pair this phone.'}
          </p>

          <dl className="kv">
            <dt>Session</dt>
            <dd id="sessionValue" className="break-anywhere">
              {sessionID || 'Not paired'}
            </dd>
            <dt>Device</dt>
            <dd id="deviceNameValue" className="break-anywhere">
              {deviceName || 'Unknown device'}
            </dd>
            <dt>Last seq</dt>
            <dd id="seqValue">{typeof lastIncomingSeq === 'number' ? String(lastIncomingSeq) : '-'}</dd>
            <dt>Last synced</dt>
            <dd id="lastSyncedValue">{lastSyncedLabel}</dd>
          </dl>

          <div className="actions">
            <button id="reconnectButton" type="button" disabled={reconnectDisabled} onClick={() => client.reconnect()}>
              Reconnect
            </button>
            <button id="snapshotButton" type="button" onClick={() => client.requestSnapshot('manual_request')}>
              Request Snapshot
            </button>
            <button id="forgetButton" type="button" hidden={!hasRememberedDevice} onClick={() => client.forgetRememberedDevice()}>
              Forget This Device
            </button>
          </div>

          <label className="switch-row" htmlFor="showSystemMessagesToggle">
            <span>Show all system messages</span>
            <input
              id="showSystemMessagesToggle"
              type="checkbox"
              checked={showAllSystemMessages}
              onChange={(event) => client.setShowAllSystemMessages(event.currentTarget.checked)}
            />
          </label>
          <p className="pairing-hint break-anywhere">By default, only user-relevant system notices are shown in transcript.</p>

          <p id="statusText" className={`status break-anywhere ${statusLevel}`}>
            {connectionStatusText || (isAuthenticated ? (isSyncStale ? 'Connected but stale.' : 'Connected.') : 'Waiting to pair.')}
          </p>
        </Dialog.Content>
      </Dialog.Portal>
    </Dialog.Root>
  );
}
