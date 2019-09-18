BEGIN;

ALTER TABLE chats ADD COLUMN options TEXT;

COMMIT;

PRAGMA user_version = 5;
