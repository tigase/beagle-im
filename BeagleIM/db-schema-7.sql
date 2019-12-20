BEGIN;

ALTER TABLE chat_history ADD COLUMN appendix TEXT;

COMMIT;

PRAGMA user_version = 7;

