#!/bin/sh
set -eu

input_file="$(mktemp "${TMPDIR:-/tmp}/codexchat-messages-assistant-input.XXXXXX")"

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
state_file="$state_dir/messages-assistant.json"

event="$(extract_raw event)"
operation="$(extract_raw payload.operation)"
input_text="$(extract_raw payload.input)"

EVENT="$event" \
OPERATION="$operation" \
INPUT_TEXT="$input_text" \
STATE_FILE="$state_file" \
/usr/bin/osascript -l JavaScript <<'JXA'
ObjC.import("Foundation");

var env = $.NSProcessInfo.processInfo.environment;
var fm = $.NSFileManager.defaultManager;

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
  var ok = $(text).writeToFileAtomicallyEncodingError(path, true, $.NSUTF8StringEncoding, null);
  if (!ok) {
    throw new Error("Failed to write messages assistant state.");
  }
}

function emptyState() {
  return {
    recipient: "",
    message: "",
  };
}

function loadState(path) {
  if (!fm.fileExistsAtPath(path)) {
    return emptyState();
  }

  try {
    var text = readText(path);
    if (!text) {
      return emptyState();
    }
    var parsed = JSON.parse(text);
    return {
      recipient: String(parsed.recipient || "").trim(),
      message: String(parsed.message || "").trim(),
    };
  } catch (_error) {
    return emptyState();
  }
}

function saveState(path, state) {
  writeText(path, JSON.stringify(state, null, 2) + "\n");
}

function parseDraft(rawInput) {
  var trimmed = String(rawInput || "").trim();
  if (!trimmed) {
    return null;
  }

  var separatorIndex = trimmed.indexOf("::");
  if (separatorIndex !== -1) {
    var recipient = trimmed.slice(0, separatorIndex).trim();
    var body = trimmed.slice(separatorIndex + 2).trim();
    if (recipient && body) {
      return { recipient: recipient, message: body };
    }
  }

  separatorIndex = trimmed.indexOf(":");
  if (separatorIndex !== -1) {
    var recipientFallback = trimmed.slice(0, separatorIndex).trim();
    var bodyFallback = trimmed.slice(separatorIndex + 1).trim();
    if (recipientFallback && bodyFallback) {
      return { recipient: recipientFallback, message: bodyFallback };
    }
  }

  return null;
}

function isDraftReady(state) {
  return Boolean(state.recipient && state.message);
}

function renderMarkdown(state, statusMessage) {
  var lines = [
    "Prepare a message draft, then confirm send in the native preview sheet.",
  ];

  if (statusMessage) {
    lines.push("", "Status: " + statusMessage);
  }

  if (isDraftReady(state)) {
    lines.push(
      "",
      "Draft recipient: `" + state.recipient + "`",
      "",
      "> " + state.message
    );
  } else {
    lines.push(
      "",
      "No draft yet. Use `Set Draft` with `Recipient :: Message` format."
    );
  }

  return lines.join("\n");
}

function renderActions(state) {
  var actions = [
    {
      id: "messages-set-draft",
      label: "Set Draft",
      kind: "promptThenEmitEvent",
      payload: {
        operation: "setDraft",
        targetHookID: "messages-assistant-action",
      },
      prompt: {
        title: "Message Draft",
        message: "Enter `Recipient :: Message`",
        placeholder: "Alex :: Running 10 minutes late.",
        submitLabel: "Save Draft",
      },
    },
  ];

  if (isDraftReady(state)) {
    actions.push({
      id: "messages-send-draft",
      label: "Preview & Send Draft",
      kind: "native.action",
      payload: {
        recipient: state.recipient,
        body: state.message,
      },
      nativeActionID: "messages.send",
      safetyLevel: "externallyVisible",
      requiresConfirmation: true,
      externallyVisible: true,
    });

    actions.push({
      id: "messages-clear-draft",
      label: "Clear Draft",
      kind: "emitEvent",
      payload: {
        operation: "clearDraft",
        targetHookID: "messages-assistant-action",
      },
    });
  }

  return actions;
}

function main() {
  var stateFile = getenv("STATE_FILE");
  var state = loadState(stateFile);
  var event = getenv("EVENT");
  var operation = getenv("OPERATION");
  var inputText = getenv("INPUT_TEXT");

  var statusMessage = "";

  if (event === "modsBar.action") {
    if (operation === "clearDraft") {
      state = emptyState();
      statusMessage = "Draft cleared.";
    } else if (operation === "setDraft") {
      var parsed = parseDraft(inputText);
      if (parsed) {
        state = parsed;
        statusMessage = "Draft updated.";
      } else {
        statusMessage = "Draft format invalid. Use `Recipient :: Message`.";
      }
    }

    saveState(stateFile, state);
  }

  var payload = {
    ok: true,
    modsBar: {
      title: "Messages Assistant",
      markdown: renderMarkdown(state, statusMessage),
      scope: "thread",
      actions: renderActions(state),
    },
  };

  var encoded = $(JSON.stringify(payload) + "\n").dataUsingEncoding($.NSUTF8StringEncoding);
  $.NSFileHandle.fileHandleWithStandardOutput.writeData(encoded);
}

main();
JXA
