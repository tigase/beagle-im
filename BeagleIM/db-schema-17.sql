CREATE TABLE IF NOT EXISTS accounts (
    name TEXT NOT NULL COLLATE NOCASE,
    enabled INTEGER NOT NULL,
    server_endpoint TEXT,
    roster_version TEXT,
    status_message TEXT,
    last_endpoint TEXT,
    -- omemo id, accepted ssl certificate, nickname, disable TLS 1.3, known server features
    additional TEXT
);

CREATE UNIQUE INDEX IF NOT EXISTS accounts_name_key on accounts ( name );
