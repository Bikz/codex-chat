'use client';

import { useEffect } from 'react';
import { AccountSheet } from '@/components/remote/account-sheet';
import { ChatView } from '@/components/remote/chat-view';
import { HomeView } from '@/components/remote/home-view';
import { PreconnectCard } from '@/components/remote/preconnect-card';
import { ProjectSheet } from '@/components/remote/project-sheet';
import { QRScannerSheet } from '@/components/remote/qr-scanner-sheet';
import { exposeE2EHarness } from '@/lib/e2e/harness';
import { useVisualViewportSync } from '@/lib/mobile/visual-viewport';
import { getRemoteClient } from '@/lib/remote/client';
import { useRemoteStore } from '@/lib/remote/store';
import { useThemeColorMeta } from '@/lib/theme/theme-color';
import { useShallow } from 'zustand/react/shallow';

export function RemoteControlApp() {
  const client = getRemoteClient();
  useVisualViewportSync();
  useThemeColorMeta();

  const { isAuthenticated, isSyncStale, currentView, selectedThreadID } = useRemoteStore(
    useShallow((state) => ({
      isAuthenticated: state.isAuthenticated,
      isSyncStale: state.isSyncStale,
      currentView: state.currentView,
      selectedThreadID: state.selectedThreadID
    }))
  );

  useEffect(() => {
    client.init();
    exposeE2EHarness();
    return () => client.destroy();
  }, [client]);

  const showConnected = isAuthenticated;
  const badgeText = showConnected ? (isSyncStale ? 'Stale' : 'Connected') : 'Disconnected';
  const showChatView = currentView === 'thread' && Boolean(selectedThreadID);

  return (
    <>
      <header className="topbar">
        <div className="title-wrap">
          <h1>Codex Chat Remote</h1>
          <p className="subtitle">Control your local Codex Chat session securely.</p>
        </div>
        <button
          id="accountButton"
          className="connection-button"
          type="button"
          aria-label="Open account and connection controls"
          onClick={() => client.openAccountSheet()}
        >
          <span id="connectionBadge" className={`badge ${showConnected ? 'connected' : ''} ${showConnected && isSyncStale ? 'stale' : ''}`}>
            {badgeText}
          </span>
        </button>
      </header>

      <main className="app-main" data-testid="app-shell">
        <PreconnectCard />

        <section id="workspacePanel" className="workspace" hidden={!isAuthenticated}>
          <HomeView hidden={showChatView} />
          <ChatView hidden={!showChatView} />
        </section>
      </main>

      <ProjectSheet />
      <AccountSheet />
      <QRScannerSheet />
    </>
  );
}
