#!/usr/bin/env python3
from __future__ import annotations

import threading
from pathlib import Path

from PIL import Image
from huggingface_hub import snapshot_download

MODEL_ID: str = "HuggingFaceTB/SmolVLM-256M-Instruct"
_model_lock: threading.Lock = threading.Lock()
_pipeline = None


def ensure_model_cached() -> str:
    return snapshot_download(repo_id=MODEL_ID)


def generate_flavour_text(image_path: Path, sticker_name: str, pack_name: str, rarity: str) -> str:
    generator = _get_pipeline()
    prompt: str = (
        "Look carefully at the supplied sticker artwork and write concise collectible flavour text for what is actually depicted. "
        "Use the visible subject, pose, clothing, objects, expression, and mood as your primary evidence. "
        "Write one or two polished sentences, 12 to 35 words total. "
        "Do not describe it as an image, artwork, sticker, illustration, or game asset. "
        "Do not mention rarity, pack names, IDs, probabilities, or game mechanics. "
        "Do not invent a different proper name. "
        f"The authored sticker name is {sticker_name!r}. "
        f"The authored pack is {pack_name!r} and rarity is {rarity!r}; use those only as subtle tonal context."
    )
    with Image.open(image_path) as source_image:
        image: Image.Image = source_image.convert("RGB")
        messages: list[dict[str, object]] = [
            {
                "role": "user",
                "content": [
                    {"type": "image"},
                    {"type": "text", "text": prompt},
                ],
            }
        ]
        outputs = generator(
            text=messages,
            images=[image],
            max_new_tokens=96,
            do_sample=False,
            return_full_text=False,
        )
    if not outputs:
        return ""
    generated = outputs[0].get("generated_text", "")
    if isinstance(generated, list):
        text_parts: list[str] = []
        for item in generated:
            if isinstance(item, dict) and item.get("type") == "text":
                text_parts.append(str(item.get("text", "")))
        generated = " ".join(text_parts)
    return str(generated).strip().strip('"')


def _get_pipeline():
    global _pipeline
    with _model_lock:
        if _pipeline is None:
            from transformers import pipeline

            _pipeline = pipeline(
                "image-text-to-text",
                model=MODEL_ID,
                device_map="auto",
            )
    return _pipeline
