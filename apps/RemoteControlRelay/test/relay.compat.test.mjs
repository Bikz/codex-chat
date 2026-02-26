import assert from "node:assert/strict";
import { randomBytes } from "node:crypto";
import { spawn } from "node:child_process";
import net from "node:net";
import path from "node:path";
import { fileURLToPath } from "node:url";
import test from "node:test";
import { WebSocket } from "ws";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const relayNodeRoot = path.resolve(__dirname, "..");
const repoRoot = path.resolve(relayNodeRoot, "..", "..");
const relayRustRoot = path.join(repoRoot, "apps", "RemoteControlRelayRust");

function randomToken(bytes = 24) {
  return randomBytes(bytes).toString("base64url");
}

function wait(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

async function reservePort() {
  return await new Promise((resolve, reject) => {
    const server = net.createServer();
    server.once("error", reject);
    server.listen(0, "127.0.0.1", () => {
      const address = server.address();
      if (!address || typeof address === "string") {
        reject(new Error("Unable to resolve ephemeral port"));
        return;
      }
      const port = address.port;
      server.close((closeError) => {
        if (closeError) {
          reject(closeError);
          return;
        }
        resolve(port);
      });
    });
  });
}

async function waitForRelay(baseURL, attempts = 90) {
  for (let index = 0; index < attempts; index += 1) {
    try {
      const response = await fetch(`${baseURL}/healthz`);
      if (response.ok) {
        return;
      }
    } catch {
      // Relay startup race.
    }
    await wait(125);
  }
  throw new Error(`Relay did not become healthy in time: ${baseURL}`);
}

async function openWebSocket(url, { origin } = {}) {
  return await new Promise((resolve, reject) => {
    const headers = origin ? { origin } : undefined;
    const socket = new WebSocket(url, { headers });

    const onError = (error) => {
      cleanup();
      reject(error);
    };
    const onOpen = () => {
      cleanup();
      resolve(socket);
    };
    const cleanup = () => {
      socket.off("error", onError);
      socket.off("open", onOpen);
    };

    socket.once("error", onError);
    socket.once("open", onOpen);
  });
}

async function nextJSONMessage(socket, timeoutMs = 5000, context = "unknown") {
  return await new Promise((resolve, reject) => {
    const timeout = setTimeout(() => {
      cleanup();
      reject(new Error(`Timed out waiting for websocket message [${context}]`));
    }, timeoutMs);

    const onMessage = (raw) => {
      cleanup();
      resolve(JSON.parse(raw.toString("utf8")));
    };
    const onError = (error) => {
      cleanup();
      reject(error);
    };
    const cleanup = () => {
      clearTimeout(timeout);
      socket.off("message", onMessage);
      socket.off("error", onError);
    };

    socket.once("message", onMessage);
    socket.once("error", onError);
  });
}

async function nextMatchingJSONMessage(socket, predicate, timeoutMs = 5000, context = "unknown") {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    const remaining = Math.max(50, deadline - Date.now());
    const message = await nextJSONMessage(socket, remaining, context);
    if (predicate(message)) {
      return message;
    }
  }
  throw new Error(`Timed out waiting for matching websocket message [${context}]`);
}

async function closeSocket(socket) {
  if (!socket) {
    return;
  }
  if (socket.readyState === WebSocket.CLOSED || socket.readyState === WebSocket.CLOSING) {
    return;
  }
  await new Promise((resolve) => {
    const timeout = setTimeout(resolve, 500);
    socket.once("close", () => {
      clearTimeout(timeout);
      resolve();
    });
    socket.close();
  });
}

async function startRelay(kind) {
  const port = await reservePort();
  const host = "127.0.0.1";
  const baseURL = `http://${host}:${port}`;
  let child;

  if (kind === "node") {
    child = spawn("node", ["src/server.mjs"], {
      cwd: relayNodeRoot,
      stdio: "ignore",
      env: {
        ...process.env,
        PORT: String(port),
        HOST: host,
        PUBLIC_BASE_URL: baseURL,
        ALLOWED_ORIGINS: "http://localhost:4173",
        TOKEN_ROTATION_GRACE_MS: "120"
      }
    });
  } else if (kind === "rust") {
    child = spawn("cargo", ["run", "--quiet"], {
      cwd: relayRustRoot,
      stdio: "ignore",
      env: {
        ...process.env,
        PORT: String(port),
        HOST: host,
        PUBLIC_BASE_URL: baseURL,
        ALLOWED_ORIGINS: "http://localhost:4173",
        TOKEN_ROTATION_GRACE_MS: "120",
        RUST_LOG: "error"
      }
    });
  } else {
    throw new Error(`Unsupported relay kind: ${kind}`);
  }

  await waitForRelay(baseURL);

  return {
    baseURL,
    wsURL: `ws://${host}:${port}/ws`,
    stop: async () => {
      if (!child || child.exitCode !== null) {
        return;
      }
      child.kill("SIGTERM");
      await wait(400);
      if (child.exitCode === null) {
        child.kill("SIGKILL");
      }
    }
  };
}

async function probeRotatedTokenRejection(wsURL, token) {
  const probe = await openWebSocket(wsURL, { origin: "http://localhost:4173" });
  try {
    probe.send(
      JSON.stringify({
        type: "relay.auth",
        token
      })
    );

    const outcome = await new Promise((resolve, reject) => {
      const timeout = setTimeout(() => {
        cleanup();
        resolve({ accepted: false, reason: "timeout" });
      }, 3000);

      const onMessage = (raw) => {
        const payload = JSON.parse(raw.toString("utf8"));
        cleanup();
        resolve({
          accepted: payload?.type === "auth_ok",
          reason: payload?.type === "auth_ok" ? "auth_ok" : payload?.type || "message"
        });
      };

      const onClose = () => {
        cleanup();
        resolve({ accepted: false, reason: "close" });
      };

      const onError = (error) => {
        cleanup();
        reject(error);
      };

      const cleanup = () => {
        clearTimeout(timeout);
        probe.off("message", onMessage);
        probe.off("close", onClose);
        probe.off("error", onError);
      };

      probe.once("message", onMessage);
      probe.once("close", onClose);
      probe.once("error", onError);
    });

    return !outcome.accepted;
  } finally {
    await closeSocket(probe);
  }
}

async function runScenario(relayKind) {
  const relay = await startRelay(relayKind);
  const client = new Headers({ "content-type": "application/json" });

  const sessionID = randomToken(16);
  const joinToken = randomToken(32);
  const desktopSessionToken = randomToken(32);
  const joinTokenExpiresAt = new Date(Date.now() + 120_000).toISOString();

  let desktopSocket;
  let mobileSocket;
  let secondMobileSocket;

  try {
    const pairStartResponse = await fetch(`${relay.baseURL}/pair/start`, {
      method: "POST",
      headers: client,
      body: JSON.stringify({
        sessionID,
        joinToken,
        desktopSessionToken,
        joinTokenExpiresAt,
        relayWebSocketURL: relay.wsURL,
        idleTimeoutSeconds: 1800
      })
    });

    const pairStartBody = await pairStartResponse.json();
    const wsURL = pairStartBody.wsURL || relay.wsURL;

    desktopSocket = await openWebSocket(wsURL);
    desktopSocket.send(
      JSON.stringify({
        type: "relay.auth",
        token: desktopSessionToken
      })
    );
    const desktopAuth = await nextJSONMessage(desktopSocket, 5000, `${relayKind}:desktop-auth`);

    const joinPromise = fetch(`${relay.baseURL}/pair/join`, {
      method: "POST",
      headers: {
        "content-type": "application/json",
        origin: "http://localhost:4173"
      },
      body: JSON.stringify({
        sessionID,
        joinToken
      })
    });

    const pairRequest = await nextMatchingJSONMessage(
      desktopSocket,
      (message) => message?.type === "relay.pair_request",
      5000,
      `${relayKind}:pair-request`
    );
    desktopSocket.send(
      JSON.stringify({
        type: "relay.pair_decision",
        sessionID,
        requestID: pairRequest.requestID,
        approved: true
      })
    );

    const joinResponse = await joinPromise;
    const joinPayload = await joinResponse.json();
    const firstToken = joinPayload.deviceSessionToken;

    mobileSocket = await openWebSocket(wsURL, { origin: "http://localhost:4173" });
    mobileSocket.send(
      JSON.stringify({
        type: "relay.auth",
        token: firstToken
      })
    );
    const mobileAuth = await nextJSONMessage(mobileSocket, 5000, `${relayKind}:mobile-auth`);
    const rotatedToken = mobileAuth.nextDeviceSessionToken;

    mobileSocket.send(
      JSON.stringify({
        schemaVersion: 1,
        sessionID,
        seq: 1,
        timestamp: new Date().toISOString(),
        relayConnectionID: "spoofed-connection",
        relayDeviceID: "spoofed-device",
        payload: {
          type: "command",
          payload: {
            name: "thread.select",
            threadID: "thread-compat"
          }
        }
      })
    );

    const forwarded = await nextMatchingJSONMessage(
      desktopSocket,
      (message) => message?.payload?.type === "command",
      5000,
      `${relayKind}:forwarded-command`
    );

    await closeSocket(mobileSocket);
    await wait(200);

    const firstTokenRejected = await probeRotatedTokenRejection(wsURL, firstToken);

    secondMobileSocket = await openWebSocket(wsURL, { origin: "http://localhost:4173" });
    secondMobileSocket.send(
      JSON.stringify({
        type: "relay.auth",
        token: rotatedToken
      })
    );
    const secondAuth = await nextJSONMessage(secondMobileSocket, 5000, `${relayKind}:second-mobile-auth`);

    return {
      pairStartOK: pairStartResponse.status === 200,
      desktopAuthOK: desktopAuth?.type === "auth_ok" && desktopAuth?.role === "desktop",
      pairRequestOK: pairRequest?.type === "relay.pair_request" && pairRequest?.sessionID === sessionID,
      joinOK: joinResponse.status === 200,
      joinDeviceIDPresent: typeof joinPayload?.deviceID === "string" && joinPayload.deviceID.length > 0,
      joinTokenPresent: typeof firstToken === "string" && firstToken.length > 0,
      mobileAuthOK: mobileAuth?.type === "auth_ok" && mobileAuth?.role === "mobile",
      rotatedTokenIssued: typeof rotatedToken === "string" && rotatedToken.length > 0 && rotatedToken !== firstToken,
      spoofedConnectionRejected:
        typeof forwarded?.relayConnectionID === "string" &&
        forwarded.relayConnectionID !== "spoofed-connection",
      spoofedDeviceRejected:
        forwarded?.relayDeviceID === joinPayload.deviceID && forwarded?.relayDeviceID !== "spoofed-device",
      firstTokenRejected,
      rotatedTokenAccepted: secondAuth?.type === "auth_ok" && secondAuth?.role === "mobile"
    };
  } finally {
    await closeSocket(secondMobileSocket);
    await closeSocket(mobileSocket);
    await closeSocket(desktopSocket);
    await relay.stop();
  }
}

test(
  "node and rust relays remain protocol-compatible for pairing, auth rotation, and command forwarding",
  { timeout: 300_000 },
  async () => {
    const nodeResult = await runScenario("node");
    const rustResult = await runScenario("rust");

    assert.deepEqual(
      rustResult,
      nodeResult,
      [
        "Rust relay behavior diverged from Node relay baseline.",
        `Node: ${JSON.stringify(nodeResult)}`,
        `Rust: ${JSON.stringify(rustResult)}`
      ].join("\n")
    );
  }
);
