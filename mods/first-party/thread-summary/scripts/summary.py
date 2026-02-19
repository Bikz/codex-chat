#!/usr/bin/env python3
import json
from datetime import datetime, timezone
from pathlib import Path

MAX_LINES = 40


def read_input() -> dict:
    line = input().strip()
    return json.loads(line) if line else {}


def summary_file(thread_id: str) -> Path:
    state_dir = Path('.codexchat') / 'state'
    state_dir.mkdir(parents=True, exist_ok=True)
    return state_dir / f'summary-{thread_id}.md'


def read_lines(path: Path) -> list[str]:
    if not path.exists():
        return []
    return [line for line in path.read_text(encoding='utf-8').splitlines() if line.strip()]


def write_lines(path: Path, lines: list[str]) -> None:
    if not lines:
        if path.exists():
            path.unlink()
        return
    trimmed = lines[-MAX_LINES:]
    path.write_text('\n'.join(trimmed) + '\n', encoding='utf-8')


def build_turn_line(payload: dict, event: str) -> str:
    status = payload.get('status', event)
    error = (payload.get('error') or '').strip()
    stamp = datetime.now(timezone.utc).strftime('%H:%M:%S')
    if error:
        snippet = error[:100]
        return f'- {stamp} UTC · {status} · {snippet}'
    return f'- {stamp} UTC · {status}'


def render(lines: list[str]) -> dict:
    markdown = '\n'.join(lines) if lines else '_No turns summarized yet._'
    return {
        'ok': True,
        'modsBar': {
            'title': 'Thread Summary',
            'scope': 'thread',
            'markdown': markdown,
            'actions': [
                {
                    'id': 'summary-clear',
                    'label': 'Clear Timeline',
                    'kind': 'emitEvent',
                    'payload': {
                        'operation': 'clear',
                        'targetHookID': 'summary-action'
                    }
                }
            ]
        }
    }


def main() -> None:
    envelope = read_input()
    event = envelope.get('event', '')
    thread_id = envelope.get('thread', {}).get('id', '')
    if not thread_id:
        print(json.dumps({'ok': False, 'log': 'Missing thread id'}))
        return

    path = summary_file(thread_id)
    lines = read_lines(path)
    action_payload = envelope.get('payload', {}) or {}

    if event in ('turn.completed', 'turn.failed'):
        lines.append(build_turn_line(action_payload, event))
        lines = lines[-MAX_LINES:]
        write_lines(path, lines)
    elif event == 'modsBar.action':
        operation = action_payload.get('operation', '').strip().lower()
        if operation == 'clear':
            lines = []
            write_lines(path, lines)

    print(json.dumps(render(lines)))


if __name__ == '__main__':
    main()
