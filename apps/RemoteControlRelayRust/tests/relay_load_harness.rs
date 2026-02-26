use std::net::SocketAddr;
use std::sync::Arc;
use std::time::Duration;

use futures_util::{SinkExt, StreamExt};
use remote_control_relay_rust::config::RelayConfig;
use remote_control_relay_rust::service::{build_router, new_state};
use reqwest::StatusCode;
use serde::Serialize;
use serde_json::{json, Value};
use tokio::net::TcpListener;
use tokio::sync::{Mutex, Semaphore};
use tokio::task::JoinHandle;
use tokio::time::Instant;
use tokio_tungstenite::tungstenite::client::IntoClientRequest;
use tokio_tungstenite::tungstenite::Message;

type TestSocket =
    tokio_tungstenite::WebSocketStream<tokio_tungstenite::MaybeTlsStream<tokio::net::TcpStream>>;

#[derive(Clone)]
struct LoadHarnessConfig {
    sessions: usize,
    messages_per_session: u64,
    setup_concurrency: usize,
    roundtrip_timeout_ms: u64,
    p95_latency_budget_ms: u64,
    base_url: Option<String>,
    origin: String,
    results_path: Option<String>,
}

impl LoadHarnessConfig {
    fn from_env() -> Self {
        Self {
            sessions: parse_env_usize("RELAY_LOAD_SESSIONS", 50),
            messages_per_session: parse_env_u64("RELAY_LOAD_MESSAGES_PER_SESSION", 10),
            setup_concurrency: parse_env_usize("RELAY_LOAD_SETUP_CONCURRENCY", 16),
            roundtrip_timeout_ms: parse_env_u64("RELAY_LOAD_ROUNDTRIP_TIMEOUT_MS", 2_000),
            p95_latency_budget_ms: parse_env_u64("RELAY_LOAD_P95_BUDGET_MS", 750),
            base_url: std::env::var("RELAY_LOAD_BASE_URL")
                .ok()
                .map(|value| value.trim().trim_end_matches('/').to_string())
                .filter(|value| !value.is_empty()),
            origin: std::env::var("RELAY_LOAD_ORIGIN")
                .ok()
                .map(|value| value.trim().to_string())
                .filter(|value| !value.is_empty())
                .unwrap_or_else(|| "http://localhost:4173".to_string()),
            results_path: std::env::var("RELAY_LOAD_RESULTS_PATH")
                .ok()
                .map(|value| value.trim().to_string())
                .filter(|value| !value.is_empty()),
        }
    }
}

#[derive(Serialize)]
struct LoadHarnessSummary {
    status: String,
    base_url: String,
    origin: String,
    sessions: usize,
    messages_per_session: u64,
    sample_count: usize,
    p50_latency_ms: u128,
    p95_latency_ms: u128,
    p99_latency_ms: u128,
    max_latency_ms: u128,
    p95_latency_budget_ms: u64,
    passes_latency_budget: bool,
    outbound_send_failures: u64,
    slow_consumer_disconnects: u64,
    passes_backpressure_budget: bool,
    error_count: usize,
    first_error: Option<String>,
}

fn persist_summary_if_requested(
    config: &LoadHarnessConfig,
    summary: &LoadHarnessSummary,
) -> Result<(), String> {
    let Some(path) = config.results_path.as_ref() else {
        return Ok(());
    };

    let output_path = std::path::Path::new(path);
    if let Some(parent) = output_path.parent() {
        std::fs::create_dir_all(parent)
            .map_err(|error| format!("failed creating results directory: {error}"))?;
    }

    let encoded = serde_json::to_string_pretty(summary)
        .map_err(|error| format!("failed encoding results summary: {error}"))?;
    std::fs::write(output_path, encoded)
        .map_err(|error| format!("failed writing results summary: {error}"))?;
    Ok(())
}

fn parse_env_usize(key: &str, fallback: usize) -> usize {
    std::env::var(key)
        .ok()
        .and_then(|value| value.parse::<usize>().ok())
        .filter(|value| *value > 0)
        .unwrap_or(fallback)
}

fn parse_env_u64(key: &str, fallback: u64) -> u64 {
    std::env::var(key)
        .ok()
        .and_then(|value| value.parse::<u64>().ok())
        .filter(|value| *value > 0)
        .unwrap_or(fallback)
}

async fn spawn_test_server() -> (String, JoinHandle<()>) {
    let listener = TcpListener::bind("127.0.0.1:0")
        .await
        .expect("bind listener");
    let addr = listener.local_addr().expect("listener local addr");

    let mut config = RelayConfig::from_env();
    config.host = "127.0.0.1".to_string();
    config.port = addr.port();
    config.public_base_url = format!("http://{}:{}", addr.ip(), addr.port());
    config.allowed_origins = ["http://localhost:4173".to_string()].into_iter().collect();

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

struct SessionHandles {
    session_id: String,
    desktop_session_token: String,
    desktop_socket: TestSocket,
    mobile_socket: TestSocket,
}

async fn pair_connected_mobile(
    base: &str,
    origin: &str,
    client: &reqwest::Client,
) -> Result<SessionHandles, String> {
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
        .map_err(|error| format!("pair start request failed: {error}"))?;

    if start_response.status() != StatusCode::OK {
        return Err(format!(
            "pair start failed with status {}",
            start_response.status()
        ));
    }

    let start_payload: Value = start_response
        .json()
        .await
        .map_err(|error| format!("pair start payload decode failed: {error}"))?;
    let ws_url = start_payload
        .get("wsURL")
        .and_then(Value::as_str)
        .ok_or_else(|| "pair start response missing wsURL".to_string())?
        .to_string();

    let (mut desktop_socket, _) = tokio_tungstenite::connect_async(&ws_url)
        .await
        .map_err(|error| format!("desktop websocket connect failed: {error}"))?;

    desktop_socket
        .send(Message::Text(
            json!({ "type": "relay.auth", "token": desktop_session_token })
                .to_string()
                .into(),
        ))
        .await
        .map_err(|error| format!("desktop auth send failed: {error}"))?;

    let desktop_auth = desktop_socket
        .next()
        .await
        .ok_or_else(|| "desktop auth frame missing".to_string())
        .and_then(|value| value.map_err(|error| format!("desktop auth ws error: {error}")))?;
    if !matches!(desktop_auth, Message::Text(_)) {
        return Err("desktop auth response was not a text frame".to_string());
    }

    let join_response_future = {
        let base = base.to_string();
        let origin = origin.to_string();
        let session_id = session_id.clone();
        let join_token = join_token.clone();
        let client = client.clone();
        tokio::spawn(async move {
            client
                .post(format!("{base}/pair/join"))
                .header("Origin", origin)
                .json(&json!({
                    "sessionID": session_id,
                    "joinToken": join_token,
                    "deviceName": "Load Harness iPhone",
                }))
                .send()
                .await
        })
    };

    let pair_request = desktop_socket
        .next()
        .await
        .ok_or_else(|| "desktop pair request frame missing".to_string())
        .and_then(|value| value.map_err(|error| format!("desktop pair request ws error: {error}")))?;
    let pair_request_text = pair_request
        .to_text()
        .map_err(|error| format!("pair request is not text: {error}"))?;
    let pair_request_json: Value =
        serde_json::from_str(pair_request_text).map_err(|error| format!("pair request decode failed: {error}"))?;
    let request_id = pair_request_json
        .get("requestID")
        .and_then(Value::as_str)
        .ok_or_else(|| "pair request missing requestID".to_string())?
        .to_string();

    desktop_socket
        .send(Message::Text(
            json!({
                "type": "relay.pair_decision",
                "sessionID": session_id,
                "requestID": request_id,
                "approved": true,
            })
            .to_string()
            .into(),
        ))
        .await
        .map_err(|error| format!("desktop pair decision send failed: {error}"))?;

    let join_response = join_response_future
        .await
        .map_err(|error| format!("pair join task join failed: {error}"))?
        .map_err(|error| format!("pair join request failed: {error}"))?;
    if join_response.status() != StatusCode::OK {
        return Err(format!(
            "pair join failed with status {}",
            join_response.status()
        ));
    }

    let join_payload: Value = join_response
        .json()
        .await
        .map_err(|error| format!("pair join payload decode failed: {error}"))?;
    let device_token = join_payload
        .get("deviceSessionToken")
        .and_then(Value::as_str)
        .ok_or_else(|| "pair join missing deviceSessionToken".to_string())?
        .to_string();

    let mut mobile_request = ws_url
        .into_client_request()
        .map_err(|error| format!("mobile ws request build failed: {error}"))?;
    mobile_request.headers_mut().insert(
        "Origin",
        origin
            .parse()
            .map_err(|error| format!("invalid origin header value: {error}"))?,
    );

    let (mut mobile_socket, _) = tokio_tungstenite::connect_async(mobile_request)
        .await
        .map_err(|error| format!("mobile websocket connect failed: {error}"))?;

    mobile_socket
        .send(Message::Text(
            json!({ "type": "relay.auth", "token": device_token })
                .to_string()
                .into(),
        ))
        .await
        .map_err(|error| format!("mobile auth send failed: {error}"))?;

    let mobile_auth = mobile_socket
        .next()
        .await
        .ok_or_else(|| "mobile auth frame missing".to_string())
        .and_then(|value| value.map_err(|error| format!("mobile auth ws error: {error}")))?;
    if !matches!(mobile_auth, Message::Text(_)) {
        return Err("mobile auth response was not a text frame".to_string());
    }

    Ok(SessionHandles {
        session_id,
        desktop_session_token,
        desktop_socket,
        mobile_socket,
    })
}

async fn await_forwarded_command(
    desktop_socket: &mut TestSocket,
    expected_seq: u64,
    timeout: Duration,
) -> Result<(), String> {
    let deadline = tokio::time::Instant::now() + timeout;
    loop {
        let remaining = deadline
            .checked_duration_since(tokio::time::Instant::now())
            .ok_or_else(|| "timed out waiting for forwarded command".to_string())?;
        let frame = tokio::time::timeout(remaining, desktop_socket.next())
            .await
            .map_err(|_| "timed out waiting for forwarded command".to_string())?
            .ok_or_else(|| "desktop socket closed while waiting for forwarded command".to_string())
            .and_then(|value| value.map_err(|error| format!("desktop ws receive error: {error}")))?;

        let Message::Text(text) = frame else {
            continue;
        };

        let parsed: Value = serde_json::from_str(&text)
            .map_err(|error| format!("forwarded payload decode failed: {error}"))?;

        if parsed
            .pointer("/payload/type")
            .and_then(Value::as_str)
            .is_some_and(|value| value == "command")
            && parsed
                .get("seq")
                .and_then(Value::as_u64)
                .is_some_and(|seq| seq == expected_seq)
        {
            return Ok(());
        }
    }
}

fn percentile(sorted: &[u128], pct: f64) -> u128 {
    if sorted.is_empty() {
        return 0;
    }

    let clamped = pct.clamp(0.0, 1.0);
    let index = ((sorted.len() - 1) as f64 * clamped).round() as usize;
    sorted[index]
}

#[tokio::test]
#[ignore = "manual load harness"]
async fn relay_parallel_sessions_load_harness() {
    let cfg = LoadHarnessConfig::from_env();
    let (base, server_task) = if let Some(base_url) = cfg.base_url.clone() {
        (base_url, None)
    } else {
        let (local_base, task) = spawn_test_server().await;
        (local_base, Some(task))
    };
    let client = reqwest::Client::new();

    let semaphore = Arc::new(Semaphore::new(cfg.setup_concurrency.max(1)));
    let roundtrip_samples_ms = Arc::new(Mutex::new(Vec::<u128>::new()));
    let errors = Arc::new(Mutex::new(Vec::<String>::new()));

    let mut tasks = Vec::with_capacity(cfg.sessions);

    for session_index in 0..cfg.sessions {
        let permit_pool = Arc::clone(&semaphore);
        let base = base.clone();
        let origin = cfg.origin.clone();
        let client = client.clone();
        let roundtrip_samples_ms = Arc::clone(&roundtrip_samples_ms);
        let roundtrip_timeout = Duration::from_millis(cfg.roundtrip_timeout_ms);
        let messages_per_session = cfg.messages_per_session;

        tasks.push(tokio::spawn(async move {
            let _permit = permit_pool
                .acquire_owned()
                .await
                .map_err(|error| format!("permit acquisition failed: {error}"))?;

            let mut handles = pair_connected_mobile(&base, &origin, &client).await?;

            for seq in 1..=messages_per_session {
                let payload = json!({
                    "schemaVersion": 1,
                    "sessionID": handles.session_id,
                    "seq": seq,
                    "payload": {
                        "type": "command",
                        "payload": {
                            "name": "thread.select",
                            "threadID": format!("thread-{}", session_index),
                        }
                    }
                })
                .to_string();

                let start = Instant::now();
                handles
                    .mobile_socket
                    .send(Message::Text(payload.into()))
                    .await
                    .map_err(|error| format!("mobile send failed: {error}"))?;

                await_forwarded_command(&mut handles.desktop_socket, seq, roundtrip_timeout).await?;

                roundtrip_samples_ms
                    .lock()
                    .await
                    .push(start.elapsed().as_millis());
            }

            // Best-effort session close to keep harness deterministic.
            let _ = client
                .post(format!("{base}/pair/stop"))
                .json(&json!({
                    "sessionID": handles.session_id,
                    "desktopSessionToken": handles.desktop_session_token,
                }))
                .send()
                .await;

            Ok::<(), String>(())
        }));
    }

    for task in tasks {
        match task.await {
            Ok(Ok(())) => {}
            Ok(Err(error)) => errors.lock().await.push(error),
            Err(error) => errors
                .lock()
                .await
                .push(format!("task join error: {error}")),
        }
    }

    let failures = errors.lock().await.clone();
    if !failures.is_empty() {
        let failure_summary = LoadHarnessSummary {
            status: "task_failures".to_string(),
            base_url: base.clone(),
            origin: cfg.origin.clone(),
            sessions: cfg.sessions,
            messages_per_session: cfg.messages_per_session,
            sample_count: 0,
            p50_latency_ms: 0,
            p95_latency_ms: 0,
            p99_latency_ms: 0,
            max_latency_ms: 0,
            p95_latency_budget_ms: cfg.p95_latency_budget_ms,
            passes_latency_budget: false,
            outbound_send_failures: 0,
            slow_consumer_disconnects: 0,
            passes_backpressure_budget: false,
            error_count: failures.len(),
            first_error: failures.first().cloned(),
        };
        if let Err(error) = persist_summary_if_requested(&cfg, &failure_summary) {
            panic!("failed persisting load harness failure summary: {error}");
        }

        let first = failures.first().cloned().unwrap_or_else(|| "unknown error".to_string());
        panic!(
            "load harness encountered {} errors; first: {}",
            failures.len(),
            first
        );
    }

    let mut samples = roundtrip_samples_ms.lock().await.clone();
    samples.sort_unstable();
    let expected_samples = cfg.sessions as u64 * cfg.messages_per_session;
    assert_eq!(samples.len() as u64, expected_samples);

    let p50 = percentile(&samples, 0.50);
    let p95 = percentile(&samples, 0.95);
    let p99 = percentile(&samples, 0.99);
    let max = *samples.last().unwrap_or(&0);

    let metrics = reqwest::get(format!("{base}/metricsz"))
        .await
        .expect("metrics request")
        .json::<Value>()
        .await
        .expect("metrics payload");

    let outbound_send_failures = metrics
        .get("outboundSendFailures")
        .and_then(Value::as_u64)
        .unwrap_or(0);
    let slow_consumer_disconnects = metrics
        .get("slowConsumerDisconnects")
        .and_then(Value::as_u64)
        .unwrap_or(0);
    let passes_latency_budget = p95 <= cfg.p95_latency_budget_ms as u128;
    let passes_backpressure_budget = outbound_send_failures == 0 && slow_consumer_disconnects == 0;
    let success_summary = LoadHarnessSummary {
        status: "ok".to_string(),
        base_url: base.clone(),
        origin: cfg.origin.clone(),
        sessions: cfg.sessions,
        messages_per_session: cfg.messages_per_session,
        sample_count: samples.len(),
        p50_latency_ms: p50,
        p95_latency_ms: p95,
        p99_latency_ms: p99,
        max_latency_ms: max,
        p95_latency_budget_ms: cfg.p95_latency_budget_ms,
        passes_latency_budget,
        outbound_send_failures,
        slow_consumer_disconnects,
        passes_backpressure_budget,
        error_count: 0,
        first_error: None,
    };
    if let Err(error) = persist_summary_if_requested(&cfg, &success_summary) {
        panic!("failed persisting load harness summary: {error}");
    }

    println!(
        "relay load harness summary: sessions={} messages_per_session={} samples={} p50={}ms p95={}ms p99={}ms max={}ms outboundSendFailures={} slowConsumerDisconnects={}",
        cfg.sessions,
        cfg.messages_per_session,
        samples.len(),
        p50,
        p95,
        p99,
        max,
        outbound_send_failures,
        slow_consumer_disconnects,
    );

    assert!(
        passes_latency_budget,
        "p95 latency {}ms exceeded budget {}ms",
        p95,
        cfg.p95_latency_budget_ms
    );

    assert_eq!(
        outbound_send_failures, 0,
        "expected no outbound send failures during harness"
    );
    assert_eq!(
        slow_consumer_disconnects, 0,
        "expected no slow consumer disconnects during harness"
    );

    if let Some(task) = server_task {
        task.abort();
    }
}
