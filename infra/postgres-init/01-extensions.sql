-- Enable PostGIS and helpers on first DB init.
-- The postgis/postgis image includes the extension binaries; we just activate them.
CREATE EXTENSION IF NOT EXISTS postgis;
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS pgcrypto;
