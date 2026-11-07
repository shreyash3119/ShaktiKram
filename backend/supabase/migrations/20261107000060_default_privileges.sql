-- Stage 2 / hardening: PostgreSQL gives PUBLIC execute on every new function. A schema-level "revoke from public" cannot remove
-- that built-in default, so the Stage 1 default-deny only covered functions that existed when migration 800 ran.
-- This sets the global default for functions created by the migration role. Grant execute explicitly where a client needs it.
alter default privileges revoke execute on functions from public;
alter default privileges in schema public revoke execute on functions from anon, authenticated;
