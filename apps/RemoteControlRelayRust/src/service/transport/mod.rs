use super::*;

mod http;
mod websocket;

pub fn build_router(state: SharedRelayState) -> Router {
    let max_json_bytes = state.config.max_json_bytes;
    let cors_layer = build_cors_layer(&state.config);

    Router::new()
        .route("/healthz", axum::routing::get(healthz))
        .route("/metricsz", axum::routing::get(metricsz))
        .route(
            "/pair/start",
            axum::routing::post(http::pair_start).options(http::pair_options),
        )
        .route(
            "/pair/join",
            axum::routing::post(http::pair_join).options(http::pair_options),
        )
        .route(
            "/pair/refresh",
            axum::routing::post(http::pair_refresh).options(http::pair_options),
        )
        .route(
            "/pair/stop",
            axum::routing::post(http::pair_stop).options(http::pair_options),
        )
        .route(
            "/devices/list",
            axum::routing::post(http::devices_list).options(http::pair_options),
        )
        .route(
            "/devices/revoke",
            axum::routing::post(http::device_revoke).options(http::pair_options),
        )
        .route("/ws", axum::routing::get(websocket::ws_upgrade))
        .with_state(state)
        .layer(DefaultBodyLimit::max(max_json_bytes))
        .layer(cors_layer)
}

pub(super) fn origin_allowed(config: &RelayConfig, headers: &HeaderMap) -> bool {
    let origin = headers.get("origin").and_then(|value| value.to_str().ok());
    if origin.is_none() {
        return true;
    }
    is_allowed_origin(&config.allowed_origins, origin)
}
