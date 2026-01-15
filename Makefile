PROJECT_NAME = barba-rossa
COMPOSE_FILE = podman/docker-compose.yaml
PODMAN = podman
PODMAN_COMPOSE = $(PODMAN) compose
QUEUE_MANAGER = ./queue_manager.sh

# Настройки по умолчанию
WORKERS = 3
INTERVAL = 60

# Цели по умолчанию
.DEFAULT_GOAL := help

# Вывод справки
help:
	@echo "\033[1mДоступные команды:\033[0m"
	@echo ""
	@echo "  \033[1mОсновные команды:\033[0m"
	@echo "    \033[1mhelp\033[0m          - Показать это сообщение"
	@echo "    \033[1mbuild\033[0m        - Собрать контейнер"
	@echo "    \033[1mup\033[0m           - Запустить контейнер в фоновом режиме"
	@echo "    \033[1mdown\033[0m         - Остановить и удалить контейнер"
	@echo "    \033[1mexec\033[0m         - Войти в запущенный контейнер"
	@echo "    \033[1mlogs\033[0m        - Показать логи контейнера"
	@echo "    \033[1mrun\033[0m         - Запустить скрипт в контейнере"
	@echo "    \033[1mclean\033[0m       - Очистить временные файлы"
	@echo ""
	@echo "  \033[1mУправление очередью:\033[0m"
	@echo "    \033[1madd URL=...\033[0m    - Добавить видео в очередь"
	@echo "    \033[1mqueue-show\033[0m     - Показать текущую очередь"
	@echo "    \033[1mqueue-clear\033[0m    - Очистить очередь"
	@echo "    \033[1mqueue-start\033[0m    - Запустить обработку очереди"
	@echo "    \033[1mqueue-stop\033[0m     - Остановить обработку очереди"
	@echo "    \033[1mqueue-status\033[0m   - Показать статус обработки"
	@echo ""
	@echo "  \033[1mПримеры использования:\033[0m"
	@echo "    make add URL=https://youtube.com/watch?v=..."
	@echo "    make queue-start WORKERS=5 INTERVAL=30"

# Сборка контейнера
build:
	$(PODMAN_COMPOSE) -f $(COMPOSE_FILE) build

# Запуск контейнера
up:
	mkdir -p data/{output,meta}
	$(PODMAN_COMPOSE) -f $(COMPOSE_FILE) up -d

# Остановка контейнера
down:
	$(PODMAN_COMPOSE) -f $(COMPOSE_FILE) down

# Вход в контейнер
exec:
	$(PODMAN) exec -it $(PROJECT_NAME)-cli /bin/bash

# Просмотр логов
logs:
	$(PODMAN) logs -f $(PROJECT_NAME)-cli

# Запуск скрипта
run:
	$(PODMAN) exec -it $(PROJECT_NAME)-cli /app/barba-rossa-cli.sh

# Управление очередью
add:
	@if [ -z "$(URL)" ]; then \
		echo "Ошибка: не указан URL. Используйте: make add URL=ссылка_на_видео"; \
		exit 1; \
	fi
	@$(QUEUE_MANAGER) add "$(URL)"

queue-show:
	@$(QUEUE_MANAGER) show

queue-clear:
	@$(QUEUE_MANAGER) clear

queue-start:
	@echo "Запуск обработки очереди: $(WORKERS) воркеров, интервал $(INTERVAL)с"
	@$(QUEUE_MANAGER) start $(WORKERS) $(INTERVAL)

queue-stop:
	@$(QUEUE_MANAGER) stop

queue-status:
	@$(QUEUE_MANAGER) status

# Устаревшие команды (для обратной совместимости)
process:
	@echo "Внимание: команда 'make process' устарела. Используйте 'make queue-start'"
	@make queue-start

queue:
	@echo "Внимание: команда 'make queue' устарела. Используйте 'make queue-show'"
	@make queue-show

clear-queue:
	@echo "Внимание: команда 'make clear-queue' устарела. Используйте 'make queue-clear'"
	@make queue-clear
	
# Очистка временных файлов
clean:
	rm -rf data/temp/*

.PHONY: help build up down exec logs run add process queue clear-queue clean
