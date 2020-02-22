BEGIN;

ALTER TABLE roster_items ADD COLUMN annotations TEXT;

COMMIT;

PRAGMA user_version = 9;
