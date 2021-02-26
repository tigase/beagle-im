CREATE VIRTUAL TABLE IF NOT EXISTS chat_history_fts_index USING FTS5(data, content=chat_history, content_rowid=id);

INSERT INTO chat_history_fts_index(rowid, data) SELECT id, data FROM chat_history;

CREATE TRIGGER chat_history_ai AFTER INSERT ON chat_history BEGIN
    INSERT INTO chat_history_fts_index(rowid, data) VALUES (new.id, new.data);
END;

CREATE TRIGGER chat_history_ad AFTER DELETE ON chat_history BEGIN
    INSERT INTO chat_history_fts_index(chat_history_fts_index, rowid, data) VALUES('delete', old.id, old.data);
END;

CREATE TRIGGER chat_history_au AFTER UPDATE OF id, data ON chat_history BEGIN
    INSERT INTO chat_history_fts_index(chat_history_fts_index, rowid, data) VALUES('delete', old.id, old.data);
    INSERT INTO chat_history_fts_index(rowid, data) VALUES (new.id, new.data);
END;
