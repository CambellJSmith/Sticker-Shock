#!/usr/bin/env python3
from __future__ import annotations

import threading
from pathlib import Path

from PIL import Image
from huggingface_hub import snapshot_download

MODEL_ID: str = "HuggingFaceTB/SmolVLM-256M-Instruct"
PROMPT_PATH: Path = Path(__file__).resolve().parent / "flavour_prompt.txt"
_model_lock: threading.Lock = threading.Lock()
_pipeline = None


def ensure_model_cached() -> str:
    return snapshot_download(repo_id=MODEL_ID)


def load_base_prompt() -> str:
    if not PROMPT_PATH.is_file():
        return "Write exactly four fun, charming, professional, child-appropriate sentences of flavour text describing the supplied image."
    return PROMPT_PATH.read_text(encoding="utf-8").strip()


def save_base_prompt(prompt: str) -> None:
    PROMPT_PATH.write_text(prompt.strip() + "\n", encoding="utf-8")


def generate_flavour_text(image_path: Path, sticker_name: str, pack_name: str, rarity: str) -> str:
    generator = _get_pipeline()
    base_prompt: str = load_base_prompt()
    prompt: str = (
        base_prompt
        + "\n\nLook carefully at the supplied sticker artwork and base the response on what is actually visible. "
        "Use the visible subject, pose, clothing, objects, expression, and mood as evidence. "
        "Write as though the depicted subject genuinely exists. "
        "Do not describe it as an image, artwork, sticker, illustration, or game asset. "
        "Do not mention rarity, pack names, IDs, probabilities, artists, or game mechanics. "
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
            max_new_tokens=180,
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
