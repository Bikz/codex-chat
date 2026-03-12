'use client';

import { useState } from 'react';
import { getRemoteClient } from '@/lib/remote/client';
import { useRemoteStore } from '@/lib/remote/store';
import type { RuntimeRequest } from '@/lib/remote/types';
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
            <RuntimeRequestCard
              key={runtimeRequest.requestID}
              runtimeRequest={runtimeRequest}
              canRespondToRuntimeRequests={canRespondToRuntimeRequests}
              onRespond={(responseOptionID, draft) =>
                client.respondToRuntimeRequest(runtimeRequest, responseOptionID, draft)
              }
            />
          ))
        )}
      </div>
    </>
  );
}

function RuntimeRequestCard({
  runtimeRequest,
  canRespondToRuntimeRequests,
  onRespond
}: {
  runtimeRequest: RuntimeRequest;
  canRespondToRuntimeRequests: boolean;
  onRespond: (responseOptionID: string, draft?: { text?: string | null; optionID?: string | null }) => void;
}) {
  const [text, setText] = useState('');
  const [selectedOptionID, setSelectedOptionID] = useState<string>(runtimeRequest.options[0]?.id ?? '');

  const showsChoicePicker = runtimeRequest.kind === 'userInput' && runtimeRequest.options.length > 0;
  const showsTextInput = runtimeRequest.kind === 'userInput' || runtimeRequest.kind === 'mcpElicitation';
  const selectedOptionDescription =
    runtimeRequest.options.find((option) => option.id === selectedOptionID)?.description ?? null;

  return (
    <article className="approval-card">
      <div className="approval-title">{runtimeRequest.title || `#${runtimeRequest.requestID || '?'}`}</div>
      <div className="approval-text">{runtimeRequest.summary || 'Pending runtime request'}</div>

      {runtimeRequest.permissions.length > 0 ? (
        <div className="approval-meta">
          Permissions: {runtimeRequest.permissions.join(', ')}
        </div>
      ) : null}

      {showsChoicePicker ? (
        <label className="approval-field">
          <span className="approval-field-label">Choice</span>
          <select
            className="approval-select"
            aria-label={`Choice for ${runtimeRequest.title || runtimeRequest.requestID}`}
            value={selectedOptionID}
            onChange={(event) => setSelectedOptionID(event.target.value)}
          >
            <option value="">No preset choice</option>
            {runtimeRequest.options.map((option) => (
              <option key={option.id} value={option.id}>
                {option.label}
              </option>
            ))}
          </select>
          {selectedOptionDescription ? <div className="approval-meta">{selectedOptionDescription}</div> : null}
        </label>
      ) : null}

      {showsTextInput ? (
        <label className="approval-field">
          <span className="approval-field-label">Response</span>
          <textarea
            className="approval-input"
            aria-label={`Response for ${runtimeRequest.title || runtimeRequest.requestID}`}
            value={text}
            rows={runtimeRequest.kind === 'mcpElicitation' ? 3 : 4}
            placeholder="Type a response"
            onChange={(event) => setText(event.target.value)}
          />
        </label>
      ) : null}

      {canRespondToRuntimeRequests && runtimeRequest.responseOptions.length > 0 ? (
        <div className="approval-actions">
          {runtimeRequest.responseOptions.map((option, index) => (
            <button
              key={`${runtimeRequest.requestID}-${option.id}`}
              className={index === 0 ? 'primary' : undefined}
              type="button"
              onClick={() =>
                onRespond(option.id, {
                  text,
                  optionID: selectedOptionID || null
                })
              }
            >
              {option.label}
            </button>
          ))}
        </div>
      ) : null}
    </article>
  );
}
