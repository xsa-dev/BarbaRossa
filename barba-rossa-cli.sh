#!/bin/bash

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Barba Rossa CLI
# @raycast.mode compact

# Optional parameters:
# @raycast.icon 🤖
# @raycast.argument1 { "type": "text", "placeholder": "URL or 'process'" }
# @raycast.packageName Barba Rossa

# Documentation:
# @raycast.description Обработка YouTube видео через очередь
# @raycast.author Alxy Dev
# @raycast.authorURL https://raycast.com/aleksey_savin

# Отключаем автоматический выход при ошибке, чтобы скрипт продолжал выполнение
# set -e  # Закомментировано для продолжения выполнения при ошибках

# Пути и настройки
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
QUEUE_MANAGER="$SCRIPT_DIR/queue_manager.sh"

# Качество видео по умолчанию
DEFAULT_QUALITY="720p"

# Язык результата по умолчанию для TTS
DEFAULT_RESLANG="ru"

# Функция для преобразования качества в формат yt-dlp
get_quality_format() {
    local quality="$1"
    case "$quality" in
        "360p")
            echo "best[height<=360]"
            ;;
        "480p")
            echo "best[height<=480]"
            ;;
        "720p")
            echo "best[height<=720]"
            ;;
        "1080p")
            echo "best[height<=1080]"
            ;;
        "best")
            echo "best"
            ;;
        *)
            echo "best[height<=720]"  # По умолчанию 720p
            ;;
    esac
}

# Функция для проверки валидности языка результата
is_valid_reslang() {
    local reslang="$1"
    case "$reslang" in
        "ru"|"en"|"es"|"fr"|"de"|"it"|"pt"|"pl"|"tr"|"uk"|"be"|"kk"|"uz"|"az"|"ky"|"tg")
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

# Функция для получения информации о языках
show_languages() {
    echo "Доступные языки для перевода:"
    echo "  ru - Русский (по умолчанию)"
    echo "  en - Английский"
    echo "  es - Испанский"
    echo "  fr - Французский"
    echo "  de - Немецкий"
    echo "  it - Итальянский"
    echo "  pt - Португальский"
    echo "  pl - Польский"
    echo "  tr - Турецкий"
    echo "  uk - Украинский"
    echo "  be - Белорусский"
    echo "  kk - Казахский"
    echo "  uz - Узбекский"
    echo "  az - Азербайджанский"
    echo "  ky - Киргизский"
    echo "  tg - Таджикский"
}

# Проверяем наличие менеджера очередей
if [ ! -f "$QUEUE_MANAGER" ]; then
    echo "Ошибка: Не найден файл queue_manager.sh"
    exit 1
fi

# Функция для обработки URL
process_youtube_url() {
    local youtube_url="$1"
    echo "Обработка YouTube URL: $youtube_url"
    
    # Остальной код обработки видео...
    # (весь существующий код обработки видео из оригинального скрипта)
    
    # Здесь будет существующий код обработки видео
    # ...
    
    echo "Обработка завершена: $youtube_url"
}

# Функция для обработки плейлиста
process_playlist() {
    local playlist_url="$1"
    local quality="$2"
    local reslang="$3"
    local start_num="${4:-1}"
    local end_num="$5"
    
    # Проверяем валидность языка результата
    if ! is_valid_reslang "$reslang"; then
        echo "Ошибка: Неверный язык результата '$reslang'"
        show_languages
        return 1
    fi
    
    echo "Обработка плейлиста: $playlist_url"
    echo "Качество: ${quality:-720p}"
    echo "Язык: ${reslang:-ru}"
    echo "Диапазон: $start_num - ${end_num:-все}"
    
    # Получаем список видео из плейлиста
    echo "=== Получение списка видео из плейлиста ==="
    
    # Создаем временный файл для списка видео
    local temp_playlist_file="./temp/playlist_$(date +%s).txt"
    
    # Получаем список URL видео из плейлиста
    local playlist_args=("--get-url" "--flat-playlist")
    if [ -n "$start_num" ] && [ "$start_num" -gt 1 ]; then
        playlist_args+=("--playlist-start" "$start_num")
    fi
    if [ -n "$end_num" ]; then
        playlist_args+=("--playlist-end" "$end_num")
    fi
    
    if yt-dlp "${playlist_args[@]}" "$playlist_url" > "$temp_playlist_file" 2>/dev/null; then
        local video_count=$(wc -l < "$temp_playlist_file")
        echo "Найдено $video_count видео в плейлисте"
        
        # Добавляем каждое видео в очередь
        local counter=0
        while IFS= read -r video_url; do
            if [ -n "$video_url" ]; then
                counter=$((counter + 1))
                echo "Добавляем в очередь видео $counter: $video_url"
                "$QUEUE_MANAGER" add "$video_url"
            fi
        done < "$temp_playlist_file"
        
        echo "Добавлено $counter видео в очередь"
        echo "Плейлист добавлен в очередь. Для обработки выполните: $0 process [$quality]"
        
        # Удаляем временный файл
        rm -f "$temp_playlist_file"
    else
        echo "Ошибка: Не удалось получить список видео из плейлиста"
        rm -f "$temp_playlist_file"
        exit 1
    fi
}

# Основная логика
if [ $# -eq 0 ]; then
    echo "Использование:"
    echo "  $0 <youtube_url> [quality] [reslang]  - Добавить видео в очередь"
    echo "  $0 playlist <playlist_url> [quality] [reslang] [start] [end] - Добавить плейлист в очередь"
    echo "  $0 process [quality] [reslang]      - Обработать следующее видео из очереди"
    echo "  $0 queue        - Показать текущую очередь"
    echo "  $0 clear       - Очистить очередь"
    echo "  $0 languages   - Показать доступные языки"
    echo ""
    echo "Качество видео (по умолчанию 720p):"
    echo "  360p, 480p, 720p, 1080p, best"
    echo ""
    echo "Языки перевода (по умолчанию ru):"
    echo "  ru, en, es, fr, de, it, pt, pl, tr, uk, be, kk, uz, az, ky, tg"
    echo ""
    echo "Плейлисты:"
    echo "  start - начальный номер видео (по умолчанию 1)"
    echo "  end   - конечный номер видео (по умолчанию все)"
    exit 1
fi

# Определяем качество видео и язык результата
video_quality="${2:-$DEFAULT_QUALITY}"
reslang="${3:-$DEFAULT_RESLANG}"

case "$1" in
    process)
        # Проверяем валидность языка результата
        if ! is_valid_reslang "$reslang"; then
            echo "Ошибка: Неверный язык результата '$reslang'"
            show_languages
            exit 1
        fi
        
        # Получаем следующий URL из очереди
        next_url="$("$QUEUE_MANAGER" next)"
        
        if [ "$next_url" = "Очередь пуста" ]; then
            echo "Очередь пуста"
            exit 0
        fi
        
        echo "Обработка видео: $next_url (качество: $video_quality, язык: $reslang)"
        youtube_url="$next_url"
        
        # Устанавливаем переменные для обработки
        quality_arg="$video_quality"
        lang_arg="$reslang"
        ;;
    playlist)
        if [ -z "$2" ]; then
            echo "Ошибка: не указан URL плейлиста"
            echo "Использование: $0 playlist <playlist_url> [quality] [reslang] [start] [end]"
            exit 1
        fi
        process_playlist "$2" "$3" "$4" "$5" "$6"
        exit 0
        ;;
    languages)
        show_languages
        exit 0
        ;;
    queue)
        "$QUEUE_MANAGER" show
        exit 0
        ;;
    clear)
        "$QUEUE_MANAGER" clear
        exit 0
        ;;
    *)
        # Проверяем валидность языка результата
        if ! is_valid_reslang "$reslang"; then
            echo "Ошибка: Неверный язык результата '$reslang'"
            show_languages
            exit 1
        fi
        
        # Добавляем URL в очередь
        youtube_url="$1"
        "$QUEUE_MANAGER" add "$youtube_url"
        echo "Для обработки следующего видео выполните: $0 process [$video_quality] [$reslang]"
        exit 0
        ;;
esac

echo "Начинаем обработку: $youtube_url (качество: $video_quality)"

# Создаем необходимые директории
mkdir -p "$SCRIPT_DIR/temp" "$SCRIPT_DIR/out" "$SCRIPT_DIR/meta" "$SCRIPT_DIR/output"

# Extract video ID from URL using sed
video_id=$(echo "$youtube_url" | sed -n 's/.*v=\([^&]*\).*/\1/p')
if [ -z "$video_id" ]; then
    video_id=$(echo "$youtube_url" | sed -n 's/.*youtu\.be\/\([^?]*\).*/\1/p')
fi

# Clean up any existing temporary files related to this video_id to avoid partial download issues
echo "Cleaning up existing temporary files for video ID $video_id..."
rm -f ./temp/*${video_id}*.* 2>/dev/null


# Extract video ID from URL
video_id=$(echo "$youtube_url" | sed -n 's/.*[?&]v=\([^&]*\).*/\1/p')
if [ -z "$video_id" ]; then
    # Try alternative URL format (youtu.be/ID)
    video_id=$(echo "$youtube_url" | sed -n 's/.*youtu\.be\/\([^?&]*\).*/\1/p')
    if [ -z "$video_id" ]; then
        echo "Error: Could not extract video ID from URL"
        echo ""
        echo "Possible reasons:"
        echo "  1. URL contains tracking parameters (?si=...)"
        echo "  2. URL format is not recognized"
        echo ""
        echo "Solution: Use the 'Share' button on YouTube to get a clean URL"
        echo "  - On YouTube video page, click Share button"
        echo "  - Copy the link (format: https://youtu.be/VIDEO_ID)"
        echo ""
        echo "Example of correct URL:"
        echo "  https://youtu.be/32Ie8OGrPNc"
        echo ""
        echo "Avoid URLs like:"
        echo "  https://www.youtube.com/watch?v=32Ie8OGrPNc?si=..."
        exit 1
    fi
fi

echo "Video ID: $video_id"

# Получаем безопасное имя файла из названия видео
safe_title=$(
    yt-dlp --get-title "$youtube_url" | \
    tr -d '\n\r"' | \
    tr -d "'\`*?/\\<>|:" | \
    sed 's/^[ \t]*//;s/[ \t]*$//' | \
    tr ' ' '_' | \
    tr -cd '\11\12\15\40-\176' | \
    sed 's/[\/:?*<>|\"'"'"'`]/_/g' | \
    sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | \
    head -c 100
)

# Debug log for safe_title
echo "Safe title for filenames: $safe_title"

# Определяем пути к файлам с безопасным именем
video_file="./temp/${safe_title}_${video_id}.mp4"
output_file="./output/${safe_title}_${video_id}_final.mp4"
log_message_file="./meta/${safe_title}_${video_id}_$(date +%Y%m%d_%H%M%S).log_message"

# Ensure output and meta directories exist
mkdir -p "./output" "./meta" "./temp"

# Создаем функцию для логирования
log_message() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] $1" | tee -a "$log_message_file"
}

echo "Video will be saved as: $video_file"
log_message "Starting processing of video: $youtube_url"

# Download video if it doesn't exist
if [ ! -f "$video_file" ]; then
    log_message "=== Downloading video (this may take a while) ==="
    
    # Пробуем скачать в самом простом формате
    log_message "Starting video download to: $video_file"
    log_message "Current directory: $(pwd)"
    
    # Сначала проверим доступные форматы
    log_message "Checking available formats..."
    yt-dlp -F "$youtube_url" 2>&1 | tee -a "$log_message_file"
    
    # Проверяем наличие aria2c для ускорения загрузки
    if command -v aria2c >/dev/null 2>&1; then
        log_message "aria2c found, will use it for faster downloads"
        downloader_args=(
            "--external-downloader" "aria2c"
            "--external-downloader-args" "-x 16 -s 16 -k 1M"
            "--buffer-size" "16K"
            "--http-chunk-size" "1M"
        )
    else
        log_message "aria2c not found, using built-in downloader"
        downloader_args=()
    fi
    
    # Пробуем скачать видео в разных форматах
    log_message "Trying to download video with different formats..."
    
    # Получаем формат для выбранного качества
    quality_format=$(get_quality_format "$video_quality")
    
    # Форматы для попыток загрузки
    formats=(
        "bestvideo[ext=mp4]+bestaudio[ext=m4a]/best[ext=mp4]/best"  # Попробуем сначала MP4
        "bestvideo+bestaudio/best"  # Любой формат видео + аудио
        "$quality_format"  # Выбранное качество
        'best'  # Лучшее доступное качество
    )
    
    download_success=false
    
    for format in "${formats[@]}"; do
        log_message "Trying format: $format"
        
        # Удаляем предыдущую попытку, если она была
        rm -f "$video_file"
        
        if yt-dlp -f "$format" \
            --output "$video_file" \
            --no-continue \
            --no-part \
            --force-overwrites \
            --no-clean-infojson \
            --merge-output-format mp4 \
            --retries 3 \
            --fragment-retries 3 \
            "${downloader_args[@]}" \
            "$youtube_url" 2>&1 | tee -a "$log_message_file"; then
            
            if [ -f "$video_file" ]; then
                file_size=$(du -h "$video_file" | cut -f1)
                log_message "Successfully downloaded video with format: $format (size: $file_size)"
                download_success=true
                break
            else
                log_message "Download reported success but file not found: $video_file"
            fi
        else
            log_message "Failed to download with format: $format"
        fi
    done
    
    if [ "$download_success" = true ]; then
        
        # Проверяем, что файл действительно создан
        if [ -f "$video_file" ]; then
            file_size=$(du -h "$video_file" | cut -f1)
            log_message "Video successfully downloaded to: $video_file (size: $file_size)"
            
            # Скачиваем метаданные отдельно
            log_message "Downloading metadata..."
            mkdir -p "./meta"
            yt-dlp --skip-download \
                --write-info-json \
                --write-description \
                --write-thumbnail \
                --write-annotations \
                --write-sub \
                --sub-lang en,ru \
                --convert-subs srt \
                --output "./meta/${safe_title}_${video_id}" \
                "$youtube_url" 2>&1 | tee -a "$log_message_file" || log_message "Warning: Failed to download some metadata"
                
            log_message "Video processing complete. Metadata has been downloaded to meta/ directory."
            
            # Выводим информацию о файле
            log_message "Video file info:"
            file "$video_file" | tee -a "$log_message_file"
            ffprobe -v error -show_format -show_streams "$video_file" 2>&1 | head -20 | tee -a "$log_message_file"
        else
            log_message "ERROR: Video file was not created: $video_file"
            log_message "Current directory content:"
            ls -la "$(dirname "$video_file")" | tee -a "$log_message_file"
            exit 1
        fi
    else
        log_message "Error: Failed to download video"
        exit 1
    fi
else
    log_message "Video already exists in temp directory. Using existing file: $video_file"
fi

# Generate voiceover using vot-cli-live
log_message "=== Running vot-cli-live to generate voiceover ==="
temp_output="./temp/"

# Get current timestamp before running vot-cli-live
before_vot=$(date +%s)

# Run vot-cli-live with timeout using bash built-in
translation_success=0
log_message "=== Starting translation attempt 1 ==="

# Функция для запуска с таймаутом
run_with_timeout() {
    local timeout=3600  # 60 минут для длинных видео
    local cmd=("$@")
    
    # Запускаем команду в фоне
    "${cmd[@]}" 2>&1 | tee -a "$log_message_file" &
    local pid=$!
    
    # Запускаем таймер
    ( sleep $timeout && kill -HUP $pid ) 2>/dev/null & 
    local timer_pid=$!
    
    # Ждем завершения команды
    if wait $pid 2>/dev/null; then
        kill -9 $timer_pid 2>/dev/null
        return 0
    else
        log_message "=== Command timed out after $timeout seconds ==="
        return 1
    fi
}

# Улучшенный fallback-механизм с цепочкой попыток
translation_success=0
fallback_attempts=0

# Попытка 1: Основной режим (живые голоса, русский)
log_message "=== Попытка 1: Живые голоса (по умолчанию) ==="
if run_with_timeout vot-cli-live "$youtube_url" --output "$temp_output" \
     --output-file "${safe_title}.mp3" --reslang "$reslang" && [ -f "${temp_output}/${safe_title}.mp3" ]; then
    translation_success=1
    log_message "✅ Успешный перевод с живыми голосами"
else
    log_message "❌ Попытка 1 провалилась"
    fallback_attempts=1

    # Попытка 2: TTS режим (альтернативный TTS)
    log_message "=== Попытка 2: Стандартный TTS ==="
    if run_with_timeout vot-cli-live "$youtube_url" --output "$temp_output" \
         --output-file "${safe_title}.mp3" --reslang "$reslang" --voice-style=tts && [ -f "${temp_output}/${safe_title}.mp3" ]; then
        translation_success=1
        log_message "✅ Успешный перевод с TTS"
    else
        log_message "❌ Попытка 2 провалилась"
        fallback_attempts=2
    fi
fi

# Если все попытки провалились
if [ $translation_success -eq 0 ]; then
    log_message "❌ Все попытки перевода провалились ($fallback_attempts попыток)"
    log_message "Используем оригинальное видео"
    # Копируем оригинальное видео в выходной файл с припиской ORIGINAL
    cp "$video_file" "${output_file%.*}_ORIGINAL.${output_file##*.}"
    log_message "Saved original video as: ${output_file%.*}_ORIGINAL.${output_file##*.}"
    exit 0
fi

# Find the generated audio file by vot-cli-live
log_message "=== Searching for generated audio file ==="
audio_file=""
expected_audio="./temp/${safe_title}.mp3"

if [ $translation_success -eq 1 ]; then
    log_message "Expected audio file path: $expected_audio"

    # Check if file exists
    if [ -f "$expected_audio" ]; then
        audio_file="$expected_audio"
        log_message "✓ Audio file found: $audio_file"

        # Display file info
        if command -v ls >/dev/null 2>&1; then
            file_size=$(ls -lh "$audio_file" | awk '{print $5}')
            log_message "Audio file size: $file_size"
        fi
    else
        log_message "✗ Expected audio file not found: $expected_audio"

        # List all mp3 files in temp for debugging
        log_message "All MP3 files in ./temp/:"
        find "./temp" -type f -name "*.mp3" -maxdepth 1 2>/dev/null | while read f; do
            if [ -f "$f" ]; then
                file_size=$(ls -lh "$f" 2>/dev/null | awk '{print $5}')
                log_message "  - $(basename "$f") ($file_size)"
            fi
        done
    fi

    if [ -n "$audio_file" ] && [ -f "$audio_file" ]; then
        
        # Check if the video file exists and has an audio stream
        if [ ! -f "$video_file" ]; then
            log_message "Error: Video file not found at $video_file"
            exit 1
        fi
        
        if ! ffprobe -v error -select_streams a -show_entries stream=codec_type -of default=noprint_wrappers=1:nokey=1 "$video_file" 2>/dev/null | grep -q "audio"; then
            log_message "Warning: Input video has no audio stream. Using generated audio only."
            if ! ffmpeg -y -i "$video_file" -i "$audio_file" -c:v copy -c:a aac -map 0:v:0 -map 1:a:0 -shortest "$output_file" 2>&1 | tee -a "$log_message_file"; then
                log_message "Error: Failed to merge video with audio-only stream"
                exit 1
            fi
        else
            # Mix original audio (at 30% volume) with new audio
            log_message "=== Merging video and audio with ffmpeg ==="
            if ! ffmpeg -y -i "$video_file" -i "$audio_file" \
                -filter_complex "[0:a]volume=0.3[a0];[a0][1:a]amix=inputs=2:duration=shortest[a]" \
                -map 0:v:0 -map "[a]" -c:v copy -c:a aac -map_metadata 0 -map_metadata:s:v 0:s:v -map_metadata:s:a 0:s:a -shortest "$output_file" 2>&1 | tee -a "$log_message_file"; then
                log_message "Error: Failed to merge video and audio"
                exit 1
            fi
        fi
        
        if [ $? -ne 0 ]; then
            echo -e "\nError: Failed to merge video and audio with ffmpeg. Copying video without audio."
            if [ -f "$video_file" ]; then
                cp "$video_file" "$output_file"
            else
                log_message "Error: Video file not found at $video_file"
                exit 1
            fi
        fi
    else
        log_message "✗ No audio file found. Expected: $expected_audio"
        log_message "Possible reasons:"
        log_message "  - Translation failed (see vot-cli-live output above)"
        log_message "  - File was created with different name"
        log_message "  - vot-cli-live version changed naming convention"
        log_message ""
        log_message "Using original video audio only."
        if [ -f "$video_file" ]; then
            cp "$video_file" "$output_file"
            log_message "✓ Copied original video to: $output_file"
        else
            log_message "✗ Error: Video file not found at $video_file"
            exit 1
        fi
    fi
fi

echo -e "\n=== Processing complete! ==="
echo "Output file: $output_file"

# Check if output file was created successfully
# if [ -f "$output_file" ]; then
#     echo "Success! Final video saved to: $output_file"
#     file_size=$(du -h "$output_file" | cut -f1)
#     echo "File size: $file_size"

#     if [[ "$*" == *"-y"* ]]; then
#         open_choice="n"
#     else
#         read -p "Do you want to open the output file? (y/n): " open_choice
#     fi
#     if [ "$open_choice" = "y" ] || [ "$open_choice" = "Y" ]; then
#         echo "Opening $output_file..."
#         open "$output_file"
#     fi
# else
#     echo "Error: Failed to create output file."
#     exit 1
# fi

# if [[ "$*" == *"-y"* ]]; then
#     clean_choice="y"
# else
#     read -p "Do you want to clean up temporary files? (y/n): " clean_choice
# fi
# if [ "$clean_choice" = "y" ] || [ "$clean_choice" = "Y" ]; then
#     echo "Cleaning up temporary files..."
#     rm -f ./temp/*${video_id}*.*
#     echo "Temporary files removed."
# fi
