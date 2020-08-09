BEGIN;

ALTER TABLE chat_history ADD COLUMN master_id INT;
ALTER TABLE chat_history ADD COLUMN correction_stanza_id TEXT;
ALTER TABLE chat_history ADD COLUMN correction_timestamp INTEGER;

COMMIT;

PRAGMA user_version = 11;
