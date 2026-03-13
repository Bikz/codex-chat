use super::*;

const REMOTE_DESKTOP_STATUS_PROBE_TIMEOUT_MS: i64 = 150;
const REMOTE_DESKTOP_STATUS_PROBE_POLL_INTERVAL_MS: u64 = 15;

pub(super) enum SocketAuth {
    Desktop,
    Mobile {
        device_id: String,
        connection_id: String,
    },
}

pub(super) struct AuthenticatedSocket {
    pub(super) session_id: String,
    pub(super) auth: SocketAuth,
}

pub(super) enum SocketAuthFailure {
    Rejected,
    SessionExpired,
}

impl AuthenticatedSocket {
    pub(super) fn session_id(&self) -> &str {
        &self.session_id
    }
}

fn rollback_desktop_auth_registration(
    relay: &mut RelayState,
    session_id: &str,
    shutdown_tx: &watch::Sender<bool>,
) {
    let Some(session) = relay.sessions.get_mut(session_id) else {
        return;
    };
    if session
        .desktop_socket
        .as_ref()
        .is_some_and(|socket| socket.shutdown.same_channel(shutdown_tx))
    {
        session.desktop_socket = None;
        session.desktop_connected = false;
    }
}

fn rollback_mobile_auth_registration(
    relay: &mut RelayState,
    session_id: &str,
    device_id: &str,
    connection_id: &str,
    old_token: &str,
    next_token: &str,
    now: i64,
) {
    if let Some(session) = relay.sessions.get_mut(session_id) {
        session.mobile_sockets.remove(connection_id);
        session
            .command_sequence_by_connection_id
            .remove(connection_id);
        session.last_activity_at_ms = now;
        if let Some(device) = session.devices.get_mut(device_id) {
            device.current_session_token = old_token.to_string();
            device
                .retired_session_tokens
                .retain(|token| token.token != old_token);
            device.last_seen_at_ms = now;
        }
    }

    relay.device_token_index.remove(next_token);
    relay.device_token_index.insert(
        old_token.to_string(),
        DeviceTokenContext {
            session_id: session_id.to_string(),
            device_id: device_id.to_string(),
            expires_at_ms: None,
        },
    );
}

async fn resolve_cross_instance_desktop_presence(
    state: &SharedRelayState,
    session_id: &str,
    has_local_desktop: bool,
) -> bool {
    if has_local_desktop {
        return true;
    }
    if state.cross_instance_bus.is_none() {
        return false;
    }

    {
        let mut relay = state.inner.lock().await;
        let Some(session) = relay.sessions.get_mut(session_id) else {
            return false;
        };
        session.desktop_connected = false;
    }

    publish_cross_instance_control_desktop_status_probe(state, session_id);

    let deadline = now_ms().saturating_add(REMOTE_DESKTOP_STATUS_PROBE_TIMEOUT_MS);
    loop {
        let is_connected = {
            let relay = state.inner.lock().await;
            relay
                .sessions
                .get(session_id)
                .is_some_and(desktop_connected)
        };
        if is_connected || now_ms() >= deadline {
            return is_connected;
        }
        sleep(Duration::from_millis(
            REMOTE_DESKTOP_STATUS_PROBE_POLL_INTERVAL_MS,
        ))
        .await;
    }
}

pub(super) async fn authenticate_socket(
    state: &SharedRelayState,
    token: &str,
    origin: Option<&str>,
    remote_ip: &str,
    user_agent: Option<&str>,
    tx: &mpsc::Sender<Message>,
    shutdown_tx: &watch::Sender<bool>,
) -> Result<AuthenticatedSocket, SocketAuthFailure> {
    let auth_context = {
        let relay = state.inner.lock().await;
        resolve_auth_context(&relay, token)
    };

    let auth_context = if let Some(auth_context) = auth_context {
        auth_context
    } else {
        refresh_sessions_from_persistence(state, true).await;
        let mut relay = state.inner.lock().await;
        let refreshed = resolve_auth_context(&relay, token);
        if refreshed.is_none() {
            record_ws_auth_failure_reason(&mut relay, "token_not_found");
            warn!(
                "[relay-rs] ws_auth_failure reason=token_not_found remote_ip={} user_agent={}",
                remote_ip,
                user_agent.unwrap_or("-")
            );
        }
        refreshed.ok_or(SocketAuthFailure::SessionExpired)?
    };

    let mut relay = state.inner.lock().await;
    let current_active_connections = relay_runtime_stats(&relay).active_web_sockets;
    let reconnection_without_growth = match &auth_context {
        AuthContext::Desktop { session_id } => relay
            .sessions
            .get(session_id)
            .and_then(|session| session.desktop_socket.as_ref())
            .is_some(),
        AuthContext::Mobile {
            session_id,
            device_id,
        } => relay.sessions.get(session_id).is_some_and(|session| {
            session
                .mobile_sockets
                .values()
                .any(|socket| socket.device_id.as_deref() == Some(device_id.as_str()))
        }),
    };
    if current_active_connections >= state.config.max_active_websocket_connections
        && !reconnection_without_growth
    {
        record_ws_auth_failure_reason(&mut relay, "relay_over_capacity");
        warn!(
            "[relay-rs] ws_auth_failure reason=relay_over_capacity active={} limit={} remote_ip={} user_agent={}",
            current_active_connections,
            state.config.max_active_websocket_connections,
            remote_ip,
            user_agent.unwrap_or("-")
        );
        if !try_send_payload(
            tx,
            json!({ "type": "disconnect", "reason": "relay_over_capacity" }).to_string(),
        ) {
            relay.outbound_send_failures = relay.outbound_send_failures.saturating_add(1);
        }
        return Err(SocketAuthFailure::Rejected);
    }

    match auth_context {
        AuthContext::Desktop { session_id } => {
            let (
                auth_payload,
                desktop_status_event,
                desktop_status_send_failures,
                desktop_status_slow_consumer_disconnects,
            ) = {
                let Some(session) = relay.sessions.get_mut(&session_id) else {
                    record_ws_auth_failure_reason(&mut relay, "desktop_session_missing");
                    warn!(
                        "[relay-rs] ws_auth_failure reason=desktop_session_missing remote_ip={} user_agent={}",
                        remote_ip,
                        user_agent.unwrap_or("-")
                    );
                    return Err(SocketAuthFailure::SessionExpired);
                };
                session.last_activity_at_ms = now_ms();

                if let Some(existing) = session.desktop_socket.take() {
                    request_socket_disconnect(&existing, "desktop_reconnected");
                }

                session.desktop_socket = Some(SocketHandle {
                    tx: tx.clone(),
                    shutdown: shutdown_tx.clone(),
                    device_id: None,
                });
                session.desktop_connected = true;

                let payload = RelayAuthOk {
                    message_type: "auth_ok".to_string(),
                    role: "desktop".to_string(),
                    session_id: session_id.clone(),
                    device_id: None,
                    next_device_session_token: None,
                    connected_device_count: session.mobile_sockets.len(),
                    desktop_connected: desktop_connected(session),
                };
                let (desktop_status_event, send_failures, slow_consumer_disconnects) =
                    send_desktop_status(session);
                (
                    payload,
                    desktop_status_event,
                    send_failures,
                    slow_consumer_disconnects,
                )
            };
            if !try_send_payload(
                tx,
                serde_json::to_string(&auth_payload).unwrap_or_else(|_| "{}".to_string()),
            ) {
                rollback_desktop_auth_registration(&mut relay, &session_id, shutdown_tx);
                relay.outbound_send_failures = relay.outbound_send_failures.saturating_add(1);
                return Err(SocketAuthFailure::Rejected);
            }
            relay.outbound_send_failures = relay
                .outbound_send_failures
                .saturating_add(desktop_status_send_failures);
            relay.slow_consumer_disconnects = relay
                .slow_consumer_disconnects
                .saturating_add(desktop_status_slow_consumer_disconnects);
            relay.ws_auth_successes = relay.ws_auth_successes.saturating_add(1);

            info!(
                "[relay-rs] desktop_connected session={}",
                session_log_id(&session_id)
            );
            drop(relay);
            publish_cross_instance_session(
                state,
                &session_id,
                "mobile",
                None,
                desktop_status_event,
            );
            persist_session_if_needed(state, &session_id).await;
            sync_session_bus_subscription(state, &session_id).await;
            Ok(AuthenticatedSocket {
                session_id,
                auth: SocketAuth::Desktop,
            })
        }
        AuthContext::Mobile {
            session_id,
            device_id,
        } => {
            if !is_allowed_origin(&state.config.allowed_origins, origin) {
                record_ws_auth_failure_reason(&mut relay, "mobile_origin_not_allowed");
                warn!(
                    "[relay-rs] ws_auth_failure reason=mobile_origin_not_allowed remote_ip={} user_agent={}",
                    remote_ip,
                    user_agent.unwrap_or("-")
                );
                return Err(SocketAuthFailure::Rejected);
            }

            let connection_id = random_token(10);
            let now = now_ms();
            let next_token = random_token(32);

            let (old_token, connected_device_count, device_count_event, local_desktop) = {
                let Some(session) = relay.sessions.get_mut(&session_id) else {
                    record_ws_auth_failure_reason(&mut relay, "mobile_session_missing");
                    warn!(
                        "[relay-rs] ws_auth_failure reason=mobile_session_missing remote_ip={} user_agent={}",
                        remote_ip,
                        user_agent.unwrap_or("-")
                    );
                    return Err(SocketAuthFailure::SessionExpired);
                };
                session.last_activity_at_ms = now;

                if !session.devices.contains_key(&device_id) {
                    record_ws_auth_failure_reason(&mut relay, "device_not_registered");
                    warn!(
                        "[relay-rs] ws_auth_failure reason=device_not_registered remote_ip={} user_agent={}",
                        remote_ip,
                        user_agent.unwrap_or("-")
                    );
                    return Err(SocketAuthFailure::SessionExpired);
                }

                close_existing_mobile_socket_for_device(session, &device_id, "device_reconnected");

                if session.mobile_sockets.len() >= state.config.max_devices_per_session {
                    record_ws_auth_failure_reason(&mut relay, "device_cap_reached");
                    warn!(
                        "[relay-rs] ws_auth_failure reason=device_cap_reached remote_ip={} user_agent={}",
                        remote_ip,
                        user_agent.unwrap_or("-")
                    );
                    return Err(SocketAuthFailure::Rejected);
                }

                let Some(device) = session.devices.get_mut(&device_id) else {
                    record_ws_auth_failure_reason(&mut relay, "device_record_missing");
                    warn!(
                        "[relay-rs] ws_auth_failure reason=device_record_missing remote_ip={} user_agent={}",
                        remote_ip,
                        user_agent.unwrap_or("-")
                    );
                    return Err(SocketAuthFailure::SessionExpired);
                };
                let old_token = device.current_session_token.clone();
                device.current_session_token = next_token.clone();
                device
                    .retired_session_tokens
                    .retain(|token| now < token.expires_at_ms && token.token != old_token);
                if state.config.token_rotation_grace_ms > 0 {
                    device.retired_session_tokens.push(RetiredDeviceToken {
                        token: old_token.clone(),
                        expires_at_ms: now + state.config.token_rotation_grace_ms as i64,
                    });
                }
                device.last_seen_at_ms = now;

                session.mobile_sockets.insert(
                    connection_id.clone(),
                    SocketHandle {
                        tx: tx.clone(),
                        shutdown: shutdown_tx.clone(),
                        device_id: Some(device_id.clone()),
                    },
                );

                let connected_device_count = session.mobile_sockets.len();
                (
                    old_token,
                    connected_device_count,
                    device_count_payload(session),
                    session.desktop_socket.clone(),
                )
            };

            if state.config.token_rotation_grace_ms == 0 {
                relay.device_token_index.remove(&old_token);
            } else {
                relay.device_token_index.insert(
                    old_token.clone(),
                    DeviceTokenContext {
                        session_id: session_id.clone(),
                        device_id: device_id.clone(),
                        expires_at_ms: Some(now + state.config.token_rotation_grace_ms as i64),
                    },
                );
            }

            relay.device_token_index.insert(
                next_token.clone(),
                DeviceTokenContext {
                    session_id: session_id.clone(),
                    device_id: device_id.clone(),
                    expires_at_ms: None,
                },
            );

            drop(relay);
            if let Err(error) = persist_session_if_needed_checked(state, &session_id).await {
                let mut relay = state.inner.lock().await;
                rollback_mobile_auth_registration(
                    &mut relay,
                    &session_id,
                    &device_id,
                    &connection_id,
                    &old_token,
                    &next_token,
                    now,
                );
                record_ws_auth_failure_reason(&mut relay, "token_rotation_persist_failed");
                warn!(
                    "[relay-rs] ws_auth_failure reason=token_rotation_persist_failed session={} remote_ip={} user_agent={} error={error}",
                    session_log_id(&session_id),
                    remote_ip,
                    user_agent.unwrap_or("-")
                );
                return Err(SocketAuthFailure::Rejected);
            }
            sync_session_bus_subscription(state, &session_id).await;
            let desktop_connected = resolve_cross_instance_desktop_presence(
                state,
                &session_id,
                local_desktop.is_some(),
            )
            .await;

            let payload = RelayAuthOk {
                message_type: "auth_ok".to_string(),
                role: "mobile".to_string(),
                session_id: session_id.clone(),
                device_id: Some(device_id.clone()),
                next_device_session_token: Some(next_token.clone()),
                connected_device_count,
                desktop_connected,
            };
            if !try_send_payload(
                tx,
                serde_json::to_string(&payload).unwrap_or_else(|_| "{}".to_string()),
            ) {
                let mut relay = state.inner.lock().await;
                rollback_mobile_auth_registration(
                    &mut relay,
                    &session_id,
                    &device_id,
                    &connection_id,
                    &old_token,
                    &next_token,
                    now,
                );
                relay.outbound_send_failures = relay.outbound_send_failures.saturating_add(1);
                drop(relay);
                persist_session_if_needed(state, &session_id).await;
                return Err(SocketAuthFailure::Rejected);
            }
            let mut outbound_send_failures = 0_u64;
            let mut slow_consumer_disconnects = 0_u64;
            if let Some(desktop) = &local_desktop {
                if !try_send_payload(&desktop.tx, device_count_event.clone()) {
                    outbound_send_failures = outbound_send_failures.saturating_add(1);
                    slow_consumer_disconnects = slow_consumer_disconnects.saturating_add(1);
                    request_socket_disconnect(desktop, "slow_consumer");
                }
            }

            let mut relay = state.inner.lock().await;
            relay.outbound_send_failures = relay
                .outbound_send_failures
                .saturating_add(outbound_send_failures);
            relay.slow_consumer_disconnects = relay
                .slow_consumer_disconnects
                .saturating_add(slow_consumer_disconnects);
            relay.ws_auth_successes = relay.ws_auth_successes.saturating_add(1);

            info!(
                "[relay-rs] mobile_connected session={} devices={}",
                session_log_id(&session_id),
                connected_device_count
            );
            drop(relay);
            publish_cross_instance_session(state, &session_id, "desktop", None, device_count_event);

            Ok(AuthenticatedSocket {
                session_id,
                auth: SocketAuth::Mobile {
                    device_id,
                    connection_id,
                },
            })
        }
    }
}

pub(super) fn resolve_auth_context(relay: &RelayState, token: &str) -> Option<AuthContext> {
    if !is_opaque_token(token, 22) {
        return None;
    }

    if let Some(session_id) = relay.desktop_token_index.get(token) {
        if relay.sessions.contains_key(session_id) {
            return Some(AuthContext::Desktop {
                session_id: session_id.clone(),
            });
        }
    }

    relay.device_token_index.get(token).and_then(|ctx| {
        if let Some(expires) = ctx.expires_at_ms {
            if now_ms() >= expires {
                return None;
            }
        }

        Some(AuthContext::Mobile {
            session_id: ctx.session_id.clone(),
            device_id: ctx.device_id.clone(),
        })
    })
}

pub(super) async fn disconnect_socket(state: &SharedRelayState, auth: &AuthenticatedSocket) {
    let mut relay = state.inner.lock().await;
    let Some(session) = relay.sessions.get_mut(auth.session_id()) else {
        return;
    };

    session.last_activity_at_ms = now_ms();
    let mut device_count_event: Option<String> = None;
    let mut desktop_status_event: Option<String> = None;
    let mut outbound_send_failures = 0_u64;
    let mut slow_consumer_disconnects = 0_u64;

    match &auth.auth {
        SocketAuth::Desktop => {
            session.desktop_socket = None;
            session.desktop_connected = false;
            if let Some(pending) = session.pending_join_request.take() {
                let _ = pending.decision_tx.send(JoinDecision {
                    approved: false,
                    reason: "desktop_disconnected".to_string(),
                });
            }
            let (event, send_failures, consumer_disconnects) = send_desktop_status(session);
            desktop_status_event = Some(event);
            outbound_send_failures = outbound_send_failures.saturating_add(send_failures);
            slow_consumer_disconnects =
                slow_consumer_disconnects.saturating_add(consumer_disconnects);
            info!(
                "[relay-rs] desktop_disconnected session={}",
                session_log_id(auth.session_id())
            );
        }
        SocketAuth::Mobile {
            connection_id,
            device_id: _,
        } => {
            session.mobile_sockets.remove(connection_id);
            session
                .command_sequence_by_connection_id
                .remove(connection_id);
            send_device_count(session);
            device_count_event = Some(device_count_payload(session));
            info!(
                "[relay-rs] mobile_disconnected session={} devices={}",
                session_log_id(auth.session_id()),
                session.mobile_sockets.len()
            );
        }
    }
    relay.outbound_send_failures = relay
        .outbound_send_failures
        .saturating_add(outbound_send_failures);
    relay.slow_consumer_disconnects = relay
        .slow_consumer_disconnects
        .saturating_add(slow_consumer_disconnects);

    drop(relay);

    if let Some(event) = device_count_event {
        publish_cross_instance_session(state, auth.session_id(), "desktop", None, event);
    }
    if let Some(event) = desktop_status_event {
        publish_cross_instance_session(state, auth.session_id(), "mobile", None, event);
        persist_session_if_needed(state, auth.session_id()).await;
    }
    sync_session_bus_subscription(state, auth.session_id()).await;
}
