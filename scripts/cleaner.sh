#!/bin/bash

# Цвета для вывода
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Функция очистки с проверкой места до и после
clean_action() {
    local task_name=$1
    local cmd=$2
    
    echo -e "${YELLOW}[+] Запуск: $task_name...${NC}"
    
    # Считаем место до
    local space_before=$(df -h / | awk 'NR==2 {print $4}')
    
    # Выполняем команду
    if eval "$cmd"; then
        local space_after=$(df -h / | awk 'NR==2 {print $4}')
        echo -e "${GREEN}[OK] Действие завершено. Свободно: $space_before -> $space_after${NC}"
    else
        echo -e "${RED}[ERROR] Ошибка при выполнении $task_name${NC}"
    fi
}

menu() {
    while true; do
        clear
        echo -e "${YELLOW}--- СИСТЕМА ОЧИСТКИ (Proxmox) ---${NC}"
        df -h | grep '^/'
        echo -e "\n1) Очистить кэш APT"
        echo "2) Удалить ненужные зависимости (autoremove)"
        echo "3) Очистить кэш эскизов (thumbnails)"
        echo "4) Урезать системные логи (до 100MB)"
        echo "5) ПОЛНАЯ ОЧИСТКА (все пункты)"
        echo "0) Выход"
        read -p "Выберите действие [0-5]: " choice

        case $choice in
            1) clean_action "Очистка кэша APT" "sudo apt-get clean" ;;
            2) clean_action "Удаление зависимостей" "sudo apt-get autoremove -y" ;;
            3) clean_action "Очистка эскизов" "rm -rf ~/.cache/thumbnails/*" ;;
            4) clean_action "Урезание логов" "sudo journalctl --vacuum-size=100M" ;;
            5) 
                clean_action "APT" "sudo apt-get clean"
                clean_action "Autoremove" "sudo apt-get autoremove -y"
                clean_action "Thumbnails" "rm -rf ~/.cache/thumbnails/*"
                clean_action "Logs" "sudo journalctl --vacuum-size=100M"
                ;;
            0) echo "Выход..."; exit ;;
            *) echo -e "${RED}Неверный выбор!${NC}" ;;
        esac
        read -p "Нажмите Enter, чтобы вернуться в меню..."
    done
}

menu
