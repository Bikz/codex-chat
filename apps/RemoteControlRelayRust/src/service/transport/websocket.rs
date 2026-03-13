use super::*;

pub(super) async fn ws_upgrade(
    State(state): State<SharedRelayState>,
    headers: HeaderMap,
    ConnectInfo(addr): ConnectInfo<SocketAddr>,
    Query(query): Query<HashMap<String, String>>,
    ws: WebSocketUpgrade,
) -> impl IntoResponse {
    let origin = headers
        .get("origin")
        .and_then(|value| value.to_str().ok())
        .map(ToOwned::to_owned);
    let legacy_query_token = if state.config.allow_legacy_query_token_auth {
        query.get("token").cloned()
    } else {
        None
    };
    let max_message_size = state.config.max_ws_message_bytes;

    ws.max_message_size(max_message_size)
        .max_frame_size(max_message_size)
        .on_upgrade(move |socket| async move {
            handle_socket(state, socket, headers, addr, origin, legacy_query_token).await;
        })
}

pub(super) async fn handle_socket(
    state: SharedRelayState,
    socket: WebSocket,
    headers: HeaderMap,
    addr: SocketAddr,
    origin: Option<String>,
    legacy_query_token: Option<String>,
) {
    let (mut writer, mut reader) = socket.split();
    let (tx, mut rx) = mpsc::channel::<Message>(state.config.max_socket_outbound_queue.max(8));
    let (shutdown_tx, mut shutdown_rx) = watch::channel(false);
    let client_ip = client_ip(&state.config, &headers, addr);
    let user_agent = headers
        .get("user-agent")
        .and_then(|value| value.to_str().ok())
        .map(ToOwned::to_owned);

    {
        let mut relay = state.inner.lock().await;
        relay.ws_auth_attempts = relay.ws_auth_attempts.saturating_add(1);
    }

    let writer_task = tokio::spawn(async move {
        while let Some(payload) = rx.recv().await {
            if writer.send(payload).await.is_err() {
                break;
            }
        }
    });

    let auth_message = if let Some(token) = legacy_query_token {
        Some(RelayAuthMessage {
            message_type: "relay.auth".to_string(),
            token,
        })
    } else {
        match timeout(
            Duration::from_millis(state.config.ws_auth_timeout_ms),
            reader.next(),
        )
        .await
        {
            Ok(Some(Ok(Message::Text(raw)))) => serde_json::from_str::<RelayAuthMessage>(&raw).ok(),
            _ => None,
        }
    };

    let Some(auth_message) = auth_message else {
        warn!(
            "[relay-rs] ws_auth_failure reason=auth_timeout_or_missing_payload remote_ip={} user_agent={}",
            client_ip,
            user_agent.as_deref().unwrap_or("-")
        );
        let _ = try_send_payload(&tx, "{}".to_string());
        close_writer_task(writer_task, tx).await;
        return;
    };

    if auth_message.message_type != "relay.auth" || !is_opaque_token(&auth_message.token, 22) {
        warn!(
            "[relay-rs] ws_auth_failure reason=invalid_auth_payload remote_ip={} user_agent={}",
            client_ip,
            user_agent.as_deref().unwrap_or("-")
        );
        close_writer_task(writer_task, tx).await;
        return;
    }

    let auth = authenticate_socket(
        &state,
        &auth_message.token,
        origin.as_deref(),
        &client_ip,
        user_agent.as_deref(),
        &tx,
        &shutdown_tx,
    )
    .await;
    let auth = match auth {
        Ok(auth) => auth,
        Err(SocketAuthFailure::SessionExpired) => {
            close_writer_task_with_policy_violation(writer_task, tx, "session_expired").await;
            return;
        }
        Err(SocketAuthFailure::Rejected) => {
            close_writer_task(writer_task, tx).await;
            return;
        }
    };

    let mut ws_message_rate_bucket = RateBucket {
        count: 0,
        window_ends_at_ms: now_ms() + 60_000,
    };
    let mut last_heartbeat_at_ms = now_ms();
    let heartbeat_interval_ms = state.config.ws_heartbeat_interval_ms.max(1_000);
    let heartbeat_timeout_ms = state
        .config
        .ws_heartbeat_timeout_ms
        .max(heartbeat_interval_ms.saturating_mul(2));
    let mut heartbeat = interval(Duration::from_millis(heartbeat_interval_ms));
    heartbeat.set_missed_tick_behavior(MissedTickBehavior::Delay);
    heartbeat.tick().await;

    'socket_loop: loop {
        tokio::select! {
            changed = shutdown_rx.changed() => {
                if changed.is_err() || *shutdown_rx.borrow() {
                    break;
                }
            }
            _ = heartbeat.tick() => {
                let now = now_ms();
                if now - last_heartbeat_at_ms > heartbeat_timeout_ms as i64 {
                    let _ = try_send_payload(
                        &tx,
                        json!({
                            "type": "disconnect",
                            "reason": "heartbeat_timeout"
                        })
                        .to_string(),
                    );
                    break;
                }
                if !try_send_message(&tx, Message::Ping(Vec::new().into())) {
                    break;
                }
            }
            message = reader.next() => {
                let Some(message) = message else {
                    break;
                };
                let raw = match message {
                    Ok(Message::Text(raw)) => {
                        last_heartbeat_at_ms = now_ms();
                        raw
                    }
                    Ok(Message::Pong(_)) => {
                        last_heartbeat_at_ms = now_ms();
                        touch_session_activity(&state, auth.session_id()).await;
                        continue;
                    }
                    Ok(Message::Ping(payload)) => {
                        last_heartbeat_at_ms = now_ms();
                        let _ = try_send_message(&tx, Message::Pong(payload));
                        touch_session_activity(&state, auth.session_id()).await;
                        continue;
                    }
                    Ok(Message::Close(_)) | Err(_) => break,
                    _ => continue,
                };
                if raw.len() > state.config.max_ws_message_bytes {
                    let _ = try_send_payload(
                        &tx,
                        json!({
                            "type": "disconnect",
                            "reason": "message_too_large"
                        })
                        .to_string(),
                    );
                    break;
                }

                if !consume_rate_bucket(
                    &mut ws_message_rate_bucket,
                    state.config.max_ws_messages_per_minute,
                ) {
                    let _ = try_send_payload(
                        &tx,
                        json!({
                            "type": "disconnect",
                            "reason": "socket_rate_limited"
                        })
                        .to_string(),
                    );
                    break;
                }

                let parsed = serde_json::from_str::<Value>(&raw).ok();
                let mut publish_target: Option<(&'static str, String)> = None;
                let mut publish_pair_decision = false;
                let mut outbound_send_failures = 0_u64;
                let mut slow_consumer_disconnects = 0_u64;
                let mut mobile_targets: Vec<SocketHandle> = Vec::new();
                let mut desktop_target: Option<SocketHandle> = None;
                let mut relay_error: Option<(String, String)> = None;
                let mut should_continue = false;
                let mut should_break = false;

                {
                    let mut relay = state.inner.lock().await;
                    if !relay.sessions.contains_key(auth.session_id()) {
                        continue;
                    }

                    if let Some(session) = relay.sessions.get_mut(auth.session_id()) {
                        if !socket_matches_active_registration(session, &auth, &shutdown_tx) {
                            should_break = true;
                        } else {
                            session.last_activity_at_ms = now_ms();

                            if let Some(parsed) = parsed.as_ref() {
                                if parsed
                                    .get("sessionID")
                                    .and_then(Value::as_str)
                                    .is_some_and(|id| id != auth.session_id())
                                {
                                    should_continue = true;
                                }
                            }

                            if !should_continue {
                                match &auth.auth {
                                    SocketAuth::Desktop => {
                                        if let Ok(pair_decision) =
                                            serde_json::from_str::<RelayPairDecision>(&raw)
                                        {
                                            if pair_decision.message_type == "relay.pair_decision" {
                                                apply_pair_decision(
                                                    session,
                                                    &pair_decision,
                                                    Some(&tx),
                                                );
                                                publish_pair_decision = true;
                                                should_continue = true;
                                            }
                                        }

                                        if !should_continue {
                                            mobile_targets =
                                                session.mobile_sockets.values().cloned().collect();
                                            publish_target = Some(("mobile", raw.to_string()));
                                        }
                                    }
                                    SocketAuth::Mobile {
                                        device_id,
                                        connection_id,
                                    } => {
                                        let is_command_or_snapshot =
                                            parsed.as_ref().is_some_and(|payload| {
                                                payload
                                                    .pointer("/payload/type")
                                                    .and_then(Value::as_str)
                                                    .is_some_and(|value| value == "command")
                                                    || payload.get("type").and_then(Value::as_str)
                                                        == Some("relay.snapshot_request")
                                            });
                                        if is_command_or_snapshot && !desktop_connected(session) {
                                            relay_error = Some((
                                                "desktop_offline".to_string(),
                                                "Mac is offline. Reconnect desktop and try again."
                                                    .to_string(),
                                            ));
                                            should_continue = true;
                                        }

                                        if !should_continue {
                                            match validate_mobile_payload(
                                                session,
                                                parsed.as_ref(),
                                                auth.session_id(),
                                                connection_id,
                                                device_id,
                                                &state.config,
                                            ) {
                                                Ok(()) => {}
                                                Err(error) => {
                                                    relay_error = Some((
                                                        error.code.to_string(),
                                                        error.message,
                                                    ));
                                                    should_continue = true;
                                                }
                                            }
                                        }

                                        if !should_continue {
                                            let forwarded = inject_mobile_metadata(
                                                &raw,
                                                connection_id,
                                                device_id,
                                            );
                                            desktop_target = session.desktop_socket.clone();
                                            publish_target = Some(("desktop", forwarded));
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                if should_break {
                    break 'socket_loop;
                }
                if let Some((error_code, error_message)) = relay_error {
                    send_relay_error(&tx, &error_code, &error_message);
                    continue;
                }
                if publish_pair_decision {
                    publish_cross_instance_control_pair_decision(
                        &state,
                        auth.session_id(),
                        raw.to_string(),
                    );
                    continue;
                }
                if should_continue {
                    continue;
                }

                for mobile in &mobile_targets {
                    if !try_send_payload(&mobile.tx, raw.to_string()) {
                        outbound_send_failures = outbound_send_failures.saturating_add(1);
                        slow_consumer_disconnects = slow_consumer_disconnects.saturating_add(1);
                        request_socket_disconnect(mobile, "slow_consumer");
                    }
                }

                if let Some(desktop) = &desktop_target {
                    if let Some((_, payload)) = publish_target.as_ref() {
                        if !try_send_payload(&desktop.tx, payload.clone()) {
                            outbound_send_failures = outbound_send_failures.saturating_add(1);
                            slow_consumer_disconnects = slow_consumer_disconnects.saturating_add(1);
                            request_socket_disconnect(desktop, "slow_consumer");
                        }
                    }
                }

                if let Some((target, payload)) = publish_target {
                    publish_cross_instance_session(
                        &state,
                        auth.session_id(),
                        target,
                        None,
                        payload,
                    );
                }

                if outbound_send_failures > 0 || slow_consumer_disconnects > 0 {
                    let mut relay = state.inner.lock().await;
                    relay.outbound_send_failures = relay
                        .outbound_send_failures
                        .saturating_add(outbound_send_failures);
                    relay.slow_consumer_disconnects = relay
                        .slow_consumer_disconnects
                        .saturating_add(slow_consumer_disconnects);
                }
            }
        }
    }

    disconnect_socket(&state, &auth).await;
    close_writer_task(writer_task, tx).await;
}

pub(super) async fn close_writer_task(
    mut writer_task: tokio::task::JoinHandle<()>,
    tx: mpsc::Sender<Message>,
) {
    drop(tx);
    if timeout(Duration::from_millis(100), &mut writer_task)
        .await
        .is_err()
    {
        writer_task.abort();
    }
}

async fn close_writer_task_with_policy_violation(
    writer_task: tokio::task::JoinHandle<()>,
    tx: mpsc::Sender<Message>,
    reason: &'static str,
) {
    let _ = try_send_payload(
        &tx,
        json!({
            "type": "disconnect",
            "reason": reason,
        })
        .to_string(),
    );
    let _ = try_send_message(
        &tx,
        Message::Close(Some(CloseFrame {
            code: axum::extract::ws::close_code::POLICY,
            reason: reason.into(),
        })),
    );
    close_writer_task(writer_task, tx).await;
}

fn socket_matches_active_registration(
    session: &SessionRecord,
    auth: &AuthenticatedSocket,
    shutdown_tx: &watch::Sender<bool>,
) -> bool {
    match &auth.auth {
        SocketAuth::Desktop => session
            .desktop_socket
            .as_ref()
            .is_some_and(|socket| socket.shutdown.same_channel(shutdown_tx)),
        SocketAuth::Mobile {
            device_id,
            connection_id,
        } => session
            .mobile_sockets
            .get(connection_id)
            .is_some_and(|socket| {
                socket.shutdown.same_channel(shutdown_tx)
                    && socket.device_id.as_deref() == Some(device_id.as_str())
            }),
    }
}
