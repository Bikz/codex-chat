'use client';

import { getRemoteClient } from '@/lib/remote/client';
import { useRemoteStore } from '@/lib/remote/store';
import { useShallow } from 'zustand/react/shallow';

export function ApprovalsTray() {
  const client = getRemoteClient();
  const { selectedThreadID, pendingApprovals, canApproveRemotely } = useRemoteStore(
    useShallow((state) => ({
      selectedThreadID: state.selectedThreadID,
      pendingApprovals: state.pendingApprovals,
      canApproveRemotely: state.canApproveRemotely
    }))
  );

  const threadApprovals = pendingApprovals.filter((approval) => approval.threadID === selectedThreadID);
  const globalApprovals = pendingApprovals.filter((approval) => !approval.threadID);
  const allVisibleApprovals = [...threadApprovals, ...globalApprovals];

  return (
    <>
      <div id="approvalGlobalSummary" className="approval-summary-line" hidden={globalApprovals.length === 0}>
        {globalApprovals.length === 1
          ? '1 session approval is pending outside this chat.'
          : `${globalApprovals.length} session approvals are pending outside this chat.`}
      </div>
      <div id="approvalTray" className="approval-tray" hidden={false}>
        {allVisibleApprovals.length === 0 ? (
          <div className="approval-summary-line">No pending approvals.</div>
        ) : (
          allVisibleApprovals.map((approval) => (
            <article key={approval.requestID} className="approval-card">
              <div className="approval-title">#{approval.requestID || '?'}</div>
              <div className="approval-text">{approval.summary || 'Pending approval request'}</div>
              {canApproveRemotely ? (
                <div className="approval-actions">
                  <button className="primary" type="button" onClick={() => client.respondApproval(approval.requestID, 'approve_once')}>
                    Approve once
                  </button>
                  <button type="button" onClick={() => client.respondApproval(approval.requestID, 'approve_for_session')}>
                    Approve session
                  </button>
                  <button type="button" onClick={() => client.respondApproval(approval.requestID, 'decline')}>
                    Decline
                  </button>
                </div>
              ) : null}
            </article>
          ))
        )}
      </div>
    </>
  );
}
