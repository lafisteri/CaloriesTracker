import { fireEvent, render, screen } from '@testing-library/react'
import { afterEach, beforeEach, describe, expect, it } from 'vitest'

import { App } from './app'

describe('App navigation', () => {
  beforeEach(() => {
    window.history.pushState({}, '', '/today')
  })

  afterEach(() => {
    window.history.pushState({}, '', '/')
  })

  it('opens every foundation page from bottom navigation', () => {
    render(<App />)

    expect(screen.getByRole('heading', { name: 'Сегодня' })).toBeInTheDocument()

    fireEvent.click(screen.getByRole('link', { name: 'Дневник' }))
    expect(screen.getByRole('heading', { name: 'Дневник' })).toBeInTheDocument()

    fireEvent.click(screen.getByRole('link', { name: 'Продукты' }))
    expect(screen.getByRole('heading', { name: 'Продукты' })).toBeInTheDocument()

    fireEvent.click(screen.getByRole('link', { name: 'Цели' }))
    expect(screen.getByRole('heading', { name: 'Цели' })).toBeInTheDocument()
  })
})
