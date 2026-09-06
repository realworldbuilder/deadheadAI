/** Small D1 helpers: one query, one row, or a batch, with typed rows. */
export async function q<T = Record<string, unknown>>(
  db: D1Database, sql: string, ...binds: unknown[]
): Promise<T[]> {
  const { results } = await db.prepare(sql).bind(...binds).all<T>();
  return results;
}

export async function one<T = Record<string, unknown>>(
  db: D1Database, sql: string, ...binds: unknown[]
): Promise<T | null> {
  const row = await db.prepare(sql).bind(...binds).first<T>();
  return row ?? null;
}

export function stmt(db: D1Database, sql: string, ...binds: unknown[]): D1PreparedStatement {
  return db.prepare(sql).bind(...binds);
}
