#!/bin/bash

# Проверка аргументов
if [ "$#" -ne 2 ]; then
    echo "Usage: $0 <YouTube URL> <output file path>"
    exit 2
fi

youtube_url="$1"
output_path="$2"

# Извлечение ID видео
video_id=$(echo "$youtube_url" | sed -n 's/.*v=\([^&]*\).*/\1/p')
if [ -z "$video_id" ]; then
    video_id=$(echo "$youtube_url" | sed -n 's/.*youtu\.be\/\([^?]*\).*/\1/p')
fi

# Скачивание видео
mkdir -p results
yt-dlp --cookies-from-browser safari -o "results/%(id)s.%(ext)s" "$youtube_url"
if [ $? -ne 0 ]; then
    echo "Error: yt-dlp failed to download video."
    exit 1
fi

# Получение ссылки на озвучку
audio_url=$(vot-cli "$youtube_url" 2>&1 | grep -o 'https://vtrans\.s3-private\.mds\.yandex\.net/tts/prod/[^\"]*' | tail -1)
if [ -z "$audio_url" ]; then
    echo "Error: Could not extract audio URL from vot-cli output."
    exit 1
fi

# Скачивание озвучки
wget -O audio.mp3 "$audio_url"
if [ $? -ne 0 ]; then
    echo "Error: Failed to download audio."
    exit 1
fi

# Поиск скачанного видео
video_file=$(ls results/${video_id}.* 2>/dev/null | grep -E '\.(mkv|webm|mp4)$' | head -1)
if [ -z "$video_file" ]; then
    echo "Error: No video file (mkv, webm, or mp4) found for video ID $video_id."
    exit 1
fi

# Сведение аудио
ffmpeg -i "$video_file" -i audio.mp3 -filter_complex "[0:a]volume=0.3[a0];[a0][1:a]amix=inputs=2:duration=shortest[a]" -map 0:v:0 -map "[a]" -c:v copy -c:a aac -shortest "$output_path"
if [ $? -ne 0 ]; then
    echo "Error: ffmpeg failed to create output."
    exit 1
fi

# Проверка результата
if [ ! -f "$output_path" ]; then
    echo "Error: Output file was not created."
    exit 1
fi

# Получение task_id из output_path (например, results/1234.mp4)
task_id=$(basename "$output_path" | sed 's/\..*$//')
ru_filename="ru_${task_id}.mp4"
ru_filepath="$(dirname "$output_path")/$ru_filename"

# Переименование итогового файла
mv "$output_path" "$ru_filepath"

# Удаление временных файлов
tmp_audio="audio.mp3"
if [ -f "$tmp_audio" ]; then
    rm -f "$tmp_audio"
fi
if [ -f "$video_file" ]; then
    rm -f "$video_file"
fi

# Сообщение об успехе
echo "Success: $ru_filepath"
exit 0