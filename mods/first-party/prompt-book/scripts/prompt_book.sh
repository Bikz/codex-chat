#!/bin/sh
set -eu

input_file="$(mktemp "${TMPDIR:-/tmp}/codexchat-prompt-book-input.XXXXXX")"

cleanup() {
  rm -f "$input_file"
}
trap cleanup EXIT

cat > "$input_file"

extract_raw() {
  /usr/bin/plutil -extract "$1" raw -o - "$input_file" 2>/dev/null || true
}

state_dir=".codexchat/state"
mkdir -p "$state_dir"
state_file="$state_dir/prompt-book.json"

event="$(extract_raw event)"
operation="$(extract_raw payload.operation)"
input_text="$(extract_raw payload.input)"
index_text="$(extract_raw payload.index)"

EVENT="$event" \
OPERATION="$operation" \
INPUT_TEXT="$input_text" \
INDEX_TEXT="$index_text" \
STATE_FILE="$state_file" \
/usr/bin/osascript -l JavaScript <<'JXA'
ObjC.import("Foundation");

var fm = $.NSFileManager.defaultManager;
var env = $.NSProcessInfo.processInfo.environment;
var MAX_PROMPTS = 12;
var MAX_ACTIONS = 1 + (MAX_PROMPTS * 3);
var DEFAULT_PROMPTS = [
  {
    id: "ship-checklist",
    title: "Ship Checklist",
    text: "Run our ship checklist for this branch: tests, docs, release notes, and rollout risks.",
  },
  {
    id: "risk-scan",
    title: "Risk Scan",
    text: "Review this diff for regressions, edge cases, and missing tests. Prioritize high-severity risks first.",
  },
];

function getenv(key) {
  var raw = env.objectForKey(key);
  return raw ? String(ObjC.unwrap(raw)) : "";
}

function readText(path) {
  var data = $.NSData.dataWithContentsOfFile(path);
  if (!data) {
    return null;
  }
  var text = $.NSString.alloc.initWithDataEncoding(data, $.NSUTF8StringEncoding);
  return text ? String(ObjC.unwrap(text)) : null;
}

function writeText(path, text) {
  var nsText = $(text);
  var ok = nsText.writeToFileAtomicallyEncodingError(path, true, $.NSUTF8StringEncoding, null);
  if (!ok) {
    throw new Error("Failed to write prompt book state.");
  }
}

function clonePrompt(prompt) {
  return {
    id: String(prompt.id),
    title: String(prompt.title),
    text: String(prompt.text),
  };
}

function defaultPrompts() {
  return DEFAULT_PROMPTS.map(clonePrompt);
}

function makeUUID() {
  return String(ObjC.unwrap($.NSUUID.UUID.UUIDString)).toLowerCase();
}

function normalizePrompts(rawPrompts) {
  var normalized = [];
  if (Array.isArray(rawPrompts)) {
    for (var i = 0; i < rawPrompts.length; i += 1) {
      var item = rawPrompts[i] || {};
      var title = String(item.title || "").trim();
      var text = String(item.text || "").trim();
      if (!text) {
        continue;
      }
      normalized.push({
        id: String(item.id || makeUUID()),
        title: title || text.slice(0, 28),
        text: text,
      });
      if (normalized.length >= MAX_PROMPTS) {
        break;
      }
    }
  }
  if (normalized.length === 0) {
    return defaultPrompts();
  }
  return normalized.slice(0, MAX_PROMPTS);
}

function loadPrompts(path) {
  if (!fm.fileExistsAtPath(path)) {
    return defaultPrompts();
  }

  try {
    var text = readText(path);
    if (!text) {
      return defaultPrompts();
    }
    var parsed = JSON.parse(text);
    return normalizePrompts(parsed.prompts || []);
  } catch (_error) {
    return defaultPrompts();
  }
}

function savePrompts(path, prompts) {
  var payload = { prompts: prompts.slice(0, MAX_PROMPTS) };
  writeText(path, JSON.stringify(payload, null, 2) + "\n");
}

function parsePromptInput(raw) {
  var text = String(raw || "").trim();
  if (text.indexOf("::") !== -1) {
    var parts = text.split("::");
    var title = String(parts.shift() || "").trim();
    var body = String(parts.join("::") || "").trim();
    if (body) {
      return {
        title: title || body.slice(0, 28),
        text: body,
      };
    }
  }

  return {
    title: text ? text.slice(0, 28) : "Prompt",
    text: text,
  };
}

function applyAction(prompts, operation, inputText, indexText) {
  var next = prompts.slice(0, MAX_PROMPTS);
  var trimmedInput = String(inputText || "").trim();
  var parsedIndex = parseInt(String(indexText || "").trim(), 10);
  var hasIndex = !Number.isNaN(parsedIndex) && parsedIndex >= 0 && parsedIndex < next.length;

  if (operation === "add" && trimmedInput) {
    var created = parsePromptInput(trimmedInput);
    if (created.text) {
      next.push({
        id: makeUUID(),
        title: created.title,
        text: created.text,
      });
      return next.slice(0, MAX_PROMPTS);
    }
  }

  if (operation === "edit" && trimmedInput && hasIndex) {
    var updated = parsePromptInput(trimmedInput);
    if (updated.text) {
      next[parsedIndex].title = updated.title;
      next[parsedIndex].text = updated.text;
    }
    return next.slice(0, MAX_PROMPTS);
  }

  if (operation === "delete" && hasIndex) {
    next.splice(parsedIndex, 1);
    return next.slice(0, MAX_PROMPTS);
  }

  return next.slice(0, MAX_PROMPTS);
}

function renderMarkdown(prompts) {
  if (!prompts.length) {
    return "_No prompts saved yet. Use Add Prompt._";
  }

  var lines = ["Saved prompts:"];
  for (var i = 0; i < prompts.length; i += 1) {
    var prompt = prompts[i];
    var title = String(prompt.title || "").trim() || ("Prompt " + (i + 1));
    var text = String(prompt.text || "").trim();
    var preview = text.length <= 120 ? text : (text.slice(0, 117) + "...");
    lines.push("- " + (i + 1) + ". **" + title + "** - " + preview);
  }
  return lines.join("\n");
}

function renderActions(prompts) {
  var actions = [
    {
      id: "prompt-add",
      label: "Add Prompt",
      kind: "promptThenEmitEvent",
      payload: {
        operation: "add",
        targetHookID: "prompt-book-action",
      },
      prompt: {
        title: "Add Prompt",
        message: "Use `Title :: Prompt` or just a prompt body.",
        placeholder: "Ship Checklist :: Run release checks for this branch.",
      },
    },
  ];

  for (var i = 0; i < prompts.length; i += 1) {
    var prompt = prompts[i];
    var label = String(prompt.title || "").trim() || ("Prompt " + (i + 1));
    var promptText = String(prompt.text || "");

    actions.push({
      id: "send-" + i,
      label: "Send: " + label,
      kind: "composer.insertAndSend",
      payload: {
        text: promptText,
      },
    });
    actions.push({
      id: "edit-" + i,
      label: "Edit: " + label,
      kind: "promptThenEmitEvent",
      payload: {
        operation: "edit",
        index: String(i),
        targetHookID: "prompt-book-action",
      },
      prompt: {
        title: "Edit " + label,
        message: "Use `Title :: Prompt` or just a prompt body.",
        placeholder: "Title :: Updated prompt",
        initialValue: label + " :: " + promptText,
        submitLabel: "Save",
      },
    });
    actions.push({
      id: "delete-" + i,
      label: "Delete: " + label,
      kind: "emitEvent",
      payload: {
        operation: "delete",
        index: String(i),
        targetHookID: "prompt-book-action",
      },
    });
  }

  return actions.slice(0, MAX_ACTIONS);
}

var stateFile = getenv("STATE_FILE");
var event = getenv("EVENT");
var operation = String(getenv("OPERATION") || "").trim().toLowerCase();
var inputText = getenv("INPUT_TEXT");
var indexText = getenv("INDEX_TEXT");

var prompts = loadPrompts(stateFile);
if (event === "modsBar.action") {
  prompts = applyAction(prompts, operation, inputText, indexText);
  savePrompts(stateFile, prompts);
} else if (!fm.fileExistsAtPath(stateFile)) {
  savePrompts(stateFile, prompts);
}

var output = {
  ok: true,
  modsBar: {
    title: "Prompt Book",
    scope: "global",
    markdown: renderMarkdown(prompts),
    actions: renderActions(prompts),
  },
};

JSON.stringify(output);
JXA
