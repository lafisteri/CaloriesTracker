import type { ComponentPropsWithoutRef } from 'react'
import { Link, type LinkProps } from 'react-router-dom'

type BackLinkProps = Omit<LinkProps, 'aria-label' | 'children' | 'className'> & {
  className?: string
}

type BackButtonProps = Omit<ComponentPropsWithoutRef<'button'>, 'aria-label' | 'children' | 'className' | 'type'> & {
  className?: string
}

const backLinkText = '< < <'

/** Shared visual treatment for navigation back-links while preserving their destination. */
export function BackLink({ className, ...props }: BackLinkProps) {
  return <Link {...props} className={getBackLinkClassName(className)} aria-label="Назад">{backLinkText}</Link>
}

/** Shared visual treatment for navigation back-buttons while preserving their handler. */
export function BackButton({ className, ...props }: BackButtonProps) {
  return <button {...props} className={getBackLinkClassName(className)} type="button" aria-label="Назад">{backLinkText}</button>
}

function getBackLinkClassName(className: string | undefined): string {
  return className === undefined ? 'back-link' : `back-link ${className}`
}
