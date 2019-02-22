BEGIN;

ALTER TABLE chats ADD COLUMN name TEXT;

COMMIT;

PRAGMA user_version = 2;

