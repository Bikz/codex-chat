'use client';

import { getRemoteClient } from '@/lib/remote/client';
import { getUserVisibleThreadPreview, getVisibleThreads, pendingApprovalsByThread } from '@/lib/remote/selectors';
import { useRemoteStore } from '@/lib/remote/store';
import { useShallow } from 'zustand/react/shallow';

export function ChatList() {
  const client = getRemoteClient();
  const { threads, projects, selectedProjectFilterID, selectedThreadID, pendingApprovals, turnStateByThreadID, unreadByThreadID, messagesByThreadID } =
    useRemoteStore(
      useShallow((state) => ({
        threads: state.threads,
        projects: state.projects,
        selectedProjectFilterID: state.selectedProjectFilterID,
        selectedThreadID: state.selectedThreadID,
        pendingApprovals: state.pendingApprovals,
        turnStateByThreadID: state.turnStateByThreadID,
        unreadByThreadID: state.unreadByThreadID,
        messagesByThreadID: state.messagesByThreadID
      }))
    );

  const visibleThreads = getVisibleThreads(threads, selectedProjectFilterID);
  const approvalsByThread = pendingApprovalsByThread(pendingApprovals);

  let emptyMessage = '';
  if (threads.length === 0 && projects.length === 0) {
    emptyMessage = 'No projects yet';
  } else if (threads.length === 0) {
    emptyMessage = 'No chats yet';
  } else if (visibleThreads.length === 0 && selectedProjectFilterID !== 'all') {
    emptyMessage = 'No chats in this project';
  }

  return (
    <>
      <div id="chatListEmpty" className="empty-state" hidden={!emptyMessage}>
        {emptyMessage}
      </div>
      <ul id="chatList" className="chat-list" aria-label="Chats" hidden={Boolean(emptyMessage)}>
        {visibleThreads.map((thread) => {
          const running = turnStateByThreadID.get(thread.id) === true;
          const approvals = approvalsByThread.get(thread.id) || 0;
          const hasUnread = unreadByThreadID.get(thread.id) === true && thread.id !== selectedThreadID;
          const previewText = getUserVisibleThreadPreview(messagesByThreadID.get(thread.id) || []);

          return (
            <li key={thread.id}>
              <button
                type="button"
                className={`chat-row ${thread.id === selectedThreadID ? 'active' : ''}`}
                aria-label={`Open chat ${thread.title}`}
                onClick={() => client.navigateToThread(thread.id)}
              >
                <div className="chat-main">
                  <span className="chat-title">{thread.title}</span>
                  <span className="chat-badges">
                    {running ? <span className="mini-badge running">Running</span> : null}
                    {approvals > 0 ? <span className="mini-badge approval">{approvals === 1 ? '1 approval' : `${approvals} approvals`}</span> : null}
                    {hasUnread ? <span className="mini-badge unread">New</span> : null}
                  </span>
                </div>
                <div className="chat-preview">{previewText}</div>
              </button>
            </li>
          );
        })}
      </ul>
    </>
  );
}
