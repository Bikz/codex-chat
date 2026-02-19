#!/usr/bin/env python3
import json
import uuid
from pathlib import Path

DEFAULT_PROMPTS = [
    {
        'id': 'ship-checklist',
        'title': 'Ship Checklist',
        'text': 'Run our ship checklist for this branch: tests, docs, release notes, and rollout risks.'
    },
    {
        'id': 'risk-scan',
        'title': 'Risk Scan',
        'text': 'Review this diff for regressions, edge cases, and missing tests. Prioritize high-severity risks first.'
    }
]
MAX_PROMPTS = 12


def read_input() -> dict:
    line = input().strip()
    return json.loads(line) if line else {}


def state_file() -> Path:
    state_dir = Path('.codexchat') / 'state'
    state_dir.mkdir(parents=True, exist_ok=True)
    return state_dir / 'prompt-book.json'


def load_prompts(path: Path) -> list[dict]:
    if not path.exists():
        return DEFAULT_PROMPTS.copy()
    try:
        data = json.loads(path.read_text(encoding='utf-8'))
        prompts = data.get('prompts', [])
        if isinstance(prompts, list):
            normalized = []
            for item in prompts:
                title = str(item.get('title', '')).strip()
                text = str(item.get('text', '')).strip()
                if not text:
                    continue
                normalized.append({
                    'id': str(item.get('id') or uuid.uuid4()),
                    'title': title or text[:28],
                    'text': text,
                })
            return normalized[:MAX_PROMPTS] if normalized else DEFAULT_PROMPTS.copy()
    except Exception:
        pass
    return DEFAULT_PROMPTS.copy()


def save_prompts(path: Path, prompts: list[dict]) -> None:
    payload = {'prompts': prompts[:MAX_PROMPTS]}
    path.write_text(json.dumps(payload, indent=2, sort_keys=True) + '\n', encoding='utf-8')


def parse_prompt_input(raw: str) -> tuple[str, str]:
    text = (raw or '').strip()
    if '::' in text:
        title, body = text.split('::', 1)
        title = title.strip()
        body = body.strip()
        if body:
            return (title or body[:28], body)
    return (text[:28] if text else 'Prompt', text)


def apply_action(prompts: list[dict], payload: dict) -> list[dict]:
    operation = str(payload.get('operation', '')).strip().lower()
    input_text = str(payload.get('input', '')).strip()
    index_text = str(payload.get('index', '')).strip()

    if operation == 'add' and input_text:
        title, body = parse_prompt_input(input_text)
        if body:
            prompts.append({'id': str(uuid.uuid4()), 'title': title, 'text': body})
            return prompts[:MAX_PROMPTS]

    if operation == 'edit' and input_text and index_text.isdigit():
        index = int(index_text)
        if 0 <= index < len(prompts):
            title, body = parse_prompt_input(input_text)
            if body:
                prompts[index]['title'] = title
                prompts[index]['text'] = body

    if operation == 'delete' and index_text.isdigit():
        index = int(index_text)
        if 0 <= index < len(prompts):
            del prompts[index]

    return prompts[:MAX_PROMPTS]


def render_markdown(prompts: list[dict]) -> str:
    if not prompts:
        return '_No prompts saved yet. Use Add Prompt._'
    lines = ['Saved prompts:']
    for i, prompt in enumerate(prompts, start=1):
        title = prompt['title'].strip() or f'Prompt {i}'
        text = prompt['text'].strip()
        preview = text if len(text) <= 120 else text[:117] + '...'
        lines.append(f'- {i}. **{title}** - {preview}')
    return '\n'.join(lines)


def render_actions(prompts: list[dict]) -> list[dict]:
    actions = [
        {
            'id': 'prompt-add',
            'label': 'Add Prompt',
            'kind': 'promptThenEmitEvent',
            'payload': {
                'operation': 'add',
                'targetHookID': 'prompt-book-action'
            },
            'prompt': {
                'title': 'Add Prompt',
                'message': 'Use `Title :: Prompt` or just a prompt body.',
                'placeholder': 'Ship Checklist :: Run release checks for this branch.'
            }
        }
    ]

    for index, prompt in enumerate(prompts):
        label = prompt['title'].strip() or f'Prompt {index + 1}'
        actions.append({
            'id': f'send-{index}',
            'label': f'Send: {label}',
            'kind': 'composer.insertAndSend',
            'payload': {'text': prompt['text']}
        })
        actions.append({
            'id': f'edit-{index}',
            'label': f'Edit: {label}',
            'kind': 'promptThenEmitEvent',
            'payload': {
                'operation': 'edit',
                'index': str(index),
                'targetHookID': 'prompt-book-action'
            },
            'prompt': {
                'title': f'Edit {label}',
                'message': 'Use `Title :: Prompt` or just a prompt body.',
                'placeholder': 'Title :: Updated prompt',
                'initialValue': f"{label} :: {prompt['text']}",
                'submitLabel': 'Save'
            }
        })
        actions.append({
            'id': f'delete-{index}',
            'label': f'Delete: {label}',
            'kind': 'emitEvent',
            'payload': {
                'operation': 'delete',
                'index': str(index),
                'targetHookID': 'prompt-book-action'
            }
        })

    return actions[:36]


def main() -> None:
    envelope = read_input()
    path = state_file()
    prompts = load_prompts(path)

    if envelope.get('event') == 'modsBar.action':
        prompts = apply_action(prompts, envelope.get('payload', {}) or {})
        save_prompts(path, prompts)
    elif not path.exists():
        save_prompts(path, prompts)

    output = {
        'ok': True,
        'modsBar': {
            'title': 'Prompt Book',
            'scope': 'global',
            'markdown': render_markdown(prompts),
            'actions': render_actions(prompts)
        }
    }
    print(json.dumps(output))


if __name__ == '__main__':
    main()
