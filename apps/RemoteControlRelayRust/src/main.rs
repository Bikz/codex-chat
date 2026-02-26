use std::net::SocketAddr;

use remote_control_relay_rust::config::RelayConfig;
use remote_control_relay_rust::service::{build_router, new_state};
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
    let addr: SocketAddr = format!("{}:{}", config.host, config.port)
        .parse()
        .expect("invalid host/port configuration");

    let state = new_state(config.clone());
    let app = build_router(state);

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

    axum::serve(
        listener,
        app.into_make_service_with_connect_info::<SocketAddr>(),
    )
    .await
    .expect("relay server terminated unexpectedly");
}
