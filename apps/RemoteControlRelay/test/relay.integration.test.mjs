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
const relayRoot = path.resolve(__dirname, "..");

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

async function waitForRelay(baseURL, attempts = 40) {
  for (let index = 0; index < attempts; index += 1) {
    try {
      const response = await fetch(`${baseURL}/healthz`);
      if (response.ok) {
        return;
      }
    } catch {
      // Relay boot race; retry.
    }
    await wait(75);
  }
  throw new Error("Relay did not become healthy in time");
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

async function nextJSONMessage(socket, timeoutMs = 5000) {
  return await new Promise((resolve, reject) => {
    const timeout = setTimeout(() => {
      cleanup();
      reject(new Error("Timed out waiting for websocket message"));
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

async function expectWebSocketAuthFailure(url, { origin }, expectedStatusCode) {
  await new Promise((resolve, reject) => {
    const socket = new WebSocket(url, { headers: { origin } });
    socket.once("open", () => {
      socket.close(1000, "unexpected_open");
      reject(new Error("Expected websocket auth failure, but socket opened"));
    });
    socket.once("error", (error) => {
      try {
        assert.match(String(error.message), new RegExp(String(expectedStatusCode)));
        resolve();
      } catch (assertionError) {
        reject(assertionError);
      }
    });
  });
}

test("pair join requires desktop approval and rotates device session tokens", async () => {
  const port = await reservePort();
  const host = "127.0.0.1";
  const baseURL = `http://${host}:${port}`;
  const wsURL = `ws://${host}:${port}/ws`;

  const relayProcess = spawn("node", ["src/server.mjs"], {
    cwd: relayRoot,
    stdio: "ignore",
    env: {
      ...process.env,
      PORT: String(port),
      HOST: host,
      PUBLIC_BASE_URL: baseURL,
      ALLOWED_ORIGINS: "http://localhost:4173"
    }
  });

  try {
    await waitForRelay(baseURL);

    const sessionID = randomToken(16);
    const joinToken = randomToken(32);
    const desktopSessionToken = randomToken(32);
    const joinTokenExpiresAt = new Date(Date.now() + 120_000).toISOString();

    const pairStartResponse = await fetch(`${baseURL}/pair/start`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({
        sessionID,
        joinToken,
        desktopSessionToken,
        joinTokenExpiresAt,
        relayWebSocketURL: wsURL,
        idleTimeoutSeconds: 1800
      })
    });
    assert.equal(pairStartResponse.status, 200);

    const desktopSocket = await openWebSocket(`${wsURL}?token=${desktopSessionToken}`);
    const desktopAuth = await nextJSONMessage(desktopSocket);
    assert.equal(desktopAuth.type, "auth_ok");
    assert.equal(desktopAuth.role, "desktop");

    const joinPromise = fetch(`${baseURL}/pair/join`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({
        sessionID,
        joinToken
      })
    });

    const pairRequest = await nextJSONMessage(desktopSocket);
    assert.equal(pairRequest.type, "relay.pair_request");
    assert.equal(pairRequest.sessionID, sessionID);
    assert.equal(typeof pairRequest.requestID, "string");

    desktopSocket.send(
      JSON.stringify({
        type: "relay.pair_decision",
        sessionID,
        requestID: pairRequest.requestID,
        approved: true
      })
    );

    const joinResponse = await joinPromise;
    assert.equal(joinResponse.status, 200);
    const joinPayload = await joinResponse.json();
    assert.equal(joinPayload.sessionID, sessionID);
    assert.equal(typeof joinPayload.deviceSessionToken, "string");
    assert.equal(typeof joinPayload.deviceID, "string");

    const firstToken = joinPayload.deviceSessionToken;
    const mobileSocket = await openWebSocket(`${wsURL}?token=${firstToken}`, {
      origin: "http://localhost:4173"
    });
    const mobileAuth = await nextJSONMessage(mobileSocket);
    assert.equal(mobileAuth.type, "auth_ok");
    assert.equal(mobileAuth.role, "mobile");
    assert.equal(mobileAuth.deviceID, joinPayload.deviceID);
    assert.equal(typeof mobileAuth.nextDeviceSessionToken, "string");
    assert.notEqual(mobileAuth.nextDeviceSessionToken, firstToken);
    const rotatedToken = mobileAuth.nextDeviceSessionToken;

    mobileSocket.close();

    await expectWebSocketAuthFailure(`${wsURL}?token=${firstToken}`, {
      origin: "http://localhost:4173"
    }, 401);

    const secondMobileSocket = await openWebSocket(`${wsURL}?token=${rotatedToken}`, {
      origin: "http://localhost:4173"
    });
    const secondMobileAuth = await nextJSONMessage(secondMobileSocket);
    assert.equal(secondMobileAuth.type, "auth_ok");
    assert.equal(secondMobileAuth.role, "mobile");
    assert.equal(secondMobileAuth.deviceID, joinPayload.deviceID);
    assert.equal(typeof secondMobileAuth.nextDeviceSessionToken, "string");
    assert.notEqual(secondMobileAuth.nextDeviceSessionToken, rotatedToken);

    secondMobileSocket.close();
    desktopSocket.close();
  } finally {
    relayProcess.kill("SIGTERM");
    await wait(150);
    if (relayProcess.exitCode === null) {
      relayProcess.kill("SIGKILL");
    }
  }
});
