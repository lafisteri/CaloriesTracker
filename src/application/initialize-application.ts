import { initializeRepositories } from '@/data/repositories'

/** Starts repository infrastructure before the UI is mounted. */
export async function initializeApplication(): Promise<void> {
  await initializeRepositories()
}
