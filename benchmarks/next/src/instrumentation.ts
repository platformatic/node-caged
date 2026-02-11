import { db } from './lib/db'

export async function register() {
  // Pre-initialize database to avoid file reads during request handling
  await db.initialize()
}
