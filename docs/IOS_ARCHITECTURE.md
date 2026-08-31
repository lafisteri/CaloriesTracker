# iOS architecture

**Статус:** актуальная техническая архитектура

**Обновлено:** 2026-08-31
**Граница документа:** нативное Swift/SwiftUI-приложение. Пользовательское
поведение описано в PRODUCT_SPEC.md.

## 1. Обзор

CaloriesTracker — local-first приложение. SwiftData является рабочим source of
truth, а Supabase — необязательная инфраструктура backup/restore. Обычная
работа с дневником никогда не ждёт сеть, авторизацию или синхронизацию.

Основной путь зависимостей:

    SwiftUI View
      -> ViewModel / feature state
      -> Application Service
      -> Domain values and calculators
      -> Repository protocol
      -> SwiftData Repository
      -> SwiftData records / ModelContainer

- **Views** рендерят состояние, передают пользовательский intent и не получают
  SwiftData records напрямую.
- **View models и feature state** владеют transient form, loading/error state и
  защищают публикацию асинхронных результатов.
- **Application services** координируют validation, разрешение версий,
  расчёты, snapshot, сортировку и сохранение.
- **Domain** содержит value types, LocalDay, перечисления, calculators и
  repository protocols. Он не зависит от SwiftUI или SwiftData.
- **Data** содержит SwiftData models, mappers, repositories, миграции и
  sync-инфраструктуру. Persistent models не пересекают границу repository.

## 2. Composition root и навигация

AppDependencies — единственный composition root. Он создаёт один
ModelContainer на схеме V5, SwiftData repositories, application services и,
только при наличии конфигурации Supabase, auth, transport и sync-компоненты.
Зависимости передаются в feature roots, а не создаются во Views.

AppRouter хранит выбранную вкладку и typed paths:

- todayPath для TodayRoute;
- catalogPath для CatalogRoute;
- короткоживущие intents для возврата из Product Editor обратно в Amount.

Today и Catalog имеют собственные NavigationStack. Statistics изолирован в
своём корневом stack. Смена вкладки сбрасывает только дочернюю навигацию Today;
данные выбранного LocalDay остаются в state TodayViewModel.

## 3. Domain invariants

### LocalDay

LocalDay — гражданская дата Gregorian calendar в форме YYYY-MM-DD, не UTC
timestamp. Сравнение, выбор целей, дневник и недельная статистика работают с
этим ключом. Date для отображения строится в локальный полдень и не
сохраняется как идентичность дня.

### Product и ProductVersion

Product — логическая сущность с постоянным UUID, logical metadata, указателем
на current version и business timestamps. Удаление soft: сохраняется
deletedAt.

ProductVersion неизменяем. Начальная версия имеет номер 1 и не имеет base;
следующая принадлежит тому же Product, ссылается на предшествующую и имеет
строго следующий номер. Unit, base amount и nutrition принадлежат версии.
Изменение только logical metadata не создаёт версию; изменение versioned
значений создаёт новую.

### Recipe, RecipeVersion и RecipeIngredient

Recipe устроен аналогично Product: logical metadata, current version,
createdAt/updatedAt и soft delete.

RecipeVersion неизменяем и имеет ту же последовательную lineage-семантику.
Она содержит total nutrition, optional cookedWeight, optional servingsCount и
упорядоченный состав. RecipeIngredient — дочерняя immutable позиция с
позицией в списке и exact ProductVersion. В системе не существует вложенной
ссылки recipe-to-recipe: выбор рецепта для состава разворачивается в его
закреплённые product ingredients.

### DiaryEntry

DiaryEntry сохраняет nutrition snapshot, source name, source version, amount и
unit на момент сохранения. Позднее изменение источника не пересчитывает
исторические записи автоматически.

Постоянная идентичность записи включает id, LocalDay, sourceType, sourceID и
createdAt. Meal, sort order, amount, unit, nutrition snapshot, updatedAt и
tombstone изменяемы. sourceVersionID и sourceName могут измениться только
явным contextual rebase существующей product-записи, после проверки
принадлежности новой версии тому же Product.

### WeeklyGoal

WeeklyGoal — aggregate из effectiveFrom и семи DailyMacroGoal. Его логическая
и sync-идентичность — детерминированный UUIDv5 от effectiveFrom с фиксированным
namespace; она не зависит от устройства, locale или часового пояса.

effectiveFrom задаёт историческую применимость. Сохранение в тот же день
обновляет существующий aggregate, сохраняет id и createdAt, заменяет все семь
дневных значений и меняет updatedAt. Новый effectiveFrom создаёт новый
aggregate. Goals не имеют soft delete. UI отсекает no-op save до repository.

## 4. Persistence

### SwiftData source of truth

Production ModelContainer локальный: CloudKit mirroring выключен. Текущая
версионированная схема — V5 и содержит:

- ProductRecord, ProductVersionRecord;
- RecipeRecord, RecipeVersionRecord, RecipeIngredientRecord;
- DiaryEntryRecord;
- WeeklyGoalRecord и DailyMacroGoalRecord;
- SyncOutboxRecord, SyncRemoteStateRecord, SyncPullStateRecord,
  SyncBootstrapStateRecord.

Product, Recipe и DiaryEntry используют retained soft deletes. Внешнее
удаление не удаляет версии и snapshots, нужные для истории и синхронизации.

### Transaction boundaries

SwiftData repositories владеют текущей persistence isolation и своим
MainActor ModelContext. Локальная mutation сохраняет изменённые domain records
и соответствующий outbox marker одним ModelContext.save(). При ошибке context
откатывается.

Application services собирают доменную операцию до вызова repository: например,
рассчитывают nutrition snapshot, следующую version или нормализованный порядок.
Repository не публикует partial domain state. Remote apply получает context от
Pull coordinator, чтобы локальная merge, metadata и outbox effects также были
зафиксированы одной транзакцией.

### Миграции

Migration plan содержит V1–V5 и четыре lightweight stages. V2 добавила outbox,
V3 — account-scoped remote revision и pull cursor, V4 — bootstrap marker, V5
добавила updatedAt к WeeklyGoal persistence model. Обычная миграция не
backfill-ит существующие доменные записи в outbox.

Перед следующей structural migration historical schemas Product/Recipe/Diary
records нужно отдельно пересмотреть и зафиксировать. Это планируемое
ограничение миграционной стратегии, а не текущий defect.

## 5. Sync architecture

### Роль и граница

SwiftData остаётся активным local source of truth. Supabase хранит canonical
payloads для backup/restore и не участвует в UI live sync между устройствами.
Нет CloudKit sync, Realtime subscription, silent push, BGTaskScheduler или
background fetch.

SupabaseAuthService предоставляет passwordless email OTP и восстановление
сессии. SupabaseSyncTransport — actor с сетевыми запросами без SwiftData
mutation: upload выполняется через RLS-protected push_sync_record RPC, pull
читает sync_records по возрастанию server_revision. Transport проверяет
expected account до и после каждого запроса.

### Identity и canonical payload

Каждая переносимая сущность имеет SyncEntityKey из entity type и UUID. Ровно
шесть top-level entity types участвуют в sync:

- product и productVersion;
- recipe и recipeVersion;
- diaryEntry;
- weeklyGoal.

RecipeVersion содержит упорядоченные закреплённые ингредиенты внутри payload,
WeeklyGoal — семь дневных целей. Operational metadata не входит в payload.
Все domain Date на sync-границе нормализуются до canonical Unix milliseconds;
wire dates кодируются из этой величины. LocalDay остаётся civil-date value.

Remote payload — недоверенный input. Перед insertion или mutation local store
валидирует schema version, UUID и owner identity, конечность значений, unit,
lineage immutable versions, pins ингредиентов, derived recipe totals и
dependencies. Неизменяемая версия с тем же UUID должна иметь идентичное
canonical content; иначе это invariant violation.

Mutable Product, Recipe, DiaryEntry и WeeklyGoal используют deterministic
whole-record last-writer-wins по canonical updatedAt. Tombstone побеждает
активное состояние. При равном timestamp canonical sorted-key JSON payload
даёт детерминированный tie-break. Missing ProductVersion, RecipeVersion или
source version откладывает remote record, не создавая placeholder.

### SyncOutbox и Push

SyncOutbox создаётся явно на local repository mutation и coalesces изменения
по stable entity key: более позднее изменение заменяет token и время очереди,
а не добавляет вторую запись.

SyncPushCoordinator читает стабильный snapshot pending outbox в порядке
enqueuedAt, key, экспортирует canonical payload и передаёт последнюю известную
remote revision как optimistic-concurrency expectation. За один запуск
обрабатывается ограниченный batch до 50 элементов.

После accepted ответа coordinator в одной транзакции сохраняет account-scoped
remote revision и подтверждает outbox item только по **точному** token
отправленного snapshot. Если пользователь изменил сущность во время network
await, новый token остаётся pending. Conflict или missing remote record не
подтверждают item и обрабатываются normal Pull path.

### Pull

SyncPullCoordinator хранит cursor отдельно для каждого account и запрашивает
страницы до 200 remote records, с ограничением пяти страниц и 1 000 records на
один run. server_revision монотонно возрастает; пропуски корректны, потому что
sync_records — latest-snapshot table, а не append-only log.

Coordinator может временно смотреть дальше persistent cursor, чтобы получить
dependency. Cursor продвигается только до безопасной позиции перед первой
необработанной, invalid или deferred записью. Merge результата, remote revision
для key, cursor, нужные republish outbox effects и acknowledgement stale
token выполняются одной save-транзакцией.

Повторный Pull идемпотентен. Local-wins сохраняет local value, фиксирует
увиденную remote revision и ставит explicit republish без вращения уже
ожидающего token. Dependency deferral, corruption или validation failure не
пропускаются курсором.

### Bootstrap

SyncBootstrapCoordinator запускается для account без completed marker. Он
сначала тянет cloud state до безопасного завершения, затем сканирует локальные
top-level identities в dependency-friendly порядке и seed-ит только те, для
которых account не знает remote revision. Существующие outbox tokens
сохраняются.

Bootstrap повторяет Pull -> Push -> Pull ограниченное число раз, максимум
десять rounds. Он завершён только после caught-up Pull без blockers,
отсутствия pending outbox и известной remote revision у каждой локальной
top-level identity. Marker сохраняется per account; незавершённый run безопасно
продолжается после перезапуска.

До репликации local store нормализует legacy WeeklyGoal UUID к canonical UUIDv5
для effectiveFrom. Это idempotent data normalization, а не новая SwiftData
schema migration.

### Orchestrator и lifecycle

SyncOrchestrator actor — единственная точка планирования. Он получает wake от:

- active scene phase;
- доступной или восстановленной auth session;
- committed local mutation через post-commit SyncChangeNotifier;
- ручного «Синхронизировать сейчас»;
- foreground periodic refresh раз в 60 секунд.

Local changes debounce-ятся 1,8 секунды. Пока приложение активно,
orchestrator выполняет bootstrap при необходимости, затем ограниченные циклы
Pull -> Push -> Pull. В одном wake допускается до трёх convergence cycles;
здоровая оставшаяся работа планирует coalesced continuation, а не бесконечный
busy loop. Transient network/server failures используют ограниченную retry
последовательность 2, 5, 15, 30 и 60 секунд.

Запуск single-flight: wake во время run лишь помечает последующий run. При
inactive/background отменяются scheduled debounce, retry и periodic tasks. Для
каждой sync-фазы run закреплён за account UUID и account generation. Sign out
или вход под другим account отменяет старую работу до её merge, cursor advance
или acknowledgement.

Account-scoped metadata, remote revisions, pull cursors и bootstrap markers
изолированы по account. Sign out сохраняет local data, outbox и metadata;
другой account получает своё sync namespace.

## 6. Concurrency и жизненный цикл feature state

View models, services и SwiftData repositories используют current MainActor
persistence/UI isolation. Это позволяет синхронно сформировать и сохранить
одну локальную domain mutation, не блокируя network work: SyncOrchestrator и
Supabase transport изолированы actor-ами.

Архитектурно значимые guards:

- Today, Statistics, Catalog lists и Recipe detail публикуют результат только
  последнего request, чтобы поздняя загрузка не заменила новое состояние.
- Amount, Product Editor, Recipe Editor и Goal Editor блокируют второе
  in-flight сохранение.
- SyncOrchestrator single-flight и exact-token outbox acknowledgement не дают
  устаревшему network result удалить более свежую локальную работу.

## 7. Deferred engineering decisions

- Перенести storage isolation на ModelActor только если измеренная
  производительность этого потребует.
- Выполнить Swift 6 strict-concurrency migration отдельной совместимой работой.
- Перед следующей structural migration полностью зафиксировать historical
  SwiftData schemas.
- Добавить live UI refresh после Pull, если появится реальный
  multi-device сценарий.
- Спроектировать server-reset/cloud-recovery UX, если это станет операционно
  необходимо.
