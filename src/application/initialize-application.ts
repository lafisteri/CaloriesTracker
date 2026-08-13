import { initializeLocalDatabase } from '@/data/database/calorie-database'

/** Starts infrastructure before the UI is mounted. */
export async function initializeApplication(): Promise<void> {
  await initializeLocalDatabase()
}
