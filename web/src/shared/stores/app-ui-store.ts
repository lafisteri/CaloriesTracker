import { create } from 'zustand'

interface AppUiState {
  isBottomNavigationVisible: boolean
  setBottomNavigationVisible: (isVisible: boolean) => void
}

/** UI-only state. Persisted nutrition data is kept in IndexedDB instead. */
export const useAppUiStore = create<AppUiState>((set) => ({
  isBottomNavigationVisible: true,
  setBottomNavigationVisible: (isBottomNavigationVisible) => set({ isBottomNavigationVisible }),
}))
