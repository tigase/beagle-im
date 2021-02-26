CREATE TABLE IF NOT EXISTS chat_history_sync (
    id TEXT NOT NULL COLLATE NOCASE,
    account TEXT NOT NULL COLLATE NOCASE,
    component TEXT COLLATE NOCASE,
    from_timestamp INTEGER NOT NULL,
    from_id TEXT,
    to_timestamp INTEGER NOT NULL
);
