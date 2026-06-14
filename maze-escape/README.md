# 🏰 Maze Escape — Roblox Game

Полноценная Roblox-игра в жанре лабиринтов с процедурной генерацией, прогрессией и монетизацией.

## Структура проекта (Rojo)

```
maze-escape/
├── default.project.json          # Rojo конфиг
├── src/
│   ├── shared/                   # ReplicatedStorage → Shared
│   │   ├── Constants.luau        # Все конфиги игры
│   │   ├── Types.luau            # Типы данных
│   │   ├── MazeGenerator.luau   # Процедурная генерация лабиринтов
│   │   └── RemoteDefinitions.luau
│   │
│   ├── server/                   # ServerScriptService → Server
│   │   ├── init.server.luau      # Точка входа сервера
│   │   ├── Services/
│   │   │   ├── PlayerDataService.luau  # DataStore, XP, монеты
│   │   │   ├── MazeService.luau        # Генерация и управление лабиринтами
│   │   │   ├── ShopService.luau        # Магазин (покупка/экипировка)
│   │   │   ├── QuestService.luau       # Дневные и недельные квесты
│   │   │   └── RewardService.luau      # Ежедневные награды
│   │   └── Managers/
│   │       └── LeaderboardManager.luau # OrderedDataStore таблицы лидеров
│   │
│   └── client/                   # StarterPlayerScripts → Client
│       ├── init.client.luau      # Точка входа клиента
│       ├── Controllers/
│       │   ├── MazeController.luau     # Монеты, чекпоинты, выход, лава
│       │   ├── EffectController.luau   # Следы, ауры, питомцы, освещение
│       │   └── InputController.luau   # Клавиатура и мобильный ввод
│       └── UI/
│           ├── MainGui.luau      # HUD (монеты, уровень, таймер, мир)
│           ├── ShopGui.luau      # Магазин с категориями
│           ├── QuestGui.luau     # Квесты + ежедневная награда
│           ├── LeaderboardGui.luau # Таблица лидеров (топ-10)
│           └── NotificationGui.luau  # Toast-уведомления и достижения
```

## Быстрый старт

### 1. Установка Rojo

```bash
# Windows (aftman / foreman)
aftman add rojo-rbx/rojo
aftman install

# Или скачать с https://rojo.space
```

### 2. Синхронизация

```bash
cd maze-escape
rojo serve
```

В Roblox Studio:
- Открой плагин **Rojo**
- Нажми **Connect** → `localhost:34872`
- Готово — файлы синхронизируются в реальном времени

### 3. Настройка перед публикацией

Открой `src/shared/Constants.luau` и замени ID:

```luau
-- Gamepass IDs (получи из Creator Hub после создания)
Constants.GAMEPASS_IDS = {
    DoubleCoins     = 12345678,   -- твой ID
    VIP             = 12345679,
    SpeedBoost      = 12345680,
    NightVision     = 12345681,
    ExtraCheckpoint = 12345682,
    RainbowTrail    = 12345683,
}

-- Developer Product IDs
Constants.PRODUCT_IDS = {
    SkipLevel          = 87654321,
    PathHint           = 87654322,
    TeleportCheckpoint = 87654323,
    Revive             = 87654324,
}
```

## Особенности

### Миры (7 штук)
| # | Название | Механики | Размер |
|---|----------|----------|--------|
| 1 | Classic Maze | — | 15×15 |
| 2 | Forest Maze | Туман, ложные пути | 19×19 |
| 3 | Ice Maze | Скользкий пол | 21×21 |
| 4 | Lava Maze | Урон от лавы | 23×23 |
| 5 | Dark Maze | Ограниченная видимость | 25×25 |
| 6 | Tech Maze | Двери, кнопки | 27×27 |
| 7 | Chaos Maze | Все механики | 31×31 |

### Генерация лабиринтов
- Алгоритм: **Recursive Backtracker (DFS)**
- Гарантирует существование пути к выходу
- Случайный сид при каждом заходе
- BFS для системы подсказок пути

### Монетизация
**Gamepasses:** ×2 монеты, VIP, ускорение, ночное зрение, доп. чекпоинт, радужный след

**Developer Products:** пропуск уровня, подсказка пути, телепорт к чекпоинту, возрождение

**Магазин за монеты:** следы (5 шт.), ауры (3 шт.), питомцы (3 шт.), эффекты (2 шт.)

### Удержание игроков
- Ежедневные награды (7-дневный стрик)
- 3 дневных квеста + 4 недельных квеста
- 12 достижений
- Система уровней аккаунта (макс. 100)
- Таблица лидеров (топ-10 по мазам, монетам, времени)

## Оптимизация

- Лабиринт каждого игрока в своём `Folder` (не мешают друг другу)
- Серверная валидация всех наград
- DataStore автосохранение каждые 60 секунд
- Сбор монет через proximity-проверку (не TouchEnded)
- Освещение через `PointLight` вместо `GlobalShadows` на мобильных
