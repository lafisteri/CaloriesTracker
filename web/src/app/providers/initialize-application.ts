import { initializeRepositories } from '@/data/repositories'

/** Opens local repository infrastructure before the React UI is mounted. */
export async function initializeApplication(): Promise<void> {
  await initializeRepositories()
}
