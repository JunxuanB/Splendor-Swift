import { DurableObject } from "cloudflare:workers";
import {
  GAME_PROTOCOL_VERSION,
  RELAY_PROTOCOL_VERSION,
  type RoomDescriptorDTO,
  type RoomListing,
} from "./protocol";

interface DirectoryRow {
  [key: string]: SqlStorageValue;
  room_id: string;
  code: string;
  descriptor_json: string;
  is_public: number;
  host_connected: number;
}

export class RoomDirectory extends DurableObject<Env> {
  constructor(ctx: DurableObjectState, env: Env) {
    super(ctx, env);
    ctx.blockConcurrencyWhile(async () => {
      this.ctx.storage.sql.exec(`
        CREATE TABLE IF NOT EXISTS rooms (
          room_id TEXT PRIMARY KEY,
          code TEXT NOT NULL UNIQUE,
          descriptor_json TEXT NOT NULL,
          is_public INTEGER NOT NULL,
          host_connected INTEGER NOT NULL,
          updated_at INTEGER NOT NULL
        );
        CREATE INDEX IF NOT EXISTS rooms_public_connected
          ON rooms(is_public, host_connected, updated_at);
      `);
    });
  }

  createRoom(descriptor: RoomDescriptorDTO, isPublic: boolean): { code: string } | null {
    const existing = this.ctx.storage.sql.exec("SELECT room_id FROM rooms WHERE room_id = ?", descriptor.id).toArray();
    if (existing.length > 0) return null;

    for (let attempt = 0; attempt < 20; attempt += 1) {
      const code = makeRoomCode();
      try {
        this.ctx.storage.sql.exec(
          `INSERT INTO rooms(room_id, code, descriptor_json, is_public, host_connected, updated_at)
           VALUES (?, ?, ?, ?, 0, ?)`,
          descriptor.id,
          code,
          JSON.stringify(descriptor),
          isPublic ? 1 : 0,
          Date.now(),
        );
        return { code };
      } catch (error) {
        if (!(error instanceof Error) || !error.message.includes("UNIQUE")) throw error;
      }
    }
    throw new Error("room_code_exhausted");
  }

  upsertRoom(listing: RoomListing): void {
    this.ctx.storage.sql.exec(
      `INSERT INTO rooms(room_id, code, descriptor_json, is_public, host_connected, updated_at)
       VALUES (?, ?, ?, ?, ?, ?)
       ON CONFLICT(room_id) DO UPDATE SET
         descriptor_json = excluded.descriptor_json,
         is_public = excluded.is_public,
         host_connected = excluded.host_connected,
         updated_at = excluded.updated_at`,
      listing.descriptor.id,
      listing.code,
      JSON.stringify(listing.descriptor),
      listing.isPublic ? 1 : 0,
      listing.hostConnected ? 1 : 0,
      Date.now(),
    );
  }

  setHostConnected(roomID: string, connected: boolean): void {
    this.ctx.storage.sql.exec(
      "UPDATE rooms SET host_connected = ?, updated_at = ? WHERE room_id = ?",
      connected ? 1 : 0,
      Date.now(),
      roomID,
    );
  }

  removeRoom(roomID: string): void {
    this.ctx.storage.sql.exec("DELETE FROM rooms WHERE room_id = ?", roomID);
  }

  listRooms(): RoomListing[] {
    return this.ctx.storage.sql
      .exec<DirectoryRow>(
        "SELECT room_id, code, descriptor_json, is_public, host_connected FROM rooms WHERE is_public = 1 AND host_connected = 1 ORDER BY updated_at DESC",
      )
      .toArray()
      .map(rowToListing);
  }

  getRoom(roomID: string): RoomListing | null {
    const rows = this.ctx.storage.sql
      .exec<DirectoryRow>(
        "SELECT room_id, code, descriptor_json, is_public, host_connected FROM rooms WHERE room_id = ?",
        roomID,
      )
      .toArray();
    return rows[0] ? rowToListing(rows[0]) : null;
  }

  getRoomByCode(code: string): RoomListing | null {
    const rows = this.ctx.storage.sql
      .exec<DirectoryRow>(
        "SELECT room_id, code, descriptor_json, is_public, host_connected FROM rooms WHERE code = ?",
        code.toUpperCase(),
      )
      .toArray();
    return rows[0] ? rowToListing(rows[0]) : null;
  }
}

function rowToListing(row: DirectoryRow): RoomListing {
  return {
    descriptor: JSON.parse(row.descriptor_json) as RoomDescriptorDTO,
    code: row.code,
    isPublic: row.is_public === 1,
    hostConnected: row.host_connected === 1,
    relayProtocolVersion: RELAY_PROTOCOL_VERSION,
    gameProtocolVersion: GAME_PROTOCOL_VERSION,
  };
}

function makeRoomCode(): string {
  const alphabet = "23456789ABCDEFGHJKMNPQRSTUVWXYZ";
  const random = new Uint8Array(6);
  crypto.getRandomValues(random);
  return Array.from(random, (value) => alphabet[value % alphabet.length]).join("");
}
