BEGIN;

CREATE TABLE IF NOT EXISTS chats (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    account TEXT NOT NULL COLLATE NOCASE,
    jid TEXT NOT NULL COLLATE NOCASE,
    type INTEGER NOT NULL,
    timestamp INTEGER NOT NULL,
    nickname TEXT,
    password TEXT
);

CREATE INDEX IF NOT EXISTS chat_jid_idx on chats (
    jid, account
);

CREATE TABLE IF NOT EXISTS chat_history (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    account TEXT NOT NULL COLLATE NOCASE,
    jid TEXT NOT NULL COLLATE NOCASE,
    author_jid TEXT,
    author_nickname TEXT,
    timestamp INTEGER NOT NULL,
    item_type INTEGER NOT NULL,
    data TEXT,
    stanza_id TEXT,
    state INTEGER,
    preview TEXT,
    error TEXT
);

CREATE INDEX IF NOT EXISTS chat_history_account_jid_timestamp_idx on chat_history (
    account, jid, timestamp
);

CREATE INDEX IF NOT EXISTS chat_history_account_jid_state_idx on chat_history (
    account, jid, state
);

CREATE TABLE IF NOT EXISTS roster_items (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    account TEXT NOT NULL COLLATE NOCASE,
    jid TEXT NOT NULL COLLATE NOCASE,
    name TEXT,
    subscription TEXT,
    timestamp INTEGER,
    ask INTEGER
);

CREATE TABLE IF NOT EXISTS roster_groups (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT
);

CREATE TABLE IF NOT EXISTS roster_items_groups (
    item_id INTEGER NOT NULL,
    group_id INTEGER NOT NULL,
    FOREIGN KEY(item_id) REFERENCES roster_items(id),
    FOREIGN KEY(group_id) REFERENCES roster_groups(id)
);

CREATE INDEX IF NOT EXISTS roster_item_account_idx on roster_items (
    account
);

CREATE INDEX IF NOT EXISTS roster_item_groups_item_id_idx ON roster_items_groups (item_id);
CREATE INDEX IF NOT EXISTS roster_item_groups_group_id_idx ON roster_items_groups (group_id);

CREATE TABLE IF NOT EXISTS vcards_cache (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    jid TEXT NOT NULL COLLATE NOCASE,
    data TEXT,
    timestamp INTEGER
);

CREATE INDEX IF NOT EXISTS vcards_cache_jid_idx on vcards_cache (
    jid
);

CREATE TABLE IF NOT EXISTS avatars_cache (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    jid TEXT NOT NULL COLLATE NOCASE,
    account TEXT NOT NULL COLLATE NOCASE,
    hash TEXT NOT NULL,
    type TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS avatars_cache_account_jid_idx on avatars_cache (
    account, jid
);

CREATE TABLE IF NOT EXISTS caps_features (
    node TEXT NOT NULL,
    feature TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS caps_features_node_idx on caps_features (
    node
);

CREATE INDEX IF NOT EXISTS caps_features_feature_idx on caps_features (
    feature
);

CREATE TABLE IF NOT EXISTS caps_identities (
    node TEXT NOT NULL,
    name TEXT,
    type TEXT,
    category TEXT
);

CREATE INDEX IF NOT EXISTS caps_indentities_node_idx on caps_identities (
    node
);

COMMIT;

PRAGMA user_version = 1;
