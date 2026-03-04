use super::*;

pub fn build_router(state: SharedRelayState) -> Router {
    let max_json_bytes = state.config.max_json_bytes;
    let cors_layer = build_cors_layer(&state.config);

    Router::new()
        .route("/healthz", axum::routing::get(healthz))
        .route("/metricsz", axum::routing::get(metricsz))
        .route(
            "/pair/start",
            axum::routing::post(pair_start).options(pair_options),
        )
        .route(
            "/pair/join",
            axum::routing::post(pair_join).options(pair_options),
        )
        .route(
            "/pair/refresh",
            axum::routing::post(pair_refresh).options(pair_options),
        )
        .route(
            "/pair/stop",
            axum::routing::post(pair_stop).options(pair_options),
        )
        .route(
            "/devices/list",
            axum::routing::post(devices_list).options(pair_options),
        )
        .route(
            "/devices/revoke",
            axum::routing::post(device_revoke).options(pair_options),
        )
        .route("/ws", axum::routing::get(ws_upgrade))
        .with_state(state)
        .layer(DefaultBodyLimit::max(max_json_bytes))
        .layer(cors_layer)
}

pub(super) async fn pair_options(
    State(state): State<SharedRelayState>,
    headers: HeaderMap,
) -> impl IntoResponse {
    if !origin_allowed(&state.config, &headers) {
        return StatusCode::FORBIDDEN;
    }

    StatusCode::NO_CONTENT
}

pub(super) async fn pair_start(
    State(state): State<SharedRelayState>,
    headers: HeaderMap,
    ConnectInfo(addr): ConnectInfo<SocketAddr>,
    Json(request): Json<PairStartRequest>,
) -> axum::response::Response {
    {
        let mut relay = state.inner.lock().await;
        relay.pair_start_requests = relay.pair_start_requests.saturating_add(1);
    }

    if !origin_allowed(&state.config, &headers) {
        return error_response(
            StatusCode::FORBIDDEN,
            "origin_not_allowed",
            "Origin is not allowed.",
        );
    }

    let client_ip = client_ip(&state.config, &headers, addr);
    if is_rate_limited(&state, &client_ip).await {
        return error_response(
            StatusCode::TOO_MANY_REQUESTS,
            "rate_limited",
            "Too many pairing attempts. Try again in a minute.",
        );
    }

    if !is_opaque_token(&request.session_id, 16)
        || !is_opaque_token(&request.join_token, 22)
        || !is_opaque_token(&request.desktop_session_token, 22)
    {
        return error_response(
            StatusCode::BAD_REQUEST,
            "invalid_pair_start",
            "sessionID, joinToken, and desktopSessionToken must be high-entropy opaque identifiers.",
        );
    }

    let Ok(expires_at) = DateTime::parse_from_rfc3339(&request.join_token_expires_at) else {
        return error_response(
            StatusCode::BAD_REQUEST,
            "invalid_pair_start",
            "joinTokenExpiresAt must be a valid RFC3339 timestamp.",
        );
    };

    let join_token_expires_at_ms = expires_at.timestamp_millis();
    if join_token_expires_at_ms <= now_ms() {
        return error_response(
            StatusCode::BAD_REQUEST,
            "expired_join_token",
            "joinTokenExpiresAt must be in the future.",
        );
    }

    let relay_web_socket_url = request
        .relay_web_socket_url
        .as_deref()
        .and_then(normalize_relay_web_socket_url)
        .unwrap_or_else(|| state.config.websocket_url());
    let desktop_session_token = request.desktop_session_token.clone();
    let idle_timeout_seconds = request
        .idle_timeout_seconds
        .unwrap_or(1_800)
        .clamp(60, 86_400);

    let mut relay = state.inner.lock().await;
    let replaced_existing_session = relay.sessions.contains_key(&request.session_id);
    if replaced_existing_session {
        close_session(
            &mut relay,
            &request.session_id,
            "replaced_by_new_pair_start",
        );
    }

    relay.sessions.insert(
        request.session_id.clone(),
        SessionRecord {
            session_id: request.session_id.clone(),
            join_token: request.join_token,
            join_token_expires_at_ms,
            join_token_used_at_ms: None,
            desktop_session_token: desktop_session_token.clone(),
            relay_web_socket_url: relay_web_socket_url.clone(),
            idle_timeout_seconds,
            created_at_ms: now_ms(),
            last_activity_at_ms: now_ms(),
            desktop_socket: None,
            desktop_connected: false,
            mobile_sockets: HashMap::new(),
            devices: HashMap::new(),
            command_rate_buckets: HashMap::new(),
            session_command_rate_bucket: None,
            snapshot_request_rate_buckets: HashMap::new(),
            command_sequence_by_connection_id: HashMap::new(),
            pending_join_request: None,
        },
    );
    relay
        .desktop_token_index
        .insert(desktop_session_token, request.session_id.clone());

    info!(
        "[relay-rs] pair_start session={}",
        session_log_id(&request.session_id)
    );
    drop(relay);
    if replaced_existing_session {
        let disconnect_payload =
            json!({ "type": "disconnect", "reason": "replaced_by_new_pair_start" }).to_string();
        publish_cross_instance_session(
            &state,
            &request.session_id,
            "desktop",
            None,
            disconnect_payload.clone(),
        );
        publish_cross_instance_session(
            &state,
            &request.session_id,
            "mobile",
            None,
            disconnect_payload,
        );
    }
    persist_session_if_needed(&state, &request.session_id).await;
    {
        let mut relay = state.inner.lock().await;
        relay.pair_start_successes = relay.pair_start_successes.saturating_add(1);
    }

    (
        StatusCode::OK,
        Json(PairStartResponse {
            accepted: true,
            session_id: request.session_id,
            ws_url: relay_web_socket_url,
        }),
    )
        .into_response()
}

pub(super) async fn pair_join(
    State(state): State<SharedRelayState>,
    headers: HeaderMap,
    ConnectInfo(addr): ConnectInfo<SocketAddr>,
    Json(request): Json<PairJoinRequest>,
) -> axum::response::Response {
    {
        let mut relay = state.inner.lock().await;
        relay.pair_join_requests = relay.pair_join_requests.saturating_add(1);
    }

    if !origin_allowed(&state.config, &headers) {
        return pair_join_failure_response(
            StatusCode::FORBIDDEN,
            "origin_not_allowed",
            "Origin is not allowed.",
        );
    }

    let client_ip = client_ip(&state.config, &headers, addr);
    if is_rate_limited(&state, &client_ip).await {
        return pair_join_failure_response(
            StatusCode::TOO_MANY_REQUESTS,
            "rate_limited",
            "Too many pairing attempts. Try again in a minute.",
        );
    }

    if !is_opaque_token(&request.session_id, 16) || !is_opaque_token(&request.join_token, 22) {
        return pair_join_failure_response(
            StatusCode::BAD_REQUEST,
            "invalid_pair_join",
            "sessionID and joinToken are required.",
        );
    }

    refresh_sessions_from_persistence(&state, false).await;

    let requested_device_name = request
        .device_name
        .as_deref()
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .map(|value| value.chars().take(64).collect::<String>());

    let (
        decision_rx,
        request_id,
        pair_request_payload,
        outbound_send_failures,
        slow_consumer_disconnects,
    ) = {
        let mut relay = state.inner.lock().await;
        if relay.pending_join_waiters >= state.config.max_pending_join_waiters {
            return pair_join_failure_response(
                StatusCode::SERVICE_UNAVAILABLE,
                "pairing_backpressure",
                "Relay is handling too many pending pairing approvals. Retry shortly.",
            );
        }

        let now = now_ms();
        let request_id = random_token(10);
        let (tx, rx) = oneshot::channel::<JoinDecision>();

        let (
            pair_request_payload,
            pair_request_outbound_send_failures,
            pair_request_slow_consumer_disconnects,
        ) = {
            let Some(session) = relay.sessions.get_mut(&request.session_id) else {
                return pair_join_failure_response(
                    StatusCode::NOT_FOUND,
                    "session_not_found",
                    "Remote session not found.",
                );
            };

            if now >= session.join_token_expires_at_ms {
                return pair_join_failure_response(
                    StatusCode::GONE,
                    "join_token_expired",
                    "Join token has expired.",
                );
            }

            if session.join_token_used_at_ms.is_some() {
                return pair_join_failure_response(
                    StatusCode::CONFLICT,
                    "join_token_already_used",
                    "Join token has already been redeemed. Start a new session from desktop.",
                );
            }

            if !safe_token_equals(&session.join_token, &request.join_token) {
                return pair_join_failure_response(
                    StatusCode::FORBIDDEN,
                    "invalid_join_token",
                    "Join token is invalid.",
                );
            }

            if session.devices.len() >= state.config.max_devices_per_session {
                return pair_join_failure_response(
                    StatusCode::CONFLICT,
                    "device_cap_reached",
                    &format!(
                        "This session allows at most {} connected devices.",
                        state.config.max_devices_per_session
                    ),
                );
            }

            if session.desktop_socket.is_none() && state.cross_instance_bus.is_none() {
                return pair_join_failure_response(
                    StatusCode::CONFLICT,
                    "desktop_not_connected",
                    "Desktop is not connected to relay. Re-open Remote Control on desktop and retry.",
                );
            }

            if let Some(pending) = &session.pending_join_request {
                warn!(
                    "[relay-rs] pair_join_failure code=pair_request_in_progress status={}",
                    StatusCode::CONFLICT.as_u16()
                );
                return (
                    StatusCode::CONFLICT,
                    Json(json!({
                        "error": "pair_request_in_progress",
                        "message": "A pairing approval request is already pending on desktop.",
                        "requestID": pending.request_id,
                        "expiresAt": iso_from_millis(pending.expires_at_ms),
                    })),
                )
                    .into_response();
            }

            let join_remaining_ms = (session.join_token_expires_at_ms - now).max(0);
            let timeout_ms = state
                .config
                .pair_approval_timeout_ms
                .min(join_remaining_ms as u64)
                .max(5_000);

            let pending = PendingJoinRequest {
                request_id: request_id.clone(),
                requester_ip: client_ip.clone(),
                requested_at_ms: now,
                expires_at_ms: now + timeout_ms as i64,
                decision_tx: tx,
            };

            let payload = RelayPairRequest {
                message_type: "relay.pair_request".to_string(),
                session_id: session.session_id.clone(),
                request_id: pending.request_id.clone(),
                device_name: requested_device_name.clone(),
                requester_ip: pending.requester_ip.clone(),
                requested_at: iso_from_millis(pending.requested_at_ms),
                expires_at: iso_from_millis(pending.expires_at_ms),
            };
            let encoded_payload =
                serde_json::to_string(&payload).unwrap_or_else(|_| "{}".to_string());

            let mut publish_remote_payload = None;
            let mut delivered_to_local_desktop = false;
            let mut outbound_send_failures = 0_u64;
            let mut slow_consumer_disconnects = 0_u64;
            if let Some(desktop) = &session.desktop_socket {
                if try_send_payload(&desktop.tx, encoded_payload.clone()) {
                    delivered_to_local_desktop = true;
                } else {
                    outbound_send_failures = outbound_send_failures.saturating_add(1);
                    slow_consumer_disconnects = slow_consumer_disconnects.saturating_add(1);
                    request_socket_disconnect(desktop, "slow_consumer");
                }
            }

            if !delivered_to_local_desktop && state.cross_instance_bus.is_some() {
                publish_remote_payload = Some(encoded_payload);
            }

            if publish_remote_payload.is_none() && !delivered_to_local_desktop {
                return pair_join_failure_response(
                    StatusCode::CONFLICT,
                    "desktop_not_connected",
                    "Desktop is not connected to relay. Re-open Remote Control on desktop and retry.",
                );
            }

            session.pending_join_request = Some(pending);
            (
                publish_remote_payload,
                outbound_send_failures,
                slow_consumer_disconnects,
            )
        };

        relay.pending_join_waiters += 1;
        (
            rx,
            request_id,
            pair_request_payload,
            pair_request_outbound_send_failures,
            pair_request_slow_consumer_disconnects,
        )
    };

    if outbound_send_failures > 0 || slow_consumer_disconnects > 0 {
        let mut relay = state.inner.lock().await;
        relay.outbound_send_failures = relay
            .outbound_send_failures
            .saturating_add(outbound_send_failures);
        relay.slow_consumer_disconnects = relay
            .slow_consumer_disconnects
            .saturating_add(slow_consumer_disconnects);
    }

    if let Some(payload) = pair_request_payload {
        publish_cross_instance_session(&state, &request.session_id, "desktop", None, payload);
    }

    let timeout_ms = state.config.pair_approval_timeout_ms;
    let decision = match timeout(Duration::from_millis(timeout_ms), decision_rx).await {
        Ok(Ok(result)) => result,
        Ok(Err(_)) => JoinDecision {
            approved: false,
            reason: "desktop_disconnected".to_string(),
        },
        Err(_) => JoinDecision {
            approved: false,
            reason: "approval_timeout".to_string(),
        },
    };

    let mut relay = state.inner.lock().await;
    relay.pending_join_waiters = relay.pending_join_waiters.saturating_sub(1);

    let device_name = sanitize_device_name(requested_device_name.as_deref());
    let (device_id, device_session_token, ws_url, session_id_for_token) = {
        let Some(session) = relay.sessions.get_mut(&request.session_id) else {
            return pair_join_failure_response(
                StatusCode::CONFLICT,
                "desktop_not_connected",
                "Desktop disconnected before pairing could be approved.",
            );
        };

        if let Some(pending) = &session.pending_join_request {
            if pending.request_id == request_id {
                session.pending_join_request = None;
            }
        }

        if !decision.approved {
            return match decision.reason.as_str() {
                "approval_timeout" => pair_join_failure_response(
                    StatusCode::REQUEST_TIMEOUT,
                    "pair_request_timed_out",
                    "Desktop pairing approval timed out.",
                ),
                "desktop_disconnected" | "session_closed" => pair_join_failure_response(
                    StatusCode::CONFLICT,
                    "desktop_not_connected",
                    "Desktop disconnected before pairing could be approved.",
                ),
                _ => pair_join_failure_response(
                    StatusCode::FORBIDDEN,
                    "pair_request_denied",
                    "Desktop denied this pairing request.",
                ),
            };
        }

        if now_ms() >= session.join_token_expires_at_ms {
            return pair_join_failure_response(
                StatusCode::GONE,
                "join_token_expired",
                "Join token has expired.",
            );
        }

        if !safe_token_equals(&session.join_token, &request.join_token) {
            return pair_join_failure_response(
                StatusCode::FORBIDDEN,
                "invalid_join_token",
                "Join token is invalid.",
            );
        }

        let device_id = random_token(12);
        let device_session_token = random_token(32);
        let now = now_ms();
        session.join_token_used_at_ms = Some(now);
        session.last_activity_at_ms = now;
        session.devices.insert(
            device_id.clone(),
            DeviceRecord {
                current_session_token: device_session_token.clone(),
                name: device_name.clone(),
                joined_at_ms: now,
                last_seen_at_ms: now,
            },
        );

        (
            device_id,
            device_session_token,
            session.relay_web_socket_url.clone(),
            session.session_id.clone(),
        )
    };

    relay.device_token_index.insert(
        device_session_token.clone(),
        DeviceTokenContext {
            session_id: session_id_for_token,
            device_id: device_id.clone(),
            expires_at_ms: None,
        },
    );

    info!(
        "[relay-rs] pair_join session={}",
        session_log_id(&request.session_id)
    );
    drop(relay);
    persist_session_if_needed(&state, &request.session_id).await;
    {
        let mut relay = state.inner.lock().await;
        relay.pair_join_successes = relay.pair_join_successes.saturating_add(1);
    }

    (
        StatusCode::OK,
        Json(PairJoinResponse {
            accepted: true,
            session_id: request.session_id,
            device_id,
            device_session_token,
            ws_url,
        }),
    )
        .into_response()
}

pub(super) async fn pair_refresh(
    State(state): State<SharedRelayState>,
    headers: HeaderMap,
    ConnectInfo(addr): ConnectInfo<SocketAddr>,
    Json(request): Json<PairRefreshRequest>,
) -> axum::response::Response {
    {
        let mut relay = state.inner.lock().await;
        relay.pair_refresh_requests = relay.pair_refresh_requests.saturating_add(1);
    }

    if !origin_allowed(&state.config, &headers) {
        return error_response(
            StatusCode::FORBIDDEN,
            "origin_not_allowed",
            "Origin is not allowed.",
        );
    }

    let client_ip = client_ip(&state.config, &headers, addr);
    if is_rate_limited(&state, &client_ip).await {
        return error_response(
            StatusCode::TOO_MANY_REQUESTS,
            "rate_limited",
            "Too many relay management requests. Try again in a minute.",
        );
    }

    if !is_opaque_token(&request.session_id, 16)
        || !is_opaque_token(&request.join_token, 22)
        || !is_opaque_token(&request.desktop_session_token, 22)
    {
        return error_response(
            StatusCode::BAD_REQUEST,
            "invalid_pair_refresh",
            "sessionID, joinToken, and desktopSessionToken are required.",
        );
    }

    refresh_sessions_from_persistence(&state, false).await;

    let Ok(expires_at) = DateTime::parse_from_rfc3339(&request.join_token_expires_at) else {
        return error_response(
            StatusCode::BAD_REQUEST,
            "invalid_pair_refresh",
            "joinTokenExpiresAt must be a valid RFC3339 timestamp.",
        );
    };

    let join_token_expires_at_ms = expires_at.timestamp_millis();
    if join_token_expires_at_ms <= now_ms() {
        return error_response(
            StatusCode::BAD_REQUEST,
            "expired_join_token",
            "joinTokenExpiresAt must be in the future.",
        );
    }

    let ws_url = {
        let mut relay = state.inner.lock().await;
        let Some(session) = relay.sessions.get_mut(&request.session_id) else {
            return error_response(
                StatusCode::NOT_FOUND,
                "session_not_found",
                "Remote session not found.",
            );
        };

        if !safe_token_equals(
            &session.desktop_session_token,
            &request.desktop_session_token,
        ) {
            return error_response(
                StatusCode::FORBIDDEN,
                "invalid_desktop_session_token",
                "Desktop session token is invalid.",
            );
        }

        session.join_token = request.join_token.clone();
        session.join_token_expires_at_ms = join_token_expires_at_ms;
        session.join_token_used_at_ms = None;
        session.last_activity_at_ms = now_ms();
        session.relay_web_socket_url.clone()
    };

    persist_session_if_needed(&state, &request.session_id).await;
    {
        let mut relay = state.inner.lock().await;
        relay.pair_refresh_successes = relay.pair_refresh_successes.saturating_add(1);
    }

    (
        StatusCode::OK,
        Json(PairRefreshResponse {
            accepted: true,
            session_id: request.session_id,
            ws_url,
        }),
    )
        .into_response()
}

pub(super) async fn pair_stop(
    State(state): State<SharedRelayState>,
    headers: HeaderMap,
    ConnectInfo(addr): ConnectInfo<SocketAddr>,
    Json(request): Json<PairStopRequest>,
) -> axum::response::Response {
    if !origin_allowed(&state.config, &headers) {
        return error_response(
            StatusCode::FORBIDDEN,
            "origin_not_allowed",
            "Origin is not allowed.",
        );
    }

    let client_ip = client_ip(&state.config, &headers, addr);
    if is_rate_limited(&state, &client_ip).await {
        return error_response(
            StatusCode::TOO_MANY_REQUESTS,
            "rate_limited",
            "Too many relay management requests. Try again in a minute.",
        );
    }

    if !is_opaque_token(&request.session_id, 16)
        || !is_opaque_token(&request.desktop_session_token, 22)
    {
        return error_response(
            StatusCode::BAD_REQUEST,
            "invalid_pair_stop",
            "sessionID and desktopSessionToken are required.",
        );
    }

    refresh_sessions_from_persistence(&state, false).await;

    let mut relay = state.inner.lock().await;
    if let Some(session) = relay.sessions.get(&request.session_id) {
        if !safe_token_equals(
            &session.desktop_session_token,
            &request.desktop_session_token,
        ) {
            return error_response(
                StatusCode::FORBIDDEN,
                "invalid_desktop_session_token",
                "Desktop session token is invalid.",
            );
        }
    }

    close_session(&mut relay, &request.session_id, "stopped_by_desktop");
    info!(
        "[relay-rs] pair_stop session={}",
        session_log_id(&request.session_id)
    );
    drop(relay);
    let disconnect_payload =
        json!({ "type": "disconnect", "reason": "stopped_by_desktop" }).to_string();
    publish_cross_instance_session(
        &state,
        &request.session_id,
        "desktop",
        None,
        disconnect_payload.clone(),
    );
    publish_cross_instance_session(
        &state,
        &request.session_id,
        "mobile",
        None,
        disconnect_payload,
    );
    persist_session_if_needed(&state, &request.session_id).await;

    (
        StatusCode::OK,
        Json(PairStopResponse {
            accepted: true,
            session_id: request.session_id,
        }),
    )
        .into_response()
}

pub(super) async fn devices_list(
    State(state): State<SharedRelayState>,
    headers: HeaderMap,
    ConnectInfo(addr): ConnectInfo<SocketAddr>,
    Json(request): Json<DevicesListRequest>,
) -> axum::response::Response {
    if !origin_allowed(&state.config, &headers) {
        return error_response(
            StatusCode::FORBIDDEN,
            "origin_not_allowed",
            "Origin is not allowed.",
        );
    }

    let client_ip = client_ip(&state.config, &headers, addr);
    if is_rate_limited(&state, &client_ip).await {
        return error_response(
            StatusCode::TOO_MANY_REQUESTS,
            "rate_limited",
            "Too many relay management requests. Try again in a minute.",
        );
    }

    if !is_opaque_token(&request.session_id, 16)
        || !is_opaque_token(&request.desktop_session_token, 22)
    {
        return error_response(
            StatusCode::BAD_REQUEST,
            "invalid_devices_list",
            "sessionID and desktopSessionToken are required.",
        );
    }

    refresh_sessions_from_persistence(&state, false).await;

    let mut relay = state.inner.lock().await;
    let Some(session) = relay.sessions.get_mut(&request.session_id) else {
        return error_response(
            StatusCode::NOT_FOUND,
            "session_not_found",
            "Remote session not found.",
        );
    };

    if !safe_token_equals(
        &session.desktop_session_token,
        &request.desktop_session_token,
    ) {
        return error_response(
            StatusCode::FORBIDDEN,
            "invalid_desktop_session_token",
            "Desktop session token is invalid.",
        );
    }

    session.last_activity_at_ms = now_ms();
    let mut devices = session
        .devices
        .iter()
        .map(|(device_id, record)| DeviceSummary {
            device_id: device_id.clone(),
            device_name: record.name.clone(),
            connected: session
                .mobile_sockets
                .values()
                .any(|socket| socket.device_id.as_deref() == Some(device_id.as_str())),
            joined_at: iso_from_millis(record.joined_at_ms),
            last_seen_at: iso_from_millis(record.last_seen_at_ms),
        })
        .collect::<Vec<_>>();
    devices.sort_by(|lhs, rhs| lhs.joined_at.cmp(&rhs.joined_at));

    (
        StatusCode::OK,
        Json(DevicesListResponse {
            accepted: true,
            session_id: request.session_id,
            devices,
        }),
    )
        .into_response()
}

pub(super) async fn device_revoke(
    State(state): State<SharedRelayState>,
    headers: HeaderMap,
    ConnectInfo(addr): ConnectInfo<SocketAddr>,
    Json(request): Json<DeviceRevokeRequest>,
) -> axum::response::Response {
    if !origin_allowed(&state.config, &headers) {
        return error_response(
            StatusCode::FORBIDDEN,
            "origin_not_allowed",
            "Origin is not allowed.",
        );
    }

    let client_ip = client_ip(&state.config, &headers, addr);
    if is_rate_limited(&state, &client_ip).await {
        return error_response(
            StatusCode::TOO_MANY_REQUESTS,
            "rate_limited",
            "Too many relay management requests. Try again in a minute.",
        );
    }

    if !is_opaque_token(&request.session_id, 16)
        || !is_opaque_token(&request.desktop_session_token, 22)
        || !is_opaque_token(&request.device_id, 8)
    {
        return error_response(
            StatusCode::BAD_REQUEST,
            "invalid_device_revoke",
            "sessionID, desktopSessionToken, and deviceID are required.",
        );
    }

    refresh_sessions_from_persistence(&state, false).await;

    let mut relay = state.inner.lock().await;
    let session_id = request.session_id.clone();
    let device_count_event = {
        let Some(session) = relay.sessions.get_mut(&session_id) else {
            return error_response(
                StatusCode::NOT_FOUND,
                "session_not_found",
                "Remote session not found.",
            );
        };

        if !safe_token_equals(
            &session.desktop_session_token,
            &request.desktop_session_token,
        ) {
            return error_response(
                StatusCode::FORBIDDEN,
                "invalid_desktop_session_token",
                "Desktop session token is invalid.",
            );
        }

        let Some(_removed_device) = session.devices.remove(&request.device_id) else {
            return error_response(
                StatusCode::NOT_FOUND,
                "device_not_found",
                "Device is not linked to this session.",
            );
        };
        session.command_rate_buckets.remove(&request.device_id);
        session
            .snapshot_request_rate_buckets
            .remove(&request.device_id);

        session.last_activity_at_ms = now_ms();
        close_existing_mobile_socket_for_device(session, &request.device_id, "device_revoked");
        send_device_count(session);
        device_count_payload(session)
    };

    relay.device_token_index.retain(|_, token| {
        !(token.session_id == session_id && token.device_id == request.device_id)
    });
    drop(relay);
    publish_cross_instance_session(
        &state,
        &request.session_id,
        "mobile",
        Some(request.device_id.clone()),
        json!({ "type": "disconnect", "reason": "device_revoked" }).to_string(),
    );
    publish_cross_instance_session(
        &state,
        &request.session_id,
        "desktop",
        None,
        device_count_event,
    );
    persist_session_if_needed(&state, &request.session_id).await;
    sync_session_bus_subscription(&state, &request.session_id).await;

    (
        StatusCode::OK,
        Json(DeviceRevokeResponse {
            accepted: true,
            session_id: request.session_id,
            device_id: request.device_id,
        }),
    )
        .into_response()
}

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
        warn!("[relay-rs] ws_auth_failure reason=auth_timeout_or_missing_payload");
        let _ = try_send_payload(&tx, "{}".to_string());
        close_writer_task(writer_task, tx).await;
        return;
    };

    if auth_message.message_type != "relay.auth" || !is_opaque_token(&auth_message.token, 22) {
        warn!("[relay-rs] ws_auth_failure reason=invalid_auth_payload");
        close_writer_task(writer_task, tx).await;
        return;
    }

    let auth = authenticate_socket(
        &state,
        &auth_message.token,
        origin.as_deref(),
        &tx,
        &shutdown_tx,
    )
    .await;
    let Some(auth) = auth else {
        warn!("[relay-rs] ws_auth_failure reason=invalid_or_rejected_token");
        close_writer_task(writer_task, tx).await;
        return;
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

    loop {
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

                let mut relay = state.inner.lock().await;
                if !relay.sessions.contains_key(auth.session_id()) {
                    continue;
                }

                let mut outbound_send_failures = 0_u64;
                let mut slow_consumer_disconnects = 0_u64;
                if let Some(session) = relay.sessions.get_mut(auth.session_id()) {
                    session.last_activity_at_ms = now_ms();

                    if let Some(parsed) = parsed.as_ref() {
                        if parsed
                            .get("sessionID")
                            .and_then(Value::as_str)
                            .is_some_and(|id| id != auth.session_id())
                        {
                            continue;
                        }
                    }

                    match &auth.auth {
                        SocketAuth::Desktop => {
                            if let Ok(pair_decision) = serde_json::from_str::<RelayPairDecision>(&raw) {
                                if pair_decision.message_type == "relay.pair_decision" {
                                    apply_pair_decision(session, &pair_decision, Some(&tx));
                                    publish_cross_instance_control_pair_decision(
                                        &state,
                                        auth.session_id(),
                                        raw.to_string(),
                                    );
                                    continue;
                                }
                            }

                            for mobile in session.mobile_sockets.values() {
                                if !try_send_payload(&mobile.tx, raw.to_string()) {
                                    outbound_send_failures =
                                        outbound_send_failures.saturating_add(1);
                                    slow_consumer_disconnects =
                                        slow_consumer_disconnects.saturating_add(1);
                                    request_socket_disconnect(mobile, "slow_consumer");
                                }
                            }
                            publish_cross_instance_session(
                                &state,
                                auth.session_id(),
                                "mobile",
                                None,
                                raw.to_string(),
                            );
                        }
                        SocketAuth::Mobile {
                            device_id,
                            connection_id,
                        } => {
                            let is_command_or_snapshot = parsed.as_ref().is_some_and(|payload| {
                                payload
                                    .pointer("/payload/type")
                                    .and_then(Value::as_str)
                                    .is_some_and(|value| value == "command")
                                    || payload.get("type").and_then(Value::as_str)
                                        == Some("relay.snapshot_request")
                            });
                            if is_command_or_snapshot && !desktop_connected(session) {
                                send_relay_error(
                                    &tx,
                                    "desktop_offline",
                                    "Mac is offline. Reconnect desktop and try again.",
                                );
                                continue;
                            }

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
                                    send_relay_error(&tx, error.code, &error.message);
                                    continue;
                                }
                            }

                            let forwarded = inject_mobile_metadata(&raw, connection_id, device_id);
                            if let Some(desktop) = &session.desktop_socket {
                                if !try_send_payload(&desktop.tx, forwarded.clone()) {
                                    outbound_send_failures =
                                        outbound_send_failures.saturating_add(1);
                                    slow_consumer_disconnects =
                                        slow_consumer_disconnects.saturating_add(1);
                                    request_socket_disconnect(desktop, "slow_consumer");
                                }
                            }
                            publish_cross_instance_session(
                                &state,
                                auth.session_id(),
                                "desktop",
                                None,
                                forwarded,
                            );
                        }
                    }
                }
                relay.outbound_send_failures = relay
                    .outbound_send_failures
                    .saturating_add(outbound_send_failures);
                relay.slow_consumer_disconnects = relay
                    .slow_consumer_disconnects
                    .saturating_add(slow_consumer_disconnects);
            }
        }
    }

    disconnect_socket(&state, &auth).await;
    close_writer_task(writer_task, tx).await;

    let _ = client_ip(&state.config, &headers, addr);
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

pub(super) fn origin_allowed(config: &RelayConfig, headers: &HeaderMap) -> bool {
    let origin = headers.get("origin").and_then(|value| value.to_str().ok());
    if origin.is_none() {
        return true;
    }
    is_allowed_origin(&config.allowed_origins, origin)
}
