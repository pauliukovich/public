#!/bin/bash

# Функция для вывода свободного места
check_space() {
    echo "--- Свободное место ---"
    df -h | grep '^/'
}

echo "--- Меню глубокой очистки системы ---"
check_space
echo ""
echo "1) Очистить кэш APT (скачанные .deb пакеты)"
echo "2) Удалить ненужные зависимости (autoremove)"
echo "3) Очистить кэш эскизов (thumbnails - часто съедает место)"
echo "4) Урезать системные логи (оставить последние 100MB)"
echo "5) Полная очистка (все пункты)"
echo "0) Выход"
read -p "Выберите действие: " choice

case $choice in
    1) sudo apt-get clean && echo "Кэш APT очищен." ;;
    2) sudo apt-get autoremove -y && echo "Зависимости удалены." ;;
    3) rm -rf ~/.cache/thumbnails/* && echo "Кэш эскизов очищен." ;;
    4) sudo journalctl --vacuum-size=100M && echo "Логи урезаны до 100MB." ;;
    5) 
        sudo apt-get clean && sudo apt-get autoremove -y
        rm -rf ~/.cache/thumbnails/*
        sudo journalctl --vacuum-size=100M
        echo "Полная очистка завершена!"
        ;;
    0) exit ;;
    *) echo "Неверный выбор." ;;
esac

check_space
read -p "Нажмите Enter для выхода..."
