CREATE TABLE IF NOT EXISTS omemo_sessions (
    account TEXT NOT NULL COLLATE NOCASE,
    name TEXT NOT NULL,
    device_id INTEGER NOT NULL,
    key TEXT NOT NULL,

    UNIQUE (account, name, device_id) ON CONFLICT REPLACE
);

CREATE TABLE IF NOT EXISTS omemo_identities (
    account TEXT NOT NULL COLLATE NOCASE,
    name TEXT NOT NULL,
    device_id INTEGER NOT NULL,
    fingerprint TEXT NOT NULL,
    key BLOB NOT NULL,
    own INTEGER NOT NULL,
    status INTEGER NOT NULL,

    UNIQUE (account, name, fingerprint) ON CONFLICT IGNORE
);

CREATE TABLE IF NOT EXISTS omemo_pre_keys (
    account TEXT NOT NULL COLLATE NOCASE,
    id INTEGER NOT NULL,
    key BLOB NOT NULL,

    UNIQUE (account, id) ON CONFLICT REPLACE
);

CREATE TABLE IF NOT EXISTS omemo_signed_pre_keys (
    account TEXT NOT NULL COLLATE NOCASE,
    id INTEGER NOT NULL,
    key BLOB NOT NULL,

    UNIQUE (account, id) ON CONFLICT REPLACE
);


ALTER TABLE chats ADD COLUMN encryption TEXT;
ALTER TABLE chat_history ADD COLUMN encryption int;
ALTER TABLE chat_history ADD COLUMN fingerprint text;
