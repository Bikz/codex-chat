'use client';

import { getRemoteClient } from '@/lib/remote/client';
import { getUserVisibleThreadPreview, getVisibleThreads, pendingRuntimeRequestsByThread } from '@/lib/remote/selectors';
import { useRemoteStore } from '@/lib/remote/store';
import { useShallow } from 'zustand/react/shallow';
import { cn } from '@/lib/utils';

export function ChatList() {
  const client = getRemoteClient();
  const { threads, projects, selectedProjectFilterID, selectedThreadID, pendingRuntimeRequests, turnStateByThreadID, unreadByThreadID, messagesByThreadID } =
    useRemoteStore(
      useShallow((state) => ({
        threads: state.threads,
        projects: state.projects,
        selectedProjectFilterID: state.selectedProjectFilterID,
        selectedThreadID: state.selectedThreadID,
        pendingRuntimeRequests: state.pendingRuntimeRequests,
        turnStateByThreadID: state.turnStateByThreadID,
        unreadByThreadID: state.unreadByThreadID,
        messagesByThreadID: state.messagesByThreadID
      }))
    );

  const visibleThreads = getVisibleThreads(threads, selectedProjectFilterID);
  const runtimeRequestsByThread = pendingRuntimeRequestsByThread(pendingRuntimeRequests);

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
      <div id="chatListEmpty" className="mt-2 rounded-xl border border-dashed border-line text-muted p-6 text-center text-sm" hidden={!emptyMessage}>
        {emptyMessage}
      </div>
      <ul id="chatList" className="mt-2 flex flex-col gap-2" aria-label="Chats" hidden={Boolean(emptyMessage)}>
        {visibleThreads.map((thread) => {
          const running = turnStateByThreadID.get(thread.id) === true;
          const runtimeRequests = runtimeRequestsByThread.get(thread.id) || 0;
          const hasUnread = unreadByThreadID.get(thread.id) === true && thread.id !== selectedThreadID;
          const previewText = getUserVisibleThreadPreview(messagesByThreadID.get(thread.id) || []);

          return (
            <li key={thread.id}>
              <button
                type="button"
                className={cn(
                  "chat-row w-full text-left p-3 rounded-2xl min-w-0 flex flex-col gap-1 active:scale-[0.98] transition-all",
                  "bg-surface-alt hover:bg-surface-subtle border focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-accent",
                  thread.id === selectedThreadID ? "border-accent shadow-sm" : "border-transparent"
                )}
                aria-label={`Open chat ${thread.title}`}
                onClick={() => client.navigateToThread(thread.id)}
              >
                <div className="flex items-center justify-between gap-2 w-full">
                  <span className="font-semibold text-[15px] truncate text-fg flex-1">{thread.title}</span>
                  <div className="flex items-center gap-1.5 flex-shrink-0">
                    {running ? <span className="inline-flex items-center h-5 px-2 text-[10px] font-bold uppercase tracking-wider text-success bg-success/10 rounded-full">Running</span> : null}
                    {runtimeRequests > 0 ? (
                      <span className="inline-flex items-center h-5 px-2 text-[10px] font-bold uppercase tracking-wider text-danger bg-danger/10 rounded-full">{runtimeRequests === 1 ? '1 request' : `${runtimeRequests} requests`}</span>
                    ) : null}
                    {hasUnread ? <div className="w-2.5 h-2.5 bg-accent rounded-full shadow-[0_0_8px_rgba(10,132,255,0.6)]"></div> : null}
                  </div>
                </div>
                <div className="chat-preview text-[13px] text-muted line-clamp-1 leading-snug">{previewText || "Say hello..."}</div>
              </button>
            </li>
          );
        })}
      </ul>
    </>
  );
}
