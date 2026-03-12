use super::*;

pub(super) struct RelayValidationError {
    pub(super) code: &'static str,
    pub(super) message: String,
}

pub(super) fn validate_mobile_payload(
    session: &mut SessionRecord,
    parsed: Option<&Value>,
    expected_session_id: &str,
    connection_id: &str,
    device_id: &str,
    config: &RelayConfig,
) -> Result<(), RelayValidationError> {
    let Some(parsed) = parsed else {
        return Err(RelayValidationError {
            code: "invalid_payload",
            message: "Payload must be valid JSON.".to_string(),
        });
    };
    let Some(parsed_object) = parsed.as_object() else {
        return Err(RelayValidationError {
            code: "invalid_payload",
            message: "Payload must be a JSON object.".to_string(),
        });
    };

    if let Some(message_type) = parsed.get("type").and_then(Value::as_str) {
        if message_type == "relay.snapshot_request" {
            ensure_only_allowed_fields(
                parsed_object,
                &["type", "sessionID", "reason", "lastSeq"],
                "invalid_snapshot_request",
                "snapshot request",
            )?;

            let snapshot_session_id =
                parsed
                    .get("sessionID")
                    .and_then(Value::as_str)
                    .ok_or_else(|| RelayValidationError {
                        code: "invalid_snapshot_request",
                        message: "Snapshot request requires sessionID.".to_string(),
                    })?;
            if snapshot_session_id != expected_session_id {
                return Err(RelayValidationError {
                    code: "invalid_session",
                    message: "Snapshot request sessionID does not match authenticated session."
                        .to_string(),
                });
            }

            if let Some(reason_value) = parsed.get("reason") {
                let reason = reason_value.as_str().ok_or_else(|| RelayValidationError {
                    code: "invalid_snapshot_request",
                    message: "Snapshot reason must be a string.".to_string(),
                })?;
                if reason.len() > 128 {
                    return Err(RelayValidationError {
                        code: "invalid_snapshot_request",
                        message: "Snapshot reason is too long.".to_string(),
                    });
                }
            }

            if let Some(last_seq) = parsed.get("lastSeq") {
                let valid_string_last_seq = last_seq.as_str().is_some_and(|value| {
                    !value.is_empty()
                        && value.len() <= 20
                        && value.bytes().all(|byte| byte.is_ascii_digit())
                });
                if !(last_seq.is_u64()
                    || last_seq.as_i64().is_some_and(|value| value >= 0)
                    || valid_string_last_seq)
                {
                    return Err(RelayValidationError {
                        code: "invalid_snapshot_request",
                        message: "lastSeq must be numeric when provided.".to_string(),
                    });
                }
            }

            if !consume_snapshot_request_budget(
                session,
                device_id,
                config.max_snapshot_requests_per_minute,
            ) {
                return Err(RelayValidationError {
                    code: "snapshot_rate_limited",
                    message: "Too many snapshot requests from this device. Retry shortly."
                        .to_string(),
                });
            }

            return Ok(());
        }
    }

    ensure_only_allowed_fields(
        parsed_object,
        &[
            "schemaVersion",
            "sessionID",
            "seq",
            "timestamp",
            "payload",
            "relayConnectionID",
            "relayDeviceID",
        ],
        "invalid_command",
        "command envelope",
    )?;

    let envelope_session_id = parsed
        .get("sessionID")
        .and_then(Value::as_str)
        .ok_or_else(|| RelayValidationError {
            code: "invalid_command",
            message: "Command envelope requires sessionID.".to_string(),
        })?;
    if envelope_session_id != expected_session_id {
        return Err(RelayValidationError {
            code: "invalid_session",
            message: "Command envelope sessionID does not match authenticated session.".to_string(),
        });
    }

    let schema_version = parsed
        .get("schemaVersion")
        .and_then(Value::as_i64)
        .ok_or_else(|| RelayValidationError {
            code: "invalid_command",
            message: "schemaVersion is required for command envelopes.".to_string(),
        })?;
    if schema_version != 1 && schema_version != 2 {
        return Err(RelayValidationError {
            code: "unsupported_schema",
            message: "Only schemaVersion 1 or 2 is supported.".to_string(),
        });
    }

    let payload_type = parsed
        .pointer("/payload/type")
        .and_then(Value::as_str)
        .ok_or_else(|| RelayValidationError {
            code: "invalid_command",
            message: "Command envelope payload.type is required.".to_string(),
        })?;
    if payload_type != "command" {
        return Err(RelayValidationError {
            code: "invalid_command",
            message: "Only command payloads are accepted from mobile clients.".to_string(),
        });
    }
    let payload_wrapper = parsed
        .get("payload")
        .and_then(Value::as_object)
        .ok_or_else(|| RelayValidationError {
            code: "invalid_command",
            message: "Command envelope payload object is required.".to_string(),
        })?;
    ensure_only_allowed_fields(
        payload_wrapper,
        &["type", "payload"],
        "invalid_command",
        "command wrapper",
    )?;

    let command_payload = parsed
        .pointer("/payload/payload")
        .and_then(Value::as_object)
        .ok_or_else(|| RelayValidationError {
            code: "invalid_command",
            message: "Command payload object is required.".to_string(),
        })?;
    ensure_only_allowed_fields(
        command_payload,
        &[
            "name",
            "commandID",
            "threadID",
            "projectID",
            "text",
            "runtimeRequestID",
            "runtimeRequestKind",
            "runtimeRequestResponse",
        ],
        "invalid_command",
        "command payload",
    )?;
    let command_name = command_payload
        .get("name")
        .and_then(Value::as_str)
        .ok_or_else(|| RelayValidationError {
            code: "invalid_command",
            message: "Command name is required.".to_string(),
        })?;
    let command_id = command_payload
        .get("commandID")
        .and_then(Value::as_str)
        .ok_or_else(|| RelayValidationError {
            code: "invalid_command",
            message: "commandID is required.".to_string(),
        })?;
    if !is_small_identifier(command_id) {
        return Err(RelayValidationError {
            code: "invalid_command",
            message: "commandID must be a compact identifier.".to_string(),
        });
    }
    let command_seq =
        parsed
            .get("seq")
            .and_then(Value::as_u64)
            .ok_or_else(|| RelayValidationError {
                code: "invalid_command",
                message: "Command envelopes must include numeric seq.".to_string(),
            })?;

    if !consume_connection_command_sequence(session, connection_id, command_seq) {
        return Err(RelayValidationError {
            code: "replayed_command",
            message: "Command sequence was replayed or out of order.".to_string(),
        });
    }

    if !consume_device_command_budget(session, device_id, config.max_remote_commands_per_minute) {
        return Err(RelayValidationError {
            code: "command_rate_limited",
            message: "Too many remote commands from this device. Retry shortly.".to_string(),
        });
    }

    if !consume_session_command_budget(session, config.max_remote_session_commands_per_minute) {
        return Err(RelayValidationError {
            code: "command_rate_limited",
            message: "Remote command throughput for this session is temporarily saturated."
                .to_string(),
        });
    }

    match command_name {
        "thread.send_message" => {
            let thread_id = command_payload
                .get("threadID")
                .and_then(Value::as_str)
                .ok_or_else(|| RelayValidationError {
                    code: "invalid_command",
                    message: "thread.send_message requires threadID.".to_string(),
                })?;
            if !is_small_identifier(thread_id) {
                return Err(RelayValidationError {
                    code: "invalid_command",
                    message: "threadID must be a compact identifier.".to_string(),
                });
            }

            let text = command_payload
                .get("text")
                .and_then(Value::as_str)
                .ok_or_else(|| RelayValidationError {
                    code: "invalid_command",
                    message: "thread.send_message requires text.".to_string(),
                })?;
            if text.trim().is_empty() {
                return Err(RelayValidationError {
                    code: "invalid_command",
                    message: "Message text cannot be empty.".to_string(),
                });
            }
            if text.len() > config.max_remote_command_text_bytes {
                return Err(RelayValidationError {
                    code: "invalid_command",
                    message: format!(
                        "Message text exceeds {} bytes.",
                        config.max_remote_command_text_bytes
                    ),
                });
            }
        }
        "thread.select" => {
            let thread_id = command_payload
                .get("threadID")
                .and_then(Value::as_str)
                .ok_or_else(|| RelayValidationError {
                    code: "invalid_command",
                    message: "thread.select requires threadID.".to_string(),
                })?;
            if !is_small_identifier(thread_id) {
                return Err(RelayValidationError {
                    code: "invalid_command",
                    message: "threadID must be a compact identifier.".to_string(),
                });
            }
        }
        "project.select" => {
            let project_id = command_payload
                .get("projectID")
                .and_then(Value::as_str)
                .ok_or_else(|| RelayValidationError {
                    code: "invalid_command",
                    message: "project.select requires projectID.".to_string(),
                })?;
            if !is_small_identifier(project_id) {
                return Err(RelayValidationError {
                    code: "invalid_command",
                    message: "projectID must be a compact identifier.".to_string(),
                });
            }
        }
        "runtime_request.respond" => {
            let runtime_request_id = command_payload
                .get("runtimeRequestID")
                .and_then(Value::as_str)
                .ok_or_else(|| RelayValidationError {
                    code: "invalid_command",
                    message: "runtime_request.respond requires runtimeRequestID.".to_string(),
                })?;
            if !runtime_request_id.bytes().all(|byte| byte.is_ascii_digit())
                || runtime_request_id.len() > 32
            {
                return Err(RelayValidationError {
                    code: "invalid_command",
                    message: "runtimeRequestID must be numeric.".to_string(),
                });
            }

            if let Some(kind) = command_payload
                .get("runtimeRequestKind")
                .and_then(Value::as_str)
            {
                if !matches!(
                    kind,
                    "approval"
                        | "permissionsApproval"
                        | "userInput"
                        | "mcpElicitation"
                        | "dynamicToolCall"
                ) {
                    return Err(RelayValidationError {
                        code: "invalid_command",
                        message: "runtimeRequestKind is not recognized.".to_string(),
                    });
                }
            }

            validate_runtime_request_response(command_payload, config)?;
        }
        _ => {
            return Err(RelayValidationError {
                code: "invalid_command",
                message: "Command name is not allowed.".to_string(),
            });
        }
    }

    Ok(())
}

fn validate_runtime_request_response(
    command_payload: &serde_json::Map<String, Value>,
    config: &RelayConfig,
) -> Result<(), RelayValidationError> {
    let runtime_response = command_payload.get("runtimeRequestResponse");

    if runtime_response.is_none() {
        return Err(RelayValidationError {
            code: "invalid_command",
            message: "runtime_request.respond requires runtimeRequestResponse.".to_string(),
        });
    }

    let Some(runtime_response) = runtime_response else {
        return Ok(());
    };
    let Some(runtime_response_object) = runtime_response.as_object() else {
        return Err(RelayValidationError {
            code: "invalid_command",
            message: "runtimeRequestResponse must be an object.".to_string(),
        });
    };
    ensure_only_allowed_fields(
        runtime_response_object,
        &["decision", "permissions", "scope", "text", "optionID", "approved"],
        "invalid_command",
        "runtimeRequestResponse",
    )?;

    let has_known_field = runtime_response_object.contains_key("decision")
        || runtime_response_object.contains_key("permissions")
        || runtime_response_object.contains_key("scope")
        || runtime_response_object.contains_key("text")
        || runtime_response_object.contains_key("optionID")
        || runtime_response_object.contains_key("approved");
    if !has_known_field {
        return Err(RelayValidationError {
            code: "invalid_command",
            message: "runtimeRequestResponse must include at least one response field."
                .to_string(),
        });
    }

    if let Some(decision) = runtime_response_object
        .get("decision")
        .and_then(Value::as_str)
    {
        validate_runtime_request_decision(decision)?;
    }

    if let Some(permissions) = runtime_response_object.get("permissions") {
        let Some(entries) = permissions.as_array() else {
            return Err(RelayValidationError {
                code: "invalid_command",
                message: "runtimeRequestResponse.permissions must be an array.".to_string(),
            });
        };

        for entry in entries {
            let Some(permission) = entry.as_str() else {
                return Err(RelayValidationError {
                    code: "invalid_command",
                    message: "runtimeRequestResponse.permissions must contain strings."
                        .to_string(),
                });
            };
            if permission.trim().is_empty() || permission.len() > 256 {
                return Err(RelayValidationError {
                    code: "invalid_command",
                    message: "runtimeRequestResponse.permissions contains an invalid value."
                        .to_string(),
                });
            }
        }
    }

    if let Some(scope) = runtime_response_object.get("scope") {
        let Some(scope_value) = scope.as_str() else {
            return Err(RelayValidationError {
                code: "invalid_command",
                message: "runtimeRequestResponse.scope must be a string.".to_string(),
            });
        };
        if scope_value.trim().is_empty() || scope_value.len() > 128 {
            return Err(RelayValidationError {
                code: "invalid_command",
                message: "runtimeRequestResponse.scope is not valid.".to_string(),
            });
        }
    }

    if let Some(text) = runtime_response_object.get("text") {
        let Some(text_value) = text.as_str() else {
            return Err(RelayValidationError {
                code: "invalid_command",
                message: "runtimeRequestResponse.text must be a string.".to_string(),
            });
        };
        if text_value.len() > config.max_remote_command_text_bytes {
            return Err(RelayValidationError {
                code: "invalid_command",
                message: format!(
                    "runtimeRequestResponse.text exceeds {} bytes.",
                    config.max_remote_command_text_bytes
                ),
            });
        }
    }

    if let Some(option_id) = runtime_response_object.get("optionID") {
        let Some(option_id_value) = option_id.as_str() else {
            return Err(RelayValidationError {
                code: "invalid_command",
                message: "runtimeRequestResponse.optionID must be a string.".to_string(),
            });
        };
        if !is_small_identifier(option_id_value) {
            return Err(RelayValidationError {
                code: "invalid_command",
                message: "runtimeRequestResponse.optionID must be a compact identifier."
                    .to_string(),
            });
        }
    }

    if let Some(approved) = runtime_response_object.get("approved") {
        if !approved.is_boolean() {
            return Err(RelayValidationError {
                code: "invalid_command",
                message: "runtimeRequestResponse.approved must be a boolean.".to_string(),
            });
        }
    }

    Ok(())
}

fn validate_runtime_request_decision(decision: &str) -> Result<(), RelayValidationError> {
    if matches!(
        decision,
        "accept" | "acceptForSession" | "decline" | "cancel"
    ) {
        return Ok(());
    }

    Err(RelayValidationError {
        code: "invalid_command",
        message: "runtimeRequestResponse.decision is not recognized.".to_string(),
    })
}

fn ensure_only_allowed_fields(
    object: &serde_json::Map<String, Value>,
    allowed_fields: &[&str],
    error_code: &'static str,
    context: &str,
) -> Result<(), RelayValidationError> {
    if let Some(unexpected_key) = object
        .keys()
        .find(|key| !allowed_fields.contains(&key.as_str()))
    {
        return Err(RelayValidationError {
            code: error_code,
            message: format!("Unexpected field '{}' in {}.", unexpected_key, context),
        });
    }

    Ok(())
}

fn consume_device_command_budget(
    session: &mut SessionRecord,
    device_id: &str,
    max_commands_per_minute: usize,
) -> bool {
    if max_commands_per_minute == 0 {
        return false;
    }

    let now = now_ms();
    let bucket = session
        .command_rate_buckets
        .entry(device_id.to_string())
        .or_insert(RateBucket {
            count: 0,
            window_ends_at_ms: now + 60_000,
        });
    consume_rate_bucket(bucket, max_commands_per_minute)
}

fn consume_session_command_budget(
    session: &mut SessionRecord,
    max_commands_per_minute: usize,
) -> bool {
    if max_commands_per_minute == 0 {
        return false;
    }

    let now = now_ms();
    let bucket = session
        .session_command_rate_bucket
        .get_or_insert(RateBucket {
            count: 0,
            window_ends_at_ms: now + 60_000,
        });
    consume_rate_bucket(bucket, max_commands_per_minute)
}

fn consume_snapshot_request_budget(
    session: &mut SessionRecord,
    device_id: &str,
    max_requests_per_minute: usize,
) -> bool {
    if max_requests_per_minute == 0 {
        return false;
    }

    let now = now_ms();
    let bucket = session
        .snapshot_request_rate_buckets
        .entry(device_id.to_string())
        .or_insert(RateBucket {
            count: 0,
            window_ends_at_ms: now + 60_000,
        });
    consume_rate_bucket(bucket, max_requests_per_minute)
}

pub(super) fn consume_rate_bucket(bucket: &mut RateBucket, limit_per_minute: usize) -> bool {
    if limit_per_minute == 0 {
        return false;
    }

    let now = now_ms();
    if now >= bucket.window_ends_at_ms {
        bucket.count = 1;
        bucket.window_ends_at_ms = now + 60_000;
        return true;
    }

    bucket.count = bucket.count.saturating_add(1);
    bucket.count <= limit_per_minute
}

fn consume_connection_command_sequence(
    session: &mut SessionRecord,
    connection_id: &str,
    sequence: u64,
) -> bool {
    let entry = session
        .command_sequence_by_connection_id
        .entry(connection_id.to_string())
        .or_insert(0);
    if sequence <= *entry {
        return false;
    }
    *entry = sequence;
    true
}

fn is_small_identifier(value: &str) -> bool {
    if value.is_empty() || value.len() > 128 {
        return false;
    }

    value
        .chars()
        .all(|char| char.is_ascii_alphanumeric() || matches!(char, '-' | '_' | ':'))
}
