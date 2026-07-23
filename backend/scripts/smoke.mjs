import assert from "node:assert/strict";
import { WebSocket } from "ws";

const baseURL = new URL(process.env.LUMINORE_RELAY_URL ?? "https://luminore-api.junxuanb.com");
const webSocketBase = new URL(baseURL);
webSocketBase.protocol = baseURL.protocol === "https:" ? "wss:" : "ws:";

const health = await getJSON("v1/health");
assert.equal(health.relayProtocolVersion, 1);
assert.equal(health.gameProtocolVersion, 1);

const publicRoom = await createRoom(true, "Online Public Smoke");
console.log("smoke: public room created");
const publicHost = await openRoomSocket(publicRoom.roomID, "host", publicRoom.hostToken);
assert.equal((await publicHost.next()).type, "ready");
const publicRooms = (await getJSON("v1/rooms")).rooms;
assert(publicRooms.some((room) => room.descriptor.id === publicRoom.roomID));
publicHost.send({ type: "closeRoom" });
await publicHost.closed;

const hiddenRoom = await createRoom(false, "Online Hidden Smoke");
console.log("smoke: hidden room created");
const hiddenRooms = (await getJSON("v1/rooms")).rooms;
assert(!hiddenRooms.some((room) => room.descriptor.id === hiddenRoom.roomID));
const resolved = await getJSON("v1/rooms/code/" + hiddenRoom.roomCode);
assert.equal(resolved.room.descriptor.id, hiddenRoom.roomID);

let host = await openRoomSocket(hiddenRoom.roomID, "host", hiddenRoom.hostToken);
assert.deepEqual(await host.next(), {
  type: "ready",
  roomID: hiddenRoom.roomID,
  peerID: "host",
  relayProtocolVersion: 1,
});
console.log("smoke: hidden host ready");
const client = await openRoomSocket(hiddenRoom.roomID, "client");
console.log("smoke: relay peers connected");
const clientReady = await client.next();
console.log("smoke: hidden client ready");
assert.equal(clientReady.type, "ready");
assert.deepEqual(await host.next(), { type: "peerConnected", peerID: clientReady.peerID });
console.log("smoke: host saw client");

const payload = Buffer.from("opaque-not-a-wire-envelope").toString("base64");
client.send({ type: "relay", destination: "host", payload });
assert.deepEqual(await host.next(), { type: "relay", fromPeerID: clientReady.peerID, payload });
console.log("smoke: client to host relay complete");
host.send({ type: "relay", destination: "peer", peerID: clientReady.peerID, payload });
assert.deepEqual(await client.next(), { type: "relay", fromPeerID: "host", payload });
console.log("smoke: host to client relay complete");

host.close();
await host.closed;
console.log("smoke: host socket closed");
assert.deepEqual(await client.next(), { type: "hostUnavailable" });
console.log("smoke: host unavailable received");
host = await openRoomSocket(hiddenRoom.roomID, "host", hiddenRoom.hostToken);
assert.equal((await host.next()).type, "ready");
assert.deepEqual(await host.next(), { type: "peerConnected", peerID: clientReady.peerID });
assert.deepEqual(await client.next(), { type: "hostAvailable" });
console.log("smoke: host recovery complete");

const secondClient = await openRoomSocket(hiddenRoom.roomID, "client");
await secondClient.next();
await host.next();
host.send({ type: "relay", destination: "broadcast", payload });
assert.deepEqual(await client.next(), { type: "relay", fromPeerID: "host", payload });
assert.deepEqual(await secondClient.next(), { type: "relay", fromPeerID: "host", payload });

host.send({ type: "closeRoom" });
await Promise.all([host.closed, client.closed, secondClient.closed]);
console.log("smoke: explicit close complete");
const closedResponse = await fetch(new URL("v1/rooms/" + hiddenRoom.roomID, baseURL));
assert.equal(closedResponse.status, 404);

console.log(JSON.stringify({ ok: true, baseURL: baseURL.href, checks: 10 }));

async function createRoom(isPublic, name) {
  const id = crypto.randomUUID();
  const response = await fetch(new URL("v1/rooms", baseURL), {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      descriptor: {
        id,
        name,
        hostNickname: "Smoke",
        playerCount: 1,
        maximumPlayers: 7,
        isPasswordProtected: false,
        stage: "lobby",
      },
      isPublic,
      relayProtocolVersion: 1,
      gameProtocolVersion: 1,
    }),
  });
  assert.equal(response.status, 201);
  return response.json();
}

async function getJSON(path) {
  const response = await fetch(new URL(path, baseURL));
  assert.equal(response.status, 200);
  return response.json();
}

async function openRoomSocket(roomID, role, hostToken) {
  const url = new URL("v1/rooms/" + roomID + "/connect?role=" + role, webSocketBase);
  const headers = hostToken ? { Authorization: "Bearer " + hostToken } : undefined;
  const socket = new WebSocket(url, { headers });
  const queue = [];
  const waiters = [];
  socket.on("message", (data) => {
    const value = JSON.parse(data.toString());
    const waiter = waiters.shift();
    if (waiter) waiter(value);
    else queue.push(value);
  });
  const closed = new Promise((resolve) => socket.once("close", resolve));
  await new Promise((resolve, reject) => {
    socket.once("open", resolve);
    socket.once("error", reject);
  });
  return {
    closed: timeout(closed),
    next() {
      if (queue.length > 0) return Promise.resolve(queue.shift());
      return timeout(new Promise((resolve) => waiters.push(resolve)));
    },
    send(frame) {
      socket.send(JSON.stringify(frame));
    },
    close() {
      socket.terminate();
    },
  };
}

function timeout(promise) {
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error("smoke_timeout")), 10_000);
    promise.then(
      (value) => {
        clearTimeout(timer);
        resolve(value);
      },
      (error) => {
        clearTimeout(timer);
        reject(error);
      },
    );
  });
}
