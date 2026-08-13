interface PlaceholderPageProps {
  title: string
  description: string
}

/** Temporary page boundary used while feature workflows are introduced in later phases. */
export function PlaceholderPage({ title, description }: PlaceholderPageProps) {
  return (
    <section className="placeholder-page" aria-labelledby="page-title">
      <h1 id="page-title">{title}</h1>
      <p>{description}</p>
    </section>
  )
}
