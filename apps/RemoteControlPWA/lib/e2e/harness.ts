'use client';

import type { RemoteSnapshot } from '@/lib/remote/types';
import { getRemoteClient } from '@/lib/remote/client';
import { remoteStoreApi } from '@/lib/remote/store';

declare global {
  interface Window {
    __codexRemotePWAHarness?: {
      seed: (snapshot: RemoteSnapshot, options?: { authenticated?: boolean; expandApprovals?: boolean }) => void;
      openThread: (threadID: string) => void;
      openAccountSheet: () => void;
      closeAccountSheet: () => void;
      setApprovalsExpanded: (expanded: boolean) => void;
      setChatDetached: (detached: boolean) => void;
      importJoinLink: (raw: string) => boolean;
      injectMessage: (message: Record<string, unknown>) => void;
      resetStorage: () => void;
      getState: () => {
        currentView: string;
        selectedProjectFilterID: string;
        selectedThreadID: string | null;
        approvalsExpanded: boolean;
        showAllSystemMessages: boolean;
        isChatAtBottom: boolean;
        showJumpToLatest: boolean;
        queuedCommandsCount: number;
        joinToken: string | null;
      };
    };
  }
}

export function exposeE2EHarness() {
  const client = getRemoteClient();
  const harness = {
    seed(snapshot: RemoteSnapshot, options: { authenticated?: boolean; expandApprovals?: boolean } = {}) {
      if (options.authenticated !== false) {
        remoteStoreApi.setState((state) => ({
          isAuthenticated: true,
          sessionID: state.sessionID || 'e2e-session'
        }));
      }
      client.applySnapshot(snapshot || {});
      if (options.expandApprovals) {
        remoteStoreApi.setState({ approvalsExpanded: true });
      }
    },
    openThread(threadID: string) {
      client.navigateToThread(threadID);
    },
    openAccountSheet() {
      client.openAccountSheet();
    },
    closeAccountSheet() {
      client.closeAccountSheet();
    },
    setApprovalsExpanded(expanded: boolean) {
      remoteStoreApi.setState({ approvalsExpanded: Boolean(expanded) });
    },
    setChatDetached(detached: boolean) {
      remoteStoreApi.setState({
        isChatAtBottom: !detached,
        showJumpToLatest: false,
        userDetachedFromBottomAt: detached ? Date.now() : null
      });
    },
    importJoinLink(raw: string) {
      return client.importJoinLink(raw);
    },
    injectMessage(message: Record<string, unknown>) {
      client.ingestServerMessageForTesting(message);
    },
    resetStorage() {
      client.resetForE2E();
      if (typeof window !== 'undefined' && typeof window.localStorage !== 'undefined') {
        window.localStorage.clear();
      }
    },
    getState() {
      const state = remoteStoreApi.getState();
      return {
        currentView: state.currentView,
        selectedProjectFilterID: state.selectedProjectFilterID,
        selectedThreadID: state.selectedThreadID,
        approvalsExpanded: state.approvalsExpanded,
        showAllSystemMessages: state.showAllSystemMessages,
        isChatAtBottom: state.isChatAtBottom,
        showJumpToLatest: state.showJumpToLatest,
        queuedCommandsCount: state.queuedCommands.length,
        joinToken: state.joinToken
      };
    }
  };

  Object.defineProperty(window, '__codexRemotePWAHarness', {
    value: harness,
    configurable: true
  });
}
