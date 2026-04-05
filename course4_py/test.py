import numpy as np
import cv2
import matplotlib.pyplot as plt

def pro_marker_full_pipeline(file_path, clusters=4, nlm_h=20, min_area=150):
    # 1. ЗАГРУЗКА И ВОССТАНОВЛЕНИЕ ОРИГИНАЛА
    data = np.load(file_path)
    table = data['table_xy_g1_g2']
    x, y = table[:, 0].astype(int), table[:, 1].astype(int)
    w, h = x.max() - x.min() + 1, y.max() - y.min() + 1
    
    img = np.zeros((h, w), dtype=np.float32)
    img[y - y.min(), x - x.min()] = table[:, 2] # Берем g1

    # Нормализуем оригинал для показа
    img_orig_norm = cv2.normalize(img, None, 0, 255, cv2.NORM_MINMAX).astype(np.uint8)

    # --- ПРЕДОБРАБОТКА ---
    p_low, p_high = np.percentile(img[img != 0], (1, 99))
    img_clipped = np.clip(img, p_low, p_high)
    img_clipped_norm = cv2.normalize(img_clipped, None, 0, 255, cv2.NORM_MINMAX).astype(np.uint8)
    clahe = cv2.createCLAHE(clipLimit=2.0, tileGridSize=(8, 8))
    img_contrast = clahe.apply(img_clipped_norm)
    
    # 2. ФИЛЬТРАЦИЯ (NLM + Median)
    denoised = cv2.fastNlMeansDenoising(img_contrast, None, h=nlm_h, templateWindowSize=7, searchWindowSize=21)
    denoised = cv2.medianBlur(denoised, 5)

    # 3. КВАНТОВАНИЕ ФАЗ
    pixel_vals = denoised.reshape((-1, 1)).astype(np.float32)
    criteria = (cv2.TERM_CRITERIA_EPS + cv2.TERM_CRITERIA_MAX_ITER, 100, 0.2)
    _, labels_km, centers = cv2.kmeans(pixel_vals, clusters, None, criteria, 10, cv2.KMEANS_RANDOM_CENTERS)
    quantized = centers[labels_km.flatten()].reshape(denoised.shape).astype(np.uint8)

    # 4. ДВОЙНАЯ МАРКИРОВКА
    phase_labels = np.zeros_like(quantized, dtype=np.int32)
    individual_labels = np.zeros_like(quantized, dtype=np.int32)
    
    unique_colors = np.sort(np.unique(quantized))
    current_phase_id = 1
    current_individual_id = 1
    
    for color in unique_colors:
        phase_mask = np.uint8(quantized == color) * 255
        num_labels, comp_labels, stats, _ = cv2.connectedComponentsWithStats(phase_mask, connectivity=4)
        for i in range(1, num_labels): 
            if stats[i, cv2.CC_STAT_AREA] >= min_area:
                mask = (comp_labels == i)
                phase_labels[mask] = current_phase_id
                individual_labels[mask] = current_individual_id
                current_individual_id += 1
        current_phase_id += 1 

    # Подготовка цветовых карт
    cmap_ind = plt.get_cmap('jet')
    max_ind = individual_labels.max() if individual_labels.max() > 0 else 1
    colored_ind = cmap_ind(individual_labels / max_ind)
    colored_ind[individual_labels == 0] = [0, 0, 0, 1] 

    cmap_phase = plt.get_cmap('Set1', current_phase_id)
    colored_phase = cmap_phase(phase_labels / current_phase_id)
    colored_phase[phase_labels == 0] = [0, 0, 0, 1] 

    # 5. ВИЗУАЛИЗАЦИЯ 1: Дашборд из 5 графиков
    plt.figure(figsize=(25, 6))
    
    plt.subplot(1, 5, 1)
    plt.imshow(img_orig_norm, cmap='gray')
    plt.title("Оригинальное фото")
    plt.axis('off')

    plt.subplot(1, 5, 2)
    plt.imshow(img_contrast, cmap='gray')
    plt.title("После CLAHE и обрезки шума")
    plt.axis('off')

    plt.subplot(1, 5, 3)
    plt.imshow(quantized, cmap='gray')
    plt.title(f"Квантование ({clusters} фазы)")
    plt.axis('off')

    plt.subplot(1, 5, 4)
    plt.imshow(colored_ind)
    plt.title(f"Всего кусков (островов): {individual_labels.max()}")
    plt.axis('off')

    plt.subplot(1, 5, 5)
    plt.imshow(colored_phase)
    plt.title(f"Уникальных магнитных фаз: {phase_labels.max()}")
    plt.axis('off')

    plt.tight_layout()
    plt.savefig('pro_result_pipeline.png', dpi=300)
    
    # 6. ВИЗУАЛИЗАЦИЯ 2: Сравнение До/После
    plt.figure(figsize=(12, 6))
    
    plt.subplot(1, 2, 1)
    plt.imshow(img_orig_norm, cmap='gray')
    plt.title("Исходное изображение")
    plt.axis('off')

    plt.subplot(1, 2, 2)
    plt.imshow(colored_phase)
    plt.title(f"Уникальные магнитные домены: {phase_labels.max()}")
    plt.axis('off')

    plt.tight_layout()
    plt.savefig('pro_result_comparison.png', dpi=300)
    plt.show()

    marker_col = phase_labels[y - y.min(), x - x.min()]
    return np.column_stack((table, marker_col))

if __name__ == "__main__":
    result = pro_marker_full_pipeline('dataset_roi_real.npz', clusters=4, nlm_h=20, min_area=150)
    print("Готово! Сохранены файлы pro_result_pipeline.png и pro_result_comparison.png")