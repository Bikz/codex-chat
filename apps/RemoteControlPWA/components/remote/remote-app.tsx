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
import { cn } from '@/lib/utils';
import { Button } from '@/components/ui/button';

export function RemoteControlApp() {
  const client = getRemoteClient();
  useVisualViewportSync();
  useThemeColorMeta();

  const { isAuthenticated, desktopConnected, isSyncStale, currentView, selectedThreadID } = useRemoteStore(
    useShallow((state) => ({
      isAuthenticated: state.isAuthenticated,
      desktopConnected: state.desktopConnected,
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
  const isDesktopOffline = isAuthenticated && desktopConnected === false;
  const badgeText = showConnected ? (isDesktopOffline ? 'Mac offline' : isSyncStale ? 'Stale' : 'Connected') : 'Disconnected';
  const showChatView = currentView === 'thread' && Boolean(selectedThreadID);

  return (
    <>
      <header className="sticky top-0 z-20 flex items-center justify-between gap-3 border-b border-line bg-canvas/85 backdrop-blur-xl pt-[max(0.75rem,var(--safe-top))] pb-3 px-[max(1rem,var(--safe-left))] pr-[max(1rem,var(--safe-right))]">
          <div className="min-w-0 flex-1">
            <h1 className="text-lg font-bold tracking-tight text-fg truncate">Codex Chat Remote</h1>
            <p className="text-[13px] text-muted truncate mt-0.5 [@media(max-height:480px)]:hidden">Control your local Codex Chat session securely.</p>
          </div>
        <button
          id="accountButton"
          className="bg-transparent border-0 p-0 min-w-0 flex-shrink-0 active:scale-95 transition-transform"
          type="button"
          aria-label="Open account and connection controls"
          onClick={() => client.openAccountSheet()}
        >
          <span
            id="connectionBadge"
            className={cn(
              "inline-flex items-center justify-center h-8 px-3 rounded-full text-xs font-semibold whitespace-nowrap border border-line bg-surface-alt text-muted transition-colors",
              showConnected && !isDesktopOffline && !isSyncStale && "text-success border-success bg-success/10",
              showConnected && isSyncStale && "text-warning border-warning bg-warning/10",
              isDesktopOffline && "text-warning border-warning bg-warning/10"
            )}
          >
            {badgeText}
          </span>
        </button>
      </header>

      <main className="w-full max-w-[860px] mx-auto min-h-[calc(var(--vvh)-var(--safe-top))] pt-4 px-[max(1rem,var(--safe-left))] pr-[max(1rem,var(--safe-right))] pb-[calc(1rem+var(--safe-bottom))]" data-testid="app-shell">
        <PreconnectCard />

        <section id="workspacePanel" className="flex flex-col gap-4 min-w-0 max-w-full" hidden={!isAuthenticated}>
          <section id="desktopOfflineBanner" className="flex items-center justify-between gap-3 rounded-2xl bg-warning/10 border border-warning/30 p-3" hidden={!isDesktopOffline}>
            <p className="m-0 text-warning text-sm font-medium">Mac offline. Commands paused.</p>
            <Button id="desktopOfflineReconnectButton" size="sm" type="button" onClick={() => client.reconnect()} className="whitespace-nowrap bg-warning text-white border-warning hover:bg-warning/90">
              Reconnect
            </Button>
          </section>
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
