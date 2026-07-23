export const RELAY_PROTOCOL_VERSION = 1;
export const GAME_PROTOCOL_VERSION = 1;
export const MAX_ENVELOPE_BYTES = 1_048_576;
export const MAX_ROOM_CONNECTIONS = 16;
export const HOST_RECONNECT_GRACE_MS = 30 * 60 * 1_000;
export const ROOM_MAX_LIFETIME_MS = 3 * 60 * 60 * 1_000;

export const ROOM_STAGES = ["lobby", "configuration", "playing", "results"] as const;
export type RoomStage = (typeof ROOM_STAGES)[number];

export interface RoomDescriptorDTO {
  id: string;
  name: string;
  hostNickname: string;
  playerCount: number;
  maximumPlayers: number;
  isPasswordProtected: boolean;
  stage: RoomStage;
}

export interface RoomListing {
  descriptor: RoomDescriptorDTO;
  code: string;
  isPublic: boolean;
  hostConnected: boolean;
  relayProtocolVersion: number;
  gameProtocolVersion: number;
}

export interface CreateRoomRequest {
  descriptor: RoomDescriptorDTO;
  isPublic: boolean;
  relayProtocolVersion: number;
  gameProtocolVersion: number;
}

export type SocketAttachment =
  | { role: "host"; peerID: "host" }
  | { role: "client"; peerID: string };

export type ClientFrame =
  | { type: "relay"; destination: "host"; payload: string }
  | { type: "relay"; destination: "peer"; peerID: string; payload: string }
  | { type: "relay"; destination: "broadcast"; payload: string }
  | { type: "roomMetadata"; descriptor: RoomDescriptorDTO; isPublic: boolean }
  | { type: "closeRoom" };

export type ServerFrame =
  | { type: "ready"; roomID: string; peerID: string; relayProtocolVersion: number }
  | { type: "peerConnected"; peerID: string }
  | { type: "peerDisconnected"; peerID: string }
  | { type: "relay"; fromPeerID: string; payload: string }
  | { type: "hostUnavailable" }
  | { type: "hostAvailable" }
  | { type: "error"; code: string };

export function isRoomDescriptor(value: unknown): value is RoomDescriptorDTO {
  if (!isRecord(value)) return false;
  return isUUID(value.id)
    && typeof value.name === "string" && value.name.trim().length > 0 && value.name.length <= 40
    && typeof value.hostNickname === "string" && value.hostNickname.trim().length > 0 && value.hostNickname.length <= 30
    && isBoundedInteger(value.playerCount, 0, 64)
    && isBoundedInteger(value.maximumPlayers, 2, 64)
    && typeof value.isPasswordProtected === "boolean"
    && typeof value.stage === "string"
    && ROOM_STAGES.includes(value.stage as RoomStage);
}

export function parseCreateRoomRequest(value: unknown): CreateRoomRequest | null {
  if (!isRecord(value) || !isRoomDescriptor(value.descriptor) || typeof value.isPublic !== "boolean") return null;
  if (value.relayProtocolVersion !== RELAY_PROTOCOL_VERSION || value.gameProtocolVersion !== GAME_PROTOCOL_VERSION) return null;
  return {
    descriptor: value.descriptor,
    isPublic: value.isPublic,
    relayProtocolVersion: value.relayProtocolVersion,
    gameProtocolVersion: value.gameProtocolVersion,
  };
}

export function parseClientFrame(value: unknown): ClientFrame | null {
  if (!isRecord(value) || typeof value.type !== "string") return null;
  if (value.type === "closeRoom") return { type: "closeRoom" };
  if (value.type === "roomMetadata" && isRoomDescriptor(value.descriptor) && typeof value.isPublic === "boolean") {
    return { type: "roomMetadata", descriptor: value.descriptor, isPublic: value.isPublic };
  }
  if (value.type !== "relay" || typeof value.destination !== "string" || typeof value.payload !== "string") return null;
  if (!isValidPayload(value.payload)) return null;
  if (value.destination === "host") return { type: "relay", destination: "host", payload: value.payload };
  if (value.destination === "broadcast") return { type: "relay", destination: "broadcast", payload: value.payload };
  if (value.destination === "peer" && typeof value.peerID === "string" && value.peerID.length <= 64) {
    return { type: "relay", destination: "peer", peerID: value.peerID, payload: value.payload };
  }
  return null;
}

export function isUUID(value: unknown): value is string {
  return typeof value === "string"
    && /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value);
}

export function json(data: unknown, status = 200): Response {
  return Response.json(data, {
    status,
    headers: {
      "Cache-Control": "no-store",
      "Access-Control-Allow-Origin": "*",
    },
  });
}

export function randomToken(): string {
  const bytes = new Uint8Array(32);
  crypto.getRandomValues(bytes);
  return bytesToHex(bytes);
}

export async function sha256Hex(value: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value));
  return bytesToHex(new Uint8Array(digest));
}

export function hexToBytes(value: string): Uint8Array | null {
  if (value.length % 2 !== 0 || !/^[0-9a-f]+$/i.test(value)) return null;
  const bytes = new Uint8Array(value.length / 2);
  for (let index = 0; index < bytes.length; index += 1) {
    bytes[index] = Number.parseInt(value.slice(index * 2, index * 2 + 2), 16);
  }
  return bytes;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function isBoundedInteger(value: unknown, minimum: number, maximum: number): value is number {
  return typeof value === "number" && Number.isInteger(value) && value >= minimum && value <= maximum;
}

function isValidPayload(payload: string): boolean {
  if (payload.length > Math.ceil(MAX_ENVELOPE_BYTES / 3) * 4 + 4 || !/^[A-Za-z0-9+/]*={0,2}$/.test(payload)) return false;
  try {
    return atob(payload).length <= MAX_ENVELOPE_BYTES;
  } catch {
    return false;
  }
}

function bytesToHex(bytes: Uint8Array): string {
  return Array.from(bytes, (byte) => byte.toString(16).padStart(2, "0")).join("");
}
