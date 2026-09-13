import { mkdirSync } from 'node:fs'
import { dirname } from 'node:path'
import '@tanstack/react-start/server-only'
import Database from 'better-sqlite3'
import { DATABASE_PATH } from './env'

function open() {
  mkdirSync(dirname(DATABASE_PATH), { recursive: true })
  const database = new Database(DATABASE_PATH)
  database.pragma('journal_mode = WAL')
  database.pragma('foreign_keys = ON')
  database.exec(`
    CREATE TABLE IF NOT EXISTS users (
      id            TEXT PRIMARY KEY,
      email         TEXT NOT NULL UNIQUE,
      created_at    INTEGER NOT NULL,
      last_login_at INTEGER
    );

    CREATE TABLE IF NOT EXISTS login_codes (
      id          TEXT PRIMARY KEY,
      email       TEXT NOT NULL,
      code_hash   TEXT NOT NULL,
      created_at  INTEGER NOT NULL,
      expires_at  INTEGER NOT NULL,
      attempts    INTEGER NOT NULL DEFAULT 0,
      consumed_at INTEGER,
      request_ip  TEXT
    );
    CREATE INDEX IF NOT EXISTS login_codes_email_idx
      ON login_codes (email, created_at);
    CREATE INDEX IF NOT EXISTS login_codes_ip_idx
      ON login_codes (request_ip, created_at);

    CREATE TABLE IF NOT EXISTS sessions (
      id         TEXT PRIMARY KEY,
      token_hash TEXT NOT NULL UNIQUE,
      user_id    TEXT NOT NULL REFERENCES users (id) ON DELETE CASCADE,
      created_at INTEGER NOT NULL,
      expires_at INTEGER NOT NULL,
      user_agent TEXT,
      request_ip TEXT
    );
    CREATE INDEX IF NOT EXISTS sessions_user_idx ON sessions (user_id);
  `)
  return database
}

/**
 * One connection per server process. Module scope is fine for the handle
 * itself — no request data is read here.
 */
export const db: Database.Database = open()

export type UserRow = {
  id: string
  email: string
  created_at: number
  last_login_at: number | null
}

export type LoginCodeRow = {
  id: string
  email: string
  code_hash: string
  created_at: number
  expires_at: number
  attempts: number
  consumed_at: number | null
  request_ip: string | null
}

export type SessionRow = {
  id: string
  token_hash: string
  user_id: string
  created_at: number
  expires_at: number
  user_agent: string | null
  request_ip: string | null
}
