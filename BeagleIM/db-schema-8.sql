
BEGIN;

ALTER TABLE chat_history ADD COLUMN recipient_nickname TEXT;

COMMIT;

PRAGMA user_version = 8;

