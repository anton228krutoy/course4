import numpy as np
from processing import bg_v

data = np.load('dataset_roi.npz')
table = data['table_xy_g1_g2']
long_arr = table[:, [0,1,2]]
trans_arr = table[:, [0,1,3]]

import numpy as np
from processing import bg_v

def prepare_data(arr, n_outliers=10):
    """
    Подготавливает данные: вычитает фон и рассчитывает дистанцию (погрешность) 
    между соседними пикселями.
    """
    # 1. Извлекаем сырые значения g
    g_raw = arr[:, 2]

    # 2. Считаем фон
    bg = bg_v(g_raw, n_outliers)

    # 3. Очищаем данные
    g_clean = g_raw - bg

    # 4. Расчет дистанции (погрешности) между соседями
    # Нам нужно сравнить точку i с точкой i-1. 
    # Дистанция для первой точки всегда 0 (ей не с чем сравниваться).
    
    # Считаем разности между соседними элементами: [i] - [i-1]
    diff_g = np.diff(g_clean, prepend = g_clean[0])
    
    return diff_g

def distances(arr1, arr2):
    return np.sqrt(prepare_data(arr1)**2 + prepare_data(arr2)**2)


# def marker(arr: np.ndarray):
#     n = len(arr)

#     zeros = np.zeros((arr.shape[0], 1), dtype=int)
#     arr = np.hstack((arr, zeros)) 

#     while True:
#         changed = False
#         for i in range(n - 1):
#             if arr[i][3] == 0 and arr[i][2] == arr[i + 1][2]:
#                 arr[1][3] = 0 
    

'''
нужно пройти сделать уникальный маркеры на каждое совпадение цветов, добавить погрешность на совпадение arr[i][2] == arr[i + 1][2]
'''



   