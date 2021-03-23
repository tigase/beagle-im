CREATE TABLE IF NOT EXISTS chat_markers (
    account TEXT NOT NULL COLLATE NOCASE,
    jid TEXT NOT NULL COLLATE NOCASE,
    sender_nick TEXT NOT NULL,
    sender_id TEXT NOT NULL,
    sender_jid TEXT NOT NULL,
    timestamp INTEGER NOT NULL,
    type INTEGER NOT NULL
);

CREATE UNIQUE INDEX IF NOT EXISTS chat_markers_key on chat_markers (
    account, jid, sender_nick, sender_id, sender_jid
);
