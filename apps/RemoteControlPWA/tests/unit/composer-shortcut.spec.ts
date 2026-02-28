import { describe, expect, it } from 'vitest';
import { isComposerSendShortcut } from '@/lib/remote/composer-shortcut';

describe('composer shortcut', () => {
  it('matches Ctrl+Enter and Cmd+Enter', () => {
    expect(isComposerSendShortcut({ key: 'Enter', ctrlKey: true, metaKey: false })).toBe(true);
    expect(isComposerSendShortcut({ key: 'Enter', ctrlKey: false, metaKey: true })).toBe(true);
  });

  it('does not match plain Enter or non-enter keys', () => {
    expect(isComposerSendShortcut({ key: 'Enter', ctrlKey: false, metaKey: false })).toBe(false);
    expect(isComposerSendShortcut({ key: 'a', ctrlKey: true, metaKey: false })).toBe(false);
  });
});
