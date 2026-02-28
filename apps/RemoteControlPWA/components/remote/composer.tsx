'use client';

import { FormEvent, useEffect, useRef, useState } from 'react';
import { getRemoteClient } from '@/lib/remote/client';
import { isComposerSendShortcut } from '@/lib/remote/composer-shortcut';
import { useRemoteStore } from '@/lib/remote/store';
import { useShallow } from 'zustand/react/shallow';

const MAX_COMPOSER_HEIGHT = 200;

export function Composer() {
  const client = getRemoteClient();
  const formRef = useRef<HTMLFormElement>(null);
  const textAreaRef = useRef<HTMLTextAreaElement>(null);
  const [value, setValue] = useState('');

  const { selectedThreadID, isComposerDispatching } = useRemoteStore(
    useShallow((state) => ({
      selectedThreadID: state.selectedThreadID,
      isComposerDispatching: state.isComposerDispatching
    }))
  );

  const canSend = value.trim().length > 0 && Boolean(selectedThreadID) && !isComposerDispatching;

  const syncTextAreaHeight = () => {
    const textArea = textAreaRef.current;
    if (!textArea) {
      return;
    }

    textArea.style.height = 'auto';
    const nextHeight = Math.min(MAX_COMPOSER_HEIGHT, Math.max(44, textArea.scrollHeight));
    textArea.style.height = `${nextHeight}px`;
    textArea.style.overflowY = textArea.scrollHeight > MAX_COMPOSER_HEIGHT ? 'auto' : 'hidden';
  };

  useEffect(() => {
    syncTextAreaHeight();
  }, [value]);

  const onSubmit = (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    const text = value.trim();
    if (!text || !selectedThreadID || isComposerDispatching) {
      return;
    }

    const sent = client.sendComposerMessage(text);
    if (!sent) {
      return;
    }

    setValue('');
    requestAnimationFrame(() => {
      syncTextAreaHeight();
    });
  };

  useEffect(() => {
    const textArea = textAreaRef.current;
    if (!textArea) {
      return;
    }

    const onKeyDown = (event: KeyboardEvent) => {
      if (!isComposerSendShortcut({ key: event.key, metaKey: event.metaKey, ctrlKey: event.ctrlKey })) {
        return;
      }
      event.preventDefault();
      formRef.current?.requestSubmit();
    };

    textArea.addEventListener('keydown', onKeyDown);
    return () => {
      textArea.removeEventListener('keydown', onKeyDown);
    };
  }, []);

  return (
    <form id="composerForm" ref={formRef} className="composer panel" aria-label="Send instruction" onSubmit={onSubmit}>
      <label htmlFor="composerInput" className="sr-only">
        Message
      </label>
      <div className="composer-row">
        <textarea
          id="composerInput"
          ref={textAreaRef}
          className="composer-input"
          placeholder="Send instruction to Codex Chat"
          rows={1}
          value={value}
          onChange={(event) => setValue(event.target.value)}
          onFocus={() => {
            window.setTimeout(() => {
              textAreaRef.current?.scrollIntoView({ block: 'nearest' });
            }, 120);
          }}
        />
        <button type="submit" className="primary composer-send" disabled={!canSend} aria-label="Send message">
          {isComposerDispatching ? (
            <span className="sending-indicator">
              <span className="spinner" aria-hidden="true" />
              Sending
            </span>
          ) : (
            'Send'
          )}
        </button>
      </div>
      <p className="composer-hint">Enter for newline. Cmd/Ctrl+Enter sends.</p>
    </form>
  );
}
