'use client';

import { useState } from 'react';
import { getRemoteClient } from '@/lib/remote/client';
import { useRemoteStore } from '@/lib/remote/store';
import type { RuntimeRequest } from '@/lib/remote/types';
import { useShallow } from 'zustand/react/shallow';
import { Button } from '@/components/ui/button';

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
    <div className="flex flex-col gap-3">
      <div id="approvalGlobalSummary" className="text-sm text-warning font-medium px-1" hidden={globalRuntimeRequests.length === 0}>
        {globalRuntimeRequests.length === 1
          ? '1 runtime request is pending outside this chat.'
          : `${globalRuntimeRequests.length} runtime requests are pending outside this chat.`}
      </div>
      <div id="approvalTray" className="flex flex-col gap-3" hidden={false}>
        {allVisibleRuntimeRequests.length === 0 ? (
          <div className="text-sm text-muted px-1 italic">No pending runtime requests.</div>
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
    </div>
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
    <article className="bg-surface-alt border border-line rounded-2xl p-4 flex flex-col gap-3 shadow-sm">
      <div className="font-bold text-[15px] break-words text-fg">{runtimeRequest.title || `#${runtimeRequest.requestID || '?'}`}</div>
      <div className="text-sm text-muted break-words leading-relaxed">{runtimeRequest.summary || 'Pending runtime request'}</div>

      {runtimeRequest.permissions.length > 0 ? (
        <div className="text-xs text-muted break-words bg-surface rounded-lg p-2 border border-line/50">
          <span className="font-semibold text-fg">Permissions:</span> {runtimeRequest.permissions.join(', ')}
        </div>
      ) : null}

      {showsChoicePicker ? (
        <label className="flex flex-col gap-1.5 mt-1">
          <span className="text-[11px] font-bold uppercase tracking-wider text-muted px-1">Choice</span>
          <select
            className="w-full bg-surface text-fg border border-line rounded-xl px-3 py-2.5 text-sm focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-accent"
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
          {selectedOptionDescription ? <div className="text-xs text-muted px-1">{selectedOptionDescription}</div> : null}
        </label>
      ) : null}

      {showsTextInput ? (
        <label className="flex flex-col gap-1.5 mt-1">
          <span className="text-[11px] font-bold uppercase tracking-wider text-muted px-1">Response</span>
          <textarea
            className="w-full bg-surface text-fg border border-line rounded-xl px-3 py-2.5 text-sm focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-accent resize-y"
            aria-label={`Response for ${runtimeRequest.title || runtimeRequest.requestID}`}
            value={text}
            rows={runtimeRequest.kind === 'mcpElicitation' ? 3 : 4}
            placeholder="Type a response"
            onChange={(event) => setText(event.target.value)}
          />
        </label>
      ) : null}

      {canRespondToRuntimeRequests && runtimeRequest.responseOptions.length > 0 ? (
        <div className="flex flex-wrap gap-2 mt-2">
            {runtimeRequest.responseOptions.map((option, index) => (
              <Button
                key={`${runtimeRequest.requestID}-${option.id}`}
                variant={index === 0 ? 'primary' : 'default'}
                size="sm"
                type="button"
                className="flex-1"
                onClick={() =>
                  onRespond(option.id, {
                    text,
                    optionID: selectedOptionID || null
                  })
                }
              >
                {option.label}
              </Button>
            ))}
        </div>
      ) : null}
    </article>
  );
}
