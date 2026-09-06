/** Every test file starts with the notes schema applied and the 12-show catalog fixture loaded. */
import { applyD1Migrations, env } from "cloudflare:test";
import tables from "./fixtures/catalog.tables.sql?raw";
import fts from "./fixtures/catalog.fts.sql?raw";

await applyD1Migrations(env.NOTES, env.TEST_MIGRATIONS);
await env.CATALOG.exec(tables);
await env.CATALOG.exec(fts);
