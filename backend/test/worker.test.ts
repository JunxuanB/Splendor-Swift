import { SELF, env, runDurableObjectAlarm, runInDurableObject } from "cloudflare:test";
import { describe, expect, it } from "vitest";
import { ROOM_MAX_LIFETIME_MS } from "../src/protocol";

const descriptor = {
  id: "22222222-2222-4222-8222-222222222222",
  name: "Quartz Room",
  hostNickname: "Nova",
  playerCount: 1,
  maximumPlayers: 7,
  isPasswordProtected: true,
  stage: "lobby",
};

describe("Luminore relay HTTP API", () => {
  it("reports compatible protocol versions", async () => {
    const response = await SELF.fetch("https://example.test/v1/health");
    expect(response.status).toBe(200);
    expect(await response.json()).toEqual({
      service: "luminore-relay",
      relayProtocolVersion: 1,
      gameProtocolVersion: 1,
    });
  });

  it("creates and lists a public room", async () => {
    const created = await createRoom(descriptor, true);
    expect(created.response.status).toBe(201);
    expect(created.body.roomCode).toMatch(/^[23456789ABCDEFGHJKMNPQRSTUVWXYZ]{6}$/);
    expect(created.body.hostToken).toHaveLength(64);

    const listed = await SELF.fetch("https://example.test/v1/rooms");
    const payload = await listed.json<{ rooms: Array<{ descriptor: typeof descriptor }> }>();
    // A room becomes publicly discoverable only after its host WebSocket is online.
    expect(payload.rooms.map((room: { descriptor: typeof descriptor }) => room.descriptor.id)).not.toContain(descriptor.id);

    const resolved = await SELF.fetch(`https://example.test/v1/rooms/${descriptor.id}`);
    expect(resolved.status).toBe(200);
  });

  it("keeps hidden rooms out of the public list while resolving their code", async () => {
    const hiddenDescriptor = { ...descriptor, id: "33333333-3333-4333-8333-333333333333", name: "Hidden" };
    const created = await createRoom(hiddenDescriptor, false);
    const listed = await SELF.fetch("https://example.test/v1/rooms");
    const payload = await listed.json<{ rooms: Array<{ descriptor: typeof descriptor }> }>();
    expect(payload.rooms.map((room: { descriptor: typeof descriptor }) => room.descriptor.id)).not.toContain(hiddenDescriptor.id);

    const resolved = await SELF.fetch(`https://example.test/v1/rooms/code/${created.body.roomCode}`);
    expect(resolved.status).toBe(200);
    const resolvedBody = await resolved.json<{ room: { descriptor: typeof descriptor } }>();
    expect(resolvedBody.room.descriptor.id).toBe(hiddenDescriptor.id);
  });

  it("rejects incompatible and malformed room requests", async () => {
    const response = await SELF.fetch("https://example.test/v1/rooms", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ descriptor, isPublic: true, relayProtocolVersion: 2, gameProtocolVersion: 1 }),
    });
    expect(response.status).toBe(400);
  });

  it("authenticates the host and relays opaque payloads in both directions", async () => {
    const relayDescriptor = { ...descriptor, id: "44444444-4444-4444-8444-444444444444" };
    const created = await createRoom(relayDescriptor, true);

    const unauthorized = await connect(relayDescriptor.id, "host", "wrong-token");
    expect(unauthorized.status).toBe(401);

    const host = await openSocket(await connect(relayDescriptor.id, "host", created.body.hostToken));
    expect(await host.next()).toMatchObject({ type: "ready", peerID: "host" });

    const listed = await SELF.fetch("https://example.test/v1/rooms");
    const listedBody = await listed.json<{ rooms: Array<{ descriptor: typeof descriptor }> }>();
    expect(listedBody.rooms.map((room) => room.descriptor.id)).toContain(relayDescriptor.id);

    const client = await openSocket(await connect(relayDescriptor.id, "client"));
    const ready = await client.next() as { type: string; peerID: string };
    expect(ready.type).toBe("ready");
    const connected = await host.next() as { type: string; peerID: string };
    expect(connected).toEqual({ type: "peerConnected", peerID: ready.peerID });

    // This is intentionally not a WireEnvelope (or even JSON). The relay must
    // preserve it byte-for-byte and never inspect game payloads.
    const opaquePayload = btoa("not-json-game-data\u0000\u0001");
    client.socket.send(JSON.stringify({ type: "relay", destination: "host", payload: opaquePayload }));
    expect(await host.next()).toEqual({ type: "relay", fromPeerID: ready.peerID, payload: opaquePayload });

    host.socket.send(JSON.stringify({
      type: "relay",
      destination: "peer",
      peerID: ready.peerID,
      payload: opaquePayload,
    }));
    expect(await client.next()).toEqual({ type: "relay", fromPeerID: "host", payload: opaquePayload });

    const secondClient = await openSocket(await connect(relayDescriptor.id, "client"));
    await secondClient.next();
    await host.next();
    host.socket.send(JSON.stringify({ type: "relay", destination: "broadcast", payload: opaquePayload }));
    expect(await client.next()).toEqual({ type: "relay", fromPeerID: "host", payload: opaquePayload });
    expect(await secondClient.next()).toEqual({ type: "relay", fromPeerID: "host", payload: opaquePayload });

    host.socket.send(JSON.stringify({ type: "closeRoom" }));
    await Promise.all([host.closed(), client.closed(), secondClient.closed()]);
    expect((await SELF.fetch(`https://example.test/v1/rooms/${relayDescriptor.id}`)).status).toBe(404);
  });

  it("hides an unavailable host, restores it, and removes the room when the alarm expires", async () => {
    const reconnectDescriptor = { ...descriptor, id: "55555555-5555-4555-8555-555555555555" };
    const created = await createRoom(reconnectDescriptor, false);
    const host = await openSocket(await connect(reconnectDescriptor.id, "host", created.body.hostToken));
    await host.next();
    const client = await openSocket(await connect(reconnectDescriptor.id, "client"));
    const clientReady = await client.next() as { peerID: string };
    await host.next();

    host.socket.close(1000, "network_lost");
    expect(await client.next()).toEqual({ type: "hostUnavailable" });
    const unavailable = await SELF.fetch(`https://example.test/v1/rooms/${reconnectDescriptor.id}`);
    expect((await unavailable.json<{ room: { hostConnected: boolean } }>()).room.hostConnected).toBe(false);

    const restoredHost = await openSocket(await connect(reconnectDescriptor.id, "host", created.body.hostToken));
    expect(await restoredHost.next()).toMatchObject({ type: "ready", peerID: "host" });
    expect(await restoredHost.next()).toEqual({ type: "peerConnected", peerID: clientReady.peerID });
    expect(await client.next()).toEqual({ type: "hostAvailable" });

    restoredHost.socket.close(1000, "network_lost_again");
    expect(await client.next()).toEqual({ type: "hostUnavailable" });
    const relay = env.ROOM_RELAY.getByName(reconnectDescriptor.id);
    expect(await runDurableObjectAlarm(relay)).toBe(true);
    await client.closed();
    expect((await SELF.fetch(`https://example.test/v1/rooms/${reconnectDescriptor.id}`)).status).toBe(404);
  });

  it("expires an active room three hours after it is created", async () => {
    const expiringDescriptor = { ...descriptor, id: "77777777-7777-4777-8777-777777777777" };
    const created = await createRoom(expiringDescriptor, true);
    const host = await openSocket(await connect(expiringDescriptor.id, "host", created.body.hostToken));
    await host.next();

    const relay = env.ROOM_RELAY.getByName(expiringDescriptor.id);
    const lifecycle = await runInDurableObject(relay, async (_instance, state) => {
      const room = await state.storage.get<{ createdAt: number; expiresAt: number }>("room");
      return { room, alarm: await state.storage.getAlarm() };
    });
    expect(lifecycle.room).toBeDefined();
    expect(lifecycle.room!.expiresAt - lifecycle.room!.createdAt).toBe(ROOM_MAX_LIFETIME_MS);
    expect(lifecycle.alarm).toBe(lifecycle.room!.expiresAt);

    expect(await runDurableObjectAlarm(relay)).toBe(true);
    await host.closed();
    expect((await SELF.fetch(`https://example.test/v1/rooms/${expiringDescriptor.id}`)).status).toBe(404);
  });

  it("rejects oversized relay payloads and a seventeenth connection", async () => {
    const limitedDescriptor = { ...descriptor, id: "66666666-6666-4666-8666-666666666666" };
    const created = await createRoom(limitedDescriptor, true);
    const host = await openSocket(await connect(limitedDescriptor.id, "host", created.body.hostToken));
    await host.next();
    const clients: SocketInbox[] = [];
    for (let index = 0; index < 15; index += 1) {
      const client = await openSocket(await connect(limitedDescriptor.id, "client"));
      await client.next();
      await host.next();
      clients.push(client);
    }
    expect((await connect(limitedDescriptor.id, "client")).status).toBe(429);

    clients[0]!.socket.send(JSON.stringify({
      type: "relay",
      destination: "host",
      payload: "A".repeat(1_500_000),
    }));
    expect(await clients[0]!.next()).toEqual({ type: "error", code: "invalid_frame" });

    host.socket.send(JSON.stringify({ type: "closeRoom" }));
    await host.closed();
  });
});

async function createRoom(room: typeof descriptor, isPublic: boolean): Promise<{
  response: Response;
  body: { roomCode: string; hostToken: string };
}> {
  const response = await SELF.fetch("https://example.test/v1/rooms", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ descriptor: room, isPublic, relayProtocolVersion: 1, gameProtocolVersion: 1 }),
  });
  return { response, body: await response.json() };
}

function connect(roomID: string, role: "host" | "client", token?: string): Promise<Response> {
  const headers = new Headers({ Upgrade: "websocket" });
  if (token) headers.set("Authorization", `Bearer ${token}`);
  return SELF.fetch(`https://example.test/v1/rooms/${roomID}/connect?role=${role}`, { headers });
}

async function openSocket(response: Response): Promise<SocketInbox> {
  expect(response.status).toBe(101);
  const socket = response.webSocket;
  if (!socket) throw new Error("missing_websocket");
  return new SocketInbox(socket);
}

class SocketInbox {
  readonly socket: WebSocket;
  private readonly messages: unknown[] = [];
  private readonly waiting: Array<(value: unknown) => void> = [];
  private closePromise: Promise<void>;

  constructor(socket: WebSocket) {
    this.socket = socket;
    socket.addEventListener("message", (event) => {
      const value = JSON.parse(String(event.data)) as unknown;
      const waiter = this.waiting.shift();
      if (waiter) waiter(value);
      else this.messages.push(value);
    });
    this.closePromise = new Promise((resolve) => socket.addEventListener("close", () => resolve()));
    socket.accept();
  }

  async next(): Promise<unknown> {
    const queued = this.messages.shift();
    if (queued !== undefined) return queued;
    return withTimeout(new Promise((resolve) => this.waiting.push(resolve)));
  }

  closed(): Promise<void> {
    return withTimeout(this.closePromise);
  }
}

function withTimeout<T>(promise: Promise<T>): Promise<T> {
  return Promise.race([
    promise,
    new Promise<never>((_, reject) => setTimeout(() => reject(new Error("websocket_test_timeout")), 5_000)),
  ]);
}
