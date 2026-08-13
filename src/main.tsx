import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'
import { registerSW } from 'virtual:pwa-register'

import { initializeApplication } from '@/application/initialize-application'
import { App } from '@/app/app'
import '@/app/styles.css'

void initializeApplication().then(() => {
  createRoot(document.getElementById('root')!).render(
    <StrictMode>
      <App />
    </StrictMode>,
  )
})

registerSW({ immediate: true })
