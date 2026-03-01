'use client';

import { useCallback, useEffect, useMemo, useRef } from 'react';
import { ApprovalsTray } from '@/components/remote/approvals-tray';
import { Composer } from '@/components/remote/composer';
import { CommandCard } from '@/components/remote/message-cards/command-card';
import { DiffCard } from '@/components/remote/message-cards/diff-card';
import { getRemoteClient } from '@/lib/remote/client';
import { parseMessageText } from '@/lib/remote/message-parser';
import { getVisibleMessageWindow, getVisibleTranscriptMessages, messageIsCollapsible } from '@/lib/remote/selectors';
import { remoteStoreApi, useRemoteStore } from '@/lib/remote/store';
import { isNearBottom } from '@/lib/remote/scroll-anchor';
import { useShallow } from 'zustand/react/shallow';

const REVEAL_CHUNK_SIZE = 80;

function roleClass(role: string | undefined) {
  if (role === 'user') return 'role-user';
  return 'role-assistant';
}

export function ChatView({ hidden }: { hidden: boolean }) {
  const client = getRemoteClient();
  const messageListRef = useRef<HTMLDivElement>(null);
  const previousThreadIDRef = useRef<string | null>(null);
  const previousMessageCountRef = useRef(0);
  const revealAnchorRef = useRef<{ scrollTop: number; scrollHeight: number } | null>(null);

  const {
    selectedThreadID,
    threads,
    messagesByThreadID,
    expandedMessageIDs,
    approvalsExpanded,
    turnStateByThreadID,
    isSyncStale,
    visibleMessageLimit,
    isChatAtBottom,
    showJumpToLatest,
    userDetachedFromBottomAt,
    reasoningStateByThreadID,
    reasoningUpdatedAtByThreadID
  } = useRemoteStore(
    useShallow((state) => ({
      selectedThreadID: state.selectedThreadID,
      threads: state.threads,
      messagesByThreadID: state.messagesByThreadID,
      expandedMessageIDs: state.expandedMessageIDs,
      approvalsExpanded: state.approvalsExpanded,
      turnStateByThreadID: state.turnStateByThreadID,
      isSyncStale: state.isSyncStale,
      visibleMessageLimit: state.visibleMessageLimit,
      isChatAtBottom: state.isChatAtBottom,
      showJumpToLatest: state.showJumpToLatest,
      userDetachedFromBottomAt: state.userDetachedFromBottomAt,
      reasoningStateByThreadID: state.reasoningStateByThreadID,
      reasoningUpdatedAtByThreadID: state.reasoningUpdatedAtByThreadID
    }))
  );

  const isChatAtBottomRef = useRef(isChatAtBottom);
  const showJumpToLatestRef = useRef(showJumpToLatest);
  const userDetachedRef = useRef(userDetachedFromBottomAt);

  useEffect(() => {
    isChatAtBottomRef.current = isChatAtBottom;
    showJumpToLatestRef.current = showJumpToLatest;
    userDetachedRef.current = userDetachedFromBottomAt;
  }, [isChatAtBottom, showJumpToLatest, userDetachedFromBottomAt]);

  const thread = useMemo(() => threads.find((item) => item.id === selectedThreadID) || null, [threads, selectedThreadID]);
  const rawMessages = useMemo(() => (selectedThreadID ? messagesByThreadID.get(selectedThreadID) || [] : []), [messagesByThreadID, selectedThreadID]);
  const messages = useMemo(() => getVisibleTranscriptMessages(rawMessages), [rawMessages]);
  const visibleWindow = useMemo(() => getVisibleMessageWindow(messages, visibleMessageLimit), [messages, visibleMessageLimit]);
  const reasoningState = thread ? reasoningStateByThreadID.get(thread.id) || 'idle' : 'idle';
  const reasoningUpdatedAt = thread ? reasoningUpdatedAtByThreadID.get(thread.id) || null : null;

  const scrollToLatest = useCallback((behavior: ScrollBehavior = 'auto') => {
    const list = messageListRef.current;
    if (!list) {
      return;
    }
    list.scrollTo({
      top: list.scrollHeight,
      behavior
    });
  }, []);

  const onMessageScroll = useCallback(() => {
    const list = messageListRef.current;
    if (!list) {
      return;
    }

    const nearBottom = isNearBottom({
      scrollTop: list.scrollTop,
      scrollHeight: list.scrollHeight,
      clientHeight: list.clientHeight
    });

    const patch: Partial<ReturnType<typeof remoteStoreApi.getState>> = {};
    if (nearBottom !== isChatAtBottomRef.current) {
      patch.isChatAtBottom = nearBottom;
    }

    if (nearBottom) {
      if (showJumpToLatestRef.current) {
        patch.showJumpToLatest = false;
      }
      if (userDetachedRef.current !== null) {
        patch.userDetachedFromBottomAt = null;
      }
    } else if (isChatAtBottomRef.current && userDetachedRef.current === null) {
      patch.userDetachedFromBottomAt = Date.now();
    }

    if (Object.keys(patch).length > 0) {
      remoteStoreApi.setState(patch);
    }
  }, []);

  useEffect(() => {
    const list = messageListRef.current;
    const previousThreadID = previousThreadIDRef.current;
    const threadChanged = previousThreadID !== selectedThreadID;
    const messageCountGrew = !threadChanged && messages.length > previousMessageCountRef.current;

    if (threadChanged) {
      previousThreadIDRef.current = selectedThreadID;
      previousMessageCountRef.current = messages.length;
      remoteStoreApi.setState({
        isChatAtBottom: true,
        showJumpToLatest: false,
        userDetachedFromBottomAt: null
      });
      if (list) {
        requestAnimationFrame(() => {
          scrollToLatest('auto');
        });
      }
      return;
    }

    if (messageCountGrew) {
      const currentStoreState = remoteStoreApi.getState();
      if (currentStoreState.isChatAtBottom) {
        requestAnimationFrame(() => {
          scrollToLatest('auto');
        });
        remoteStoreApi.setState({
          isChatAtBottom: true,
          showJumpToLatest: false,
          userDetachedFromBottomAt: null
        });
      } else {
        remoteStoreApi.setState({
          showJumpToLatest: true
        });
      }
    }

    previousMessageCountRef.current = messages.length;
  }, [messages.length, scrollToLatest, selectedThreadID]);

  useEffect(() => {
    const anchor = revealAnchorRef.current;
    if (!anchor) {
      return;
    }

    const list = messageListRef.current;
    if (!list) {
      revealAnchorRef.current = null;
      return;
    }

    const delta = list.scrollHeight - anchor.scrollHeight;
    list.scrollTop = anchor.scrollTop + Math.max(0, delta);
    revealAnchorRef.current = null;
  }, [visibleMessageLimit, visibleWindow.hiddenCount]);

  useEffect(() => {
    if (!isChatAtBottom) {
      return;
    }
    requestAnimationFrame(() => {
      scrollToLatest('auto');
    });
  }, [expandedMessageIDs, isChatAtBottom, scrollToLatest]);

  useEffect(() => {
    if (!thread || reasoningState !== 'completed') {
      return;
    }

    const completedAt = reasoningUpdatedAt || Date.now();
    const elapsed = Date.now() - completedAt;
    const timeoutMs = Math.max(0, 2_500 - elapsed);
    const timer = window.setTimeout(() => {
      const latest = remoteStoreApi.getState();
      const nextStateByThread = new Map(latest.reasoningStateByThreadID);
      const nextUpdatedAtByThread = new Map(latest.reasoningUpdatedAtByThreadID);
      if (nextStateByThread.get(thread.id) === 'completed') {
        nextStateByThread.set(thread.id, 'idle');
        nextUpdatedAtByThread.delete(thread.id);
        remoteStoreApi.setState({
          reasoningStateByThreadID: nextStateByThread,
          reasoningUpdatedAtByThreadID: nextUpdatedAtByThread
        });
      }
    }, timeoutMs);

    return () => window.clearTimeout(timer);
  }, [reasoningState, reasoningUpdatedAt, thread]);

  const isRunning = thread ? turnStateByThreadID.get(thread.id) === true : false;

  return (
    <section id="chatView" className="chat-view" aria-label="Chat detail" hidden={hidden}>
      <div className="chat-topbar">
        <button id="chatBackButton" className="ghost back-button" type="button" aria-label="Back to chats" onClick={() => client.navigateHome()}>
          Back
        </button>
        <h2 id="threadTitle">{thread ? thread.title : 'Thread'}</h2>
        <span id="threadStatusChip" className="thread-status" hidden={!thread || (!isRunning && !isSyncStale)}>
          {isRunning ? 'Running' : 'Sync stale'}
        </span>
      </div>
      <div
        id="reasoningRail"
        className={`reasoning-rail ${reasoningState}`}
        hidden={!thread || reasoningState === 'idle'}
        aria-live="polite"
        aria-label={reasoningState === 'started' ? 'Reasoning in progress' : 'Reasoning completed'}
      >
        {reasoningState === 'started' ? 'Reasoning in progress…' : 'Reasoning complete'}
      </div>

      <section className="panel approvals-panel" aria-labelledby="approvalsHeading">
        <div className="section-head">
          <h3 id="approvalsHeading">Approvals</h3>
          <button
            id="toggleApprovalsButton"
            className="ghost"
            type="button"
            aria-expanded={approvalsExpanded}
            aria-controls="approvalTray"
            onClick={() => client.toggleApprovalsExpanded()}
          >
            {approvalsExpanded ? 'Hide' : 'Show'}
          </button>
        </div>
        <div hidden={!approvalsExpanded}>
          <ApprovalsTray />
        </div>
      </section>

      <section className="panel transcript-panel" aria-label="Transcript">
        <div id="messageList" ref={messageListRef} className="messages" aria-live="polite" onScroll={onMessageScroll}>
          {selectedThreadID && visibleWindow.hiddenCount > 0 ? (
            <button
              id="showOlderMessagesButton"
              type="button"
              className="ghost show-older-button"
              onClick={() => {
                const list = messageListRef.current;
                if (list) {
                  revealAnchorRef.current = {
                    scrollTop: list.scrollTop,
                    scrollHeight: list.scrollHeight
                  };
                }
                remoteStoreApi.setState((state) => ({
                  visibleMessageLimit: Math.min(state.visibleMessageLimit + REVEAL_CHUNK_SIZE, messages.length)
                }));
              }}
            >
              Show older messages ({visibleWindow.hiddenCount})
            </button>
          ) : null}

          {!selectedThreadID ? <div className="empty-state">Select a chat to view conversation updates.</div> : null}
          {selectedThreadID && messages.length === 0 ? <div className="empty-state">No user-visible messages yet.</div> : null}

          {visibleWindow.items.map((message) => {
            const messageID = message.id || `${message.threadID}-${message.createdAt}-${message.role}`;
            const parsedMessage = parseMessageText(message.text || '');
            const longTextCollapsible = messageIsCollapsible(message.text || '');
            if (parsedMessage.mode === 'reasoning_summary') {
              return null;
            }
            const cardCollapsible = parsedMessage.mode === 'command_execution' || parsedMessage.mode === 'diff_patch';
            const shouldShowToggle = cardCollapsible || longTextCollapsible;
            const expanded = expandedMessageIDs.has(messageID);
            const collapsed = shouldShowToggle && !expanded;

            return (
              <article key={messageID} className={`message ${roleClass(message.role)}`}>
                <div className="message-meta">{new Date(message.createdAt || Date.now()).toLocaleTimeString()}</div>

                {parsedMessage.mode === 'plain' ? (
                  <>
                    <div className={`message-body ${collapsed ? 'collapsed' : ''}`}>{message.text || ''}</div>
                    {shouldShowToggle ? (
                      <button className="expand-toggle" type="button" onClick={() => client.toggleMessageExpanded(messageID)}>
                        {expanded ? 'Show less' : 'Show more'}
                      </button>
                    ) : null}
                  </>
                ) : null}

                {parsedMessage.mode === 'command_execution' ? (
                  <CommandCard
                    title="Command execution"
                    status={parsedMessage.status}
                    command={parsedMessage.command}
                    details={parsedMessage.details}
                    durationMs={parsedMessage.durationMs}
                    collapsed={collapsed}
                    onToggle={() => client.toggleMessageExpanded(messageID)}
                  />
                ) : null}

                {parsedMessage.mode === 'diff_patch' ? (
                  <DiffCard
                    title={parsedMessage.title || 'Code diff'}
                    diff={parsedMessage.diff}
                    collapsed={collapsed}
                    onToggle={() => client.toggleMessageExpanded(messageID)}
                  />
                ) : null}
              </article>
            );
          })}
        </div>

        <button
          id="jumpToLatestButton"
          type="button"
          className={`primary jump-to-latest ${showJumpToLatest ? 'visible' : ''}`}
          hidden={!showJumpToLatest}
          onClick={() => {
            scrollToLatest('smooth');
            remoteStoreApi.setState({
              isChatAtBottom: true,
              showJumpToLatest: false,
              userDetachedFromBottomAt: null
            });
          }}
        >
          Jump to latest
        </button>
      </section>

      <Composer />
    </section>
  );
}
