import { DurableObject } from "cloudflare:workers";
import { timingSafeEqual } from "node:crypto";
import {
  GAME_PROTOCOL_VERSION,
  HOST_RECONNECT_GRACE_MS,
  MAX_ROOM_CONNECTIONS,
  RELAY_PROTOCOL_VERSION,
  ROOM_MAX_LIFETIME_MS,
  hexToBytes,
  parseClientFrame,
  sha256Hex,
  type RoomDescriptorDTO,
  type RoomListing,
  type ServerFrame,
  type SocketAttachment,
} from "./protocol";

interface StoredRoom {
  roomID: string;
  code: string;
  descriptor: RoomDescriptorDTO;
  isPublic: boolean;
  hostTokenHash: string;
  createdAt?: number;
  expiresAt?: number;
}

type AlarmReason = "host_timeout" | "room_expired";

const HOST_RECONNECT_DEADLINE_KEY = "hostReconnectDeadline";
const ALARM_REASON_KEY = "alarmReason";

export class RoomRelay extends DurableObject<Env> {
  constructor(ctx: DurableObjectState, env: Env) {
    super(ctx, env);
    ctx.blockConcurrencyWhile(async () => {
      const stored = await this.ctx.storage.get<StoredRoom>("room");
      if (!stored) return;

      const room = await this.ensureLifecycle(stored);
      let reconnectDeadline = await this.ctx.storage.get<number>(HOST_RECONNECT_DEADLINE_KEY);
      if (!this.hostSocket() && reconnectDeadline === undefined) {
        reconnectDeadline = Date.now() + HOST_RECONNECT_GRACE_MS;
        await this.ctx.storage.put(HOST_RECONNECT_DEADLINE_KEY, reconnectDeadline);
      }
      await this.scheduleLifecycleAlarm(room, reconnectDeadline);
    });
  }

  async initialize(room: StoredRoom): Promise<boolean> {
    const existing = await this.ctx.storage.get<StoredRoom>("room");
    if (existing) return false;
    const createdAt = Date.now();
    const stored = {
      ...room,
      createdAt,
      expiresAt: createdAt + ROOM_MAX_LIFETIME_MS,
    };
    const reconnectDeadline = createdAt + HOST_RECONNECT_GRACE_MS;
    await this.ctx.storage.put({
      room: stored,
      [HOST_RECONNECT_DEADLINE_KEY]: reconnectDeadline,
    });
    // Also expires rooms whose creator never finishes opening the host socket.
    await this.scheduleLifecycleAlarm(stored, reconnectDeadline);
    return true;
  }

  override async fetch(request: Request): Promise<Response> {
    if (request.headers.get("Upgrade")?.toLowerCase() !== "websocket") {
      return Response.json({ error: "websocket_required" }, { status: 426 });
    }
    const stored = await this.ctx.storage.get<StoredRoom>("room");
    if (!stored) return Response.json({ error: "room_not_found" }, { status: 404 });
    const room = await this.ensureLifecycle(stored);
    if (Date.now() >= room.expiresAt) {
      await this.closeRoom("room_expired");
      return Response.json({ error: "room_not_found" }, { status: 404 });
    }

    const url = new URL(request.url);
    const role = url.searchParams.get("role");
    if (role !== "host" && role !== "client") {
      return Response.json({ error: "invalid_role" }, { status: 400 });
    }
    // A reconnecting host may replace the still-closing host socket without
    // temporarily consuming an extra room slot.
    if (this.ctx.getWebSockets().length >= MAX_ROOM_CONNECTIONS && !(role === "host" && this.hostSocket())) {
      return Response.json({ error: "room_connection_limit" }, { status: 429 });
    }
    if (role === "host" && !(await this.isAuthorizedHost(request, room))) {
      return Response.json({ error: "invalid_host_token" }, { status: 401 });
    }

    const pair = new WebSocketPair();
    const client = pair[0];
    const server = pair[1];
    const attachment: SocketAttachment = role === "host"
      ? { role: "host", peerID: "host" }
      : { role: "client", peerID: crypto.randomUUID() };
    server.serializeAttachment(attachment);
    this.ctx.acceptWebSocket(server, [role]);

    if (role === "host") {
      for (const previous of this.ctx.getWebSockets("host")) {
        if (previous !== server) previous.close(4001, "host_replaced");
      }
      await this.ctx.storage.delete(HOST_RECONNECT_DEADLINE_KEY);
      await this.scheduleLifecycleAlarm(room);
      await this.setDirectoryAvailability(room, true);
      send(server, { type: "ready", roomID: room.roomID, peerID: "host", relayProtocolVersion: RELAY_PROTOCOL_VERSION });
      for (const peer of this.clientSockets()) {
        const peerAttachment = attachmentOf(peer);
        if (peerAttachment) send(server, { type: "peerConnected", peerID: peerAttachment.peerID });
        send(peer, { type: "hostAvailable" });
      }
    } else {
      send(server, {
        type: "ready",
        roomID: room.roomID,
        peerID: attachment.peerID,
        relayProtocolVersion: RELAY_PROTOCOL_VERSION,
      });
      const host = this.hostSocket();
      if (host) send(host, { type: "peerConnected", peerID: attachment.peerID });
      else send(server, { type: "hostUnavailable" });
    }
    return new Response(null, { status: 101, webSocket: client });
  }

  override async webSocketMessage(socket: WebSocket, message: string | ArrayBuffer): Promise<void> {
    const attachment = attachmentOf(socket);
    if (!attachment || typeof message !== "string" || message.length > 1_500_000) {
      send(socket, { type: "error", code: "invalid_frame" });
      return;
    }
    let decoded: unknown;
    try {
      decoded = JSON.parse(message);
    } catch {
      send(socket, { type: "error", code: "invalid_frame" });
      return;
    }
    const frame = parseClientFrame(decoded);
    if (!frame) {
      send(socket, { type: "error", code: "invalid_frame" });
      return;
    }

    if (frame.type === "closeRoom") {
      if (attachment.role !== "host") return send(socket, { type: "error", code: "host_only" });
      await this.closeRoom("host_closed");
      return;
    }
    if (frame.type === "roomMetadata") {
      if (attachment.role !== "host") return send(socket, { type: "error", code: "host_only" });
      const room = await this.ctx.storage.get<StoredRoom>("room");
      if (!room || frame.descriptor.id !== room.roomID) return send(socket, { type: "error", code: "room_mismatch" });
      const updated = { ...room, descriptor: frame.descriptor, isPublic: frame.isPublic };
      await this.ctx.storage.put("room", updated);
      await this.setDirectoryAvailability(updated, true);
      return;
    }

    if (attachment.role === "client") {
      if (frame.destination !== "host") return send(socket, { type: "error", code: "client_destination_forbidden" });
      const host = this.hostSocket();
      if (host) send(host, { type: "relay", fromPeerID: attachment.peerID, payload: frame.payload });
      else send(socket, { type: "hostUnavailable" });
      return;
    }

    if (frame.destination === "host") return send(socket, { type: "error", code: "host_destination_forbidden" });
    if (frame.destination === "broadcast") {
      for (const peer of this.clientSockets()) {
        send(peer, { type: "relay", fromPeerID: "host", payload: frame.payload });
      }
      return;
    }
    const target = this.clientSockets().find((peer) => attachmentOf(peer)?.peerID === frame.peerID);
    if (target) send(target, { type: "relay", fromPeerID: "host", payload: frame.payload });
    else send(socket, { type: "error", code: "peer_not_found" });
  }

  override async webSocketClose(socket: WebSocket): Promise<void> {
    await this.handleSocketGone(socket);
  }

  override async webSocketError(socket: WebSocket): Promise<void> {
    await this.handleSocketGone(socket);
  }

  override async alarm(): Promise<void> {
    const room = await this.ctx.storage.get<StoredRoom>("room");
    if (!room) return;
    const reason = await this.ctx.storage.get<AlarmReason>(ALARM_REASON_KEY);
    if (reason === "room_expired") {
      await this.closeRoom("room_expired");
      return;
    }
    if (!this.hostSocket()) {
      await this.closeRoom("host_timeout");
      return;
    }
    await this.ctx.storage.delete(HOST_RECONNECT_DEADLINE_KEY);
    await this.scheduleLifecycleAlarm(await this.ensureLifecycle(room));
  }

  private async handleSocketGone(socket: WebSocket): Promise<void> {
    const attachment = attachmentOf(socket);
    if (!attachment) return;
    if (attachment.role === "client") {
      const host = this.hostSocket();
      if (host) send(host, { type: "peerDisconnected", peerID: attachment.peerID });
      return;
    }
    const room = await this.ctx.storage.get<StoredRoom>("room");
    if (!room || this.hostSocket(socket)) return;
    await this.setDirectoryAvailability(room, false);
    for (const peer of this.clientSockets()) send(peer, { type: "hostUnavailable" });
    const reconnectDeadline = Date.now() + HOST_RECONNECT_GRACE_MS;
    await this.ctx.storage.put(HOST_RECONNECT_DEADLINE_KEY, reconnectDeadline);
    await this.scheduleLifecycleAlarm(await this.ensureLifecycle(room), reconnectDeadline);
  }

  private async closeRoom(reason: string): Promise<void> {
    const room = await this.ctx.storage.get<StoredRoom>("room");
    if (room) await this.directory().removeRoom(room.roomID);
    for (const socket of this.ctx.getWebSockets()) socket.close(4000, reason);
    await this.ctx.storage.deleteAlarm();
    await this.ctx.storage.deleteAll();
  }

  private async ensureLifecycle(room: StoredRoom): Promise<StoredRoom & { createdAt: number; expiresAt: number }> {
    if (room.createdAt !== undefined && room.expiresAt !== undefined) {
      return { ...room, createdAt: room.createdAt, expiresAt: room.expiresAt };
    }
    // Rooms created before lifecycle expiration was deployed receive one full
    // lifetime from their first activation under the new Worker version.
    const createdAt = room.createdAt ?? Date.now();
    const updated = {
      ...room,
      createdAt,
      expiresAt: room.expiresAt ?? createdAt + ROOM_MAX_LIFETIME_MS,
    };
    await this.ctx.storage.put("room", updated);
    return updated;
  }

  private async scheduleLifecycleAlarm(
    room: StoredRoom & { expiresAt: number },
    reconnectDeadline?: number,
  ): Promise<void> {
    const expiresFirst = reconnectDeadline === undefined || room.expiresAt <= reconnectDeadline;
    const reason: AlarmReason = expiresFirst ? "room_expired" : "host_timeout";
    await this.ctx.storage.put(ALARM_REASON_KEY, reason);
    await this.ctx.storage.setAlarm(expiresFirst ? room.expiresAt : reconnectDeadline);
  }

  private hostSocket(excluding?: WebSocket): WebSocket | undefined {
    return this.ctx.getWebSockets("host").find((socket) => socket !== excluding);
  }

  private clientSockets(): WebSocket[] {
    return this.ctx.getWebSockets("client");
  }

  private directory(): DurableObjectStub<import("./room-directory").RoomDirectory> {
    return this.env.ROOM_DIRECTORY.getByName("directory");
  }

  private async setDirectoryAvailability(room: StoredRoom, hostConnected: boolean): Promise<void> {
    const listing: RoomListing = {
      descriptor: room.descriptor,
      code: room.code,
      isPublic: room.isPublic,
      hostConnected,
      relayProtocolVersion: RELAY_PROTOCOL_VERSION,
      gameProtocolVersion: GAME_PROTOCOL_VERSION,
    };
    await this.directory().upsertRoom(listing);
  }

  private async isAuthorizedHost(request: Request, room: StoredRoom): Promise<boolean> {
    const authorization = request.headers.get("Authorization");
    if (!authorization?.startsWith("Bearer ")) return false;
    const actualHex = await sha256Hex(authorization.slice(7));
    const actual = hexToBytes(actualHex);
    const expected = hexToBytes(room.hostTokenHash);
    return actual !== null && expected !== null && timingSafeEqual(actual, expected);
  }
}

function attachmentOf(socket: WebSocket): SocketAttachment | null {
  const value: unknown = socket.deserializeAttachment();
  if (!value || typeof value !== "object" || !("role" in value) || !("peerID" in value)) return null;
  const role = value.role;
  const peerID = value.peerID;
  if ((role !== "host" && role !== "client") || typeof peerID !== "string") return null;
  return role === "host" ? { role, peerID: "host" } : { role, peerID };
}

function send(socket: WebSocket, frame: ServerFrame): void {
  try {
    socket.send(JSON.stringify(frame));
  } catch {
    // The close/error event performs authoritative cleanup.
  }
}
