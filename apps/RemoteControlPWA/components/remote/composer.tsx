'use client';

import { FormEvent, useRef } from 'react';
import { getRemoteClient } from '@/lib/remote/client';

export function Composer() {
  const client = getRemoteClient();
  const textAreaRef = useRef<HTMLTextAreaElement>(null);

  const onSubmit = (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    const text = textAreaRef.current?.value.trim() || '';
    if (!text) {
      return;
    }

    const sent = client.sendComposerMessage(text);
    if (!sent) {
      return;
    }

    if (textAreaRef.current) {
      textAreaRef.current.value = '';
    }
  };

  return (
    <form id="composerForm" className="composer panel" aria-label="Send instruction" onSubmit={onSubmit}>
      <label htmlFor="composerInput" className="sr-only">
        Message
      </label>
      <textarea
        id="composerInput"
        ref={textAreaRef}
        placeholder="Send instruction to Codex Chat"
        rows={3}
        onFocus={() => {
          window.setTimeout(() => {
            textAreaRef.current?.scrollIntoView({ block: 'nearest' });
          }, 120);
        }}
      />
      <button type="submit" className="primary">
        Send
      </button>
    </form>
  );
}
