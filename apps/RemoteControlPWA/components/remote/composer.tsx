'use client';

import { FormEvent, useEffect, useRef, useState } from 'react';
import { getRemoteClient } from '@/lib/remote/client';
import { isComposerSendShortcut } from '@/lib/remote/composer-shortcut';
import { useRemoteStore } from '@/lib/remote/store';
import { useShallow } from 'zustand/react/shallow';
import { Button } from '@/components/ui/button';

const MAX_COMPOSER_HEIGHT = 200;

export function Composer() {
  const client = getRemoteClient();
  const formRef = useRef<HTMLFormElement>(null);
  const textAreaRef = useRef<HTMLTextAreaElement>(null);
  const [value, setValue] = useState('');

  const { selectedThreadID, isComposerDispatching, isAuthenticated, desktopConnected } = useRemoteStore(
    useShallow((state) => ({
      selectedThreadID: state.selectedThreadID,
      isComposerDispatching: state.isComposerDispatching,
      isAuthenticated: state.isAuthenticated,
      desktopConnected: state.desktopConnected
    }))
  );
  const isDesktopOffline = isAuthenticated && desktopConnected === false;
  const canSend = value.trim().length > 0 && Boolean(selectedThreadID) && !isComposerDispatching && !isDesktopOffline;

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
    if (!text || !selectedThreadID || isComposerDispatching || isDesktopOffline) {
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
    <form 
      id="composerForm" 
      ref={formRef} 
      className="bg-surface rounded-[24px] border border-line shadow-sm p-3 flex flex-col gap-2 relative transition-all" 
      aria-label="Send instruction" 
      onSubmit={onSubmit}
    >
      <label htmlFor="composerInput" className="sr-only">
        Message
      </label>
      <div className="flex items-end gap-2">
        <textarea
          id="composerInput"
          ref={textAreaRef}
          className="flex-1 min-w-0 min-h-[44px] max-h-[200px] resize-none bg-surface-alt text-fg rounded-[18px] px-4 py-3 border border-line focus-visible:outline-none focus-visible:border-accent focus-visible:ring-1 focus-visible:ring-accent transition-all text-[15px] leading-relaxed"
          placeholder="Send instruction..."
          rows={1}
          value={value}
          onChange={(event) => setValue(event.target.value)}
          onFocus={() => {
            window.setTimeout(() => {
              textAreaRef.current?.scrollIntoView({ block: 'nearest' });
            }, 120);
          }}
        />
        <Button 
          type="submit" 
          variant="primary" 
          size="icon"
          className="flex-shrink-0 h-[44px] w-[44px] rounded-full self-end shadow-sm" 
          disabled={!canSend} 
          aria-label="Send message"
        >
          {isComposerDispatching ? (
            <span className="w-4 h-4 border-2 border-white/30 border-t-white rounded-full animate-spin" aria-hidden="true" />
          ) : (
            <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><path d="m22 2-7 20-4-9-9-4Z"/><path d="M22 2 11 13"/></svg>
          )}
        </Button>
      </div>
      <div className="flex items-center justify-between px-1">
        <p className="text-[11px] text-muted font-medium tracking-wide">
          {isDesktopOffline ? 'Mac offline. Reconnect desktop to send commands.' : 'Enter for newline. Cmd/Ctrl+Enter sends.'}
        </p>
        {isDesktopOffline ? (
          <Button id="composerReconnectButton" type="button" variant="ghost" size="sm" className="h-6 px-2 text-[11px]" onClick={() => client.reconnect()}>
            Try reconnect
          </Button>
        ) : null}
      </div>
    </form>
  );
}
