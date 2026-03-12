'use client';

import * as Dialog from '@radix-ui/react-dialog';
import { useMemo } from 'react';
import { getRemoteClient } from '@/lib/remote/client';
import { useRemoteStore } from '@/lib/remote/store';
import { useShallow } from 'zustand/react/shallow';
import { Button } from '@/components/ui/button';
import { cn } from '@/lib/utils';

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
    desktopConnected,
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
      desktopConnected: state.desktopConnected,
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
        <Dialog.Content id="accountSheet" className="sheet-card flex flex-col gap-4" aria-labelledby="accountSheetTitle">
          <div className="flex items-center justify-between mb-2">
            <Dialog.Title asChild>
              <h2 id="accountSheetTitle" className="text-xl font-bold tracking-tight text-fg truncate">Connection</h2>
            </Dialog.Title>
            <Dialog.Close asChild>
              <Button id="closeAccountSheetButton" variant="ghost" size="sm" type="button" aria-label="Close account and connection controls" className="h-8 px-3 rounded-full text-[13px] bg-surface-alt">
                Done
              </Button>
            </Dialog.Close>
          </div>

          <p id="pairingHint" className="text-sm text-muted leading-relaxed">
            {sessionID ? 'Session details and sync health.' : 'No active session details yet. Start from Pair this phone.'}
          </p>

          <dl className="grid grid-cols-[auto_1fr] gap-x-4 gap-y-2 mt-2 bg-surface-alt p-4 rounded-2xl border border-line text-sm">
            <dt className="text-muted font-medium">Session</dt>
            <dd id="sessionValue" className="text-fg break-all font-mono text-xs self-center">
              {sessionID || 'Not paired'}
            </dd>
            <dt className="text-muted font-medium">Device</dt>
            <dd id="deviceNameValue" className="text-fg break-all self-center">
              {deviceName || 'Unknown device'}
            </dd>
            <dt className="text-muted font-medium">Last seq</dt>
            <dd id="seqValue" className="text-fg font-mono self-center">{typeof lastIncomingSeq === 'number' ? String(lastIncomingSeq) : '-'}</dd>
            <dt className="text-muted font-medium">Last synced</dt>
            <dd id="lastSyncedValue" className="text-fg self-center">{lastSyncedLabel}</dd>
            <dt className="text-muted font-medium">Mac</dt>
            <dd id="desktopStatusValue" className={cn(
              "self-center font-semibold",
              desktopConnected === true ? "text-success" : desktopConnected === false ? "text-warning" : "text-fg"
            )}>
              {isAuthenticated ? (desktopConnected === false ? 'Offline' : desktopConnected === true ? 'Online' : 'Unknown') : '-'}
            </dd>
          </dl>

          <div className="flex flex-wrap gap-2 mt-2">
            <Button id="reconnectButton" type="button" size="sm" className="flex-1 min-w-[120px]" disabled={reconnectDisabled} onClick={() => client.reconnect()}>
              Reconnect
            </Button>
            <Button id="snapshotButton" type="button" size="sm" className="flex-1 min-w-[120px]" onClick={() => client.requestSnapshot('manual_request')}>
              Request Snapshot
            </Button>
            <Button id="forgetButton" type="button" size="sm" className="flex-1 min-w-[120px] text-danger border-danger/50 bg-danger/10 hover:bg-danger/20" hidden={!hasRememberedDevice} onClick={() => client.forgetRememberedDevice()}>
              Forget Device
            </Button>
          </div>

          <div className="bg-surface-alt rounded-2xl p-4 border border-line mt-2 flex flex-col gap-2">
            <label className="flex items-center justify-between gap-4 text-[15px] font-medium text-fg cursor-pointer" htmlFor="showSystemMessagesToggle">
              <span>Show all system messages</span>
              <input
                id="showSystemMessagesToggle"
                type="checkbox"
                className="w-5 h-5 accent-accent"
                checked={showAllSystemMessages}
                onChange={(event) => client.setShowAllSystemMessages(event.currentTarget.checked)}
              />
            </label>
            <p className="text-xs text-muted leading-relaxed">By default, only user-relevant system notices are shown in transcript.</p>
          </div>

          <p id="statusText" className={cn(
            "text-[13px] text-center font-medium mt-2 leading-relaxed break-words",
            statusLevel === 'error' ? "text-danger" : statusLevel === 'warn' ? "text-warning" : "text-muted"
          )}>
            {connectionStatusText || (isAuthenticated ? (isSyncStale ? 'Connected but stale.' : 'Connected.') : 'Waiting to pair.')}
          </p>
        </Dialog.Content>
      </Dialog.Portal>
    </Dialog.Root>
  );
}
