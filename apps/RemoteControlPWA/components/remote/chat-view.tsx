'use client';

import { useEffect, useMemo, useRef } from 'react';
import { ApprovalsTray } from '@/components/remote/approvals-tray';
import { Composer } from '@/components/remote/composer';
import { getRemoteClient } from '@/lib/remote/client';
import { messageIsCollapsible } from '@/lib/remote/selectors';
import { useRemoteStore } from '@/lib/remote/store';
import { useShallow } from 'zustand/react/shallow';

function roleClass(role: string | undefined) {
  if (role === 'user') return 'role-user';
  if (role === 'system') return 'role-system';
  return 'role-assistant';
}

export function ChatView({ hidden }: { hidden: boolean }) {
  const client = getRemoteClient();
  const messageListRef = useRef<HTMLDivElement>(null);

  const {
    selectedThreadID,
    threads,
    messagesByThreadID,
    expandedMessageIDs,
    approvalsExpanded,
    turnStateByThreadID,
    isSyncStale
  } = useRemoteStore(
    useShallow((state) => ({
      selectedThreadID: state.selectedThreadID,
      threads: state.threads,
      messagesByThreadID: state.messagesByThreadID,
      expandedMessageIDs: state.expandedMessageIDs,
      approvalsExpanded: state.approvalsExpanded,
      turnStateByThreadID: state.turnStateByThreadID,
      isSyncStale: state.isSyncStale
    }))
  );

  const thread = useMemo(() => threads.find((item) => item.id === selectedThreadID) || null, [threads, selectedThreadID]);
  const messages = useMemo(() => (selectedThreadID ? messagesByThreadID.get(selectedThreadID) || [] : []), [messagesByThreadID, selectedThreadID]);

  useEffect(() => {
    if (!messageListRef.current) {
      return;
    }
    messageListRef.current.scrollTop = messageListRef.current.scrollHeight;
  }, [messages.length, expandedMessageIDs]);

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
        <div id="messageList" ref={messageListRef} className="messages" aria-live="polite">
          {!selectedThreadID ? <div className="empty-state">Select a chat to view conversation updates.</div> : null}
          {selectedThreadID && messages.length === 0 ? <div className="empty-state">No messages yet.</div> : null}
          {messages.map((message) => {
            const messageID = message.id || `${message.threadID}-${message.createdAt}-${message.role}`;
            const collapsible = messageIsCollapsible(message.text || '');
            const expanded = expandedMessageIDs.has(messageID);
            return (
              <article key={messageID} className={`message ${roleClass(message.role)}`}>
                <div className="message-meta">
                  {(message.role || 'assistant').toLowerCase()} · {new Date(message.createdAt || Date.now()).toLocaleTimeString()}
                </div>
                <div className={`message-body ${collapsible && !expanded ? 'collapsed' : ''}`}>{message.text || ''}</div>
                {collapsible ? (
                  <button className="expand-toggle" type="button" onClick={() => client.toggleMessageExpanded(messageID)}>
                    {expanded ? 'Show less' : 'Show more'}
                  </button>
                ) : null}
              </article>
            );
          })}
        </div>
      </section>

      <Composer />
    </section>
  );
}
