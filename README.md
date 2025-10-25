# BarbaRossa

Инструмент для загрузки и обработки видео с YouTube с добавлением голосового перевода. Поддерживает пакетную обработку через файловую очередь.

## Требования

- Podman (или Docker)
- Podman Compose (или Docker Compose)
- Make (опционально, но рекомендуется)

## Установка

1. Клонируйте репозиторий:
   ```bash
   git clone https://github.com/xsa-dev/BarbaRossa.git
   cd BarbaRossa
   ```

2. Создайте необходимые директории:
   ```bash
   mkdir -p data/{output,meta}
   ```

## Использование

### Управление очередью

```bash
# Добавить видео в очередь
./barba-rossa-cli.sh "https://www.youtube.com/watch?v=..." [quality] [language]

# Добавить плейлист в очередь
./barba-rossa-cli.sh playlist "https://youtube.com/playlist?list=..." [quality] [language] [start] [end]

# Обработать следующее видео из очереди
./barba-rossa-cli.sh process [quality] [language]

# Показать текущую очередь
./barba-rossa-cli.sh queue

# Показать доступные языки
./barba-rossa-cli.sh languages

# Очистить очередь
./barba-rossa-cli.sh clear
```

#### Параметры:
- **quality**: 360p, 480p, 720p (по умолчанию), 1080p, best
- **language**: ru (по умолчанию), en, es, fr, de, it, pt, pl, tr, uk, be, kk, uz, az, ky, tg
- **start/end**: номера видео для плейлиста (например, 1 10 для первых 10 видео)

### С помощью Makefile (рекомендуется)

```bash
# Собрать контейнер
make build

# Запустить контейнер
make up

# Добавить видео в очередь
make add URL="https://www.youtube.com/watch?v=..."

# Обработать следующее видео из очереди
make process

# Показать очередь
make queue

# Очистить очередь
make clear-queue

# Остановить контейнер
make down

# Просмотр логов
make logs

# Войти в контейнер
make exec
```

### Вручную

```bash
# Сборка и запуск
podman-compose -f podman/docker-compose.yaml up -d --build

# Запуск скрипта
podman exec -it barba-rossa-cli /app/barba-rossa-cli.sh

# Остановка
podman-compose -f podman/docker-compose.yaml down
```

## Структура проекта

```
.
├── data/
│   ├── output/    # Готовые видеофайлы
│   └── meta/      # Метаданные и логи
├── podman/
│   ├── Dockerfile
│   └── docker-compose.yaml
├── barba-rossa-cli.sh  # Основной скрипт
├── queue_manager.sh    # Менеджер очереди
└── Makefile           # Управление проектом
```

## Логи и отладка

Логи контейнера можно посмотреть с помощью команды:

```bash
make logs
```

Или напрямую через podman:

```bash
podman logs -f barba-rossa-cli
```

## Очистка

Для удаления временных файлов:

```bash
make clean
```

## Лицензия

MIT
