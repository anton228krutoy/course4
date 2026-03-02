#!/usr/bin/env python3
"""
Скрипт для:
1) загрузки двух изображений (long.jpeg и trans.jpeg),
2) ручного выбора прямоугольной области ROI мышью,
3) сборки "максимально полного" датасета по ROI:
   - координаты (x, y) в ROI
   - RGB из первого изображения
   - RGB из второго изображения
   - а также grayscale версии (на всякий случай)

Выбор ROI делается по первой картинке (long.jpeg), затем тот же прямоугольник
применяется ко второй (trans.jpeg). Геометрическое совмещение НЕ выполняется.

Выходные файлы (в папке запуска):
- dataset_roi.npz  (основной датасет + метаданные)
- roi_preview.png  (картинка-проверка: ROI слева long, справа trans)

Зависимости:
- numpy
- opencv-python (cv2)
"""

from __future__ import annotations

import json
from dataclasses import asdict, dataclass
from pathlib import Path

import cv2
import numpy as np


@dataclass(frozen=True)
class Roi:
    x: int
    y: int
    w: int
    h: int


def imread_rgb(path: str | Path) -> np.ndarray:
    """Читает изображение через OpenCV и возвращает RGB uint8 [H,W,3]."""
    img_bgr = cv2.imread(str(path), cv2.IMREAD_COLOR)
    if img_bgr is None:
        raise FileNotFoundError(f"Не удалось прочитать изображение: {path}")
    img_rgb = cv2.cvtColor(img_bgr, cv2.COLOR_BGR2RGB)
    return img_rgb


def to_gray_u8(rgb: np.ndarray) -> np.ndarray:
    """RGB uint8 [H,W,3] -> grayscale uint8 [H,W]."""
    bgr = cv2.cvtColor(rgb, cv2.COLOR_RGB2BGR)
    g = cv2.cvtColor(bgr, cv2.COLOR_BGR2GRAY)
    return g


def clamp_roi(roi: Roi, shape_hw: tuple[int, int]) -> Roi:
    """Гарантирует, что ROI целиком внутри картинки."""
    h, w = shape_hw
    x = max(0, min(int(roi.x), w - 1))
    y = max(0, min(int(roi.y), h - 1))
    ww = max(1, min(int(roi.w), w - x))
    hh = max(1, min(int(roi.h), h - y))
    return Roi(x=x, y=y, w=ww, h=hh)


def select_roi_on_image(rgb: np.ndarray, window_name: str = "Select ROI") -> Roi:
    """
    Открывает окно и позволяет мышью выделить прямоугольник.
    Возвращает Roi(x,y,w,h).
    """
    # cv2.selectROI ожидает BGR
    bgr = cv2.cvtColor(rgb, cv2.COLOR_RGB2BGR)
    r = cv2.selectROI(window_name, bgr, showCrosshair=True, fromCenter=False)
    cv2.destroyWindow(window_name)

    x, y, w, h = map(int, r)
    if w <= 0 or h <= 0:
        raise RuntimeError("ROI не выбран (ширина/высота равны 0).")
    return Roi(x=x, y=y, w=w, h=h)


def build_dataset(long_rgb: np.ndarray, trans_rgb: np.ndarray, roi: Roi) -> dict[str, np.ndarray]:
    """
    Собирает датасет в виде таблицы N x 8:
    [x, y, r1, g1, b1, r2, g2, b2]  (x,y в координатах ROI: 0..w-1, 0..h-1)

    Плюс дополнительные массивы:
    - long_roi_rgb: [h,w,3]
    - trans_roi_rgb: [h,w,3]
    - long_roi_gray: [h,w]
    - trans_roi_gray: [h,w]
    """
    roi = clamp_roi(roi, (long_rgb.shape[0], long_rgb.shape[1]))
    if long_rgb.shape[:2] != trans_rgb.shape[:2]:
        raise ValueError(
            f"Размеры изображений отличаются: long={long_rgb.shape[:2]}, trans={trans_rgb.shape[:2]}. "
            "При отсутствии регистрации это критично."
        )

    x0, y0, w, h = roi.x, roi.y, roi.w, roi.h
    long_roi = long_rgb[y0 : y0 + h, x0 : x0 + w, :]
    trans_roi = trans_rgb[y0 : y0 + h, x0 : x0 + w, :]

    long_gray = to_gray_u8(long_roi)
    trans_gray = to_gray_u8(trans_roi)

    # координаты в ROI
    xs = np.tile(np.arange(w, dtype=np.int32)[None, :], (h, 1))
    ys = np.tile(np.arange(h, dtype=np.int32)[:, None], (1, w))

    # векторизуем в таблицу
    coords = np.stack([xs, ys], axis=-1).reshape(-1, 2)  # [N,2]
    p1 = long_roi.reshape(-1, 3).astype(np.uint8)  # [N,3]
    p2 = trans_roi.reshape(-1, 3).astype(np.uint8)  # [N,3]
    table = np.concatenate([coords, p1, p2], axis=1)  # [N,8]

    table_gray = np.stack(
        [
            coords[:, 0],
            coords[:, 1],
            long_gray.reshape(-1).astype(np.uint8),
            trans_gray.reshape(-1).astype(np.uint8),
        ],
        axis=1,
    )  # [N,4] => [x,y,g1,g2]

    return {
        "table_xy_rgb1_rgb2": table,  # int32/uint8 смешано -> станет int32 если сохранять как есть; поэтому ниже приводим тип
        "table_xy_g1_g2": table_gray,
        "long_roi_rgb": long_roi,
        "trans_roi_rgb": trans_roi,
        "long_roi_gray": long_gray,
        "trans_roi_gray": trans_gray,
    }


def main() -> None:
    long_path = Path("long.jpeg")
    trans_path = Path("trans.jpeg")
    out_npz = Path("dataset_roi.npz")
    out_preview = Path("roi_preview.png")

    long_rgb = imread_rgb(long_path)
    trans_rgb = imread_rgb(trans_path)

    roi = select_roi_on_image(long_rgb, window_name="Select ROI on long.jpeg (ENTER/SPACE to confirm)")

    roi = clamp_roi(roi, (long_rgb.shape[0], long_rgb.shape[1]))
    data = build_dataset(long_rgb, trans_rgb, roi)

    # Приводим таблицы к удобным типам (чтобы np.savez не делал object)
    # table: [x,y,r1,g1,b1,r2,g2,b2] -> int32
    t = data["table_xy_rgb1_rgb2"].astype(np.int32, copy=False)
    tg = data["table_xy_g1_g2"].astype(np.int32, copy=False)

    meta = {
        "long_path": str(long_path),
        "trans_path": str(trans_path),
        "roi": asdict(roi),
        "schema": {
            "table_xy_rgb1_rgb2": ["x", "y", "r1", "g1", "b1", "r2", "g2", "b2"],
            "table_xy_g1_g2": ["x", "y", "g1", "g2"],
        },
        "notes": "x,y даны в координатах ROI (0..w-1, 0..h-1). Сам ROI задан в абсолютных координатах исходных картинок.",
    }

    np.savez_compressed(
        out_npz,
        table_xy_rgb1_rgb2=t,
        table_xy_g1_g2=tg,
        long_roi_rgb=data["long_roi_rgb"],
        trans_roi_rgb=data["trans_roi_rgb"],
        long_roi_gray=data["long_roi_gray"],
        trans_roi_gray=data["trans_roi_gray"],
        meta_json=np.array(json.dumps(meta, ensure_ascii=False)),
    )

    # превью: склеим две ROI рядом, сохраним как PNG (в BGR для cv2.imwrite)
    preview_rgb = np.concatenate([data["long_roi_rgb"], data["trans_roi_rgb"]], axis=1)
    preview_bgr = cv2.cvtColor(preview_rgb, cv2.COLOR_RGB2BGR)
    cv2.imwrite(str(out_preview), preview_bgr)

    print("OK")
    print(f"ROI (absolute): x={roi.x}, y={roi.y}, w={roi.w}, h={roi.h}")
    print(f"Saved: {out_npz}")
    print(f"Saved: {out_preview}")
    print("Arrays in NPZ: table_xy_rgb1_rgb2, table_xy_g1_g2, long_roi_rgb, trans_roi_rgb, long_roi_gray, trans_roi_gray, meta_json")


if __name__ == "__main__":
    main()
