import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'
import { registerSW } from 'virtual:pwa-register'

import { App } from '@/app/app'
import { initializeApplication } from '@/app/providers/initialize-application'
import { StartupError } from '@/app/startup-error'
import '@/app/styles.css'

async function mountApplication(): Promise<void> {
  const rootElement = document.getElementById('root')

  if (rootElement === null) {
    throw new Error('Application root element is missing.')
  }

  const root = createRoot(rootElement)

  try {
    await initializeApplication()
    root.render(
      <StrictMode>
        <App />
      </StrictMode>,
    )
  } catch (error) {
    console.error('Failed to initialize the local database.', error)
    root.render(
      <StrictMode>
        <StartupError />
      </StrictMode>,
    )
  }
}

void mountApplication()

registerSW({
  immediate: true,
  onRegisterError(error) {
    console.error('Failed to register the service worker.', error)
  },
})
