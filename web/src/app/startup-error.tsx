export function StartupError() {
  return (
    <main className="startup-error">
      <section className="startup-error__card" aria-labelledby="startup-error-title">
        <h1 id="startup-error-title">Не удалось открыть хранилище</h1>
        <p>Разрешите браузеру сохранять данные на устройстве и перезапустите приложение.</p>
      </section>
    </main>
  )
}
