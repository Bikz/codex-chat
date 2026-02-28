import { describe, expect, it } from 'vitest';
import { parseMessageText } from '@/lib/remote/message-parser';

describe('message parser', () => {
  it('classifies command execution payloads', () => {
    const parsed = parseMessageText(
      "Completed commandExecution:\n{\"command\":\"/bin/zsh -lc 'cat package.json'\",\"durationMs\":52,\"type\":\"commandExecution\"}"
    );

    expect(parsed.mode).toBe('command_execution');
    if (parsed.mode !== 'command_execution') return;
    expect(parsed.status).toBe('completed');
    expect(parsed.command).toContain('/bin/zsh -lc');
    expect(parsed.durationMs).toBe(52);
  });

  it('classifies diff patches from fenced content', () => {
    const parsed = parseMessageText('```diff\n- old\n+ new\n```');
    expect(parsed.mode).toBe('diff_patch');
    if (parsed.mode !== 'diff_patch') return;
    expect(parsed.diff).toContain('+ new');
  });

  it('classifies reasoning summaries', () => {
    const parsed = parseMessageText('Started reasoning:\n{\"summary\":[\"Locating title area\",\"Checking status chip\"]}');
    expect(parsed.mode).toBe('reasoning_summary');
    if (parsed.mode !== 'reasoning_summary') return;
    expect(parsed.status).toBe('started');
    expect(parsed.summary).toContain('Locating title area');
  });

  it('falls back to plain for unknown text', () => {
    const parsed = parseMessageText('A normal assistant reply.');
    expect(parsed.mode).toBe('plain');
  });
});
