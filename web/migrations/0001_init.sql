-- The Nethead notesfile: heads, passkeys, the conference, tape lists, trees,
-- the lot. Ids are uppercase UUID strings where the iOS app may sync the row
-- later (shelves, mix tapes, journal); the conference's own numbers are
-- integers. Timestamps are ISO-8601 UTC text. Synced tables carry
-- updated_at / deleted_at / seq so a future "sign in with your handle" sync
-- needs no schema change.

CREATE TABLE users (
  id                  TEXT PRIMARY KEY,
  handle              TEXT NOT NULL UNIQUE,
  node                TEXT NOT NULL,
  name                TEXT NOT NULL,
  first_show          TEXT,
  role                TEXT NOT NULL DEFAULT 'head',
  share_spins         INTEGER NOT NULL DEFAULT 1,
  recovery_hash       TEXT NOT NULL,
  recovery_rotated_at TEXT NOT NULL,
  notes_seen_through  INTEGER NOT NULL DEFAULT 0,
  server_seq          INTEGER NOT NULL DEFAULT 0,
  created_at          TEXT NOT NULL,
  updated_at          TEXT NOT NULL,
  disabled_at         TEXT
);

CREATE TABLE passkeys (
  id            TEXT PRIMARY KEY,
  user_id       TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  public_key    BLOB NOT NULL,
  counter       INTEGER NOT NULL DEFAULT 0,
  transports    TEXT,
  device_type   TEXT,
  backed_up     INTEGER NOT NULL DEFAULT 0,
  label         TEXT,
  created_at    TEXT NOT NULL,
  last_used_at  TEXT
);
CREATE INDEX idx_passkeys_user ON passkeys(user_id);

CREATE TABLE ceremonies (
  id           TEXT PRIMARY KEY,
  kind         TEXT NOT NULL,
  user_id      TEXT,
  challenge    TEXT NOT NULL,
  payload_json TEXT,
  created_at   TEXT NOT NULL,
  expires_at   TEXT NOT NULL
);
CREATE INDEX idx_ceremonies_expires ON ceremonies(expires_at);

CREATE TABLE sessions (
  token_hash    TEXT PRIMARY KEY,
  user_id       TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  created_at    TEXT NOT NULL,
  last_seen_at  TEXT NOT NULL,
  expires_at    TEXT NOT NULL,
  user_agent    TEXT
);
CREATE INDEX idx_sessions_user ON sessions(user_id);
CREATE INDEX idx_sessions_expires ON sessions(expires_at);

CREATE TABLE topics (
  id           INTEGER PRIMARY KEY AUTOINCREMENT,
  show_id      TEXT NOT NULL UNIQUE,
  title        TEXT NOT NULL,
  note_count   INTEGER NOT NULL DEFAULT 0,
  last_note_at TEXT,
  created_at   TEXT NOT NULL
);

CREATE TABLE notes (
  id         INTEGER PRIMARY KEY AUTOINCREMENT,
  topic_id   INTEGER NOT NULL REFERENCES topics(id),
  reply_no   INTEGER NOT NULL,
  user_id    TEXT REFERENCES users(id) ON DELETE SET NULL,
  handle     TEXT,
  body       TEXT NOT NULL,
  created_at TEXT NOT NULL,
  edited_at  TEXT,
  deleted_at TEXT,
  deleted_by TEXT,
  UNIQUE (topic_id, reply_no)
);
CREATE INDEX idx_notes_user ON notes(user_id, created_at);

CREATE TABLE shelves (
  id         TEXT PRIMARY KEY,
  user_id    TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  name       TEXT NOT NULL,
  blurb      TEXT NOT NULL DEFAULT '',
  icon_name  TEXT NOT NULL DEFAULT 'sparkles',
  is_private INTEGER NOT NULL DEFAULT 0,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  deleted_at TEXT,
  seq        INTEGER NOT NULL
);
CREATE INDEX idx_shelves_user_seq ON shelves(user_id, seq);

CREATE TABLE shelf_items (
  id              TEXT PRIMARY KEY,
  shelf_id        TEXT NOT NULL REFERENCES shelves(id) ON DELETE CASCADE,
  user_id         TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  show_identifier TEXT NOT NULL,
  show_id         TEXT,
  show_date       TEXT,
  display_name    TEXT NOT NULL,
  sort_index      INTEGER NOT NULL,
  added_at        TEXT NOT NULL,
  updated_at      TEXT NOT NULL,
  deleted_at      TEXT,
  seq             INTEGER NOT NULL
);
CREATE INDEX idx_shelf_items_shelf ON shelf_items(shelf_id, sort_index);
CREATE INDEX idx_shelf_items_added ON shelf_items(shelf_id, added_at);
CREATE INDEX idx_shelf_items_user_seq ON shelf_items(user_id, seq);

CREATE TABLE mixtapes (
  id         TEXT PRIMARY KEY,
  user_id    TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  name       TEXT NOT NULL,
  blurb      TEXT NOT NULL DEFAULT '',
  icon_name  TEXT NOT NULL DEFAULT 'music.note.list',
  is_private INTEGER NOT NULL DEFAULT 0,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  deleted_at TEXT,
  seq        INTEGER NOT NULL
);
CREATE INDEX idx_mixtapes_user_seq ON mixtapes(user_id, seq);

CREATE TABLE mixtape_items (
  id                TEXT PRIMARY KEY,
  mixtape_id        TEXT NOT NULL REFERENCES mixtapes(id) ON DELETE CASCADE,
  user_id           TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  show_identifier   TEXT NOT NULL,
  file_name         TEXT NOT NULL,
  track_title       TEXT NOT NULL,
  song_key          TEXT NOT NULL DEFAULT '',
  show_date_string  TEXT NOT NULL DEFAULT '',
  show_display_name TEXT NOT NULL DEFAULT '',
  duration_seconds  REAL NOT NULL DEFAULT 0,
  sort_index        INTEGER NOT NULL,
  added_at          TEXT NOT NULL,
  updated_at        TEXT NOT NULL,
  deleted_at        TEXT,
  seq               INTEGER NOT NULL
);
CREATE INDEX idx_mixtape_items_tape ON mixtape_items(mixtape_id, sort_index);
CREATE INDEX idx_mixtape_items_added ON mixtape_items(mixtape_id, added_at);
CREATE INDEX idx_mixtape_items_user_seq ON mixtape_items(user_id, seq);

CREATE TABLE journal_entries (
  id                TEXT PRIMARY KEY,
  user_id           TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  show_identifier   TEXT NOT NULL,
  show_id           TEXT,
  show_date         TEXT,
  show_display_name TEXT NOT NULL DEFAULT '',
  body              TEXT NOT NULL,
  mood              TEXT,
  created_at        TEXT NOT NULL,
  updated_at        TEXT NOT NULL,
  deleted_at        TEXT,
  seq               INTEGER NOT NULL
);
CREATE INDEX idx_journal_user_seq ON journal_entries(user_id, seq);
CREATE INDEX idx_journal_user_show ON journal_entries(user_id, show_id);

CREATE TABLE trees (
  id         TEXT PRIMARY KEY,
  owner_id   TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  kind       TEXT NOT NULL,
  source_id  TEXT NOT NULL,
  created_at TEXT NOT NULL,
  deleted_at TEXT,
  UNIQUE (kind, source_id)
);
CREATE TABLE tree_members (
  tree_id   TEXT NOT NULL REFERENCES trees(id) ON DELETE CASCADE,
  user_id   TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  joined_at TEXT NOT NULL,
  PRIMARY KEY (tree_id, user_id)
);
CREATE INDEX idx_tree_members_user ON tree_members(user_id);

CREATE TABLE spins (
  id          INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id     TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  handle      TEXT NOT NULL,
  show_id     TEXT,
  identifier  TEXT NOT NULL,
  track_title TEXT NOT NULL,
  started_at  TEXT NOT NULL,
  updated_at  TEXT NOT NULL
);
CREATE INDEX idx_spins_updated ON spins(updated_at);
CREATE INDEX idx_spins_user ON spins(user_id, updated_at);
