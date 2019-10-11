BEGIN;

ALTER TABLE chats ADD COLUMN message_draft TEXT;

COMMIT;

PRAGMA user_version = 6;
