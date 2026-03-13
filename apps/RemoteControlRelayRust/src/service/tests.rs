use super::*;
use proptest::collection::hash_map;
use proptest::prelude::*;

fn make_test_state_with_session(session: SessionRecord) -> SharedRelayState {
    let mut sessions = HashMap::new();
    let session_id = session.session_id.clone();
    sessions.insert(session_id, session);

    SharedRelayState {
        config: RelayConfig::from_env(),
        inner: Arc::new(Mutex::new(RelayState {
            desktop_token_index: build_desktop_token_index(&sessions),
            device_token_index: build_device_token_index(&sessions),
            sessions,
            rate_buckets: HashMap::new(),
            pending_join_waiters: 0,
            outbound_send_failures: 0,
            slow_consumer_disconnects: 0,
            pair_start_requests: 0,
            pair_start_successes: 0,
            pair_join_requests: 0,
            pair_join_successes: 0,
            pair_refresh_requests: 0,
            pair_refresh_successes: 0,
            ws_auth_attempts: 0,
            ws_auth_successes: 0,
            last_persistence_refresh_at_ms: 0,
            persistence_versions: HashMap::new(),
            seen_cross_instance_nonces: HashMap::new(),
            bus_subscribed_sessions: HashSet::new(),
            bus_subscription_tasks: HashMap::new(),
        })),
        persistence: None,
        cross_instance_bus: None,
    }
}

fn make_test_session(session_id: &str, device_id: &str, token: &str) -> SessionRecord {
    SessionRecord {
        session_id: session_id.to_string(),
        join_token: "join-token".to_string(),
        join_token_expires_at_ms: now_ms() + 60_000,
        join_token_used_at_ms: Some(now_ms()),
        desktop_session_token: "desktop-token".to_string(),
        relay_web_socket_url: "ws://localhost:8787/ws".to_string(),
        idle_timeout_seconds: 1_800,
        created_at_ms: now_ms(),
        last_activity_at_ms: now_ms(),
        desktop_socket: None,
        desktop_connected: false,
        mobile_sockets: HashMap::new(),
        devices: HashMap::from([(
            device_id.to_string(),
            DeviceRecord {
                current_session_token: token.to_string(),
                retired_session_tokens: vec![],
                name: "Test Phone".to_string(),
                joined_at_ms: now_ms(),
                last_seen_at_ms: now_ms(),
            },
        )]),
        command_rate_buckets: HashMap::new(),
        session_command_rate_bucket: None,
        snapshot_request_rate_buckets: HashMap::new(),
        command_sequence_by_connection_id: HashMap::new(),
        pending_join_request: None,
    }
}

#[test]
fn persisted_runtime_round_trip_preserves_sessions_and_tokens() {
    let mut sessions = HashMap::new();
    sessions.insert(
        "session-1".to_string(),
        SessionRecord {
            session_id: "session-1".to_string(),
            join_token: "join-token".to_string(),
            join_token_expires_at_ms: 1_000,
            join_token_used_at_ms: Some(900),
            desktop_session_token: "desktop-token".to_string(),
            relay_web_socket_url: "ws://localhost:8787/ws".to_string(),
            idle_timeout_seconds: 1_800,
            created_at_ms: 100,
            last_activity_at_ms: 200,
            desktop_socket: None,
            desktop_connected: false,
            mobile_sockets: HashMap::new(),
            devices: HashMap::from([(
                "device-1".to_string(),
                DeviceRecord {
                    current_session_token: "device-token".to_string(),
                    retired_session_tokens: vec![RetiredDeviceToken {
                        token: "device-token-grace".to_string(),
                        expires_at_ms: now_ms() + 30_000,
                    }],
                    name: "Test Phone".to_string(),
                    joined_at_ms: 150,
                    last_seen_at_ms: 190,
                },
            )]),
            command_rate_buckets: HashMap::new(),
            session_command_rate_bucket: None,
            snapshot_request_rate_buckets: HashMap::new(),
            command_sequence_by_connection_id: HashMap::new(),
            pending_join_request: None,
        },
    );

    let session = sessions.get("session-1").expect("session exists");
    let persisted = PersistedSessionRecord::from_session(session);
    let restored_session = persisted
        .into_runtime()
        .expect("restored session should decode");

    assert_eq!(restored_session.devices.len(), 1);
    assert!(restored_session.desktop_socket.is_none());
    assert!(restored_session.mobile_sockets.is_empty());
    assert!(restored_session.pending_join_request.is_none());

    let mut restored_sessions = HashMap::new();
    restored_sessions.insert("session-1".to_string(), restored_session);
    let token_index = build_device_token_index(&restored_sessions);
    assert_eq!(token_index.len(), 2);
    let token_context = token_index
        .get("device-token")
        .expect("device token context should exist");
    assert_eq!(token_context.session_id, "session-1");
    assert_eq!(token_context.device_id, "device-1");
    let retired_context = token_index
        .get("device-token-grace")
        .expect("retired device token context should exist");
    assert_eq!(retired_context.session_id, "session-1");
    assert_eq!(retired_context.device_id, "device-1");
    assert!(retired_context.expires_at_ms.is_some());

    let desktop_index = build_desktop_token_index(&restored_sessions);
    assert_eq!(
        desktop_index.get("desktop-token").map(String::as_str),
        Some("session-1")
    );
}

#[test]
fn consume_rate_bucket_enforces_limit_and_recovers_next_window() {
    let mut bucket = RateBucket {
        count: 0,
        window_ends_at_ms: now_ms() + 60_000,
    };

    assert!(consume_rate_bucket(&mut bucket, 2));
    assert!(consume_rate_bucket(&mut bucket, 2));
    assert!(!consume_rate_bucket(&mut bucket, 2));

    bucket.window_ends_at_ms = now_ms() - 1;
    assert!(consume_rate_bucket(&mut bucket, 2));
}

#[tokio::test]
async fn sweep_sessions_preserves_idle_session_when_trusted_devices_exist() {
    let session_id = "session-1";
    let mut session = make_test_session(session_id, "device-1", "device-token-1");
    session.idle_timeout_seconds = 60;
    session.created_at_ms = now_ms() - 120_000;
    session.last_activity_at_ms = now_ms() - 120_000;

    let mut state = make_test_state_with_session(session);
    state.config.session_retention_ms = 1_000;
    sweep_sessions(&state).await;

    let relay = state.inner.lock().await;
    assert!(relay.sessions.contains_key(session_id));
}

#[tokio::test]
async fn sweep_sessions_expires_idle_session_without_trusted_devices() {
    let session_id = "session-1";
    let mut session = make_test_session(session_id, "device-1", "device-token-1");
    session.idle_timeout_seconds = 60;
    session.devices.clear();
    session.created_at_ms = now_ms() - 120_000;
    session.last_activity_at_ms = now_ms() - 120_000;

    let mut state = make_test_state_with_session(session);
    state.config.session_retention_ms = 1_000;
    sweep_sessions(&state).await;

    let relay = state.inner.lock().await;
    assert!(!relay.sessions.contains_key(session_id));
}

#[tokio::test]
async fn cross_instance_targeted_revoke_removes_device_tokens_locally() {
    let session_id = "session-1";
    let state =
        make_test_state_with_session(make_test_session(session_id, "device-1", "device-token-1"));

    let envelope = CrossInstanceEnvelope {
        schema_version: 1,
        session_id: session_id.to_string(),
        source_instance_id: "remote-instance".to_string(),
        target: "mobile".to_string(),
        target_device_id: Some("device-1".to_string()),
        payload: json!({
            "type": "disconnect",
            "reason": "device_revoked"
        })
        .to_string(),
        issued_at_ms: now_ms(),
        nonce: "nonce-token-1".to_string(),
        signature: None,
    };
    let payload = serde_json::to_vec(&envelope).expect("encode envelope");
    handle_session_envelope(&state, "local-instance", &payload).await;

    let relay = state.inner.lock().await;
    let session = relay.sessions.get(session_id).expect("session exists");
    assert!(session.devices.is_empty());
    assert!(relay.device_token_index.is_empty());
}

#[tokio::test]
async fn cross_instance_disconnect_closes_local_stale_session() {
    let session_id = "session-1";
    let state =
        make_test_state_with_session(make_test_session(session_id, "device-1", "device-token-1"));

    let envelope = CrossInstanceEnvelope {
        schema_version: 1,
        session_id: session_id.to_string(),
        source_instance_id: "remote-instance".to_string(),
        target: "mobile".to_string(),
        target_device_id: None,
        payload: json!({
            "type": "disconnect",
            "reason": "stopped_by_desktop"
        })
        .to_string(),
        issued_at_ms: now_ms(),
        nonce: "nonce-token-2".to_string(),
        signature: None,
    };
    let payload = serde_json::to_vec(&envelope).expect("encode envelope");
    handle_session_envelope(&state, "local-instance", &payload).await;

    let relay = state.inner.lock().await;
    assert!(!relay.sessions.contains_key(session_id));
    assert!(relay.device_token_index.is_empty());
}

#[tokio::test]
async fn cross_instance_envelope_without_required_signature_is_ignored() {
    let session_id = "session-1";
    let mut state =
        make_test_state_with_session(make_test_session(session_id, "device-1", "device-token-1"));
    state.config.nats_hmac_secret = Some("01234567890123456789012345678901".to_string());

    let envelope = CrossInstanceEnvelope {
        schema_version: 1,
        session_id: session_id.to_string(),
        source_instance_id: "remote-instance".to_string(),
        target: "mobile".to_string(),
        target_device_id: None,
        payload: json!({
            "type": "disconnect",
            "reason": "stopped_by_desktop"
        })
        .to_string(),
        issued_at_ms: now_ms(),
        nonce: "nonce-token-3".to_string(),
        signature: None,
    };
    let payload = serde_json::to_vec(&envelope).expect("encode envelope");
    handle_session_envelope(&state, "local-instance", &payload).await;

    let relay = state.inner.lock().await;
    assert!(
        relay.sessions.contains_key(session_id),
        "session should remain when signature verification fails"
    );
}

#[test]
fn try_send_payload_returns_false_when_queue_is_full() {
    let (tx, mut rx) = mpsc::channel::<Message>(1);

    assert!(try_send_payload(&tx, "first".to_string()));
    assert!(
        !try_send_payload(&tx, "second".to_string()),
        "second payload should be rejected when queue is full"
    );

    let first = rx.try_recv().expect("first payload should remain in queue");
    assert_eq!(first, Message::Text("first".to_string().into()));
}

#[tokio::test]
async fn request_socket_disconnect_sends_disconnect_and_shutdown_signal() {
    let (tx, mut rx) = mpsc::channel::<Message>(4);
    let (shutdown_tx, mut shutdown_rx) = watch::channel(false);
    let handle = SocketHandle {
        tx,
        shutdown: shutdown_tx,
        device_id: Some("device-1".to_string()),
    };

    request_socket_disconnect(&handle, "slow_consumer");

    let payload = rx.recv().await.expect("disconnect payload");
    let Message::Text(payload_text) = payload else {
        panic!("expected text disconnect payload");
    };
    let parsed: Value = serde_json::from_str(&payload_text).expect("disconnect json");
    assert_eq!(
        parsed.get("reason").and_then(Value::as_str),
        Some("slow_consumer")
    );

    shutdown_rx.changed().await.expect("shutdown change");
    assert!(*shutdown_rx.borrow());
}

#[tokio::test]
async fn close_session_removes_all_device_tokens_for_closed_session() {
    let session_id = "session-1";
    let state =
        make_test_state_with_session(make_test_session(session_id, "device-1", "device-token-1"));

    let mut relay = state.inner.lock().await;
    relay.device_token_index.insert(
        "grace-token".to_string(),
        DeviceTokenContext {
            session_id: session_id.to_string(),
            device_id: "device-1".to_string(),
            expires_at_ms: Some(now_ms() + 30_000),
        },
    );
    relay.device_token_index.insert(
        "other-session-token".to_string(),
        DeviceTokenContext {
            session_id: "session-2".to_string(),
            device_id: "device-9".to_string(),
            expires_at_ms: None,
        },
    );

    close_session(&mut relay, session_id, "test_close");

    assert!(!relay.sessions.contains_key(session_id));
    assert!(
        !relay.device_token_index.contains_key("device-token-1"),
        "current device token should be removed"
    );
    assert!(
        !relay.device_token_index.contains_key("grace-token"),
        "grace token should also be removed"
    );
    assert!(
        relay.device_token_index.contains_key("other-session-token"),
        "other sessions should remain untouched"
    );
}

#[tokio::test]
async fn sweep_sessions_prunes_expired_retired_device_tokens() {
    let session_id = "session-1";
    let state =
        make_test_state_with_session(make_test_session(session_id, "device-1", "device-token-1"));

    {
        let mut relay = state.inner.lock().await;
        let session = relay.sessions.get_mut(session_id).expect("session exists");
        let device = session.devices.get_mut("device-1").expect("device exists");
        device.retired_session_tokens.push(RetiredDeviceToken {
            token: "expired-grace-token".to_string(),
            expires_at_ms: now_ms() - 1,
        });
        relay.device_token_index.insert(
            "expired-grace-token".to_string(),
            DeviceTokenContext {
                session_id: session_id.to_string(),
                device_id: "device-1".to_string(),
                expires_at_ms: Some(now_ms() - 1),
            },
        );
    }

    sweep_sessions(&state).await;

    let relay = state.inner.lock().await;
    let session = relay.sessions.get(session_id).expect("session exists");
    let device = session.devices.get("device-1").expect("device exists");
    assert!(
        device
            .retired_session_tokens
            .iter()
            .all(|token| token.token != "expired-grace-token"),
        "expired grace token should be pruned from persisted session state"
    );
    assert!(
        !relay.device_token_index.contains_key("expired-grace-token"),
        "expired grace token should be pruned from the auth index"
    );
}

#[tokio::test]
async fn drain_sessions_for_shutdown_closes_active_sessions() {
    let session_id = "session-1";
    let state =
        make_test_state_with_session(make_test_session(session_id, "device-1", "device-token-1"));

    drain_sessions_for_shutdown(&state).await;

    let relay = state.inner.lock().await;
    assert!(relay.sessions.is_empty());
    assert!(relay.device_token_index.is_empty());
    assert!(relay.desktop_token_index.is_empty());
}

#[test]
fn replay_invariant_rejects_duplicate_cross_instance_nonce() {
    let mut relay = RelayState {
        sessions: HashMap::new(),
        desktop_token_index: HashMap::new(),
        device_token_index: HashMap::new(),
        rate_buckets: HashMap::new(),
        pending_join_waiters: 0,
        outbound_send_failures: 0,
        slow_consumer_disconnects: 0,
        pair_start_requests: 0,
        pair_start_successes: 0,
        pair_join_requests: 0,
        pair_join_successes: 0,
        pair_refresh_requests: 0,
        pair_refresh_successes: 0,
        ws_auth_attempts: 0,
        ws_auth_successes: 0,
        last_persistence_refresh_at_ms: 0,
        persistence_versions: HashMap::new(),
        seen_cross_instance_nonces: HashMap::new(),
        bus_subscribed_sessions: HashSet::new(),
        bus_subscription_tasks: HashMap::new(),
    };
    let now = now_ms();
    let envelope = CrossInstanceEnvelope {
        schema_version: 1,
        session_id: "session-1".to_string(),
        source_instance_id: "remote-instance".to_string(),
        target: "desktop".to_string(),
        target_device_id: None,
        payload: "{}".to_string(),
        issued_at_ms: now,
        nonce: "nonce-token-4".to_string(),
        signature: None,
    };

    assert!(register_cross_instance_nonce(
        &mut relay, &envelope, now, 120_000, 30_000
    ));
    assert!(
        !register_cross_instance_nonce(&mut relay, &envelope, now, 120_000, 30_000),
        "duplicate nonce should be rejected as replay"
    );
}

fn make_protocol_validation_config() -> RelayConfig {
    let mut config = RelayConfig::from_env();
    config.max_remote_commands_per_minute = 60;
    config.max_remote_session_commands_per_minute = 120;
    config.max_snapshot_requests_per_minute = 30;
    config.max_remote_command_text_bytes = 1_024;
    config
}

fn make_valid_command_payload(session_id: &str, sequence: u64) -> Value {
    json!({
        "schemaVersion": 2,
        "sessionID": session_id,
        "seq": sequence,
        "payload": {
            "type": "command",
            "payload": {
                "name": "thread.select",
                "commandID": format!("cmd-{}", sequence),
                "threadID": "thread-1"
            }
        }
    })
}

#[test]
fn protocol_invariant_rejects_replayed_command_sequences() {
    let config = make_protocol_validation_config();
    let mut session = make_test_session("session-1", "device-1", "token-1");
    let payload = make_valid_command_payload("session-1", 7);

    let first_result = validate_mobile_payload(
        &mut session,
        Some(&payload),
        "session-1",
        "conn-1",
        "device-1",
        &config,
    );
    assert!(first_result.is_ok());

    let replay_result = validate_mobile_payload(
        &mut session,
        Some(&payload),
        "session-1",
        "conn-1",
        "device-1",
        &config,
    );
    assert_eq!(
        replay_result.err().map(|error| error.code),
        Some("replayed_command")
    );
}

#[test]
fn protocol_invariant_rejects_invalid_snapshot_last_sequence() {
    let config = make_protocol_validation_config();
    let mut session = make_test_session("session-1", "device-1", "token-1");
    let payload = json!({
        "type": "relay.snapshot_request",
        "sessionID": "session-1",
        "lastSeq": -1,
        "reason": "integration-test"
    });

    let result = validate_mobile_payload(
        &mut session,
        Some(&payload),
        "session-1",
        "conn-1",
        "device-1",
        &config,
    );
    assert_eq!(
        result.err().map(|error| error.code),
        Some("invalid_snapshot_request")
    );
}

#[test]
fn protocol_invariant_overwrites_spoofed_mobile_metadata() {
    let raw = json!({
        "schemaVersion": 2,
        "sessionID": "session-1",
        "seq": 1,
        "relayConnectionID": "spoofed-connection",
        "relayDeviceID": "spoofed-device",
        "payload": {
            "type": "command",
            "payload": {
                "name": "thread.select",
                "commandID": "cmd-1",
                "threadID": "thread-1"
            }
        }
    })
    .to_string();

    let injected = inject_mobile_metadata(&raw, "conn-actual", "device-actual");
    let parsed: Value = serde_json::from_str(&injected).expect("injected payload");

    assert_eq!(
        parsed.get("relayConnectionID").and_then(Value::as_str),
        Some("conn-actual")
    );
    assert_eq!(
        parsed.get("relayDeviceID").and_then(Value::as_str),
        Some("device-actual")
    );
}

#[test]
fn protocol_invariant_rejects_missing_command_id() {
    let config = make_protocol_validation_config();
    let mut session = make_test_session("session-1", "device-1", "token-1");
    let payload = json!({
        "schemaVersion": 2,
        "sessionID": "session-1",
        "seq": 7,
        "payload": {
            "type": "command",
            "payload": {
                "name": "thread.select",
                "threadID": "thread-1"
            }
        }
    });

    let result = validate_mobile_payload(
        &mut session,
        Some(&payload),
        "session-1",
        "conn-1",
        "device-1",
        &config,
    );
    assert_eq!(
        result.err().map(|error| error.code),
        Some("invalid_command")
    );
}

#[test]
fn protocol_invariant_accepts_runtime_request_response_commands() {
    let config = make_protocol_validation_config();
    let mut session = make_test_session("session-1", "device-1", "token-1");
    let payload = json!({
        "schemaVersion": 2,
        "sessionID": "session-1",
        "seq": 8,
        "payload": {
            "type": "command",
            "payload": {
                "name": "runtime_request.respond",
                "commandID": "cmd-8",
                "runtimeRequestID": "42",
                "runtimeRequestKind": "approval",
                "runtimeRequestResponse": {
                    "decision": "accept",
                    "optionID": "accept"
                }
            }
        }
    });

    let result = validate_mobile_payload(
        &mut session,
        Some(&payload),
        "session-1",
        "conn-1",
        "device-1",
        &config,
    );
    assert!(result.is_ok());
}

#[test]
fn protocol_invariant_rejects_legacy_approval_response_commands() {
    let config = make_protocol_validation_config();
    let mut session = make_test_session("session-1", "device-1", "token-1");
    let payload = json!({
        "schemaVersion": 2,
        "sessionID": "session-1",
        "seq": 9,
        "payload": {
            "type": "command",
            "payload": {
                "name": "approval.respond",
                "commandID": "cmd-9",
                "approvalRequestID": "42",
                "approvalDecision": "approve_once"
            }
        }
    });

    let result = validate_mobile_payload(
        &mut session,
        Some(&payload),
        "session-1",
        "conn-1",
        "device-1",
        &config,
    );
    assert!(result.is_err());
}

#[test]
fn protocol_invariant_rejects_runtime_request_responses_without_fields() {
    let config = make_protocol_validation_config();
    let mut session = make_test_session("session-1", "device-1", "token-1");
    let payload = json!({
        "schemaVersion": 2,
        "sessionID": "session-1",
        "seq": 10,
        "payload": {
            "type": "command",
            "payload": {
                "name": "runtime_request.respond",
                "commandID": "cmd-10",
                "runtimeRequestID": "42",
                "runtimeRequestResponse": {}
            }
        }
    });

    let result = validate_mobile_payload(
        &mut session,
        Some(&payload),
        "session-1",
        "conn-1",
        "device-1",
        &config,
    );
    assert_eq!(
        result.err().map(|error| error.code),
        Some("invalid_command")
    );
}

proptest! {
    #[test]
    fn property_snapshot_last_seq_accepts_numeric_strings(last_seq in "[0-9]{1,20}") {
        let config = make_protocol_validation_config();
        let mut session = make_test_session("session-1", "device-1", "token-1");
        let payload = json!({
            "type": "relay.snapshot_request",
            "sessionID": "session-1",
            "lastSeq": last_seq,
            "reason": "property"
        });

        let result = validate_mobile_payload(
            &mut session,
            Some(&payload),
            "session-1",
            "conn-1",
            "device-1",
            &config,
        );

        prop_assert!(result.is_ok());
    }

    #[test]
    fn property_snapshot_last_seq_rejects_non_numeric_strings(last_seq in "[A-Za-z_][A-Za-z0-9_]{0,19}") {
        let config = make_protocol_validation_config();
        let mut session = make_test_session("session-1", "device-1", "token-1");
        let payload = json!({
            "type": "relay.snapshot_request",
            "sessionID": "session-1",
            "lastSeq": last_seq,
            "reason": "property"
        });

        let result = validate_mobile_payload(
            &mut session,
            Some(&payload),
            "session-1",
            "conn-1",
            "device-1",
            &config,
        );

        prop_assert_eq!(
            result.err().map(|error| error.code),
            Some("invalid_snapshot_request")
        );
    }

    #[test]
    fn property_inject_mobile_metadata_overwrites_spoofed_values(
        mut fields in hash_map("[a-z]{1,8}", any::<i32>(), 0..12)
    ) {
        fields.insert("relayConnectionID".to_string(), 7);
        fields.insert("relayDeviceID".to_string(), 9);

        let mut payload = serde_json::Map::new();
        for (key, value) in fields {
            payload.insert(key, Value::Number(value.into()));
        }

        let raw = Value::Object(payload).to_string();
        let injected = inject_mobile_metadata(&raw, "conn-prop", "device-prop");
        let parsed: Value = serde_json::from_str(&injected).expect("valid injected json");

        prop_assert_eq!(
            parsed.get("relayConnectionID").and_then(Value::as_str),
            Some("conn-prop")
        );
        prop_assert_eq!(
            parsed.get("relayDeviceID").and_then(Value::as_str),
            Some("device-prop")
        );
    }
}
