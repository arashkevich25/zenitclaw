#!/bin/sh
docker run -d \
    --name neuron-zeroclaw \
    -p 42617:42617 \
    -v zeroclaw_data:/zeroclaw-data \
    -e TELEGRAM_BOT_TOKEN="8705690179:AAER14nogGMPjJE3SclwI0Cm8aKcdufdt20" \
    -e GEMINI_API_KEY="AIzaSyBF2u-iem6cr9V3RhYvj79mVc6Ov50oDgM" \
    -e BRAVE_API_KEY="BSA-gSVH6VEb8rQ-ZbXgJAB3SvkFzBY" \
    neuron-zeroclaw-gemini
