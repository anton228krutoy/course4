import numpy as np
import cv2
import matplotlib.pyplot as plt

def process_channel(img, clusters, nlm_h, min_area):
    """Вспомогательная функция, прогоняющая 1 канал через наш пайплайн"""
    # 1. Предобработка
    p_low, p_high = np.percentile(img[img != 0], (1, 99))
    img_clipped = np.clip(img, p_low, p_high)
    img_clipped_norm = cv2.normalize(img_clipped, None, 0, 255, cv2.NORM_MINMAX).astype(np.uint8)
    clahe = cv2.createCLAHE(clipLimit=2.0, tileGridSize=(8, 8))
    img_contrast = clahe.apply(img_clipped_norm)
    
    # 2. Фильтрация
    denoised = cv2.fastNlMeansDenoising(img_contrast, None, h=nlm_h, templateWindowSize=7, searchWindowSize=21)
    denoised = cv2.medianBlur(denoised, 5)

    # 3. Квантование
    pixel_vals = denoised.reshape((-1, 1)).astype(np.float32)
    criteria = (cv2.TERM_CRITERIA_EPS + cv2.TERM_CRITERIA_MAX_ITER, 100, 0.2)
    _, labels_km, centers = cv2.kmeans(pixel_vals, clusters, None, criteria, 10, cv2.KMEANS_RANDOM_CENTERS)
    quantized = centers[labels_km.flatten()].reshape(denoised.shape).astype(np.uint8)

    # 4. Двойная маркировка
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

    return img_contrast, quantized, individual_labels, phase_labels, current_phase_id

def apply_cmap(labels, max_id, cmap_name):
    """Помощник для раскраски размеченных матриц (чтобы фон был черным)"""
    cmap = plt.get_cmap(cmap_name, max_id)
    colored = cmap(labels / (max_id if max_id > 0 else 1))
    colored[labels == 0] = [0, 0, 0, 1]
    return colored

def pro_marker_dual_channel(file_path, clusters=4, nlm_h=20, min_area=150):
    # --- ЗАГРУЗКА ДАННЫХ ---
    data = np.load(file_path)
    table = data['table_xy_g1_g2']
    x, y = table[:, 0].astype(int), table[:, 1].astype(int)
    w, h = x.max() - x.min() + 1, y.max() - y.min() + 1
    
    # Создаем два холста
    img_g1 = np.zeros((h, w), dtype=np.float32)
    img_g2 = np.zeros((h, w), dtype=np.float32)
    img_g1[y - y.min(), x - x.min()] = table[:, 2] # g1
    img_g2[y - y.min(), x - x.min()] = table[:, 3] # g2

    img_g1_norm = cv2.normalize(img_g1, None, 0, 255, cv2.NORM_MINMAX).astype(np.uint8)
    img_g2_norm = cv2.normalize(img_g2, None, 0, 255, cv2.NORM_MINMAX).astype(np.uint8)

    # --- ОБРАБОТКА ОБЕИХ КОМПОНЕНТ ---
    contr_g1, quant_g1, ind_g1, phase_g1, max_ph_g1 = process_channel(img_g1, clusters, nlm_h, min_area)
    contr_g2, quant_g2, ind_g2, phase_g2, max_ph_g2 = process_channel(img_g2, clusters, nlm_h, min_area)

    # --- ЛОГИКА НАЛОЖЕНИЯ (ПОИСК СОВПАДЕНИЙ) ---
    combined_codes = phase_g1 * 100 + phase_g2
    valid_mask = (phase_g1 > 0) & (phase_g2 > 0) # Игнорируем фон/границы
    
    unique_combinations = np.unique(combined_codes[valid_mask])
    overlay_labels = np.zeros_like(phase_g1, dtype=np.int32)
    
    current_overlay_id = 1
    for code in unique_combinations:
        overlay_labels[(combined_codes == code) & valid_mask] = current_overlay_id
        current_overlay_id += 1

    # --- ВИЗУАЛИЗАЦИЯ 1: ДВУХЭТАЖНЫЙ ДАШБОРД ---
    fig, axes = plt.subplots(2, 5, figsize=(25, 10))
    fig.suptitle('Pro Анализ Каналов', fontsize=18)
    
    def plot_row(ax_row, orig, contr, quant, ind, phase, max_ind, max_ph, title_prefix):
        ax_row[0].imshow(orig, cmap='gray')
        ax_row[0].set_title(f"{title_prefix}: Оригинал")
        ax_row[1].imshow(contr, cmap='gray')
        ax_row[1].set_title(f"{title_prefix}: CLAHE")
        ax_row[2].imshow(quant, cmap='gray')
        ax_row[2].set_title(f"{title_prefix}: Квантование")
        ax_row[3].imshow(apply_cmap(ind, max_ind, 'jet'))
        ax_row[3].set_title(f"{title_prefix}: Кусков ({ind.max()})")
        ax_row[4].imshow(apply_cmap(phase, max_ph, 'Set1'))
        ax_row[4].set_title(f"{title_prefix}: Уник. фаз ({phase.max()})")
        for ax in ax_row: ax.axis('off')

    plot_row(axes[0], img_g1_norm, contr_g1, quant_g1, ind_g1, phase_g1, ind_g1.max(), max_ph_g1, "G1")
    plot_row(axes[1], img_g2_norm, contr_g2, quant_g2, ind_g2, phase_g2, ind_g2.max(), max_ph_g2, "G2")
    
    plt.tight_layout()
    plt.savefig('pro_result_dual_dashboard.png', dpi=300)

    # --- ВИЗУАЛИЗАЦИЯ 2: РЕЗУЛЬТАТ НАЛОЖЕНИЯ С ОРИГИНАЛАМИ ---
    fig2, axes2 = plt.subplots(2, 3, figsize=(18, 12))
    fig2.suptitle('Наглядное Пересечение Доменов', fontsize=18)

    axes2[0, 0].imshow(img_g1_norm, cmap='gray')
    axes2[0, 0].set_title(f"Оригинал G1")
    axes2[0, 0].axis('off')

    axes2[0, 1].imshow(img_g2_norm, cmap='gray')
    axes2[0, 1].set_title(f"Оригинал G2")
    axes2[0, 1].axis('off')

    axes2[0, 2].axis('off')

    axes2[1, 0].imshow(apply_cmap(phase_g1, max_ph_g1, 'Set1'))
    axes2[1, 0].set_title(f"Магнитные фазы G1")
    axes2[1, 0].axis('off')

    axes2[1, 1].imshow(apply_cmap(phase_g2, max_ph_g2, 'Set1'))
    axes2[1, 1].set_title(f"Магнитные фазы G2")
    axes2[1, 1].axis('off')

    axes2[1, 2].imshow(apply_cmap(overlay_labels, current_overlay_id, 'hsv'))
    axes2[1, 2].set_title(f"Пересечение (Истинных 2D-векторов: {overlay_labels.max()})")
    axes2[1, 2].axis('off')

    plt.tight_layout()
    plt.savefig('pro_result_overlay.png', dpi=300)
    plt.show()

    # --- СБОРКА И СОХРАНЕНИЕ НОВОГО ДАТАСЕТА ---
    m_g1 = phase_g1[y - y.min(), x - x.min()]
    m_g2 = phase_g2[y - y.min(), x - x.min()]
    m_over = overlay_labels[y - y.min(), x - x.min()]
    
    # Склеиваем старую таблицу и 3 новых колонки
    final_table = np.column_stack((table, m_g1, m_g2, m_over))
    
    # Сохраняем в новый файл
    out_filename = 'dataset_roi_marked.npz'
    np.savez(out_filename, table_marked=final_table)
    print(f"Новый датасет успешно сохранен в файл: {out_filename}")
    print("В массиве 'table_marked' теперь находятся оригинальные данные + 3 колонки с разметкой (G1, G2, Overlay).")
    
    return final_table

if __name__ == "__main__":
    result = pro_marker_dual_channel('dataset_roi_real.npz', clusters=4, nlm_h=20, min_area=150)
    print(f"Готово! Найдено {int(result[:, -1].max())} уникальных 2D-доменов.")