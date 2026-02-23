#!/bin/sh
docker run -d \
    --name neuron-zeroclaw \
    -p 42617:42617 \
    -v zeroclaw_data:/zeroclaw-data \
    -v "$(pwd)/IDENTITY.md:/zeroclaw-data/.zeroclaw/workspace/IDENTITY.md:ro" \
    -e TELEGRAM_BOT_TOKEN="" \
    -e OLLAMA_BASE_URL="https://ollama.com/api" \
    -e OLLAMA_API_KEY="" \
    -e BRAVE_API_KEY="" \
    -e GMAIL_ADDRESS="ai.arashkevich17@gmail.com" \
    -e GMAIL_APP_PASSWORD="" \
    neuron-zeroclaw-ollama
