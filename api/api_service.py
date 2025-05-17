from fastapi import FastAPI, BackgroundTasks, HTTPException
from fastapi.responses import FileResponse
from pydantic import BaseModel
import uuid
import subprocess
import os
import re
import shutil
from typing import Dict, Optional, List, Tuple

app = FastAPI()

# Создаем необходимые директории
BASE_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RESULTS_DIR = os.path.join(os.path.dirname(__file__), 'results')
TEMP_DIR = os.path.join(BASE_DIR, 'temp')
OUT_DIR = os.path.join(BASE_DIR, 'out')
META_DIR = os.path.join(BASE_DIR, 'meta')

for directory in [RESULTS_DIR, TEMP_DIR, OUT_DIR, META_DIR]:
    os.makedirs(directory, exist_ok=True)

# Статусы задач
TASKS: Dict[str, dict] = {}

class ProcessRequest(BaseModel):
    url: str
    use_cookies: bool = True
    cookies_path: Optional[str] = None
    save_metadata: bool = True
    cleanup_temp: bool = True

@app.post("/process")
def process_video(request: ProcessRequest, background_tasks: BackgroundTasks):
    task_id = str(uuid.uuid4())
    TASKS[task_id] = {
        "status": "processing", 
        "filename": None, 
        "metadata_filename": None,
        "error": None
    }
    background_tasks.add_task(
        run_barba_rossa, 
        request.url, 
        task_id,
        request.use_cookies,
        request.cookies_path,
        request.save_metadata,
        request.cleanup_temp
    )
    return {"task_id": task_id}

def extract_video_id(url: str) -> str:
    """Extract YouTube video ID from URL."""
    video_id = re.search(r'v=([^&]*)', url)
    if video_id:
        return video_id.group(1)
    
    video_id = re.search(r'youtu\.be/([^?]*)', url)
    if video_id:
        return video_id.group(1)
    
    return ""

def download_video(url: str, video_id: str, use_cookies: bool = True, cookies_path: Optional[str] = None) -> Tuple[bool, str]:
    """Download video from YouTube using yt-dlp."""
    # Clean up any existing temporary files for this video ID
    for file in os.listdir(TEMP_DIR):
        if video_id in file:
            os.remove(os.path.join(TEMP_DIR, file))
    
    # Set up cookies option
    cookies_option = []
    if use_cookies:
        if cookies_path:
            cookies_option = ["--cookies", cookies_path]
        else:
            cookies_option = ["--cookies-from-browser", "safari"]
    
    # Download the video
    cmd = ["yt-dlp"] + cookies_option + ["-o", f"{TEMP_DIR}/%(id)s.%(ext)s", url]
    result = subprocess.run(cmd, capture_output=True, text=True)
    
    if result.returncode != 0:
        return False, result.stderr
    return True, ""

def get_video_metadata(url: str, video_id: str, save_metadata: bool) -> Tuple[str, Optional[str]]:
    """Extract and save video metadata."""
    # Get video title
    title_result = subprocess.run(
        ["yt-dlp", "--get-title", url], 
        capture_output=True, 
        text=True
    )
    video_title = title_result.stdout.strip()
    if not video_title:
        video_title = video_id
    
    # Clean title for filename use
    clean_title = re.sub(r'[^a-zA-Z0-9_-]', '_', video_title.replace(' ', '_'))
    
    metadata_filename = None
    if save_metadata:
        metadata_filename = f"{clean_title}_metadata.txt"
        metadata_path = os.path.join(META_DIR, metadata_filename)
        
        with open(metadata_path, 'w') as metadata_file:
            # 1. Save video title
            metadata_file.write("Video Title:\n")
            metadata_file.write(f"{video_title}\n\n")
            
            # 2. Save video description
            metadata_file.write("Video Description:\n")
            subprocess.run(["yt-dlp", "--write-description", "--skip-download", "-o", f"{TEMP_DIR}/%(id)s.%(ext)s", url])
            description_files = [f for f in os.listdir(TEMP_DIR) if f.endswith('.description') and video_id in f]
            if description_files:
                with open(os.path.join(TEMP_DIR, description_files[0]), 'r', encoding='utf-8', errors='replace') as desc_file:
                    metadata_file.write(desc_file.read())
                # Clean up description file
                os.remove(os.path.join(TEMP_DIR, description_files[0]))
            else:
                metadata_file.write("Not available\n")
            metadata_file.write("\n")
            
            # 3. Save original language subtitles
            metadata_file.write("Original Language Subtitles:\n")
            # Try to detect original language
            lang_result = subprocess.run(
                ["yt-dlp", "--print", "language", url],
                capture_output=True,
                text=True
            )
            original_lang = lang_result.stdout.strip()
            if not original_lang or original_lang == "null":
                original_lang = "en"  # Fallback to English
            
            subprocess.run([
                "yt-dlp", "--write-subs", "--sub-langs", original_lang, 
                "--skip-download", "-o", f"{TEMP_DIR}/%(id)s.%(ext)s", url
            ])
            
            subtitle_files = [f for f in os.listdir(TEMP_DIR) if f.endswith('.vtt') and video_id in f and original_lang in f]
            if subtitle_files:
                subtitle_path = os.path.join(TEMP_DIR, subtitle_files[0])
                # Convert VTT to plain text (remove timestamps)
                with open(subtitle_path, 'r', encoding='utf-8', errors='replace') as sub_file:
                    for line in sub_file:
                        if not re.match(r'^[0-9]{2}:[0-9]{2}:[0-9]{2}.[0-9]{3} --> ', line) and line.strip():
                            metadata_file.write(line)
                
                # Clean up subtitle file
                os.remove(subtitle_path)
            else:
                metadata_file.write(f"Not available for language {original_lang}\n")
            metadata_file.write("\n")
            
            # 4. Save automatic Russian subtitles
            metadata_file.write("Automatic Russian Subtitles:\n")
            subprocess.run([
                "yt-dlp", "--write-auto-subs", "--sub-langs", "ru", 
                "--skip-download", "-o", f"{TEMP_DIR}/%(id)s.%(ext)s", url
            ])
            
            ru_subtitle_files = [f for f in os.listdir(TEMP_DIR) if f.endswith('.vtt') and video_id in f and 'ru' in f]
            if ru_subtitle_files:
                ru_subtitle_path = os.path.join(TEMP_DIR, ru_subtitle_files[0])
                # Convert VTT to plain text (remove timestamps)
                with open(ru_subtitle_path, 'r', encoding='utf-8', errors='replace') as sub_file:
                    for line in sub_file:
                        if not re.match(r'^[0-9]{2}:[0-9]{2}:[0-9]{2}.[0-9]{3} --> ', line) and line.strip():
                            metadata_file.write(line)
                
                # Clean up subtitle file
                os.remove(ru_subtitle_path)
            else:
                metadata_file.write("Not available\n")
            metadata_file.write("\n")
            
            # 5. Save original video link
            metadata_file.write("Original Video Link:\n")
            metadata_file.write(f"{url}\n\n")
    
    return clean_title, metadata_filename

def get_voiceover_audio(url: str) -> Tuple[bool, str, Optional[str]]:
    """Get voiceover audio using vot-cli."""
    # Run vot-cli to generate voiceover
    vot_result = subprocess.run(["vot-cli", url], capture_output=True, text=True)
    
    if vot_result.returncode != 0:
        return False, "vot-cli failed to execute.", None
    
    # Extract audio URL from output
    audio_url_match = re.search(r'(https://vtrans\.s3-private\.mds\.yandex\.net/tts/prod/[^"]*)', vot_result.stdout)
    if not audio_url_match:
        return False, "Could not extract audio URL from vot-cli output.", None
    
    audio_url = audio_url_match.group(1)
    audio_path = os.path.join(TEMP_DIR, "audio.mp3")
    
    # Download the audio
    wget_result = subprocess.run(["wget", "-O", audio_path, audio_url], capture_output=True, text=True)
    
    if wget_result.returncode != 0:
        return False, f"Could not download audio from {audio_url}.", None
    
    return True, "", audio_path

def find_video_file(video_id: str) -> Optional[str]:
    """Find the downloaded video file in temp directory."""
    video_files = []
    for file in os.listdir(TEMP_DIR):
        if video_id in file and re.search(r'\.(mkv|webm|mp4)$', file):
            video_files.append(os.path.join(TEMP_DIR, file))
    
    if not video_files:
        return None
    
    # Return the first matching file
    return video_files[0]

def merge_video_audio(video_file: str, audio_file: str, output_path: str) -> bool:
    """Merge video and audio using ffmpeg."""
    cmd = [
        "ffmpeg", "-i", video_file, "-i", audio_file,
        "-filter_complex", "[0:a]volume=0.3[a0];[a0][1:a]amix=inputs=2:duration=shortest[a]",
        "-map", "0:v:0", "-map", "[a]", "-c:v", "copy", "-c:a", "aac", "-shortest",
        output_path
    ]
    
    result = subprocess.run(cmd, capture_output=True, text=True)
    return result.returncode == 0

def run_barba_rossa(
    url: str, 
    task_id: str, 
    use_cookies: bool = True,
    cookies_path: Optional[str] = None,
    save_metadata: bool = True,
    cleanup_temp: bool = True
):
    try:
        # Extract video ID
        video_id = extract_video_id(url)
        if not video_id:
            raise ValueError("Could not extract video ID from URL")
        
        # Download video
        download_success, download_error = download_video(url, video_id, use_cookies, cookies_path)
        if not download_success:
            raise ValueError(f"Failed to download video: {download_error}")
        
        # Get video metadata
        clean_title, metadata_filename = get_video_metadata(url, video_id, save_metadata)
        
        # Get voiceover audio
        audio_success, audio_error, audio_path = get_voiceover_audio(url)
        if not audio_success:
            raise ValueError(f"Failed to get voiceover audio: {audio_error}")
        
        # Find video file
        video_file = find_video_file(video_id)
        if not video_file:
            raise ValueError(f"No video file found for video ID {video_id}")
        
        # Create output filename
        output_filename = f"ru_{task_id}.mp4"
        output_path = os.path.join(RESULTS_DIR, output_filename)
        
        # Merge video and audio
        merge_success = merge_video_audio(video_file, audio_path, output_path)
        if not merge_success:
            raise ValueError("Failed to merge video and audio with ffmpeg")
        
        # Check if output file was created
        if not os.path.exists(output_path):
            raise ValueError("Output file was not created")
        
        # Update task status
        TASKS[task_id]["status"] = "done"
        TASKS[task_id]["filename"] = output_filename
        TASKS[task_id]["metadata_filename"] = metadata_filename
        
        # Clean up temporary files if requested
        if cleanup_temp:
            if os.path.exists(audio_path):
                os.remove(audio_path)
            
            for file in os.listdir(TEMP_DIR):
                if video_id in file:
                    os.remove(os.path.join(TEMP_DIR, file))
    
    except Exception as e:
        TASKS[task_id]["status"] = "error"
        TASKS[task_id]["error"] = str(e)

@app.get("/status/{task_id}")
def get_status(task_id: str):
    task = TASKS.get(task_id)
    if not task:
        raise HTTPException(status_code=404, detail="Task not found")
    return {
        "status": task["status"], 
        "filename": task["filename"], 
        "metadata_filename": task["metadata_filename"],
        "error": task["error"]
    }

@app.get("/results/{filename}")
def get_result(filename: str):
    file_path = os.path.join(RESULTS_DIR, filename)
    if not os.path.exists(file_path):
        raise HTTPException(status_code=404, detail="File not found")
    
    media_type = "video/mp4"
    if filename.endswith(".txt"):
        media_type = "text/plain"
    
    return FileResponse(file_path, media_type=media_type, filename=filename)

@app.get("/metadata/{filename}")
def get_metadata(filename: str):
    file_path = os.path.join(META_DIR, filename)
    if not os.path.exists(file_path):
        raise HTTPException(status_code=404, detail="Metadata file not found")
    return FileResponse(file_path, media_type="text/plain", filename=filename)
