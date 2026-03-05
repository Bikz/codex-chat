use std::net::SocketAddr;

use remote_control_relay_rust::config::RelayConfig;
use remote_control_relay_rust::service::{build_router, drain_sessions_for_shutdown, new_state};
use tokio::net::TcpListener;
use tracing::info;
use tracing_subscriber::EnvFilter;

#[tokio::main]
async fn main() {
    tracing_subscriber::fmt()
        .with_env_filter(
            EnvFilter::try_from_default_env().unwrap_or_else(|_| EnvFilter::new("info")),
        )
        .compact()
        .init();

    let config = RelayConfig::from_env();
    if let Err(error) = config.validate() {
        panic!("[relay-rs] invalid configuration: {error}");
    }
    let addr: SocketAddr = format!("{}:{}", config.host, config.port)
        .parse()
        .expect("invalid host/port configuration");

    let state = new_state(config.clone()).await;
    let app = build_router(state.clone());

    let listener = TcpListener::bind(addr)
        .await
        .expect("failed to bind relay listener");

    info!("[relay-rs] listening on {}", addr);
    info!("[relay-rs] public base URL: {}", config.public_base_url);
    if config.allowed_origins.contains("*") {
        info!("[relay-rs] allowed origins: *");
    } else {
        let mut origins = config.allowed_origins.iter().cloned().collect::<Vec<_>>();
        origins.sort();
        info!("[relay-rs] allowed origins: {}", origins.join(", "));
    }

    let shutdown_state = state;
    axum::serve(
        listener,
        app.into_make_service_with_connect_info::<SocketAddr>(),
    )
    .with_graceful_shutdown(async move {
        wait_for_shutdown_signal().await;
        info!("[relay-rs] shutdown signal received; draining sessions");
        drain_sessions_for_shutdown(&shutdown_state).await;
    })
    .await
    .expect("relay server terminated unexpectedly");
}

async fn wait_for_shutdown_signal() {
    let ctrl_c = async {
        if let Err(error) = tokio::signal::ctrl_c().await {
            tracing::warn!("[relay-rs] failed waiting for ctrl_c signal: {error}");
        }
    };

    #[cfg(unix)]
    let terminate = async {
        match tokio::signal::unix::signal(tokio::signal::unix::SignalKind::terminate()) {
            Ok(mut signal) => {
                let _ = signal.recv().await;
            }
            Err(error) => {
                tracing::warn!("[relay-rs] failed registering terminate signal handler: {error}");
            }
        }
    };

    #[cfg(not(unix))]
    let terminate = std::future::pending::<()>();

    tokio::select! {
        _ = ctrl_c => {}
        _ = terminate => {}
    }
}
