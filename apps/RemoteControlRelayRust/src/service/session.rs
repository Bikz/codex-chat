use super::*;

pub(super) fn start_session_sweeper(state: SharedRelayState) {
    tokio::spawn(async move {
        loop {
            sleep(Duration::from_secs(30)).await;
            sweep_sessions(&state).await;
        }
    });
}

pub(super) async fn sweep_sessions(state: &SharedRelayState) {
    let now = now_ms();
    let mut relay = state.inner.lock().await;

    let mut close_ids = Vec::new();
    let mut mutated_session_ids = HashSet::new();
    for (session_id, session) in &relay.sessions {
        let has_connected_sockets =
            session.desktop_socket.is_some() || !session.mobile_sockets.is_empty();
        let has_trusted_devices = !session.devices.is_empty();
        let idle_limit_ms = session.idle_timeout_seconds.max(60) as i64 * 1_000;
        if !has_connected_sockets
            && !has_trusted_devices
            && now - session.last_activity_at_ms >= idle_limit_ms
        {
            close_ids.push((session_id.clone(), "idle_timeout".to_string()));
            continue;
        }

        let is_past_retention =
            now - session.created_at_ms >= state.config.session_retention_ms as i64;
        let has_no_connections = !has_connected_sockets;
        if is_past_retention && has_no_connections && !has_trusted_devices {
            close_ids.push((session_id.clone(), "retention_expired".to_string()));
        }
    }

    let mut did_mutate = false;
    let mut closed_session_ids = Vec::new();
    for (session_id, reason) in close_ids {
        close_session(&mut relay, &session_id, &reason);
        did_mutate = true;
        closed_session_ids.push(session_id);
    }

    for (session_id, session) in &mut relay.sessions {
        let mut session_mutated = false;
        for device in session.devices.values_mut() {
            let retired_count_before = device.retired_session_tokens.len();
            device
                .retired_session_tokens
                .retain(|token| now < token.expires_at_ms);
            if device.retired_session_tokens.len() != retired_count_before {
                session_mutated = true;
            }
        }
        if session_mutated {
            did_mutate = true;
            mutated_session_ids.insert(session_id.clone());
        }
    }

    let token_count_before = relay.device_token_index.len();
    relay.device_token_index.retain(|_, ctx| {
        ctx.expires_at_ms
            .map(|expires| now < expires)
            .unwrap_or(true)
    });
    if relay.device_token_index.len() != token_count_before {
        did_mutate = true;
    }
    let rate_bucket_count_before = relay.rate_buckets.len();
    relay
        .rate_buckets
        .retain(|_, bucket| now < bucket.window_ends_at_ms);
    if relay.rate_buckets.len() != rate_bucket_count_before {
        did_mutate = true;
    }
    drop(relay);

    if did_mutate {
        for session_id in closed_session_ids {
            let payload = json!({ "type": "disconnect", "reason": "session_expired" }).to_string();
            publish_cross_instance_session(state, &session_id, "desktop", None, payload.clone());
            publish_cross_instance_session(state, &session_id, "mobile", None, payload);
            persist_session_if_needed(state, &session_id).await;
            sync_session_bus_subscription(state, &session_id).await;
        }
        for session_id in mutated_session_ids {
            persist_session_if_needed(state, &session_id).await;
        }
    }
}

pub(super) fn close_existing_mobile_socket_for_device(
    session: &mut SessionRecord,
    device_id: &str,
    reason: &str,
) {
    let key = session
        .mobile_sockets
        .iter()
        .find(|(_, handle)| handle.device_id.as_deref() == Some(device_id))
        .map(|(connection_id, _)| connection_id.clone());

    if let Some(key) = key {
        if let Some(handle) = session.mobile_sockets.remove(&key) {
            session.command_sequence_by_connection_id.remove(&key);
            request_socket_disconnect(&handle, reason);
        }
    }
}

pub(super) fn desktop_connected(session: &SessionRecord) -> bool {
    session.desktop_connected || session.desktop_socket.is_some()
}

pub(super) fn desktop_status_payload(session: &SessionRecord) -> String {
    let payload = RelayDesktopStatus {
        message_type: "relay.desktop_status".to_string(),
        session_id: session.session_id.clone(),
        desktop_connected: desktop_connected(session),
    };
    serde_json::to_string(&payload).unwrap_or_else(|_| "{}".to_string())
}

pub(super) fn send_desktop_status(session: &SessionRecord) -> (String, u64, u64) {
    let payload = desktop_status_payload(session);
    let mut outbound_send_failures = 0_u64;
    let mut slow_consumer_disconnects = 0_u64;

    for mobile in session.mobile_sockets.values() {
        if !try_send_payload(&mobile.tx, payload.clone()) {
            outbound_send_failures = outbound_send_failures.saturating_add(1);
            slow_consumer_disconnects = slow_consumer_disconnects.saturating_add(1);
            request_socket_disconnect(mobile, "slow_consumer");
        }
    }

    (payload, outbound_send_failures, slow_consumer_disconnects)
}

pub(super) fn send_device_count(session: &SessionRecord) {
    let payload = device_count_payload(session);
    let Some(desktop) = &session.desktop_socket else {
        return;
    };

    if !try_send_payload(&desktop.tx, payload) {
        request_socket_disconnect(desktop, "slow_consumer");
    }
}

pub(super) fn device_count_payload(session: &SessionRecord) -> String {
    let payload = RelayDeviceCount {
        message_type: "relay.device_count".to_string(),
        session_id: session.session_id.clone(),
        connected_device_count: session.mobile_sockets.len(),
    };
    serde_json::to_string(&payload).unwrap_or_else(|_| "{}".to_string())
}

pub(super) async fn touch_session_activity(state: &SharedRelayState, session_id: &str) {
    let mut relay = state.inner.lock().await;
    if let Some(session) = relay.sessions.get_mut(session_id) {
        session.last_activity_at_ms = now_ms();
    }
}

pub(super) async fn is_rate_limited(state: &SharedRelayState, ip: &str) -> bool {
    let now = now_ms();
    let mut relay = state.inner.lock().await;
    let bucket = relay
        .rate_buckets
        .entry(ip.to_string())
        .or_insert(RateBucket {
            count: 0,
            window_ends_at_ms: now + 60_000,
        });

    if now >= bucket.window_ends_at_ms {
        bucket.count = 1;
        bucket.window_ends_at_ms = now + 60_000;
        return false;
    }

    bucket.count += 1;
    bucket.count > state.config.max_pair_requests_per_minute
}

pub(super) fn close_session(relay: &mut RelayState, session_id: &str, reason: &str) {
    let Some(session) = relay.sessions.remove(session_id) else {
        return;
    };
    relay.bus_subscribed_sessions.remove(session_id);
    if let Some(task) = relay.bus_subscription_tasks.remove(session_id) {
        task.abort();
    }

    if let Some(pending) = session.pending_join_request {
        let _ = pending.decision_tx.send(JoinDecision {
            approved: false,
            reason: "session_closed".to_string(),
        });
    }

    relay
        .device_token_index
        .retain(|_, context| context.session_id != session.session_id);
    relay
        .desktop_token_index
        .remove(&session.desktop_session_token);

    if let Some(desktop) = session.desktop_socket {
        request_socket_disconnect(&desktop, reason);
    }

    for mobile in session.mobile_sockets.into_values() {
        request_socket_disconnect(&mobile, reason);
    }

    info!(
        "[relay-rs] closed session={} reason={reason}",
        session_log_id(session_id)
    );
}

pub async fn drain_sessions_for_shutdown(state: &SharedRelayState) {
    let session_ids = {
        let mut relay = state.inner.lock().await;
        let ids = relay.sessions.keys().cloned().collect::<Vec<_>>();
        for session_id in &ids {
            close_session(&mut relay, session_id, "server_shutdown");
        }
        ids
    };

    for session_id in session_ids {
        let disconnect_payload =
            json!({ "type": "disconnect", "reason": "server_shutdown" }).to_string();
        publish_cross_instance_session(
            state,
            &session_id,
            "desktop",
            None,
            disconnect_payload.clone(),
        );
        publish_cross_instance_session(state, &session_id, "mobile", None, disconnect_payload);
        persist_session_if_needed(state, &session_id).await;
        sync_session_bus_subscription(state, &session_id).await;
    }
}
