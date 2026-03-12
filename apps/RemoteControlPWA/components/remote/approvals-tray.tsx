'use client';

import { getRemoteClient } from '@/lib/remote/client';
import { useRemoteStore } from '@/lib/remote/store';
import { useShallow } from 'zustand/react/shallow';

export function ApprovalsTray() {
  const client = getRemoteClient();
  const { selectedThreadID, pendingRuntimeRequests, canRespondToRuntimeRequests } = useRemoteStore(
    useShallow((state) => ({
      selectedThreadID: state.selectedThreadID,
      pendingRuntimeRequests: state.pendingRuntimeRequests,
      canRespondToRuntimeRequests: state.canRespondToRuntimeRequests
    }))
  );

  const threadRuntimeRequests = pendingRuntimeRequests.filter((runtimeRequest) => runtimeRequest.threadID === selectedThreadID);
  const globalRuntimeRequests = pendingRuntimeRequests.filter((runtimeRequest) => !runtimeRequest.threadID);
  const allVisibleRuntimeRequests = [...threadRuntimeRequests, ...globalRuntimeRequests];

  return (
    <>
      <div id="approvalGlobalSummary" className="approval-summary-line" hidden={globalRuntimeRequests.length === 0}>
        {globalRuntimeRequests.length === 1
          ? '1 runtime request is pending outside this chat.'
          : `${globalRuntimeRequests.length} runtime requests are pending outside this chat.`}
      </div>
      <div id="approvalTray" className="approval-tray" hidden={false}>
        {allVisibleRuntimeRequests.length === 0 ? (
          <div className="approval-summary-line">No pending runtime requests.</div>
        ) : (
          allVisibleRuntimeRequests.map((runtimeRequest) => (
            <article key={runtimeRequest.requestID} className="approval-card">
              <div className="approval-title">{runtimeRequest.title || `#${runtimeRequest.requestID || '?'}`}</div>
              <div className="approval-text">{runtimeRequest.summary || 'Pending runtime request'}</div>
              {canRespondToRuntimeRequests && runtimeRequest.responseOptions.length > 0 ? (
                <div className="approval-actions">
                  {runtimeRequest.responseOptions.map((option, index) => (
                    <button
                      key={`${runtimeRequest.requestID}-${option.id}`}
                      className={index === 0 ? 'primary' : undefined}
                      type="button"
                      onClick={() => client.respondToRuntimeRequest(runtimeRequest, option.id)}
                    >
                      {option.label}
                    </button>
                  ))}
                </div>
              ) : null}
            </article>
          ))
        )}
      </div>
    </>
  );
}
