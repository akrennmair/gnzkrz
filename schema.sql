CREATE TABLE gnzkrz_urls (
	id INTEGER PRIMARY KEY NOT NULL AUTO_INCREMENT,
	url VARCHAR(1024),
	remote_addr VARCHAR(64),
	created DATETIME,
	access_count INTEGER,
	enabled INTEGER(1)
);

CREATE INDEX gnzkrz_idx_url ON gnzkrz_urls (url);
CREATE INDEX gnzkrz_idx_enabled ON gnzkrz_urls (enabled);
