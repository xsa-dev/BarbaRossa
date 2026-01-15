#!/bin/bash

# Файл для хранения очереди
QUEUE_FILE="./queue.txt"
LOCK_FILE="./queue.lock"
STATUS_DIR="./status"
PID_FILE="./processor.pid"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Настройки по умолчанию
MAX_WORKERS=3
PROCESS_INTERVAL=60  # секунды между обработкой элементов

# Создаем необходимые директории
mkdir -p "$STATUS_DIR"

# Создаем файл очереди, если его нет
if [ ! -f "$QUEUE_FILE" ]; then
    touch "$QUEUE_FILE"
fi

# Функция для блокировки файла очереди
acquire_lock() {
    local max_attempts=10
    local attempt=0
    
    while [ $attempt -lt $max_attempts ]; do
        if (set -o noclobber; echo "$$") > "$LOCK_FILE" 2>/dev/null; then
            trap 'rm -f "$LOCK_FILE"; exit' INT TERM EXIT
            return 0
        fi
        sleep 0.1
        ((attempt++))
    done
    return 1
}

# Функция для разблокировки файла очереди
release_lock() {
    rm -f "$LOCK_FILE"
    trap - INT TERM EXIT
}

# Добавление URL в очередь
add_to_queue() {
    local url="$1"
    
    if ! acquire_lock; then
        echo "Ошибка: не удалось получить блокировку для очереди"
        return 1
    fi
    
    # Проверяем, есть ли уже такой URL в очереди
    if ! grep -qFx "$url" "$QUEUE_FILE"; then
        echo "$url" >> "$QUEUE_FILE"
        echo "Добавлено в очередь: $url"
    else
        echo "URL уже в очереди: $url"
    fi
    
    release_lock
}

# Получение следующего URL из очереди
get_next_from_queue() {
    if ! acquire_lock; then
        echo "Ошибка: не удалось получить блокировку для очереди"
        return 1
    fi
    
    if [ ! -s "$QUEUE_FILE" ]; then
        echo "Очередь пуста"
        release_lock
        return 1
    fi
    
    # Берем первую строку из файла
    local url=$(head -n 1 "$QUEUE_FILE")
    # Удаляем первую строку из файла
    tail -n +2 "$QUEUE_FILE" > "${QUEUE_FILE}.tmp" && mv "${QUEUE_FILE}.tmp" "$QUEUE_FILE"
    
    release_lock
    echo "$url"
}

# Показать текущую очередь
show_queue() {
    if [ ! -s "$QUEUE_FILE" ]; then
        echo "Очередь пуста"
        return 0
    fi
    
    echo "Текущая очередь:"
    cat -n "$QUEUE_FILE"
    return 0
}

# Очистка очереди
clear_queue() {
    if ! acquire_lock; then
        echo "Ошибка: не удалось получить блокировку для очереди"
        return 1
    fi
    
    > "$QUEUE_FILE"
    echo "Очередь очищена"
    
    release_lock
    return 0
}

# Функция обработки одного элемента
process_item() {
    local url="$1"
    local worker_id=$2
    local status_file="${STATUS_DIR}/worker_${worker_id}.status"
    
    echo "Обработка: $url" > "$status_file"
    
    # Здесь вызываем основной скрипт для обработки URL
    "$SCRIPT_DIR/barba-rossa-cli.sh" "$url"
    
    # Проверяем статус выполнения
    if [ $? -eq 0 ]; then
        echo "Успешно обработано: $url"
        echo "success" > "$status_file"
    else
        echo "Ошибка при обработке: $url"
        echo "error" > "$status_file"
    fi
}

# Функция рабочего процесса
worker() {
    local worker_id=$1
    local interval=$2
    
    while true; do
        # Проверяем, нужно ли завершить работу
        if [ -f "${STATUS_DIR}/stop" ]; then
            echo "Воркер $worker_id завершает работу"
            rm -f "${STATUS_DIR}/worker_${worker_id}.status"
            exit 0
        fi
        
        # Получаем следующий URL из очереди
        local url=$(get_next_from_queue)
        
        if [[ "$url" != "Очередь пуста" ]]; then
            process_item "$url" "$worker_id"
            sleep "$interval"
        else
            # Если очередь пуста, ждем перед следующей проверкой
            sleep 10
        fi
    done
}

# Запуск обработки очереди
start_processing() {
    local workers=${1:-$MAX_WORKERS}
    local interval=${2:-$PROCESS_INTERVAL}
    
    # Проверяем, не запущен ли уже процессор
    if [ -f "$PID_FILE" ]; then
        local pid=$(cat "$PID_FILE")
        if ps -p "$pid" > /dev/null 2>&1; then
            echo "Процесс обработки уже запущен (PID: $pid)"
            return 1
        fi
    fi
    
    # Создаем файл для остановки, если его нет
    touch "${STATUS_DIR}/stop"
    sleep 1
    rm -f "${STATUS_DIR}/stop"
    
    # Запускаем воркеры в фоновом режиме
    for ((i=1; i<=workers; i++)); do
        worker "$i" "$interval" &
        echo $! >> "${PID_FILE}.tmp"
    done
    
    mv "${PID_FILE}.tmp" "$PID_FILE"
    echo "Запущено $workers воркеров с интервалом ${interval}с"
}

# Остановка обработки
stop_processing() {
    if [ ! -f "$PID_FILE" ]; then
        echo "Процесс обработки не запущен"
        return 1
    fi
    
    # Создаем файл для остановки
    touch "${STATUS_DIR}/stop"
    
    # Останавливаем все дочерние процессы
    while read -r pid; do
        if ps -p "$pid" > /dev/null 2>&1; then
            kill "$pid" 2>/dev/null
        fi
    done < "$PID_FILE"
    
    # Удаляем PID файл
    rm -f "$PID_FILE"
    
    echo "Обработка остановлена"
}

# Показать статус обработки
show_status() {
    if [ -f "$PID_FILE" ]; then
        local pids=$(cat "$PID_FILE")
        local running=0
        
        for pid in $pids; do
            if ps -p "$pid" > /dev/null 2>&1; then
                ((running++))
            fi
        done
        
        echo "Статус: запущено $running воркеров"
        
        # Показываем статус каждого воркера
        for status_file in "$STATUS_DIR"/worker_*.status; do
            if [ -f "$status_file" ]; then
                local worker_id=$(basename "$status_file" | cut -d'_' -f2 | cut -d'.' -f1)
                echo "  Воркер $worker_id: $(cat "$status_file")"
            fi
        done
    else
        echo "Процесс обработки не запущен"
    fi
}

# Обработка команд
if [ $# -eq 0 ]; then
    echo "Использование: $0 {add URL|next|show|clear|start [workers] [interval]|stop|status}"
    exit 1
fi

case "$1" in
    add)
        if [ -z "$2" ]; then
            echo "Ошибка: не указан URL для добавления"
            exit 1
        fi
        add_to_queue "$2"
        ;;
    next)
        get_next_from_queue
        ;;
    show)
        show_queue
        ;;
    clear)
        clear_queue
        ;;
    start)
        start_processing "$2" "$3"
        ;;
    stop)
        stop_processing
        ;;
    status)
        show_status
        ;;
    *)
        echo "Использование: $0 {add URL|next|show|clear|start [workers] [interval]|stop|status}"
        exit 1
        ;;
esac

exit 0
