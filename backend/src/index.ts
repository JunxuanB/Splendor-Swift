import { RoomDirectory } from "./room-directory";
import { RoomRelay } from "./room-relay";
import {
  GAME_PROTOCOL_VERSION,
  RELAY_PROTOCOL_VERSION,
  isUUID,
  json,
  parseCreateRoomRequest,
  randomToken,
  sha256Hex,
} from "./protocol";

export { RoomDirectory, RoomRelay };

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);
    try {
      if (request.method === "OPTIONS") {
        return new Response(null, {
          status: 204,
          headers: {
            "Access-Control-Allow-Origin": "*",
            "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
            "Access-Control-Allow-Headers": "Authorization, Content-Type",
          },
        });
      }
      if (request.method === "GET" && url.pathname === "/v1/health") {
        return json({
          service: "luminore-relay",
          relayProtocolVersion: RELAY_PROTOCOL_VERSION,
          gameProtocolVersion: GAME_PROTOCOL_VERSION,
        });
      }
      if (request.method === "GET" && url.pathname === "/v1/rooms") {
        const rooms = await directory(env).listRooms();
        return json({ rooms });
      }
      if (request.method === "POST" && url.pathname === "/v1/rooms") {
        const body = await readJSON(request, 16_384);
        if (body === TOO_LARGE) return json({ error: "request_too_large" }, 413);
        if (body === INVALID_JSON) return json({ error: "invalid_room" }, 400);
        const parsed = parseCreateRoomRequest(body);
        if (!parsed) return json({ error: "invalid_room" }, 400);

        const created = await directory(env).createRoom(parsed.descriptor, parsed.isPublic);
        if (!created) return json({ error: "room_already_exists" }, 409);
        const hostToken = randomToken();
        const initialized = await env.ROOM_RELAY.getByName(parsed.descriptor.id).initialize({
          roomID: parsed.descriptor.id,
          code: created.code,
          descriptor: parsed.descriptor,
          isPublic: parsed.isPublic,
          hostTokenHash: await sha256Hex(hostToken),
        });
        if (!initialized) {
          await directory(env).removeRoom(parsed.descriptor.id);
          return json({ error: "room_already_exists" }, 409);
        }
        return json({
          roomID: parsed.descriptor.id,
          roomCode: created.code,
          hostToken,
          relayProtocolVersion: RELAY_PROTOCOL_VERSION,
        }, 201);
      }

      const codeMatch = url.pathname.match(/^\/v1\/rooms\/code\/([A-Za-z0-9]{6})$/);
      if (request.method === "GET" && codeMatch?.[1]) {
        const room = await directory(env).getRoomByCode(codeMatch[1]);
        return room ? json({ room }) : json({ error: "room_not_found" }, 404);
      }

      const connectMatch = url.pathname.match(/^\/v1\/rooms\/([^/]+)\/connect$/);
      if (request.method === "GET" && connectMatch?.[1] && isUUID(connectMatch[1])) {
        return env.ROOM_RELAY.getByName(connectMatch[1]).fetch(request);
      }

      const roomMatch = url.pathname.match(/^\/v1\/rooms\/([^/]+)$/);
      if (request.method === "GET" && roomMatch?.[1] && isUUID(roomMatch[1])) {
        const room = await directory(env).getRoom(roomMatch[1]);
        return room ? json({ room }) : json({ error: "room_not_found" }, 404);
      }
      return json({ error: "not_found" }, 404);
    } catch (error) {
      console.error(JSON.stringify({
        message: "request_failed",
        method: request.method,
        path: url.pathname,
        error: error instanceof Error ? error.message : String(error),
      }));
      return json({ error: "internal_error" }, 500);
    }
  },
} satisfies ExportedHandler<Env>;

function directory(env: Env): DurableObjectStub<RoomDirectory> {
  return env.ROOM_DIRECTORY.getByName("directory");
}

const TOO_LARGE = Symbol("too_large");
const INVALID_JSON = Symbol("invalid_json");

async function readJSON(request: Request, maximumBytes: number): Promise<unknown | typeof TOO_LARGE | typeof INVALID_JSON> {
  const declaredLength = Number(request.headers.get("Content-Length") ?? "0");
  if (declaredLength > maximumBytes) return TOO_LARGE;
  if (!request.body) return INVALID_JSON;

  const reader = request.body.getReader();
  const chunks: Uint8Array[] = [];
  let byteCount = 0;
  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      byteCount += value.byteLength;
      if (byteCount > maximumBytes) {
        await reader.cancel("request_too_large");
        return TOO_LARGE;
      }
      chunks.push(value);
    }
  } catch {
    return INVALID_JSON;
  }

  const bytes = new Uint8Array(byteCount);
  let offset = 0;
  for (const chunk of chunks) {
    bytes.set(chunk, offset);
    offset += chunk.byteLength;
  }
  try {
    return JSON.parse(new TextDecoder().decode(bytes)) as unknown;
  } catch {
    return INVALID_JSON;
  }
}
