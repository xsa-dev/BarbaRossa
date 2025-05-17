#!/bin/bash

# Ensure required directories exist
mkdir -p ./temp ./out ./meta

# Prompt for YouTube video URL
read -p "Enter YouTube video URL: " youtube_url

# Extract video ID from URL using sed
video_id=$(echo "$youtube_url" | sed -n 's/.*v=\([^&]*\).*/\1/p')
if [ -z "$video_id" ]; then
    video_id=$(echo "$youtube_url" | sed -n 's/.*youtu\.be\/\([^?]*\).*/\1/p')
fi

# Clean up any existing temporary files related to this video_id to avoid partial download issues
echo "Cleaning up existing temporary files for video ID $video_id..."
rm -f ./temp/*${video_id}*.* 2>/dev/null

# Function to download video with yt-dlp
download_video() {
    local url="$1"
    local cookies_option="$2"
    # Change to temp directory for download
    cd ./temp
    # Run yt-dlp and show progress in real-time, capture exit status
    yt-dlp $cookies_option "$url"
    local status=$?
    # Return to the original directory
    cd ..
    if [ $status -eq 0 ]; then
        echo "Video downloaded successfully to temp directory."
        return 0
    else
        echo "Error downloading video."
        return 1
    fi
}

# Try downloading video without cookies first
echo "Attempting to download video without cookies..."
download_video "$youtube_url" ""
download_status=$?

# If download fails, prompt for cookies
if [ $download_status -ne 0 ]; then
    echo "Failed to download video. It may require cookies for access (e.g., age-restricted content)."
    read -p "Do you want to use a cookies file? (y/n): " use_cookies
    if [ "$use_cookies" = "y" ] || [ "$use_cookies" = "Y" ]; then
        read -p "Enter path to cookies file (or press Enter to use Safari cookies): " cookies_path
        if [ -z "$cookies_path" ]; then
            # Use Safari cookies if no path provided
            download_video "$youtube_url" "--cookies-from-browser safari"
        else
            # Use provided cookies file
            download_video "$youtube_url" "--cookies $cookies_path"
        fi
        if [ $? -ne 0 ]; then
            echo "Error: Could not download video even with cookies."
            exit 1
        fi
    else
        echo "Download aborted by user."
        exit 1
    fi
fi

# Get video title using yt-dlp and clean it for filename
video_title=$(cd ./temp && yt-dlp --get-title "$youtube_url" 2>/dev/null | tr -s ' ' '_' | sed 's/[^a-zA-Z0-9_-]/_/g')
if [ -z "$video_title" ]; then
    echo "Warning: Could not get video title, using video ID as filename."
    video_title="$video_id"
fi
output_file="./out/${video_title}.mp4"
metadata_file="./meta/${video_title}_metadata.txt"

# Initialize metadata file
echo "Saving metadata to $metadata_file..."
: > "$metadata_file"

# 1. Save video title
echo "Video Title:" >> "$metadata_file"
(cd ./temp && yt-dlp --print title "$youtube_url" >> "../$metadata_file" 2>/dev/null) || echo "Not available" >> "$metadata_file"
echo "" >> "$metadata_file"

# 2. Save video description
echo "Video Description:" >> "$metadata_file"
(cd ./temp && yt-dlp --write-description "$youtube_url" 2>/dev/null)
description_file=$(ls ./temp/*${video_id}*.description 2>/dev/null | head -1)
if [ -n "$description_file" ] && [ -f "$description_file" ]; then
    cat "$description_file" >> "$metadata_file"
    rm -f "$description_file" # Clean up description file
else
    echo "Not available" >> "$metadata_file"
fi
echo "" >> "$metadata_file"

# 3. Save original language subtitles
echo "Original Language Subtitles:" >> "$metadata_file"
# Try to detect original language (if available)
original_lang=$(cd ./temp && yt-dlp --print language "$youtube_url" 2>/dev/null)
if [ -z "$original_lang" ] || [ "$original_lang" = "null" ]; then
    original_lang="en" # Fallback to English if language not detected
fi
(cd ./temp && yt-dlp --write-subs --sub-langs "$original_lang" --skip-download "$youtube_url" 2>/dev/null)
subtitle_file=$(ls ./temp/*${video_id}*.$original_lang*.vtt 2>/dev/null | head -1)
if [ -n "$subtitle_file" ] && [ -f "$subtitle_file" ]; then
    # Convert VTT to plain text (remove timestamps)
    sed '/^[0-9]\{2\}:[0-9]\{2\}:[0-9]\{2\}.[0-9]\{3\} --> /d' "$subtitle_file" | grep -v '^$' >> "$metadata_file"
    rm -f "$subtitle_file" # Clean up subtitle file
else
    echo "Not available for language $original_lang" >> "$metadata_file"
fi
echo "" >> "$metadata_file"

# 4. Save automatic Russian subtitles
echo "Automatic Russian Subtitles:" >> "$metadata_file"
(cd ./temp && yt-dlp --write-auto-subs --sub-langs "ru" --skip-download "$youtube_url" 2>/dev/null)
auto_subtitle_file=$(ls ./temp/*${video_id}*.ru*.vtt 2>/dev/null | head -1)
if [ -n "$auto_subtitle_file" ] && [ -f "$auto_subtitle_file" ]; then
    # Convert VTT to plain text (remove timestamps)
    sed '/^[0-9]\{2\}:[0-9]\{2\}:[0-9]\{2\}.[0-9]\{3\} --> /d' "$auto_subtitle_file" | grep -v '^$' >> "$metadata_file"
    rm -f "$auto_subtitle_file" # Clean up subtitle file
else
    echo "Not available" >> "$metadata_file"
fi
echo "" >> "$metadata_file"

# 5. Save original video link
echo "Original Video Link:" >> "$metadata_file"
echo "$youtube_url" >> "$metadata_file"
echo "" >> "$metadata_file"

# Get voiceover audio using vot-cli and capture the audio URL
echo "Running vot-cli to generate voiceover..."
# Use tee to display output in real-time and save to a temporary file
temp_output="./temp/vot_output.txt"
vot-cli "$youtube_url" 2>&1 | tee "$temp_output"
vot_status=$?
audio_url=$(grep -o 'https://vtrans\.s3-private\.mds\.yandex\.net/tts/prod/[^"]*' "$temp_output" | tail -1)
rm -f "$temp_output" # Clean up temporary file

# Check if vot-cli executed successfully
if [ $vot_status -ne 0 ]; then
    echo "Error: vot-cli failed to execute."
    exit 1
fi

# Check if audio URL was extracted
if [ -z "$audio_url" ]; then
    echo "Error: Could not extract audio URL from vot-cli output."
    exit 1
fi

# Download generated audio
wget -O ./temp/audio.mp3 "$audio_url"
if [ $? -ne 0 ]; then
    echo "Error: Could not download audio from $audio_url."
    exit 1
fi

# Merge video and audio using ffmpeg, mixing original audio at 30% volume
# Use any video file generated by yt-dlp (e.g., .mkv, .webm, .mp4)
video_file=$(ls ./temp/*${video_id}*.* 2>/dev/null | grep -E '\.(mkv|webm|mp4)$' | head -1)
if [ -z "$video_file" ]; then
    echo "Error: No video file (mkv, webm, or mp4) found for video ID $video_id."
    exit 1
fi

# Mix original audio (at 30% volume) with new audio
ffmpeg -i "$video_file" -i ./temp/audio.mp3 -filter_complex "[0:a]volume=0.3[a0];[a0][1:a]amix=inputs=2:duration=shortest[a]" -map 0:v:0 -map "[a]" -c:v copy -c:a aac -shortest "$output_file"
if [ $? -ne 0 ]; then
    echo "Error: Failed to merge video and audio with ffmpeg."
    exit 1
fi

# Check if output file was created and prompt to open
if [ -f "$output_file" ]; then
    echo "Successfully created translated video at $output_file"
    echo "Metadata saved to $metadata_file"
    read -p "Do you want to open the output file? (y/n): " answer
    if [ "$answer" = "y" ] || [ "$answer" = "Y" ]; then
        open "$output_file"
    fi
else
    echo "Error: $output_file was not created."
    exit 1
fi

# Optionally clean up temporary files after successful processing
read -p "Do you want to clean up temporary files? (y/n): " cleanup
if [ "$cleanup" = "y" ] || [ "$cleanup" = "Y" ]; then
    echo "Cleaning up temporary files..."
    rm -f ./temp/*${video_id}*.*
    rm -f ./temp/audio.mp3
    echo "Temporary files removed."
fi