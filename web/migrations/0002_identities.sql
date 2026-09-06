-- Sign in with Apple: an Apple ID (its stable `sub`) mapped to a head. A head
-- can have a passkey, an Apple identity, or both; the row goes with the head.
CREATE TABLE identities (
  provider   TEXT NOT NULL,
  subject    TEXT NOT NULL,
  user_id    TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  created_at TEXT NOT NULL,
  PRIMARY KEY (provider, subject)
);
CREATE INDEX idx_identities_user ON identities(user_id);
