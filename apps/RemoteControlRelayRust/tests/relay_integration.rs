use std::net::SocketAddr;
use std::time::Duration;

use futures_util::{SinkExt, StreamExt};
use remote_control_relay_rust::config::RelayConfig;
use remote_control_relay_rust::service::{build_router, new_state};
use reqwest::StatusCode;
use serde_json::{json, Value};
use tokio::net::TcpListener;
use tokio::task::JoinHandle;
use tokio_tungstenite::tungstenite::client::IntoClientRequest;
use tokio_tungstenite::tungstenite::protocol::frame::coding::CloseCode;
use tokio_tungstenite::tungstenite::Message;

type TestSocket =
    tokio_tungstenite::WebSocketStream<tokio_tungstenite::MaybeTlsStream<tokio::net::TcpStream>>;

async fn spawn_test_server() -> (String, JoinHandle<()>) {
    spawn_test_server_with_config(|_| {}).await
}

async fn spawn_test_server_with_config(
    configure: impl FnOnce(&mut RelayConfig),
) -> (String, JoinHandle<()>) {
    let listener = TcpListener::bind("127.0.0.1:0")
        .await
        .expect("bind listener");
    let addr = listener.local_addr().expect("listener local addr");

    let mut config = RelayConfig::from_env();
    config.host = "127.0.0.1".to_string();
    config.port = addr.port();
    config.public_base_url = format!("http://{}:{}", addr.ip(), addr.port());
    config.allowed_origins = ["http://localhost:4173".to_string()].into_iter().collect();
    configure(&mut config);

    let state = new_state(config).await;
    let app = build_router(state);

    let task = tokio::spawn(async move {
        axum::serve(
            listener,
            app.into_make_service_with_connect_info::<SocketAddr>(),
        )
        .await
        .expect("serve relay");
    });

    (format!("http://{}:{}", addr.ip(), addr.port()), task)
}

fn random_token(byte_count: usize) -> String {
    let bytes = (0..byte_count)
        .map(|_| rand::random::<u8>())
        .collect::<Vec<_>>();
    use base64::Engine;
    base64::engine::general_purpose::URL_SAFE_NO_PAD.encode(bytes)
}

async fn next_matching_json_message(
    socket: &mut TestSocket,
    timeout_ms: u64,
    mut predicate: impl FnMut(&Value) -> bool,
) -> Value {
    loop {
        let message = tokio::time::timeout(Duration::from_millis(timeout_ms), socket.next())
            .await
            .expect("expected websocket frame before timeout")
            .expect("expected websocket frame")
            .expect("expected websocket message");
        if let Message::Text(text) = message {
            let payload: Value =
                serde_json::from_str(text.as_ref()).expect("expected JSON websocket payload");
            if predicate(&payload) {
                return payload;
            }
        }
    }
}

async fn expect_disconnect_with_reason(
    socket: &mut TestSocket,
    timeout_ms: u64,
    expected_reason: &str,
) {
    let disconnect = next_matching_json_message(socket, timeout_ms, |payload| {
        payload.get("type").and_then(Value::as_str) == Some("disconnect")
    })
    .await;
    assert_eq!(
        disconnect.get("reason").and_then(Value::as_str),
        Some(expected_reason)
    );
}

async fn expect_policy_close(socket: &mut TestSocket, timeout_ms: u64) {
    let frame = tokio::time::timeout(Duration::from_millis(timeout_ms), socket.next())
        .await
        .expect("expected websocket close frame before timeout")
        .expect("expected websocket close frame")
        .expect("expected websocket close message");
    match frame {
        Message::Close(Some(frame)) => {
            assert_eq!(frame.code, CloseCode::Policy);
        }
        other => panic!("expected policy close frame, got {other:?}"),
    }
}

async fn pair_connected_mobile(
    configure: impl FnOnce(&mut RelayConfig),
) -> (
    String,
    JoinHandle<()>,
    TestSocket,
    TestSocket,
    String,
    String,
    String,
) {
    let (base, task) = spawn_test_server_with_config(configure).await;
    let client = reqwest::Client::new();

    let session_id = random_token(16);
    let join_token = random_token(32);
    let desktop_session_token = random_token(32);

    let start_response = client
        .post(format!("{base}/pair/start"))
        .json(&json!({
            "schemaVersion": 2,
            "sessionID": session_id,
            "joinToken": join_token,
            "desktopSessionToken": desktop_session_token,
            "joinTokenExpiresAt": chrono::Utc::now().checked_add_signed(chrono::Duration::minutes(2)).unwrap().to_rfc3339(),
            "idleTimeoutSeconds": 1800,
        }))
        .send()
        .await
        .expect("pair start request");
    assert_eq!(start_response.status(), StatusCode::OK);
    let start_payload: Value = start_response.json().await.expect("pair start payload");
    let ws_url = start_payload
        .get("wsURL")
        .and_then(Value::as_str)
        .expect("ws url")
        .to_string();

    let (mut desktop_socket, _) = tokio_tungstenite::connect_async(&ws_url)
        .await
        .expect("desktop websocket");

    desktop_socket
        .send(Message::Text(
            json!({ "type": "relay.auth", "token": desktop_session_token }).to_string(),
        ))
        .await
        .expect("desktop auth send");

    let _desktop_auth = desktop_socket
        .next()
        .await
        .expect("desktop auth message")
        .expect("desktop auth frame");

    let join_future = tokio::spawn({
        let client = client.clone();
        let base = base.clone();
        let session_id = session_id.clone();
        let join_token = join_token.clone();
        async move {
            client
                .post(format!("{base}/pair/join"))
                .header("Origin", "http://localhost:4173")
                .json(&json!({
                    "sessionID": session_id,
                    "joinToken": join_token,
                    "deviceName": "Test iPhone",
                }))
                .send()
                .await
                .expect("pair join request")
        }
    });

    let pair_request = desktop_socket
        .next()
        .await
        .expect("pair request frame")
        .expect("pair request message");
    let pair_request_json: Value =
        serde_json::from_str(pair_request.to_text().expect("pair request text"))
            .expect("pair request json");
    let request_id = pair_request_json
        .get("requestID")
        .and_then(Value::as_str)
        .expect("requestID")
        .to_string();

    desktop_socket
        .send(Message::Text(
            json!({
                "type": "relay.pair_decision",
                "sessionID": session_id,
                "requestID": request_id,
                "approved": true,
            })
            .to_string(),
        ))
        .await
        .expect("desktop pair decision send");

    let join_response = join_future.await.expect("join task");
    assert_eq!(join_response.status(), StatusCode::OK);
    let join_payload: Value = join_response.json().await.expect("join payload");
    let device_token = join_payload
        .get("deviceSessionToken")
        .and_then(Value::as_str)
        .expect("device token")
        .to_string();

    let mut mobile_request = ws_url
        .clone()
        .into_client_request()
        .expect("mobile request");
    mobile_request.headers_mut().insert(
        "Origin",
        "http://localhost:4173".parse().expect("origin header"),
    );

    let (mut mobile_socket, _) = tokio_tungstenite::connect_async(mobile_request)
        .await
        .expect("mobile websocket");

    mobile_socket
        .send(Message::Text(
            json!({ "type": "relay.auth", "token": device_token }).to_string(),
        ))
        .await
        .expect("mobile auth send");

    let mobile_auth = mobile_socket
        .next()
        .await
        .expect("mobile auth frame")
        .expect("mobile auth message");
    let mobile_auth_json: Value =
        serde_json::from_str(mobile_auth.to_text().expect("mobile auth text"))
            .expect("mobile auth json");
    let rotated_device_token = mobile_auth_json
        .get("nextDeviceSessionToken")
        .and_then(Value::as_str)
        .expect("rotated device token")
        .to_string();

    // Drain any relay bookkeeping events before assertions.
    while let Ok(Some(Ok(_))) =
        tokio::time::timeout(Duration::from_millis(50), desktop_socket.next()).await
    {}

    (
        base,
        task,
        desktop_socket,
        mobile_socket,
        session_id,
        device_token,
        rotated_device_token,
    )
}

#[tokio::test]
async fn healthz_reports_ok() {
    let (base, task) = spawn_test_server().await;
    let response = reqwest::get(format!("{base}/healthz"))
        .await
        .expect("healthz request");

    assert_eq!(response.status(), StatusCode::OK);
    let body: Value = response.json().await.expect("healthz body");
    assert_eq!(body.get("ok").and_then(Value::as_bool), Some(true));
    assert_eq!(
        body.get("activeWebSockets").and_then(Value::as_u64),
        Some(0)
    );

    task.abort();
}

#[tokio::test]
async fn metricsz_reports_runtime_counters_for_connected_devices() {
    let (
        base,
        task,
        _desktop_socket,
        _mobile_socket,
        _session_id,
        _device_token,
        _rotated_device_token,
    ) =
        pair_connected_mobile(|config| {
            config.token_rotation_grace_ms = 0;
        })
        .await;

    let response = reqwest::get(format!("{base}/metricsz"))
        .await
        .expect("metricsz request");
    assert_eq!(response.status(), StatusCode::OK);
    let body: Value = response.json().await.expect("metricsz body");

    assert_eq!(body.get("ok").and_then(Value::as_bool), Some(true));
    assert_eq!(
        body.get("sessionsWithDesktop").and_then(Value::as_u64),
        Some(1)
    );
    assert_eq!(
        body.get("sessionsWithMobile").and_then(Value::as_u64),
        Some(1)
    );
    assert_eq!(
        body.get("activeWebSockets").and_then(Value::as_u64),
        Some(2)
    );
    assert_eq!(body.get("deviceTokens").and_then(Value::as_u64), Some(1));
    assert_eq!(
        body.get("commandRateLimitBuckets").and_then(Value::as_u64),
        Some(0)
    );
    assert_eq!(
        body.get("snapshotRateLimitBuckets").and_then(Value::as_u64),
        Some(0)
    );
    assert_eq!(
        body.get("outboundSendFailures").and_then(Value::as_u64),
        Some(0)
    );
    assert_eq!(
        body.get("slowConsumerDisconnects").and_then(Value::as_u64),
        Some(0)
    );
    assert_eq!(
        body.get("pairStartRequests").and_then(Value::as_u64),
        Some(1)
    );
    assert_eq!(
        body.get("pairStartSuccesses").and_then(Value::as_u64),
        Some(1)
    );
    assert_eq!(
        body.get("pairStartFailures").and_then(Value::as_u64),
        Some(0)
    );
    assert_eq!(
        body.get("pairJoinRequests").and_then(Value::as_u64),
        Some(1)
    );
    assert_eq!(
        body.get("pairJoinSuccesses").and_then(Value::as_u64),
        Some(1)
    );
    assert_eq!(
        body.get("pairJoinFailures").and_then(Value::as_u64),
        Some(0)
    );
    assert_eq!(
        body.get("pairRefreshRequests").and_then(Value::as_u64),
        Some(0)
    );
    assert_eq!(
        body.get("pairRefreshSuccesses").and_then(Value::as_u64),
        Some(0)
    );
    assert_eq!(
        body.get("pairRefreshFailures").and_then(Value::as_u64),
        Some(0)
    );
    assert_eq!(body.get("wsAuthAttempts").and_then(Value::as_u64), Some(2));
    assert_eq!(body.get("wsAuthSuccesses").and_then(Value::as_u64), Some(2));
    assert_eq!(body.get("wsAuthFailures").and_then(Value::as_u64), Some(0));

    task.abort();
}

#[tokio::test]
async fn pair_join_requires_desktop_connection() {
    let (base, task) = spawn_test_server().await;
    let client = reqwest::Client::new();

    let session_id = random_token(16);
    let join_token = random_token(32);
    let desktop_session_token = random_token(32);

    let start_response = client
        .post(format!("{base}/pair/start"))
        .json(&json!({
            "sessionID": session_id,
            "joinToken": join_token,
            "desktopSessionToken": desktop_session_token,
            "joinTokenExpiresAt": chrono::Utc::now().checked_add_signed(chrono::Duration::minutes(2)).unwrap().to_rfc3339(),
            "idleTimeoutSeconds": 1800,
        }))
        .send()
        .await
        .expect("pair start request");

    assert_eq!(start_response.status(), StatusCode::OK);

    let join_response = client
        .post(format!("{base}/pair/join"))
        .header("Origin", "http://localhost:4173")
        .json(&json!({
            "sessionID": session_id,
            "joinToken": join_token,
        }))
        .send()
        .await
        .expect("pair join request");

    assert_eq!(join_response.status(), StatusCode::CONFLICT);
    let payload: Value = join_response.json().await.expect("join error payload");
    assert_eq!(
        payload.get("error").and_then(Value::as_str),
        Some("desktop_not_connected")
    );

    task.abort();
}

#[tokio::test]
async fn pair_start_rejects_replacing_live_session_with_different_desktop_token() {
    let (base, task) = spawn_test_server().await;
    let client = reqwest::Client::new();

    let session_id = random_token(16);
    let first_join_token = random_token(32);
    let first_desktop_session_token = random_token(32);

    let first_start = client
        .post(format!("{base}/pair/start"))
        .json(&json!({
            "schemaVersion": 2,
            "sessionID": session_id,
            "joinToken": first_join_token,
            "desktopSessionToken": first_desktop_session_token,
            "joinTokenExpiresAt": chrono::Utc::now().checked_add_signed(chrono::Duration::minutes(2)).unwrap().to_rfc3339(),
            "idleTimeoutSeconds": 1800,
        }))
        .send()
        .await
        .expect("first pair start");
    assert_eq!(first_start.status(), StatusCode::OK);

    let first_start_payload: Value = first_start.json().await.expect("first pair start payload");
    let ws_url = first_start_payload
        .get("wsURL")
        .and_then(Value::as_str)
        .expect("ws url")
        .to_string();

    let (mut desktop_socket, _) = tokio_tungstenite::connect_async(&ws_url)
        .await
        .expect("desktop websocket");
    desktop_socket
        .send(Message::Text(
            json!({ "type": "relay.auth", "token": first_desktop_session_token }).to_string(),
        ))
        .await
        .expect("desktop auth send");
    let _auth_ok = desktop_socket
        .next()
        .await
        .expect("desktop auth frame")
        .expect("desktop auth message");

    let second_start = client
        .post(format!("{base}/pair/start"))
        .json(&json!({
            "schemaVersion": 2,
            "sessionID": session_id,
            "joinToken": random_token(32),
            "desktopSessionToken": random_token(32),
            "joinTokenExpiresAt": chrono::Utc::now().checked_add_signed(chrono::Duration::minutes(2)).unwrap().to_rfc3339(),
            "idleTimeoutSeconds": 1800,
        }))
        .send()
        .await
        .expect("second pair start");

    assert_eq!(second_start.status(), StatusCode::CONFLICT);
    let second_start_body: Value = second_start.json().await.expect("second pair start body");
    assert_eq!(
        second_start_body.get("error").and_then(Value::as_str),
        Some("session_already_active")
    );

    desktop_socket
        .close(None)
        .await
        .expect("desktop socket close");
    task.abort();
}

#[tokio::test]
async fn pair_start_rejects_unknown_fields() {
    let (base, task) = spawn_test_server().await;
    let client = reqwest::Client::new();

    let response = client
        .post(format!("{base}/pair/start"))
        .json(&json!({
            "schemaVersion": 2,
            "sessionID": random_token(16),
            "joinToken": random_token(32),
            "desktopSessionToken": random_token(32),
            "joinTokenExpiresAt": chrono::Utc::now().checked_add_signed(chrono::Duration::minutes(2)).unwrap().to_rfc3339(),
            "idleTimeoutSeconds": 1800,
            "unexpected": "field"
        }))
        .send()
        .await
        .expect("pair start with unexpected field");

    assert_eq!(response.status(), StatusCode::UNPROCESSABLE_ENTITY);
    task.abort();
}

#[tokio::test]
async fn pair_start_rejects_unsupported_schema_version() {
    let (base, task) = spawn_test_server().await;
    let client = reqwest::Client::new();

    let response = client
        .post(format!("{base}/pair/start"))
        .json(&json!({
            "schemaVersion": 1,
            "sessionID": random_token(16),
            "joinToken": random_token(32),
            "desktopSessionToken": random_token(32),
            "joinTokenExpiresAt": chrono::Utc::now().checked_add_signed(chrono::Duration::minutes(2)).unwrap().to_rfc3339(),
            "idleTimeoutSeconds": 1800,
        }))
        .send()
        .await
        .expect("pair start with unsupported schema version");

    assert_eq!(response.status(), StatusCode::BAD_REQUEST);
    let payload: Value = response
        .json()
        .await
        .expect("pair start schema error payload");
    assert_eq!(
        payload.get("error").and_then(Value::as_str),
        Some("unsupported_schema_version")
    );

    task.abort();
}

#[tokio::test]
async fn websocket_auth_rejects_new_connections_when_capacity_reached() {
    let (base, task) = spawn_test_server_with_config(|config| {
        config.max_active_websocket_connections = 1;
    })
    .await;
    let client = reqwest::Client::new();

    let session_id = random_token(16);
    let join_token = random_token(32);
    let desktop_session_token = random_token(32);

    let start_response = client
        .post(format!("{base}/pair/start"))
        .json(&json!({
            "sessionID": session_id,
            "joinToken": join_token,
            "desktopSessionToken": desktop_session_token,
            "joinTokenExpiresAt": chrono::Utc::now().checked_add_signed(chrono::Duration::minutes(2)).unwrap().to_rfc3339(),
            "idleTimeoutSeconds": 1800,
        }))
        .send()
        .await
        .expect("pair start request");
    assert_eq!(start_response.status(), StatusCode::OK);
    let start_payload: Value = start_response.json().await.expect("pair start payload");
    let ws_url = start_payload
        .get("wsURL")
        .and_then(Value::as_str)
        .expect("ws url")
        .to_string();

    let (mut desktop_socket, _) = tokio_tungstenite::connect_async(&ws_url)
        .await
        .expect("desktop websocket");
    desktop_socket
        .send(Message::Text(
            json!({ "type": "relay.auth", "token": desktop_session_token }).to_string(),
        ))
        .await
        .expect("desktop auth send");
    let _desktop_auth = desktop_socket
        .next()
        .await
        .expect("desktop auth frame")
        .expect("desktop auth message");

    let join_future = tokio::spawn({
        let client = client.clone();
        let base = base.clone();
        let session_id = session_id.clone();
        let join_token = join_token.clone();
        async move {
            client
                .post(format!("{base}/pair/join"))
                .header("Origin", "http://localhost:4173")
                .json(&json!({
                    "sessionID": session_id,
                    "joinToken": join_token,
                }))
                .send()
                .await
                .expect("pair join request")
        }
    });

    let pair_request = desktop_socket
        .next()
        .await
        .expect("pair request frame")
        .expect("pair request message");
    let pair_request_json: Value =
        serde_json::from_str(pair_request.to_text().expect("pair request text"))
            .expect("pair request json");
    let request_id = pair_request_json
        .get("requestID")
        .and_then(Value::as_str)
        .expect("requestID")
        .to_string();

    desktop_socket
        .send(Message::Text(
            json!({
                "type": "relay.pair_decision",
                "sessionID": session_id,
                "requestID": request_id,
                "approved": true,
            })
            .to_string(),
        ))
        .await
        .expect("desktop pair decision send");

    let join_response = join_future.await.expect("join task");
    assert_eq!(join_response.status(), StatusCode::OK);
    let join_payload: Value = join_response.json().await.expect("join payload");
    let device_token = join_payload
        .get("deviceSessionToken")
        .and_then(Value::as_str)
        .expect("device token")
        .to_string();

    let mut mobile_request = ws_url
        .clone()
        .into_client_request()
        .expect("mobile request");
    mobile_request.headers_mut().insert(
        "Origin",
        "http://localhost:4173".parse().expect("origin header"),
    );
    let (mut mobile_socket, _) = tokio_tungstenite::connect_async(mobile_request)
        .await
        .expect("mobile websocket");
    mobile_socket
        .send(Message::Text(
            json!({ "type": "relay.auth", "token": device_token }).to_string(),
        ))
        .await
        .expect("mobile auth send");

    let next = tokio::time::timeout(Duration::from_millis(1_000), mobile_socket.next())
        .await
        .expect("expected auth response or close");
    match next {
        Some(Ok(Message::Text(text))) => {
            let payload: Value = serde_json::from_str(&text).expect("disconnect payload json");
            assert_eq!(
                payload.get("type").and_then(Value::as_str),
                Some("disconnect")
            );
            assert_eq!(
                payload.get("reason").and_then(Value::as_str),
                Some("relay_over_capacity")
            );
        }
        Some(Ok(Message::Close(_))) | Some(Err(_)) | None => {}
        other => panic!("unexpected websocket frame: {other:?}"),
    }

    let metrics_response = reqwest::get(format!("{base}/metricsz"))
        .await
        .expect("metrics request");
    assert_eq!(metrics_response.status(), StatusCode::OK);
    let metrics_body: Value = metrics_response.json().await.expect("metrics body");
    assert_eq!(
        metrics_body
            .get("outboundSendFailures")
            .and_then(Value::as_u64),
        Some(0),
        "capacity rejection should not be counted as an outbound send failure when disconnect frame is queued"
    );

    task.abort();
}

#[tokio::test]
async fn pairing_requires_desktop_approval_rotates_mobile_token_and_handles_desktop_reconnect() {
    let (base, task) = spawn_test_server().await;
    let client = reqwest::Client::new();

    let session_id = random_token(16);
    let join_token = random_token(32);
    let desktop_session_token = random_token(32);

    let start_response = client
        .post(format!("{base}/pair/start"))
        .json(&json!({
            "sessionID": session_id,
            "joinToken": join_token,
            "desktopSessionToken": desktop_session_token,
            "joinTokenExpiresAt": chrono::Utc::now().checked_add_signed(chrono::Duration::minutes(2)).unwrap().to_rfc3339(),
            "idleTimeoutSeconds": 1800,
        }))
        .send()
        .await
        .expect("pair start request");

    assert_eq!(start_response.status(), StatusCode::OK);
    let start_payload: Value = start_response.json().await.expect("pair start payload");
    let ws_url = start_payload
        .get("wsURL")
        .and_then(Value::as_str)
        .expect("ws url")
        .to_string();

    let (mut desktop_socket, _) = tokio_tungstenite::connect_async(&ws_url)
        .await
        .expect("desktop websocket");

    desktop_socket
        .send(Message::Text(
            json!({ "type": "relay.auth", "token": desktop_session_token.clone() }).to_string(),
        ))
        .await
        .expect("desktop auth send");

    let desktop_auth = desktop_socket
        .next()
        .await
        .expect("desktop auth message")
        .expect("desktop auth frame");
    let desktop_auth_json: Value =
        serde_json::from_str(desktop_auth.to_text().expect("desktop auth text"))
            .expect("desktop auth json");
    assert_eq!(
        desktop_auth_json.get("type").and_then(Value::as_str),
        Some("auth_ok")
    );
    assert_eq!(
        desktop_auth_json.get("role").and_then(Value::as_str),
        Some("desktop")
    );
    assert_eq!(
        desktop_auth_json
            .get("desktopConnected")
            .and_then(Value::as_bool),
        Some(true)
    );

    let join_future = tokio::spawn({
        let client = client.clone();
        let base = base.clone();
        let session_id = session_id.clone();
        let join_token = join_token.clone();
        async move {
            client
                .post(format!("{base}/pair/join"))
                .header("Origin", "http://localhost:4173")
                .json(&json!({ "sessionID": session_id, "joinToken": join_token }))
                .send()
                .await
                .expect("pair join request")
        }
    });

    let pair_request = desktop_socket
        .next()
        .await
        .expect("pair request frame")
        .expect("pair request message");
    let pair_request_json: Value =
        serde_json::from_str(pair_request.to_text().expect("pair request text"))
            .expect("pair request json");

    assert_eq!(
        pair_request_json.get("type").and_then(Value::as_str),
        Some("relay.pair_request")
    );
    let request_id = pair_request_json
        .get("requestID")
        .and_then(Value::as_str)
        .expect("requestID")
        .to_string();

    desktop_socket
        .send(Message::Text(
            json!({
                "type": "relay.pair_decision",
                "sessionID": session_id.clone(),
                "requestID": request_id,
                "approved": true,
            })
            .to_string(),
        ))
        .await
        .expect("desktop pair decision send");

    let join_response = join_future.await.expect("join task");
    assert_eq!(join_response.status(), StatusCode::OK);

    let join_payload: Value = join_response.json().await.expect("join payload");
    let device_token = join_payload
        .get("deviceSessionToken")
        .and_then(Value::as_str)
        .expect("device token")
        .to_string();

    let mut mobile_request = ws_url
        .clone()
        .into_client_request()
        .expect("mobile request");
    mobile_request.headers_mut().insert(
        "Origin",
        "http://localhost:4173".parse().expect("origin header"),
    );

    let (mut mobile_socket, _) = tokio_tungstenite::connect_async(mobile_request)
        .await
        .expect("mobile websocket");

    mobile_socket
        .send(Message::Text(
            json!({ "type": "relay.auth", "token": device_token }).to_string(),
        ))
        .await
        .expect("mobile auth send");

    let mobile_auth = mobile_socket
        .next()
        .await
        .expect("mobile auth frame")
        .expect("mobile auth message");
    let mobile_auth_json: Value =
        serde_json::from_str(mobile_auth.to_text().expect("mobile auth text"))
            .expect("mobile auth json");
    assert_eq!(
        mobile_auth_json.get("type").and_then(Value::as_str),
        Some("auth_ok")
    );
    assert_eq!(
        mobile_auth_json.get("role").and_then(Value::as_str),
        Some("mobile")
    );
    assert_eq!(
        mobile_auth_json
            .get("desktopConnected")
            .and_then(Value::as_bool),
        Some(true)
    );

    let next_token = mobile_auth_json
        .get("nextDeviceSessionToken")
        .and_then(Value::as_str)
        .expect("rotated token");
    assert_ne!(next_token, "");

    desktop_socket
        .close(None)
        .await
        .expect("desktop websocket close");

    let desktop_offline_status = next_matching_json_message(&mut mobile_socket, 1_500, |payload| {
        payload.get("type").and_then(Value::as_str) == Some("relay.desktop_status")
    })
    .await;
    assert_eq!(
        desktop_offline_status
            .get("desktopConnected")
            .and_then(Value::as_bool),
        Some(false)
    );

    mobile_socket
        .send(Message::Text(
            json!({
                "schemaVersion": 2,
                "sessionID": session_id.clone(),
                "seq": 10,
                "payload": {
                    "type": "command",
                    "payload": {
                        "name": "thread.select",
                        "commandID": "cmd-10",
                        "threadID": "thread-offline"
                    }
                }
            })
            .to_string(),
        ))
        .await
        .expect("send command while desktop offline");
    let offline_error = next_matching_json_message(&mut mobile_socket, 1_000, |payload| {
        payload.get("type").and_then(Value::as_str) == Some("relay.error")
    })
    .await;
    assert_eq!(
        offline_error.get("error").and_then(Value::as_str),
        Some("desktop_offline")
    );

    let (mut desktop_reconnect_socket, _) = tokio_tungstenite::connect_async(&ws_url)
        .await
        .expect("desktop websocket reconnect");
    desktop_reconnect_socket
        .send(Message::Text(
            json!({ "type": "relay.auth", "token": desktop_session_token }).to_string(),
        ))
        .await
        .expect("desktop reconnect auth send");
    let reconnect_auth =
        next_matching_json_message(&mut desktop_reconnect_socket, 1_000, |payload| {
            payload.get("type").and_then(Value::as_str) == Some("auth_ok")
        })
        .await;
    assert_eq!(
        reconnect_auth
            .get("desktopConnected")
            .and_then(Value::as_bool),
        Some(true)
    );

    let desktop_online_status = next_matching_json_message(&mut mobile_socket, 1_500, |payload| {
        payload.get("type").and_then(Value::as_str) == Some("relay.desktop_status")
    })
    .await;
    assert_eq!(
        desktop_online_status
            .get("desktopConnected")
            .and_then(Value::as_bool),
        Some(true)
    );

    mobile_socket
        .send(Message::Text(
            json!({
                "schemaVersion": 2,
                "sessionID": session_id,
                "seq": 11,
                "payload": {
                    "type": "command",
                    "payload": {
                        "name": "thread.select",
                        "commandID": "cmd-11",
                        "threadID": "thread-online"
                    }
                }
            })
            .to_string(),
        ))
        .await
        .expect("send command after desktop reconnect");
    let forwarded = next_matching_json_message(&mut desktop_reconnect_socket, 1_000, |payload| {
        payload
            .pointer("/payload/payload/threadID")
            .and_then(Value::as_str)
            == Some("thread-online")
    })
    .await;
    assert_eq!(
        forwarded
            .pointer("/payload/payload/name")
            .and_then(Value::as_str),
        Some("thread.select")
    );

    task.abort();
}

#[tokio::test]
async fn mobile_receives_desktop_offline_status_and_command_rejection() {
    let (
        _base,
        task,
        mut desktop_socket,
        mut mobile_socket,
        session_id,
        _device_token,
        _rotated_device_token,
    ) =
        pair_connected_mobile(|_| {}).await;

    desktop_socket
        .close(None)
        .await
        .expect("desktop websocket close");

    let desktop_status = next_matching_json_message(&mut mobile_socket, 1_500, |payload| {
        payload.get("type").and_then(Value::as_str) == Some("relay.desktop_status")
    })
    .await;
    assert_eq!(
        desktop_status
            .get("desktopConnected")
            .and_then(Value::as_bool),
        Some(false)
    );

    mobile_socket
        .send(Message::Text(
            json!({
                "schemaVersion": 2,
                "sessionID": session_id,
                "seq": 11,
                "payload": {
                    "type": "command",
                    "payload": {
                        "name": "thread.select",
                        "commandID": "cmd-11",
                        "threadID": "thread-offline"
                    }
                }
            })
            .to_string(),
        ))
        .await
        .expect("send command while desktop offline");

    let relay_error = next_matching_json_message(&mut mobile_socket, 1_000, |payload| {
        payload.get("type").and_then(Value::as_str) == Some("relay.error")
    })
    .await;
    assert_eq!(
        relay_error.get("error").and_then(Value::as_str),
        Some("desktop_offline")
    );

    task.abort();
}

#[tokio::test]
async fn trusted_mobile_reauths_while_desktop_offline_without_repairing() {
    let (base, task) = spawn_test_server().await;
    let client = reqwest::Client::new();

    let session_id = random_token(16);
    let join_token = random_token(32);
    let desktop_session_token = random_token(32);

    let start_response = client
        .post(format!("{base}/pair/start"))
        .json(&json!({
            "sessionID": session_id,
            "joinToken": join_token,
            "desktopSessionToken": desktop_session_token,
            "joinTokenExpiresAt": chrono::Utc::now().checked_add_signed(chrono::Duration::minutes(2)).unwrap().to_rfc3339(),
            "idleTimeoutSeconds": 1800,
        }))
        .send()
        .await
        .expect("pair start request");
    assert_eq!(start_response.status(), StatusCode::OK);
    let start_payload: Value = start_response.json().await.expect("pair start payload");
    let ws_url = start_payload
        .get("wsURL")
        .and_then(Value::as_str)
        .expect("ws url")
        .to_string();

    let (mut desktop_socket, _) = tokio_tungstenite::connect_async(&ws_url)
        .await
        .expect("desktop websocket");
    desktop_socket
        .send(Message::Text(
            json!({ "type": "relay.auth", "token": desktop_session_token }).to_string(),
        ))
        .await
        .expect("desktop auth send");
    let _desktop_auth = next_matching_json_message(&mut desktop_socket, 1_000, |payload| {
        payload.get("type").and_then(Value::as_str) == Some("auth_ok")
    })
    .await;

    let join_future = tokio::spawn({
        let client = client.clone();
        let base = base.clone();
        let session_id = session_id.clone();
        let join_token = join_token.clone();
        async move {
            client
                .post(format!("{base}/pair/join"))
                .header("Origin", "http://localhost:4173")
                .json(&json!({ "sessionID": session_id, "joinToken": join_token }))
                .send()
                .await
                .expect("pair join request")
        }
    });

    let pair_request = next_matching_json_message(&mut desktop_socket, 1_000, |payload| {
        payload.get("type").and_then(Value::as_str) == Some("relay.pair_request")
    })
    .await;
    let request_id = pair_request
        .get("requestID")
        .and_then(Value::as_str)
        .expect("request id")
        .to_string();
    desktop_socket
        .send(Message::Text(
            json!({
                "type": "relay.pair_decision",
                "sessionID": session_id,
                "requestID": request_id,
                "approved": true,
            })
            .to_string(),
        ))
        .await
        .expect("pair decision send");

    let join_response = join_future.await.expect("join task");
    assert_eq!(join_response.status(), StatusCode::OK);
    let join_payload: Value = join_response.json().await.expect("join payload");
    let device_token = join_payload
        .get("deviceSessionToken")
        .and_then(Value::as_str)
        .expect("device token")
        .to_string();

    let mut mobile_request = ws_url
        .clone()
        .into_client_request()
        .expect("mobile request");
    mobile_request.headers_mut().insert(
        "Origin",
        "http://localhost:4173".parse().expect("origin header"),
    );
    let (mut mobile_socket, _) = tokio_tungstenite::connect_async(mobile_request)
        .await
        .expect("mobile websocket");
    mobile_socket
        .send(Message::Text(
            json!({ "type": "relay.auth", "token": device_token }).to_string(),
        ))
        .await
        .expect("mobile auth send");
    let mobile_auth = next_matching_json_message(&mut mobile_socket, 1_000, |payload| {
        payload.get("type").and_then(Value::as_str) == Some("auth_ok")
    })
    .await;
    let rotated_token = mobile_auth
        .get("nextDeviceSessionToken")
        .and_then(Value::as_str)
        .expect("rotated token")
        .to_string();
    assert_eq!(
        mobile_auth.get("desktopConnected").and_then(Value::as_bool),
        Some(true)
    );

    mobile_socket
        .close(None)
        .await
        .expect("mobile socket close");
    desktop_socket
        .close(None)
        .await
        .expect("desktop socket close");

    let mut mobile_reconnect_request = ws_url
        .into_client_request()
        .expect("mobile reconnect request");
    mobile_reconnect_request.headers_mut().insert(
        "Origin",
        "http://localhost:4173".parse().expect("origin header"),
    );
    let (mut mobile_reconnect_socket, _) =
        tokio_tungstenite::connect_async(mobile_reconnect_request)
            .await
            .expect("mobile reconnect websocket");
    mobile_reconnect_socket
        .send(Message::Text(
            json!({ "type": "relay.auth", "token": rotated_token }).to_string(),
        ))
        .await
        .expect("mobile reconnect auth send");
    let reconnect_auth =
        next_matching_json_message(&mut mobile_reconnect_socket, 1_000, |payload| {
            payload.get("type").and_then(Value::as_str) == Some("auth_ok")
        })
        .await;
    assert_eq!(
        reconnect_auth.get("role").and_then(Value::as_str),
        Some("mobile")
    );
    assert_eq!(
        reconnect_auth
            .get("desktopConnected")
            .and_then(Value::as_bool),
        Some(false)
    );
    assert!(reconnect_auth
        .get("nextDeviceSessionToken")
        .and_then(Value::as_str)
        .is_some());

    mobile_reconnect_socket
        .close(None)
        .await
        .expect("mobile reconnect close");
    task.abort();
}

#[tokio::test]
async fn stale_mobile_device_token_emits_session_expired_disconnect_and_policy_close() {
    let (
        base,
        task,
        _desktop_socket,
        mut mobile_socket,
        _session_id,
        first_device_token,
        _rotated_device_token,
    ) = pair_connected_mobile(|config| {
        config.token_rotation_grace_ms = 0;
    })
    .await;

    mobile_socket
        .close(None)
        .await
        .expect("mobile socket close");

    let ws_url = format!("{base}/ws").replace("http://", "ws://");
    let mut stale_reconnect_request = ws_url
        .into_client_request()
        .expect("stale reconnect request");
    stale_reconnect_request.headers_mut().insert(
        "Origin",
        "http://localhost:4173".parse().expect("origin header"),
    );
    let (mut stale_reconnect_socket, _) =
        tokio_tungstenite::connect_async(stale_reconnect_request)
            .await
            .expect("stale reconnect websocket");
    stale_reconnect_socket
        .send(Message::Text(
            json!({ "type": "relay.auth", "token": first_device_token }).to_string(),
        ))
        .await
        .expect("stale reconnect auth send");

    expect_disconnect_with_reason(&mut stale_reconnect_socket, 1_000, "session_expired").await;
    expect_policy_close(&mut stale_reconnect_socket, 1_000).await;

    task.abort();
}

#[tokio::test]
async fn pair_stop_closes_session_and_invalidates_join() {
    let (base, task) = spawn_test_server().await;
    let client = reqwest::Client::new();

    let session_id = random_token(16);
    let join_token = random_token(32);
    let desktop_session_token = random_token(32);

    let start_response = client
        .post(format!("{base}/pair/start"))
        .json(&json!({
            "sessionID": session_id,
            "joinToken": join_token,
            "desktopSessionToken": desktop_session_token,
            "joinTokenExpiresAt": chrono::Utc::now().checked_add_signed(chrono::Duration::minutes(2)).unwrap().to_rfc3339(),
            "idleTimeoutSeconds": 1800,
        }))
        .send()
        .await
        .expect("pair start request");
    assert_eq!(start_response.status(), StatusCode::OK);

    let stop_response = client
        .post(format!("{base}/pair/stop"))
        .json(&json!({
            "schemaVersion": 2,
            "sessionID": session_id,
            "desktopSessionToken": desktop_session_token,
        }))
        .send()
        .await
        .expect("pair stop request");
    assert_eq!(stop_response.status(), StatusCode::OK);

    let join_response = client
        .post(format!("{base}/pair/join"))
        .header("Origin", "http://localhost:4173")
        .json(&json!({
            "sessionID": session_id,
            "joinToken": join_token,
        }))
        .send()
        .await
        .expect("pair join request");
    assert_eq!(join_response.status(), StatusCode::NOT_FOUND);

    task.abort();
}

#[tokio::test]
async fn pair_stop_forces_repair_by_rejecting_trusted_device_reauth() {
    let (base, task) = spawn_test_server().await;
    let client = reqwest::Client::new();

    let session_id = random_token(16);
    let join_token = random_token(32);
    let desktop_session_token = random_token(32);

    let start_response = client
        .post(format!("{base}/pair/start"))
        .json(&json!({
            "schemaVersion": 2,
            "sessionID": session_id,
            "joinToken": join_token,
            "desktopSessionToken": desktop_session_token,
            "joinTokenExpiresAt": chrono::Utc::now().checked_add_signed(chrono::Duration::minutes(2)).unwrap().to_rfc3339(),
            "idleTimeoutSeconds": 1800,
        }))
        .send()
        .await
        .expect("pair start request");
    assert_eq!(start_response.status(), StatusCode::OK);
    let start_payload: Value = start_response.json().await.expect("pair start payload");
    let ws_url = start_payload
        .get("wsURL")
        .and_then(Value::as_str)
        .expect("ws url")
        .to_string();

    let (mut desktop_socket, _) = tokio_tungstenite::connect_async(&ws_url)
        .await
        .expect("desktop websocket");
    desktop_socket
        .send(Message::Text(
            json!({ "type": "relay.auth", "token": desktop_session_token }).to_string(),
        ))
        .await
        .expect("desktop auth send");
    let _desktop_auth = next_matching_json_message(&mut desktop_socket, 1_000, |payload| {
        payload.get("type").and_then(Value::as_str) == Some("auth_ok")
    })
    .await;

    let join_future = tokio::spawn({
        let client = client.clone();
        let base = base.clone();
        let session_id = session_id.clone();
        let join_token = join_token.clone();
        async move {
            client
                .post(format!("{base}/pair/join"))
                .header("Origin", "http://localhost:4173")
                .json(&json!({ "sessionID": session_id, "joinToken": join_token }))
                .send()
                .await
                .expect("pair join request")
        }
    });

    let pair_request = next_matching_json_message(&mut desktop_socket, 1_000, |payload| {
        payload.get("type").and_then(Value::as_str) == Some("relay.pair_request")
    })
    .await;
    let request_id = pair_request
        .get("requestID")
        .and_then(Value::as_str)
        .expect("request id")
        .to_string();
    desktop_socket
        .send(Message::Text(
            json!({
                "type": "relay.pair_decision",
                "sessionID": session_id,
                "requestID": request_id,
                "approved": true,
            })
            .to_string(),
        ))
        .await
        .expect("pair decision send");

    let join_response = join_future.await.expect("join task");
    assert_eq!(join_response.status(), StatusCode::OK);
    let join_payload: Value = join_response.json().await.expect("join payload");
    let device_token = join_payload
        .get("deviceSessionToken")
        .and_then(Value::as_str)
        .expect("device token")
        .to_string();

    let mut mobile_request = ws_url
        .clone()
        .into_client_request()
        .expect("mobile request");
    mobile_request.headers_mut().insert(
        "Origin",
        "http://localhost:4173".parse().expect("origin header"),
    );
    let (mut mobile_socket, _) = tokio_tungstenite::connect_async(mobile_request)
        .await
        .expect("mobile websocket");
    mobile_socket
        .send(Message::Text(
            json!({ "type": "relay.auth", "token": device_token }).to_string(),
        ))
        .await
        .expect("mobile auth send");
    let mobile_auth = next_matching_json_message(&mut mobile_socket, 1_000, |payload| {
        payload.get("type").and_then(Value::as_str) == Some("auth_ok")
    })
    .await;
    let rotated_token = mobile_auth
        .get("nextDeviceSessionToken")
        .and_then(Value::as_str)
        .expect("rotated token")
        .to_string();

    let stop_response = client
        .post(format!("{base}/pair/stop"))
        .json(&json!({
            "sessionID": session_id,
            "desktopSessionToken": desktop_session_token,
        }))
        .send()
        .await
        .expect("pair stop request");
    assert_eq!(stop_response.status(), StatusCode::OK);

    let stopped_disconnect = next_matching_json_message(&mut mobile_socket, 1_000, |payload| {
        payload.get("type").and_then(Value::as_str) == Some("disconnect")
    })
    .await;
    assert_eq!(
        stopped_disconnect.get("reason").and_then(Value::as_str),
        Some("stopped_by_desktop")
    );

    let mut mobile_reconnect_request = ws_url
        .into_client_request()
        .expect("mobile reconnect request");
    mobile_reconnect_request.headers_mut().insert(
        "Origin",
        "http://localhost:4173".parse().expect("origin header"),
    );
    let (mut mobile_reconnect_socket, _) =
        tokio_tungstenite::connect_async(mobile_reconnect_request)
            .await
            .expect("mobile reconnect websocket");
    mobile_reconnect_socket
        .send(Message::Text(
            json!({ "type": "relay.auth", "token": rotated_token }).to_string(),
        ))
        .await
        .expect("mobile reconnect auth send");
    let reconnect_rejected = tokio::time::timeout(Duration::from_millis(1_000), async {
        while let Some(frame) = mobile_reconnect_socket.next().await {
            match frame {
                Ok(Message::Text(raw)) => {
                    let payload: Value =
                        serde_json::from_str(raw.as_ref()).unwrap_or_else(|_| json!({}));
                    if payload.get("type").and_then(Value::as_str) == Some("auth_ok") {
                        return false;
                    }
                    if payload.get("type").and_then(Value::as_str) == Some("disconnect") {
                        return true;
                    }
                }
                Ok(Message::Close(_)) | Err(_) => return true,
                _ => {}
            }
        }
        true
    })
    .await
    .expect("expected reconnect attempt to resolve");
    assert!(
        reconnect_rejected,
        "stopped session should require re-pair and reject trusted-device reauth"
    );

    task.abort();
}

#[tokio::test]
async fn stale_desktop_session_token_emits_session_expired_disconnect_and_policy_close() {
    let (base, task) = spawn_test_server().await;
    let client = reqwest::Client::new();

    let session_id = random_token(16);
    let join_token = random_token(32);
    let desktop_session_token = random_token(32);

    let start_response = client
        .post(format!("{base}/pair/start"))
        .json(&json!({
            "schemaVersion": 2,
            "sessionID": session_id,
            "joinToken": join_token,
            "desktopSessionToken": desktop_session_token,
            "joinTokenExpiresAt": chrono::Utc::now().checked_add_signed(chrono::Duration::minutes(2)).unwrap().to_rfc3339(),
            "idleTimeoutSeconds": 1800,
        }))
        .send()
        .await
        .expect("pair start request");
    assert_eq!(start_response.status(), StatusCode::OK);
    let start_payload: Value = start_response.json().await.expect("pair start payload");
    let ws_url = start_payload
        .get("wsURL")
        .and_then(Value::as_str)
        .expect("ws url")
        .to_string();

    let stop_response = client
        .post(format!("{base}/pair/stop"))
        .json(&json!({
            "schemaVersion": 2,
            "sessionID": session_id,
            "desktopSessionToken": desktop_session_token,
        }))
        .send()
        .await
        .expect("pair stop request");
    assert_eq!(stop_response.status(), StatusCode::OK);

    let (mut stale_desktop_socket, _) = tokio_tungstenite::connect_async(&ws_url)
        .await
        .expect("stale desktop websocket");
    stale_desktop_socket
        .send(Message::Text(
            json!({ "type": "relay.auth", "token": desktop_session_token }).to_string(),
        ))
        .await
        .expect("stale desktop auth send");

    expect_disconnect_with_reason(&mut stale_desktop_socket, 1_000, "session_expired").await;
    expect_policy_close(&mut stale_desktop_socket, 1_000).await;

    task.abort();
}

#[tokio::test]
async fn pair_refresh_rotates_join_token_without_stopping_session() {
    let (base, task) = spawn_test_server().await;
    let client = reqwest::Client::new();

    let session_id = random_token(16);
    let original_join_token = random_token(32);
    let refreshed_join_token = random_token(32);
    let desktop_session_token = random_token(32);

    let start_response = client
        .post(format!("{base}/pair/start"))
        .json(&json!({
            "schemaVersion": 2,
            "sessionID": session_id,
            "joinToken": original_join_token,
            "desktopSessionToken": desktop_session_token,
            "joinTokenExpiresAt": chrono::Utc::now().checked_add_signed(chrono::Duration::minutes(2)).unwrap().to_rfc3339(),
            "idleTimeoutSeconds": 1800,
        }))
        .send()
        .await
        .expect("pair start request");
    assert_eq!(start_response.status(), StatusCode::OK);
    let start_payload: Value = start_response.json().await.expect("pair start payload");
    let ws_url = start_payload
        .get("wsURL")
        .and_then(Value::as_str)
        .expect("ws url")
        .to_string();

    let (mut desktop_socket, _) = tokio_tungstenite::connect_async(&ws_url)
        .await
        .expect("desktop websocket");
    desktop_socket
        .send(Message::Text(
            json!({ "type": "relay.auth", "token": desktop_session_token }).to_string(),
        ))
        .await
        .expect("desktop auth send");
    let _desktop_auth = desktop_socket
        .next()
        .await
        .expect("desktop auth message")
        .expect("desktop auth frame");

    let refresh_response = client
        .post(format!("{base}/pair/refresh"))
        .json(&json!({
            "schemaVersion": 2,
            "sessionID": session_id,
            "joinToken": refreshed_join_token,
            "desktopSessionToken": desktop_session_token,
            "joinTokenExpiresAt": chrono::Utc::now().checked_add_signed(chrono::Duration::minutes(2)).unwrap().to_rfc3339(),
        }))
        .send()
        .await
        .expect("pair refresh request");
    assert_eq!(refresh_response.status(), StatusCode::OK);

    let old_join_response = client
        .post(format!("{base}/pair/join"))
        .header("Origin", "http://localhost:4173")
        .json(&json!({
            "sessionID": session_id,
            "joinToken": original_join_token,
        }))
        .send()
        .await
        .expect("pair join old token");
    assert_eq!(old_join_response.status(), StatusCode::FORBIDDEN);

    let join_future = tokio::spawn({
        let client = client.clone();
        let base = base.clone();
        let session_id = session_id.clone();
        let refreshed_join_token = refreshed_join_token.clone();
        async move {
            client
                .post(format!("{base}/pair/join"))
                .header("Origin", "http://localhost:4173")
                .json(&json!({
                    "sessionID": session_id,
                    "joinToken": refreshed_join_token,
                }))
                .send()
                .await
                .expect("pair join refreshed token")
        }
    });

    let pair_request = desktop_socket
        .next()
        .await
        .expect("pair request frame")
        .expect("pair request message");
    let pair_request_json: Value =
        serde_json::from_str(pair_request.to_text().expect("pair request text"))
            .expect("pair request json");
    let request_id = pair_request_json
        .get("requestID")
        .and_then(Value::as_str)
        .expect("requestID")
        .to_string();

    desktop_socket
        .send(Message::Text(
            json!({
                "type": "relay.pair_decision",
                "sessionID": session_id,
                "requestID": request_id,
                "approved": true,
            })
            .to_string(),
        ))
        .await
        .expect("desktop pair decision send");

    let join_response = join_future.await.expect("join task");
    assert_eq!(join_response.status(), StatusCode::OK);

    task.abort();
}

#[tokio::test]
async fn pairing_endpoints_include_cors_headers_for_allowed_origin() {
    let (base, task) = spawn_test_server().await;
    let client = reqwest::Client::new();

    let response = client
        .request(reqwest::Method::OPTIONS, format!("{base}/pair/join"))
        .header("Origin", "http://localhost:4173")
        .header("Access-Control-Request-Method", "POST")
        .send()
        .await
        .expect("options request");

    assert!(response.status().is_success());
    assert_eq!(
        response
            .headers()
            .get("access-control-allow-origin")
            .and_then(|value| value.to_str().ok()),
        Some("http://localhost:4173")
    );

    task.abort();
}

#[tokio::test]
async fn devices_list_and_revoke_remove_trusted_device() {
    let (base, task) = spawn_test_server().await;
    let client = reqwest::Client::new();

    let session_id = random_token(16);
    let join_token = random_token(32);
    let desktop_session_token = random_token(32);

    let start_response = client
        .post(format!("{base}/pair/start"))
        .json(&json!({
            "sessionID": session_id,
            "joinToken": join_token,
            "desktopSessionToken": desktop_session_token,
            "joinTokenExpiresAt": chrono::Utc::now().checked_add_signed(chrono::Duration::minutes(2)).unwrap().to_rfc3339(),
            "idleTimeoutSeconds": 1800,
        }))
        .send()
        .await
        .expect("pair start request");
    assert_eq!(start_response.status(), StatusCode::OK);
    let start_payload: Value = start_response.json().await.expect("pair start payload");
    let ws_url = start_payload
        .get("wsURL")
        .and_then(Value::as_str)
        .expect("ws url")
        .to_string();

    let (mut desktop_socket, _) = tokio_tungstenite::connect_async(&ws_url)
        .await
        .expect("desktop websocket");
    desktop_socket
        .send(Message::Text(
            json!({ "type": "relay.auth", "token": desktop_session_token }).to_string(),
        ))
        .await
        .expect("desktop auth send");
    let _desktop_auth = desktop_socket
        .next()
        .await
        .expect("desktop auth message")
        .expect("desktop auth frame");

    let join_future = tokio::spawn({
        let client = client.clone();
        let base = base.clone();
        let session_id = session_id.clone();
        let join_token = join_token.clone();
        async move {
            client
                .post(format!("{base}/pair/join"))
                .header("Origin", "http://localhost:4173")
                .json(&json!({
                    "sessionID": session_id,
                    "joinToken": join_token,
                    "deviceName": "Bikram iPhone"
                }))
                .send()
                .await
                .expect("pair join request")
        }
    });

    let pair_request = desktop_socket
        .next()
        .await
        .expect("pair request frame")
        .expect("pair request message");
    let pair_request_json: Value =
        serde_json::from_str(pair_request.to_text().expect("pair request text"))
            .expect("pair request json");
    let request_id = pair_request_json
        .get("requestID")
        .and_then(Value::as_str)
        .expect("requestID")
        .to_string();

    desktop_socket
        .send(Message::Text(
            json!({
                "type": "relay.pair_decision",
                "sessionID": session_id,
                "requestID": request_id,
                "approved": true,
            })
            .to_string(),
        ))
        .await
        .expect("desktop pair decision send");

    let join_response = join_future.await.expect("join task");
    assert_eq!(join_response.status(), StatusCode::OK);
    let join_payload: Value = join_response.json().await.expect("join payload");
    let device_id = join_payload
        .get("deviceID")
        .and_then(Value::as_str)
        .expect("deviceID")
        .to_string();
    let device_session_token = join_payload
        .get("deviceSessionToken")
        .and_then(Value::as_str)
        .expect("deviceSessionToken")
        .to_string();

    let mut mobile_request = ws_url
        .clone()
        .into_client_request()
        .expect("mobile request");
    mobile_request.headers_mut().insert(
        "Origin",
        "http://localhost:4173".parse().expect("origin header"),
    );
    let (mut mobile_socket, _) = tokio_tungstenite::connect_async(mobile_request)
        .await
        .expect("mobile websocket");
    mobile_socket
        .send(Message::Text(
            json!({ "type": "relay.auth", "token": device_session_token }).to_string(),
        ))
        .await
        .expect("mobile auth send");
    let mobile_auth = next_matching_json_message(&mut mobile_socket, 1_000, |payload| {
        payload.get("type").and_then(Value::as_str) == Some("auth_ok")
    })
    .await;
    let rotated_device_token = mobile_auth
        .get("nextDeviceSessionToken")
        .and_then(Value::as_str)
        .expect("rotated device token")
        .to_string();

    let rejected_list_response = client
        .post(format!("{base}/devices/list"))
        .header("Origin", "https://evil.example")
        .json(&json!({
            "schemaVersion": 2,
            "sessionID": session_id,
            "desktopSessionToken": desktop_session_token,
        }))
        .send()
        .await
        .expect("devices list disallowed origin");
    assert_eq!(rejected_list_response.status(), StatusCode::FORBIDDEN);
    let rejected_list_payload: Value = rejected_list_response
        .json()
        .await
        .expect("devices list disallowed origin payload");
    assert_eq!(
        rejected_list_payload.get("error").and_then(Value::as_str),
        Some("origin_not_allowed")
    );

    let list_response = client
        .post(format!("{base}/devices/list"))
        .json(&json!({
            "schemaVersion": 2,
            "sessionID": session_id,
            "desktopSessionToken": desktop_session_token,
        }))
        .send()
        .await
        .expect("devices list");
    assert_eq!(list_response.status(), StatusCode::OK);
    let list_payload: Value = list_response.json().await.expect("list payload");
    let devices = list_payload
        .get("devices")
        .and_then(Value::as_array)
        .expect("devices array");
    assert_eq!(devices.len(), 1);
    assert_eq!(
        devices[0].get("deviceID").and_then(Value::as_str),
        Some(device_id.as_str())
    );
    assert_eq!(
        devices[0].get("deviceName").and_then(Value::as_str),
        Some("Bikram iPhone")
    );

    let rejected_revoke_response = client
        .post(format!("{base}/devices/revoke"))
        .header("Origin", "https://evil.example")
        .json(&json!({
            "schemaVersion": 2,
            "sessionID": session_id,
            "desktopSessionToken": desktop_session_token,
            "deviceID": device_id,
        }))
        .send()
        .await
        .expect("device revoke disallowed origin");
    assert_eq!(rejected_revoke_response.status(), StatusCode::FORBIDDEN);
    let rejected_revoke_payload: Value = rejected_revoke_response
        .json()
        .await
        .expect("device revoke disallowed origin payload");
    assert_eq!(
        rejected_revoke_payload.get("error").and_then(Value::as_str),
        Some("origin_not_allowed")
    );

    let revoke_response = client
        .post(format!("{base}/devices/revoke"))
        .json(&json!({
            "schemaVersion": 2,
            "sessionID": session_id,
            "desktopSessionToken": desktop_session_token,
            "deviceID": device_id,
        }))
        .send()
        .await
        .expect("device revoke");
    assert_eq!(revoke_response.status(), StatusCode::OK);
    let revoke_disconnect = next_matching_json_message(&mut mobile_socket, 1_000, |payload| {
        payload.get("type").and_then(Value::as_str) == Some("disconnect")
    })
    .await;
    assert_eq!(
        revoke_disconnect.get("reason").and_then(Value::as_str),
        Some("device_revoked")
    );

    let list_after_revoke = client
        .post(format!("{base}/devices/list"))
        .json(&json!({
            "schemaVersion": 2,
            "sessionID": session_id,
            "desktopSessionToken": desktop_session_token,
        }))
        .send()
        .await
        .expect("devices list after revoke");
    assert_eq!(list_after_revoke.status(), StatusCode::OK);
    let list_after_payload: Value = list_after_revoke
        .json()
        .await
        .expect("list payload after revoke");
    let devices_after = list_after_payload
        .get("devices")
        .and_then(Value::as_array)
        .expect("devices array after revoke");
    assert_eq!(devices_after.len(), 0);

    let mut reconnect_request = ws_url
        .into_client_request()
        .expect("mobile reconnect request");
    reconnect_request.headers_mut().insert(
        "Origin",
        "http://localhost:4173".parse().expect("origin header"),
    );
    let (mut mobile_reconnect_socket, _) = tokio_tungstenite::connect_async(reconnect_request)
        .await
        .expect("mobile reconnect websocket");
    mobile_reconnect_socket
        .send(Message::Text(
            json!({ "type": "relay.auth", "token": rotated_device_token }).to_string(),
        ))
        .await
        .expect("mobile reconnect auth send");
    let reconnect_rejected = tokio::time::timeout(Duration::from_millis(1_000), async {
        while let Some(frame) = mobile_reconnect_socket.next().await {
            match frame {
                Ok(Message::Text(raw)) => {
                    let payload: Value =
                        serde_json::from_str(raw.as_ref()).unwrap_or_else(|_| json!({}));
                    if payload.get("type").and_then(Value::as_str) == Some("auth_ok") {
                        return false;
                    }
                    if payload.get("type").and_then(Value::as_str) == Some("disconnect") {
                        return true;
                    }
                }
                Ok(Message::Close(_)) | Err(_) => return true,
                _ => {}
            }
        }
        true
    })
    .await
    .expect("expected reconnect attempt to resolve");
    assert!(
        reconnect_rejected,
        "revoked device token should not authenticate after device revoke"
    );

    task.abort();
}

#[tokio::test]
async fn invalid_mobile_command_is_rejected_and_not_forwarded() {
    let (
        _base,
        task,
        mut desktop_socket,
        mut mobile_socket,
        session_id,
        _device_token,
        _rotated_device_token,
    ) =
        pair_connected_mobile(|_| {}).await;

    mobile_socket
        .send(Message::Text(
            json!({
                "schemaVersion": 2,
                "sessionID": session_id,
                "seq": 1,
                "payload": {
                    "type": "command",
                    "payload": {
                        "name": "terminal.exec",
                        "commandID": "cmd-1",
                        "threadID": "11111111-1111-1111-1111-111111111111",
                        "text": "rm -rf /"
                    }
                }
            })
            .to_string(),
        ))
        .await
        .expect("send invalid command");

    let relay_error = tokio::time::timeout(Duration::from_millis(1_000), mobile_socket.next())
        .await
        .expect("expected relay error")
        .expect("relay error frame")
        .expect("relay error message");
    let relay_error_json: Value =
        serde_json::from_str(relay_error.to_text().expect("relay error text"))
            .expect("relay error json");
    assert_eq!(
        relay_error_json.get("type").and_then(Value::as_str),
        Some("relay.error")
    );
    assert_eq!(
        relay_error_json.get("error").and_then(Value::as_str),
        Some("invalid_command")
    );

    let desktop_next =
        tokio::time::timeout(Duration::from_millis(250), desktop_socket.next()).await;
    assert!(
        desktop_next.is_err(),
        "desktop unexpectedly received forwarded payload"
    );

    task.abort();
}

#[tokio::test]
async fn mobile_command_with_unexpected_field_is_rejected_and_not_forwarded() {
    let (
        _base,
        task,
        mut desktop_socket,
        mut mobile_socket,
        session_id,
        _device_token,
        _rotated_device_token,
    ) =
        pair_connected_mobile(|_| {}).await;

    mobile_socket
        .send(Message::Text(
            json!({
                "schemaVersion": 2,
                "sessionID": session_id,
                "seq": 1,
                "payload": {
                    "type": "command",
                    "payload": {
                        "name": "thread.select",
                        "commandID": "cmd-1",
                        "threadID": "11111111-1111-1111-1111-111111111111",
                        "unexpectedField": "not-allowed"
                    }
                }
            })
            .to_string(),
        ))
        .await
        .expect("send invalid command with unexpected field");

    let relay_error = tokio::time::timeout(Duration::from_millis(1_000), mobile_socket.next())
        .await
        .expect("expected relay error")
        .expect("relay error frame")
        .expect("relay error message");
    let relay_error_json: Value =
        serde_json::from_str(relay_error.to_text().expect("relay error text"))
            .expect("relay error json");
    assert_eq!(
        relay_error_json.get("type").and_then(Value::as_str),
        Some("relay.error")
    );
    assert_eq!(
        relay_error_json.get("error").and_then(Value::as_str),
        Some("invalid_command")
    );

    let desktop_next =
        tokio::time::timeout(Duration::from_millis(250), desktop_socket.next()).await;
    assert!(
        desktop_next.is_err(),
        "desktop unexpectedly received forwarded payload"
    );

    task.abort();
}

#[tokio::test]
async fn mobile_command_ignores_spoofed_relay_metadata_and_forwards() {
    let (
        _base,
        task,
        mut desktop_socket,
        mut mobile_socket,
        session_id,
        _device_token,
        _rotated_device_token,
    ) =
        pair_connected_mobile(|_| {}).await;

    mobile_socket
        .send(Message::Text(
            json!({
                "schemaVersion": 2,
                "sessionID": session_id,
                "seq": 1,
                "timestamp": chrono::Utc::now().to_rfc3339(),
                "relayConnectionID": "spoofed-connection",
                "relayDeviceID": "spoofed-device",
                "payload": {
                    "type": "command",
                    "payload": {
                        "name": "thread.select",
                        "commandID": "cmd-1",
                        "threadID": "11111111-1111-1111-1111-111111111111"
                    }
                }
            })
            .to_string(),
        ))
        .await
        .expect("send command with spoofed metadata");

    let forwarded = tokio::time::timeout(Duration::from_millis(1_000), desktop_socket.next())
        .await
        .expect("expected forwarded command")
        .expect("forwarded frame")
        .expect("forwarded message");
    let forwarded_json: Value =
        serde_json::from_str(forwarded.to_text().expect("forwarded text")).expect("forwarded json");
    assert_eq!(
        forwarded_json
            .pointer("/payload/payload/name")
            .and_then(Value::as_str),
        Some("thread.select")
    );
    assert_ne!(
        forwarded_json
            .get("relayConnectionID")
            .and_then(Value::as_str),
        Some("spoofed-connection")
    );
    assert_ne!(
        forwarded_json.get("relayDeviceID").and_then(Value::as_str),
        Some("spoofed-device")
    );

    task.abort();
}

#[tokio::test]
async fn invalid_snapshot_request_with_negative_last_seq_is_rejected() {
    let (
        _base,
        task,
        mut desktop_socket,
        mut mobile_socket,
        session_id,
        _device_token,
        _rotated_device_token,
    ) =
        pair_connected_mobile(|_| {}).await;

    mobile_socket
        .send(Message::Text(
            json!({
                "type": "relay.snapshot_request",
                "sessionID": session_id,
                "lastSeq": -1,
                "reason": "integration-test"
            })
            .to_string(),
        ))
        .await
        .expect("send invalid snapshot request");

    let relay_error = tokio::time::timeout(Duration::from_millis(1_000), mobile_socket.next())
        .await
        .expect("expected relay error")
        .expect("relay error frame")
        .expect("relay error message");
    let relay_error_json: Value =
        serde_json::from_str(relay_error.to_text().expect("relay error text"))
            .expect("relay error json");
    assert_eq!(
        relay_error_json.get("type").and_then(Value::as_str),
        Some("relay.error")
    );
    assert_eq!(
        relay_error_json.get("error").and_then(Value::as_str),
        Some("invalid_snapshot_request")
    );

    let desktop_next =
        tokio::time::timeout(Duration::from_millis(250), desktop_socket.next()).await;
    assert!(
        desktop_next.is_err(),
        "desktop unexpectedly received forwarded snapshot payload"
    );

    task.abort();
}

#[tokio::test]
async fn snapshot_request_accepts_numeric_string_last_seq_for_backward_compatibility() {
    let (
        _base,
        task,
        mut desktop_socket,
        mut mobile_socket,
        session_id,
        _device_token,
        _rotated_device_token,
    ) =
        pair_connected_mobile(|_| {}).await;

    mobile_socket
        .send(Message::Text(
            json!({
                "type": "relay.snapshot_request",
                "sessionID": session_id,
                "lastSeq": "42",
                "reason": "integration-test"
            })
            .to_string(),
        ))
        .await
        .expect("send snapshot request with string lastSeq");

    let forwarded = tokio::time::timeout(Duration::from_millis(1_000), desktop_socket.next())
        .await
        .expect("expected forwarded snapshot request")
        .expect("forwarded frame")
        .expect("forwarded message");
    let forwarded_json: Value =
        serde_json::from_str(forwarded.to_text().expect("forwarded text")).expect("forwarded json");
    assert_eq!(
        forwarded_json.get("type").and_then(Value::as_str),
        Some("relay.snapshot_request")
    );

    let relay_error = tokio::time::timeout(Duration::from_millis(250), mobile_socket.next()).await;
    assert!(
        relay_error.is_err(),
        "mobile unexpectedly received relay.error"
    );

    task.abort();
}

#[tokio::test]
async fn per_device_command_rate_limit_blocks_excess_mobile_commands() {
    let (
        _base,
        task,
        mut desktop_socket,
        mut mobile_socket,
        session_id,
        _device_token,
        _rotated_device_token,
    ) =
        pair_connected_mobile(|config| {
            config.max_remote_commands_per_minute = 2;
        })
        .await;

    for seq in 1..=3_u64 {
        mobile_socket
            .send(Message::Text(
                json!({
                    "schemaVersion": 2,
                    "sessionID": session_id,
                    "seq": seq,
                    "payload": {
                        "type": "command",
                        "payload": {
                            "name": "thread.select",
                            "commandID": format!("cmd-{}", seq),
                            "threadID": "11111111-1111-1111-1111-111111111111"
                        }
                    }
                })
                .to_string(),
            ))
            .await
            .expect("send thread.select command");
    }

    for _ in 0..2 {
        let forwarded = tokio::time::timeout(Duration::from_millis(1_000), desktop_socket.next())
            .await
            .expect("expected forwarded command")
            .expect("forwarded frame")
            .expect("forwarded message");
        let forwarded_json: Value =
            serde_json::from_str(forwarded.to_text().expect("forwarded text"))
                .expect("forwarded json");
        assert_eq!(
            forwarded_json
                .pointer("/payload/payload/name")
                .and_then(Value::as_str),
            Some("thread.select")
        );
    }

    let relay_error = tokio::time::timeout(Duration::from_millis(1_000), mobile_socket.next())
        .await
        .expect("expected rate-limit error")
        .expect("rate-limit frame")
        .expect("rate-limit message");
    let relay_error_json: Value =
        serde_json::from_str(relay_error.to_text().expect("rate-limit text"))
            .expect("rate-limit json");
    assert_eq!(
        relay_error_json.get("type").and_then(Value::as_str),
        Some("relay.error")
    );
    assert_eq!(
        relay_error_json.get("error").and_then(Value::as_str),
        Some("command_rate_limited")
    );

    let desktop_next =
        tokio::time::timeout(Duration::from_millis(250), desktop_socket.next()).await;
    assert!(
        desktop_next.is_err(),
        "desktop unexpectedly received extra forwarded payload"
    );

    task.abort();
}

#[tokio::test]
async fn per_session_command_rate_limit_blocks_excess_mobile_commands() {
    let (
        _base,
        task,
        mut desktop_socket,
        mut mobile_socket,
        session_id,
        _device_token,
        _rotated_device_token,
    ) =
        pair_connected_mobile(|config| {
            config.max_remote_commands_per_minute = 10;
            config.max_remote_session_commands_per_minute = 2;
        })
        .await;

    for seq in 1..=3_u64 {
        mobile_socket
            .send(Message::Text(
                json!({
                    "schemaVersion": 2,
                    "sessionID": session_id,
                    "seq": seq,
                    "payload": {
                        "type": "command",
                        "payload": {
                            "name": "thread.select",
                            "commandID": format!("cmd-{}", seq),
                            "threadID": "11111111-1111-1111-1111-111111111111"
                        }
                    }
                })
                .to_string(),
            ))
            .await
            .expect("send thread.select command");
    }

    for _ in 0..2 {
        let forwarded = tokio::time::timeout(Duration::from_millis(1_000), desktop_socket.next())
            .await
            .expect("expected forwarded command")
            .expect("forwarded frame")
            .expect("forwarded message");
        let forwarded_json: Value =
            serde_json::from_str(forwarded.to_text().expect("forwarded text"))
                .expect("forwarded json");
        assert_eq!(
            forwarded_json
                .pointer("/payload/payload/name")
                .and_then(Value::as_str),
            Some("thread.select")
        );
    }

    let relay_error = tokio::time::timeout(Duration::from_millis(1_000), mobile_socket.next())
        .await
        .expect("expected session rate-limit error")
        .expect("rate-limit frame")
        .expect("rate-limit message");
    let relay_error_json: Value =
        serde_json::from_str(relay_error.to_text().expect("rate-limit text"))
            .expect("rate-limit json");
    assert_eq!(
        relay_error_json.get("type").and_then(Value::as_str),
        Some("relay.error")
    );
    assert_eq!(
        relay_error_json.get("error").and_then(Value::as_str),
        Some("command_rate_limited")
    );

    let desktop_next =
        tokio::time::timeout(Duration::from_millis(250), desktop_socket.next()).await;
    assert!(
        desktop_next.is_err(),
        "desktop unexpectedly received extra forwarded payload"
    );

    task.abort();
}

#[tokio::test]
async fn per_device_snapshot_request_rate_limit_blocks_excess_requests() {
    let (
        _base,
        task,
        mut desktop_socket,
        mut mobile_socket,
        session_id,
        _device_token,
        _rotated_device_token,
    ) =
        pair_connected_mobile(|config| {
            config.max_snapshot_requests_per_minute = 2;
        })
        .await;

    for request_number in 1..=3_u64 {
        mobile_socket
            .send(Message::Text(
                json!({
                    "type": "relay.snapshot_request",
                    "sessionID": session_id,
                    "lastSeq": request_number,
                    "reason": "integration-test"
                })
                .to_string(),
            ))
            .await
            .expect("send snapshot request");
    }

    for _ in 0..2 {
        let forwarded = tokio::time::timeout(Duration::from_millis(1_000), desktop_socket.next())
            .await
            .expect("expected forwarded snapshot request")
            .expect("forwarded frame")
            .expect("forwarded message");
        let forwarded_json: Value =
            serde_json::from_str(forwarded.to_text().expect("forwarded text"))
                .expect("forwarded json");
        assert_eq!(
            forwarded_json.get("type").and_then(Value::as_str),
            Some("relay.snapshot_request")
        );
    }

    let relay_error = tokio::time::timeout(Duration::from_millis(1_000), mobile_socket.next())
        .await
        .expect("expected snapshot rate-limit error")
        .expect("rate-limit frame")
        .expect("rate-limit message");
    let relay_error_json: Value =
        serde_json::from_str(relay_error.to_text().expect("rate-limit text"))
            .expect("rate-limit json");
    assert_eq!(
        relay_error_json.get("type").and_then(Value::as_str),
        Some("relay.error")
    );
    assert_eq!(
        relay_error_json.get("error").and_then(Value::as_str),
        Some("snapshot_rate_limited")
    );

    let desktop_next =
        tokio::time::timeout(Duration::from_millis(250), desktop_socket.next()).await;
    assert!(
        desktop_next.is_err(),
        "desktop unexpectedly received extra snapshot payload"
    );

    task.abort();
}

#[tokio::test]
async fn replayed_mobile_command_sequence_is_rejected() {
    let (
        _base,
        task,
        mut desktop_socket,
        mut mobile_socket,
        session_id,
        _device_token,
        _rotated_device_token,
    ) =
        pair_connected_mobile(|_| {}).await;

    let command_payload = json!({
        "schemaVersion": 2,
        "sessionID": session_id,
        "seq": 1,
        "payload": {
            "type": "command",
            "payload": {
                "name": "thread.select",
                "commandID": "cmd-1",
                "threadID": "11111111-1111-1111-1111-111111111111"
            }
        }
    })
    .to_string();

    mobile_socket
        .send(Message::Text(command_payload.clone()))
        .await
        .expect("send first command");

    let forwarded = tokio::time::timeout(Duration::from_millis(1_000), desktop_socket.next())
        .await
        .expect("first command forwarded")
        .expect("forwarded frame")
        .expect("forwarded message");
    let forwarded_json: Value =
        serde_json::from_str(forwarded.to_text().expect("forwarded text")).expect("forwarded json");
    assert_eq!(
        forwarded_json
            .pointer("/payload/payload/name")
            .and_then(Value::as_str),
        Some("thread.select")
    );

    mobile_socket
        .send(Message::Text(command_payload))
        .await
        .expect("send replayed command");

    let relay_error = tokio::time::timeout(Duration::from_millis(1_000), mobile_socket.next())
        .await
        .expect("expected replay rejection")
        .expect("replay rejection frame")
        .expect("replay rejection message");
    let relay_error_json: Value =
        serde_json::from_str(relay_error.to_text().expect("replay rejection text"))
            .expect("replay rejection json");
    assert_eq!(
        relay_error_json.get("type").and_then(Value::as_str),
        Some("relay.error")
    );
    assert_eq!(
        relay_error_json.get("error").and_then(Value::as_str),
        Some("replayed_command")
    );

    let desktop_next =
        tokio::time::timeout(Duration::from_millis(250), desktop_socket.next()).await;
    assert!(
        desktop_next.is_err(),
        "desktop unexpectedly received replayed payload"
    );

    task.abort();
}

#[tokio::test]
async fn per_socket_websocket_message_rate_limit_disconnects_abusive_client() {
    let (
        _base,
        task,
        mut desktop_socket,
        mut mobile_socket,
        session_id,
        _device_token,
        _rotated_device_token,
    ) =
        pair_connected_mobile(|config| {
            config.max_ws_messages_per_minute = 2;
            config.max_remote_commands_per_minute = 10_000;
            config.max_remote_session_commands_per_minute = 10_000;
        })
        .await;

    for seq in 1..=3_u64 {
        mobile_socket
            .send(Message::Text(
                json!({
                    "schemaVersion": 2,
                    "sessionID": session_id,
                    "seq": seq,
                    "payload": {
                        "type": "command",
                        "payload": {
                            "name": "thread.select",
                            "commandID": format!("cmd-{}", seq),
                            "threadID": "11111111-1111-1111-1111-111111111111"
                        }
                    }
                })
                .to_string(),
            ))
            .await
            .expect("send command");
    }

    for _ in 0..2 {
        let forwarded = tokio::time::timeout(Duration::from_millis(1_000), desktop_socket.next())
            .await
            .expect("expected forwarded command")
            .expect("forwarded frame")
            .expect("forwarded message");
        let forwarded_json: Value =
            serde_json::from_str(forwarded.to_text().expect("forwarded text"))
                .expect("forwarded json");
        assert_eq!(
            forwarded_json
                .pointer("/payload/payload/name")
                .and_then(Value::as_str),
            Some("thread.select")
        );
    }

    let disconnect_or_close =
        tokio::time::timeout(Duration::from_millis(1_500), mobile_socket.next())
            .await
            .expect("expected rate-limit disconnect frame");
    match disconnect_or_close {
        Some(Ok(Message::Text(text))) => {
            let payload: Value = serde_json::from_str(text.as_ref()).expect("disconnect json");
            assert_eq!(
                payload.get("type").and_then(Value::as_str),
                Some("disconnect")
            );
            assert_eq!(
                payload.get("reason").and_then(Value::as_str),
                Some("socket_rate_limited")
            );
        }
        Some(Ok(Message::Close(_))) | Some(Err(_)) | None => {}
        other => panic!("unexpected websocket frame: {other:?}"),
    }

    task.abort();
}

#[tokio::test]
async fn redis_persistence_restores_session_after_restart_when_configured() {
    let Some(redis_url) = std::env::var("REMOTE_CONTROL_REDIS_TEST_URL")
        .ok()
        .filter(|value| !value.trim().is_empty())
    else {
        return;
    };

    let redis_key_prefix = format!("relay-test-{}", random_token(8));
    let client = reqwest::Client::new();
    let session_id = random_token(16);
    let join_token = random_token(32);
    let desktop_session_token = random_token(32);

    let (base_a, task_a) = spawn_test_server_with_config(|config| {
        config.redis_url = Some(redis_url.clone());
        config.redis_key_prefix = redis_key_prefix.clone();
    })
    .await;

    let start_response = client
        .post(format!("{base_a}/pair/start"))
        .json(&json!({
            "sessionID": session_id,
            "joinToken": join_token,
            "desktopSessionToken": desktop_session_token,
            "joinTokenExpiresAt": chrono::Utc::now().checked_add_signed(chrono::Duration::minutes(2)).unwrap().to_rfc3339(),
            "idleTimeoutSeconds": 1800,
        }))
        .send()
        .await
        .expect("pair start request");
    assert_eq!(start_response.status(), StatusCode::OK);

    task_a.abort();

    let (base_b, task_b) = spawn_test_server_with_config(|config| {
        config.redis_url = Some(redis_url.clone());
        config.redis_key_prefix = redis_key_prefix.clone();
    })
    .await;

    let ws_url = base_b.replace("http://", "ws://") + "/ws";
    let (mut desktop_socket, _) = tokio_tungstenite::connect_async(&ws_url)
        .await
        .expect("desktop websocket after restart");
    desktop_socket
        .send(Message::Text(
            json!({
                "type": "relay.auth",
                "token": desktop_session_token
            })
            .to_string(),
        ))
        .await
        .expect("desktop auth send");

    let auth_message = tokio::time::timeout(Duration::from_millis(1_000), desktop_socket.next())
        .await
        .expect("auth frame timeout")
        .expect("auth frame")
        .expect("auth message");
    let auth_json: Value =
        serde_json::from_str(auth_message.to_text().expect("auth text")).expect("auth json");
    assert_eq!(
        auth_json.get("type").and_then(Value::as_str),
        Some("auth_ok")
    );
    assert_eq!(
        auth_json.get("role").and_then(Value::as_str),
        Some("desktop")
    );
    assert_eq!(
        auth_json.get("desktopConnected").and_then(Value::as_bool),
        Some(true)
    );
    assert_eq!(
        auth_json.get("sessionID").and_then(Value::as_str),
        Some(session_id.as_str())
    );

    task_b.abort();
}

#[tokio::test]
async fn redis_persistence_preserves_rotated_mobile_grace_token_across_restart() {
    let Some(redis_url) = std::env::var("REMOTE_CONTROL_REDIS_TEST_URL")
        .ok()
        .filter(|value| !value.trim().is_empty())
    else {
        return;
    };

    let redis_key_prefix = format!("relay-test-{}", random_token(8));
    let client = reqwest::Client::new();
    let session_id = random_token(16);
    let join_token = random_token(32);
    let desktop_session_token = random_token(32);

    let (base_a, task_a) = spawn_test_server_with_config(|config| {
        config.redis_url = Some(redis_url.clone());
        config.redis_key_prefix = redis_key_prefix.clone();
        config.token_rotation_grace_ms = 30_000;
    })
    .await;

    let start_response = client
        .post(format!("{base_a}/pair/start"))
        .json(&json!({
            "sessionID": session_id,
            "joinToken": join_token,
            "desktopSessionToken": desktop_session_token,
            "joinTokenExpiresAt": chrono::Utc::now().checked_add_signed(chrono::Duration::minutes(2)).unwrap().to_rfc3339(),
            "idleTimeoutSeconds": 1800,
        }))
        .send()
        .await
        .expect("pair start request");
    assert_eq!(start_response.status(), StatusCode::OK);
    let start_payload: Value = start_response.json().await.expect("pair start payload");
    let ws_url = start_payload
        .get("wsURL")
        .and_then(Value::as_str)
        .expect("ws url")
        .to_string();

    let (mut desktop_socket, _) = tokio_tungstenite::connect_async(&ws_url)
        .await
        .expect("desktop websocket");
    desktop_socket
        .send(Message::Text(
            json!({
                "type": "relay.auth",
                "token": desktop_session_token
            })
            .to_string(),
        ))
        .await
        .expect("desktop auth send");
    let _desktop_auth = next_matching_json_message(&mut desktop_socket, 1_000, |payload| {
        payload.get("type").and_then(Value::as_str) == Some("auth_ok")
    })
    .await;

    let join_future = tokio::spawn({
        let client = client.clone();
        let base_a = base_a.clone();
        let session_id = session_id.clone();
        let join_token = join_token.clone();
        async move {
            client
                .post(format!("{base_a}/pair/join"))
                .header("Origin", "http://localhost:4173")
                .json(&json!({
                    "sessionID": session_id,
                    "joinToken": join_token,
                    "deviceName": "Restart Test iPhone",
                }))
                .send()
                .await
                .expect("pair join request")
        }
    });

    let pair_request = next_matching_json_message(&mut desktop_socket, 1_000, |payload| {
        payload.get("type").and_then(Value::as_str) == Some("relay.pair_request")
    })
    .await;
    let request_id = pair_request
        .get("requestID")
        .and_then(Value::as_str)
        .expect("requestID")
        .to_string();

    desktop_socket
        .send(Message::Text(
            json!({
                "type": "relay.pair_decision",
                "sessionID": session_id,
                "requestID": request_id,
                "approved": true,
            })
            .to_string(),
        ))
        .await
        .expect("desktop pair decision send");

    let join_response = join_future.await.expect("join task");
    assert_eq!(join_response.status(), StatusCode::OK);
    let join_payload: Value = join_response.json().await.expect("join payload");
    let first_device_token = join_payload
        .get("deviceSessionToken")
        .and_then(Value::as_str)
        .expect("device token")
        .to_string();

    let mut mobile_request = ws_url.clone().into_client_request().expect("mobile request");
    mobile_request.headers_mut().insert(
        "Origin",
        "http://localhost:4173".parse().expect("origin header"),
    );
    let (mut mobile_socket, _) = tokio_tungstenite::connect_async(mobile_request)
        .await
        .expect("mobile websocket");
    mobile_socket
        .send(Message::Text(
            json!({ "type": "relay.auth", "token": first_device_token }).to_string(),
        ))
        .await
        .expect("mobile auth send");
    let mobile_auth = next_matching_json_message(&mut mobile_socket, 1_000, |payload| {
        payload.get("type").and_then(Value::as_str) == Some("auth_ok")
    })
    .await;
    let _rotated_device_token = mobile_auth
        .get("nextDeviceSessionToken")
        .and_then(Value::as_str)
        .expect("rotated device token")
        .to_string();

    mobile_socket.close(None).await.expect("mobile socket close");
    desktop_socket.close(None).await.expect("desktop socket close");
    task_a.abort();

    let (base_b, task_b) = spawn_test_server_with_config(|config| {
        config.redis_url = Some(redis_url.clone());
        config.redis_key_prefix = redis_key_prefix.clone();
        config.token_rotation_grace_ms = 30_000;
    })
    .await;

    let mut reconnect_request = (base_b.replace("http://", "ws://") + "/ws")
        .into_client_request()
        .expect("reconnect request");
    reconnect_request.headers_mut().insert(
        "Origin",
        "http://localhost:4173".parse().expect("origin header"),
    );
    let (mut reconnect_socket, _) = tokio_tungstenite::connect_async(reconnect_request)
        .await
        .expect("reconnect websocket");
    reconnect_socket
        .send(Message::Text(
            json!({ "type": "relay.auth", "token": first_device_token }).to_string(),
        ))
        .await
        .expect("reconnect auth send");

    let reconnect_auth = next_matching_json_message(&mut reconnect_socket, 1_000, |payload| {
        payload.get("type").and_then(Value::as_str) == Some("auth_ok")
    })
    .await;
    assert_eq!(
        reconnect_auth.get("role").and_then(Value::as_str),
        Some("mobile")
    );
    assert!(reconnect_auth
        .get("nextDeviceSessionToken")
        .and_then(Value::as_str)
        .is_some());

    reconnect_socket
        .close(None)
        .await
        .expect("reconnect socket close");
    task_b.abort();
}
