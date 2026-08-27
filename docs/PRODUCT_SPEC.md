# PRODUCT_SPEC

**Status:** Current native iOS product specification
**Last updated:** 2026-08-26

This document describes accepted user-visible behaviour of the native iOS
application. `IOS_ARCHITECTURE.md` describes implementation constraints; older
web/PWA documents and historical prompts are not a source of current behaviour.

## 1. Product overview

КБЖУ — personal, local-first iOS-приложение для учёта калорий, белков, жиров и
углеводов. Пользователь самостоятельно ведёт базу продуктов и рецептов;
внешняя база питания, аккаунт и синхронизация не требуются для текущего
сценария.

Основной ежедневный сценарий:

```text
Открыть приложение
→ Сегодня
→ Добавить
→ выбрать Product или Recipe
→ указать количество
→ сохранить
```

## 2. Product principles

- Нативный, local-first интерфейс для iPhone.
- Собственная управляемая пользователем база продуктов и рецептов.
- The app remains fully usable offline. Synchronization must not block adding
  or editing local data.
- Минимум действий в ежедневном food-logging flow.
- Версионирование пищевой ценности и состава.
- Исторические записи не изменяются незаметно.
- Спокойный интерфейс без геймификации и лишних функций.

## 3. Navigation and information architecture

Нижняя навигация содержит три раздела:

```text
Статистика
Сегодня
Продукты
```

При запуске открывается **Сегодня**. Goals открываются через **«Сегодня →
Настройки → Цели»**, а не отдельной вкладкой. Внутренние переходы являются нативными
экранами, а не URL-маршрутами.

У **Сегодня** есть специальное правило: если пользователь уходит с вкладки с
открытым дочерним flow (выбор еды, Amount, редактор и т. п.), при возвращении
он видит корневой экран Today. Выбранная `LocalDay` при этом остаётся выбранной;
сбрасывается только transient-навигация.

## 4. Today and diary

**Сегодня** — дневник выбранного локального календарного дня. Пользователь
может перейти на прошлый или будущий день и вернуться к сегодняшнему.
Данные на экране всегда относятся к выбранному `LocalDay`: завершившаяся позже
загрузка предыдущего дня не может заменить данные уже выбранного нового дня.

Дневник содержит:

- навигацию по датам;
- компактную сводку **«За день»**: calories, цель calories при наличии и Б/Ж/У;
- четыре секции: Завтрак, Обед, Ужин и Перекусы;
- итог calories каждого приёма пищи;
- записи дневника и действие **«Добавить»** в каждой секции.

Пустой приём пищи остаётся компактным: он содержит действие добавления, но не
показывает технический текст для drop target. Отдельная глобальная empty-state
плашка для пустого дня не нужна.

Каждая строка `DiaryEntry` показывает только:

```text
source name
amount + unit
calories
```

Белки, жиры и углеводы остаются в дневной сводке, статистике и сохранённом
nutrition snapshot, но не повторяются в строке.

### Interactions with a DiaryEntry

```text
tap                  → открыть Amount/Edit записи
swipe справа налево  → показать destructive action с корзиной
long press + drag    → изменить порядок или перенести в другой meal
vertical swipe       → прокрутить список
```

Tap открывает Amount/Edit с фактическими сохранёнными amount и unit. В этом
режиме можно менять только amount и unit; дата и meal остаются прежними.

Удаление требует явного tap по показанной корзине, выполняется без отдельного
подтверждения и не удаляет Product, Recipe или историю версий. После него
обновляются totals дня и meal.

Drag & drop не требует Edit mode, drag handles или меню перемещения. Оно
поддерживает reorder внутри meal, перенос между meal того же дня, пустой meal и
конкретную позицию вставки. Простое касание не должно начинать drag и не должно
скрывать строку; во время drag не должно быть двух полноценных копий строки.

## 5. Food selection and Amount flow

Основной flow добавления еды в дневник:

```text
Today
→ Добавить в нужном meal
→ Catalog in selection context
→ Product или Recipe
→ Amount
→ Добавить
→ Today
```

Контекст даты и meal сохраняется на всём flow. После успешного добавления
завершённые Catalog и Amount не должны снова появляться по Back.

### Shared Catalog

Один Catalog с сегментами **Продукты** и **Рецепты**, поиском и созданием
источника используется в трёх контекстах:

| Контекст | Tap по полной строке | `+` |
| --- | --- | --- |
| Управление из вкладки «Продукты» | Открывает details | Не показывается |
| Выбор для Today | Открывает Amount для DiaryEntry | Быстро добавляет запись в выбранный meal |
| Выбор ингредиента Recipe | Открывает Amount для ingredient draft | Быстро добавляет ingredient draft |

В selection context полная строка и `+` имеют разные действия. Quick-add
добавляет источник без дополнительного Amount-экрана; пока операция идёт, в
одном selection flow нельзя запустить вторую quick-add операцию.

Создание Product или Recipe из Catalog сохраняет исходный context. В частности,
создание Product во время выбора ингредиента возвращает к выбору ингредиента, а
текущий черновик Recipe не теряется.

Soft-deleted Product и Recipe не показываются в Catalog. При отсутствии данных
экран объясняет, что нужно создать первый Product или Recipe, а основное
действие создания остаётся в toolbar.

### Defaults and consistency in selection

Для выбранного источника Catalog использует совместимое последнее
использованное amount/unit. Если такого значения нет или единица больше не
доступна, применяется fallback:

```text
г       → 100 г
порция → 1 порция
```

`Recipe.servingsCount` означает полный выход рецепта в порциях. Например,
`servingsCount = 5` не делает default потребления равным пяти порциям: fallback
по-прежнему равен одной порции.

В selection context действует единый инвариант: preview в Catalog, initial
amount/unit и preview в Amount, а также семантические amount/unit quick-add
соответствуют одному и тому же значению. Quick-add не является скрытой
конвертацией или отдельным default flow.

### Amount and units

Общий экран Amount показывает название источника, live preview calories и
Б/Ж/У, поле количества, единицу и confirm action. Для новой записи дневника
действие называется **«Добавить»**, для редактирования существующей записи —
**«Сохранить»**.

- Для нового Amount flow поле количества получает focus, открывается numeric
  keyboard, а initial text выделен для немедленной замены.
- Custom keyboard toolbar **«Готово»** не показывается.
- Нижние controls Amount остаются доступными над клавиатурой.
- Для Product доступна ровно одна base unit, поэтому единица отображается
  read-only.
- Для Recipe доступны `г`, если указан cooked weight, и `порция`, если указано
  servings count. При одной доступной единице она read-only; при двух доступен
  компактный selector.
- Пользовательские decimal numeric fields принимают максимум два знака после
  десятичного разделителя. И `.` и `,` принимаются как decimal separator.
  Ограничение относится только к ручному вводу; внутренние вычисления сохраняют
  необходимую точность.
- Ручная смена единицы не конвертирует уже введённое число. Например, `100 г`
  после выбора порций остаётся числом `100` и означает `100 порций` до ручного
  изменения пользователем.

При редактировании существующей DiaryEntry initial amount/unit и расчёт берутся
из сохранённой записи и её исторической версии источника, а не из текущего
Product или Recipe.

## 6. Products

Пользователь может создавать, искать по названию и barcode, просматривать,
редактировать и удалять Products, а также просматривать историю версий.
Barcode сейчас вводится вручную как строка; leading zeros сохраняются, а один
код не должен принадлежать двум Products.

Product form содержит название, optional barcode, base unit (`г` или `порция`),
base amount, calories, protein, fat и carbs. В новом Product числовые поля
пусты до ввода и не трактуются как ноль.

Изменение versioned данных Product — base unit, base amount, calories, protein,
fat или carbs — создаёт новую `ProductVersion`; старая версия остаётся в
истории. Изменение только name или barcode обновляет logical metadata Product
без создания новой версии. Barcode остаётся уникальным для Products, включая
удалённые.

Новая DiaryEntry использует актуальную версию, а уже сохранённая DiaryEntry
остаётся привязанной к использованной версии и собственному nutrition snapshot.
Обычное редактирование Product не переписывает существующие DiaryEntry, а
обычное редактирование их amount продолжает использовать сохранённый
`sourceVersionID`. Исключение — явное редактирование Product из Amount одной
конкретной DiaryEntry: после успешного сохранения Product обновляется только эта
запись. Её amount сохраняется, nutrition пересчитывается, `sourceName`
обновляется, а `sourceVersionID` меняется только при смене current ProductVersion.

Удаление Product выполняется без дополнительного confirmation dialog и убирает
его из обычного Catalog, не разрушая исторические Recipe и DiaryEntry. Полный
swipe не выполняет destructive delete: удаление требует явного tap по красной
корзине.

## 7. Recipes

Recipes — реализованная часть текущего продукта. Редактор Recipe позволяет
задавать:

- название;
- список ингредиентов;
- cooked weight;
- servings count.

Для сохранения требуются непустое название, хотя бы один ингредиент и хотя бы
один положительный output: cooked weight или servings count.

```text
cookedWeight  → делает доступным output в граммах
servingsCount → делает доступным output в порциях
оба значения  → доступны обе единицы output
```

Total nutrition — сумма ингредиентов. Показатели выхода рассчитываются как:

```text
per 100 г   = total / cookedWeight × 100
per serving = total / servingsCount
```

Изменение versioned данных Recipe создаёт новую `RecipeVersion`: это изменение
ingredients, их порядка, ProductVersion, amount или unit, а также cooked weight
или servings count. Изменение только name обновляет logical metadata Recipe без
создания новой версии. Предыдущие RecipeVersion и исторические DiaryEntry не
меняются.

### Ingredients and flattening

Из Recipe Editor действие **«Добавить»** открывает общий Catalog в ingredient
selection context.

```text
Product → Amount → один Product ingredient draft
Recipe  → Amount → пропорционально развёрнутые Product ingredient drafts
```

После confirm в Amount draft или развёрнутые drafts добавляются в текущий
черновик Recipe, и его nutrition пересчитывается. Это обычный row-tap flow.
Quick-add — отдельное действие `+`: оно использует тот же default amount/unit,
но добавляет один Product draft или развёрнутые Recipe drafts без экрана Amount.

Выбор Recipe как ингредиента не создаёт вложенную сохранённую связь
Recipe→Recipe. Его текущий состав разворачивается в Product ingredients с
закреплёнными версиями продуктов. Поэтому последующее изменение рецепта-источника
не меняет уже добавленный черновик или сохранённый Recipe.

Удаление Recipe выполняется без отдельного confirmation dialog и скрывает его
из обычного Catalog, сохраняя данные, нужные для истории. Полный swipe не
выполняет destructive delete: удаление требует явного tap по красной корзине.

## 8. Barcode

Нативного barcode scanner в текущей версии нет. Product поддерживает ручной
ввод и поиск barcode; camera scanning, внешние barcode/product APIs и return
flows scanner являются future work и не должны отображаться как доступная
функция.

## 9. Goals

Goals доступны из **«Сегодня → Настройки → Цели»**. WeeklyGoal содержит семь
DailyMacroGoal — calories, protein, fat и carbs для каждого дня недели. Значение
одного дня можно применить ко всем дням. Редактор показывает компактный selector
дней недели и поля только выбранного дня, сохраняя draft всех семи дней до
обычного сохранения.

Цели можно редактировать повторно. Изменения, сохранённые сегодня, действуют с
текущего local day: повторное сохранение обновляет сегодняшние цели, а
предыдущие дни сохраняют свои исторические значения. Today и Statistics для
исторической даты используют цель, действовавшую в эту дату, а не сегодняшнюю.

## 10. Statistics

**Статистика** показывает выбранную неделю: bars calories по дням, weekly
calorie balance и распределение энергии Б/Ж/У. Пользователь может перейти по
неделям и вернуться к текущей.

Проценты Б/Ж/У считаются по энергии:

```text
Protein = grams × 4
Fat     = grams × 9
Carbs   = grams × 4
```

Calories в DiaryEntry остаются отдельным snapshot и могут немного отличаться от
macro-derived energy. Будущие дни текущей недели не считаются дефицитом в
weekly balance.

## 11. Versioning and historical integrity

Historical integrity — обязательное правило продукта. DiaryEntry сохраняет:

- local day, meal и order;
- source type, logical ID и version ID;
- source name snapshot;
- amount и unit;
- snapshots calories, protein, fat и carbs.

После изменения Product или Recipe ранее сохранённые DiaryEntry не
пересчитываются автоматически. Даже при редактировании их amount/unit расчёт
использует сохранённую версию источника. Единственное Product-исключение —
успешное сохранение Product Editor, открытого из конкретной DiaryEntry: эта одна
запись намеренно rebased к текущему Product, получает актуальное имя и
пересчитанный nutrition snapshot; остальные DiaryEntry не меняются.

Metadata-only rename вне этого явного contextual rebase не переписывает
`sourceName` snapshot: запись, сохранённая для «Молоко», сохраняет это
историческое имя после переименования Product в «Молоко 2.5%».

## 12. Local storage

Текущие пользовательские данные хранятся локально в SwiftData на устройстве:
Products, ProductVersions, Recipes, RecipeVersions, ingredients, DiaryEntries и
weekly goals. Приложение не требует аккаунт для работы с этими данными.

В Today доступна компактная кнопка «Настройки». Она открывает общий раздел с
переходами **«Цели»** и **«Синхронизация»**. В разделе «Синхронизация»
пользователь может войти по email и одноразовому коду, увидеть состояние
foreground-синхронизации, запустить «Синхронизировать сейчас» или выйти.
Аккаунт остаётся опциональным: выход и отсутствие настройки не удаляют и не
ограничивают локальные Products, Recipes, Diary или Goals.

После входа локально сохранённые изменения синхронизируются при активном
приложении и появлении сети; приложение при этом не блокирует обычную работу.
Статус **«Синхронизировано»** показывается только после завершённого цикла без
ожидающих изменений или известных ошибок. До первой успешной синхронизации и
после временной ошибки интерфейс показывает ожидание/повтор, а не ложный успех.

## 13. Offline behaviour

После успешного запуска приложение работает с локальными данными без сети для
Today, Catalog, Recipe, Goals и Statistics. Это native iOS-приложение: PWA
manifest, service worker, Home Screen installation и browser routes не являются
частью текущего поведения.

## 14. UX rules

- Основные food flows используют отдельные экраны, а не маленькие bottom sheet.
- Controls должны быть touch-friendly, обычно не меньше 44 pt.
- Numeric fields используют numeric keyboard.
- Клавиатура не должна перекрывать Amount controls или мешать сохранению.
- Длинные названия не должны создавать horizontal scroll.
- Ошибки формулируются человеческим языком и не показывают технические
  исключения.
- Ошибки валидации остаются конкретными и помогают исправить ввод. Ошибки
  хранения или системы показываются как стабильное понятное сообщение, без
  деталей SwiftData, путей или системного текста.
- Destructive actions используют красную корзину и не выполняются одним swipe.

## 15. Out of scope

В текущий продукт не входят weight tracking, water tracking, exercise/steps,
gamification, social features, subscriptions, ads, medical advice, AI/photo
food recognition, HealthKit, widgets, Watch и complex onboarding.

## 16. Future and deferred

Следующие возможности не реализованы и требуют отдельного product decision:

- camera barcode scanner;
- export/import backup;
- Realtime, cloud reset/delete или отдельный conflict UI;
- external barcode/product lookup;
- web-data migration.

## 17. Document precedence

For intended product behaviour, precedence is:

```text
Current PRODUCT_SPEC.md
>
older phase prompts
>
historical planning notes
```

The document describes the product rather than development history.
