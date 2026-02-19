#!/usr/bin/env python3
import json
from pathlib import Path


def read_input() -> dict:
    line = input().strip()
    return json.loads(line) if line else {}


def notes_file(thread_id: str) -> Path:
    state_dir = Path('.codexchat') / 'state'
    state_dir.mkdir(parents=True, exist_ok=True)
    return state_dir / f'notes-{thread_id}.txt'


def read_note(path: Path) -> str:
    if not path.exists():
        return ''
    return path.read_text(encoding='utf-8').strip()


def write_note(path: Path, text: str) -> None:
    text = text.strip()
    if not text:
        if path.exists():
            path.unlink()
        return
    path.write_text(text + '\n', encoding='utf-8')


def render(note: str) -> dict:
    markdown = note if note else '_No notes yet. Use Add or Edit to save thread-specific notes._'
    return {
        'ok': True,
        'modsBar': {
            'title': 'Personal Notes',
            'scope': 'thread',
            'markdown': markdown,
            'actions': [
                {
                    'id': 'notes-add-edit',
                    'label': 'Add / Edit Note',
                    'kind': 'promptThenEmitEvent',
                    'payload': {
                        'operation': 'upsert',
                        'targetHookID': 'notes-action'
                    },
                    'prompt': {
                        'title': 'Personal Notes',
                        'message': 'Write a note for this thread.',
                        'placeholder': 'Next steps, key commands, reminders...'
                    }
                },
                {
                    'id': 'notes-clear',
                    'label': 'Clear Note',
                    'kind': 'emitEvent',
                    'payload': {
                        'operation': 'clear',
                        'targetHookID': 'notes-action'
                    }
                }
            ]
        }
    }


def main() -> None:
    payload = read_input()
    event = payload.get('event', '')
    thread_id = payload.get('thread', {}).get('id', '')
    if not thread_id:
        print(json.dumps({'ok': False, 'log': 'Missing thread id'}))
        return

    path = notes_file(thread_id)
    action_payload = payload.get('payload', {}) or {}

    if event == 'modsBar.action':
        operation = action_payload.get('operation', '').strip().lower()
        if operation == 'upsert':
            write_note(path, action_payload.get('input', ''))
        elif operation == 'clear':
            write_note(path, '')

    note = read_note(path)
    print(json.dumps(render(note)))


if __name__ == '__main__':
    main()
