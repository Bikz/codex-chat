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
import { cn } from '@/lib/utils';
import { Button } from '@/components/ui/button';

const REVEAL_CHUNK_SIZE = 80;

function roleClass(role: string | undefined) {
  if (role === 'user') return 'justify-self-end bg-accent text-accent-fg rounded-[20px] rounded-br-sm border-0';
  return 'justify-self-start bg-surface-alt text-fg rounded-[20px] rounded-bl-sm border border-line shadow-sm';
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
    runtimeRequestsExpanded,
    turnStateByThreadID,
    isSyncStale,
    visibleMessageLimit,
    isChatAtBottom,
    showJumpToLatest,
    userDetachedFromBottomAt,
    reasoningStateByThreadID,
    reasoningUpdatedAtByThreadID,
    showAllSystemMessages
  } = useRemoteStore(
    useShallow((state) => ({
      selectedThreadID: state.selectedThreadID,
      threads: state.threads,
      messagesByThreadID: state.messagesByThreadID,
      expandedMessageIDs: state.expandedMessageIDs,
      runtimeRequestsExpanded: state.runtimeRequestsExpanded,
      turnStateByThreadID: state.turnStateByThreadID,
      isSyncStale: state.isSyncStale,
      visibleMessageLimit: state.visibleMessageLimit,
      isChatAtBottom: state.isChatAtBottom,
      showJumpToLatest: state.showJumpToLatest,
      userDetachedFromBottomAt: state.userDetachedFromBottomAt,
      reasoningStateByThreadID: state.reasoningStateByThreadID,
      reasoningUpdatedAtByThreadID: state.reasoningUpdatedAtByThreadID,
      showAllSystemMessages: state.showAllSystemMessages
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
  const messages = useMemo(
    () => getVisibleTranscriptMessages(rawMessages, { showAllSystemMessages }),
    [rawMessages, showAllSystemMessages]
  );
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
    <section 
      id="chatView" 
      className="flex flex-col min-h-[calc(var(--vvh)-10.5rem-var(--safe-top))] md:min-h-[calc(var(--vvh)-8.5rem-var(--safe-top))] w-full max-w-[760px] mx-auto gap-3 h-full relative" 
      aria-label="Chat detail" 
      hidden={hidden}
    >
      <div className="flex items-center justify-between gap-3 min-w-0">
        <Button id="chatBackButton" variant="ghost" size="sm" type="button" aria-label="Back to chats" onClick={() => client.navigateHome()}>
          <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" className="mr-1"><path d="m15 18-6-6 6-6"/></svg>
          Back
        </Button>
        <h2 id="threadTitle" className="flex-1 font-semibold text-[15px] text-center truncate text-fg">
          {thread ? thread.title : 'Thread'}
        </h2>
        <span id="threadStatusChip" className="inline-flex items-center justify-center h-7 px-3 rounded-full text-[11px] font-bold uppercase tracking-wider bg-surface-alt border border-line text-muted" hidden={!thread || (!isRunning && !isSyncStale)}>
          {isRunning ? 'Running' : 'Sync stale'}
        </span>
      </div>

      <div
        id="reasoningRail"
        className={cn(
          "min-h-[30px] rounded-full px-4 inline-flex items-center text-xs font-medium border w-fit mx-auto transition-colors",
          reasoningState === 'started' ? "border-warning/50 bg-warning/10 text-warning" : "border-success/50 bg-success/10 text-success"
        )}
        hidden={!thread || reasoningState === 'idle'}
        aria-live="polite"
        aria-label={reasoningState === 'started' ? 'Reasoning in progress' : 'Reasoning completed'}
      >
        {reasoningState === 'started' ? 'Reasoning in progress…' : 'Reasoning complete'}
      </div>

      <section className="bg-surface rounded-[24px] border border-line shadow-sm p-4 flex flex-col gap-3" aria-labelledby="approvalsHeading">
        <div className="flex items-center justify-between">
          <h3 id="approvalsHeading" className="text-[13px] uppercase tracking-wider font-bold text-muted px-1">Runtime requests</h3>
          <Button
            id="toggleApprovalsButton"
            variant="ghost"
            size="sm"
            type="button"
            aria-expanded={runtimeRequestsExpanded}
            aria-controls="approvalTray"
            onClick={() => client.toggleApprovalsExpanded()}
          >
            {runtimeRequestsExpanded ? 'Hide' : 'Show'}
          </Button>
        </div>
        <div hidden={!runtimeRequestsExpanded}>
          <ApprovalsTray />
        </div>
      </section>

      <section className="bg-surface rounded-[24px] border border-line shadow-sm overflow-hidden flex-1 relative min-h-0 flex flex-col" aria-label="Transcript">
        <div id="messageList" ref={messageListRef} className="flex-1 overflow-y-auto overflow-x-hidden p-4 flex flex-col gap-3 min-h-[min(40svh,360px)] relative" aria-live="polite" onScroll={onMessageScroll}>
          {selectedThreadID && visibleWindow.hiddenCount > 0 ? (
            <Button
              id="showOlderMessagesButton"
              variant="default"
              size="sm"
              className="sticky top-0 z-10 self-center mx-auto mb-2 shadow-sm rounded-full backdrop-blur-xl bg-surface/80"
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
            </Button>
          ) : null}

          {!selectedThreadID ? <div className="my-8 rounded-xl border border-dashed border-line text-muted p-6 text-center text-sm">Select a chat to view conversation updates.</div> : null}
          {selectedThreadID && messages.length === 0 ? <div className="my-8 rounded-xl border border-dashed border-line text-muted p-6 text-center text-sm">No messages yet.</div> : null}

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
            const isUser = message.role === 'user';

            return (
              <article key={messageID} className={cn("message max-w-[88%] w-fit flex flex-col gap-1 p-3.5", roleClass(message.role))}>
                <div className={cn("text-[10px] font-medium tracking-wide uppercase opacity-70", isUser ? "text-accent-fg/70" : "text-muted")}>
                  {new Date(message.createdAt || Date.now()).toLocaleTimeString([], {hour: '2-digit', minute:'2-digit'})}
                </div>

                {parsedMessage.mode === 'plain' ? (
                  <>
                    <div className={cn("message-body whitespace-pre-wrap break-words leading-relaxed text-[15px]", collapsed && "line-clamp-6")}>
                      {message.text || ''}
                    </div>
                    {shouldShowToggle ? (
                      <button className={cn("text-xs font-semibold self-start mt-1 hover:underline", isUser ? "text-accent-fg/90" : "text-accent")} type="button" onClick={() => client.toggleMessageExpanded(messageID)}>
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

        <Button
          id="jumpToLatestButton"
          variant="primary"
          size="sm"
          className={cn(
            "absolute right-4 bottom-4 z-10 rounded-full shadow-md transition-all duration-200",
            showJumpToLatest ? "opacity-100 translate-y-0" : "opacity-0 translate-y-2 pointer-events-none"
          )}
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
        </Button>
      </section>

      <div className="sticky bottom-0 pb-[max(0.5rem,calc(0.5rem+var(--safe-bottom)))] bg-canvas/90 backdrop-blur-md pt-2">
        <Composer />
      </div>
    </section>
  );
}
