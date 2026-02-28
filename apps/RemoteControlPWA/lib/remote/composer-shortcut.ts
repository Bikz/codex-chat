export interface ComposerShortcutInput {
  key: string;
  metaKey: boolean;
  ctrlKey: boolean;
}

export function isComposerSendShortcut(input: ComposerShortcutInput): boolean {
  return (input.metaKey || input.ctrlKey) && input.key === 'Enter';
}
