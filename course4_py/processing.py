#!/usr/bin/env python3
import numpy as np
import matplotlib.pyplot as plt

# Загружаем данные
data = np.load('dataset_roi.npz')
table = data['table_xy_g1_g2']

def bg_v(v, N):
    ''' Функция вычисляет самый фон картины с учетом выбросов 
    '''

    sorted_v = np.sort(v)
    
    min_x = sorted_v[N]
    max_x = sorted_v[-1 - N]

    bg = (max_x + min_x) / 2.0
    
    return bg

def show_max_xy(table):
    """Показывает максимумы x и y"""
    x = table[:, 0]
    y = table[:, 1]
    
    print("\n" + "="*40)
    print("Максимум")
    print("="*40)
    print(f"Максимум x: {x.max()}")
    print(f"Максимум y: {y.max()}")
    print()


def plot_v(table):
    
    x_raw = table[:, 0]
    y_raw = table[:, 1]
    vx_raw = table[:, 2].copy()
    vy_raw = table[:, 3].copy()
    vx_bg = bg_v(vx_raw, 9)
    vy_bg = bg_v(vy_raw, 9)
      
    vx_raw = vx_raw - vx_bg
    
    vy_raw = vy_raw - vy_bg

    step = 15
    x = x_raw[::step]
    y = y_raw[::step]
    vx = vx_raw[::step] / 80 
    vy = vy_raw[::step] / 80 


    # СОЗДАЕМ ГРАФИК
    plt.figure(figsize=(12, 10))

    # Рисуем векторы
    plt.quiver(x, y, vx, vy, 
               color='red', 
               scale=70,  # регулирует длину стрелок
               width=0.002,
               alpha=0.7)
    
    plt.title('Векторное поле намагниченности')
    plt.xlabel('x, пиксели')
    plt.ylabel('y, пиксели')
    plt.gca().set_aspect('equal')
    plt.grid(True, alpha=0.3)
    plt.tight_layout()
    plt.savefig('vector_field_processed.png', dpi=150)
    plt.show()
    
    print(f"Построено {len(x)} векторов")
    print("График сохранен в vector_field_processed.png")


def save_original_table(table):
    """Сохраняет оригинальные значения таблицы в CSV файл"""
    np.savetxt('original_table.csv', table, delimiter=',', 
               header='x,y,g1,g2', fmt='%d')
    print("\n" + "="*40)
    print("Сохранение оригинальных значений")
    print("="*40)
    print("Таблица сохранена в original_table.csv")
    print(f"Формат: x, y, g1 (long), g2 (trans)")
    print(f"Всего строк: {len(table)}")
    print()


def show_menu():
    """Показывает меню и возвращает выбор пользователя"""
    print("\n" + "="*40)
    print("МЕНЮ ПРОГРАММЫ")
    print("="*40)
    print("1 - Построить векторное поле (plot_v)")
    print("2 - Сохранить оригинальную таблицу в CSV")
    print("3 - Показать максимумы x и y")
    print("0 - Выход")
    print("-"*40)
    
    choice = input("Ваш выбор: ")
    return choice


def main():
    while True:
        choice = show_menu()
        
        if choice == '1':
            plot_v(table)
        elif choice == '2':
            save_original_table(table)
        elif choice == '3':
            show_max_xy(table)
        elif choice == '0':
            print("Выход из программы...")
            break
        else:
            print("Неверный ввод. Пожалуйста, выберите 0-3.")
        
        input("\nНажмите Enter чтобы продолжить...")
    
    # Закрываем файл с данными
    data.close()


if __name__ == "__main__":
    main()