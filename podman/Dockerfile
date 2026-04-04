# Use a base image with Python and common tools
FROM python:3.10-slim

# Install system dependencies
RUN apt-get update && apt-get install -y \
    ffmpeg \
    wget \
    curl \
    gnupg \
    && curl -fsSL https://deb.nodesource.com/setup_18.x | bash - \
    && apt-get install -y nodejs \
    && rm -rf /var/lib/apt/lists/*

# Install Python packages
RUN pip install --no-cache-dir \
    yt-dlp 

# Install VOT-CLI globally (latest version)
RUN npm install -g vot-cli@latest

# Create working directories
WORKDIR /app
RUN mkdir -p /app/temp /app/out /app/meta

# Copy the script and make it executable
COPY barba-rossa-cli.sh /app/
RUN chmod +x /app/barba-rossa-cli.sh

# Set up entrypoint
ENTRYPOINT ["/app/barba-rossa-cli.sh"]

# Default command (can be overridden)
CMD ["--help"]