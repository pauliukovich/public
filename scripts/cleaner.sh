#!/bin/bash

# Цвета
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' 

clean_action() {
    local task_name=$1
    local cmd=$2
    
    echo -e "${YELLOW}[+] Запуск: $task_name...${NC}"
    local space_before=$(df -h / | awk 'NR==2 {print $4}')
    
    if eval "$cmd" > /dev/null 2>&1; then
        local space_after=$(df -h / | awk 'NR==2 {print $4}')
        echo -e "${GREEN}[OK] Действие завершено. Свободно: $space_before -> $space_after${NC}"
    else
        echo -e "${RED}[ERROR] Ошибка при выполнении $task_name${NC}"
    fi
}

menu() {
    while true; do
        clear
        echo -e "${BLUE}=== ХИРУРГ СИСТЕМЫ (Proxmox/Debian) ===${NC}"
        echo -e "Свободно на / : ${GREEN}$(df -h / | awk 'NR==2 {print $4}')${NC}"
        echo "----------------------------------------"
        echo "1) Очистить кэш APT"
        echo "2) Удалить ненужные зависимости (autoremove)"
        echo "3) Очистить кэш эскизов"
        echo "4) Урезать логи (до 100MB)"
        echo "5) Удалить старые ядра"
        echo "6) Исправить битые пакеты (apt -f)"
        echo "7) Очистить Docker (системный кэш)"
        echo "8) ПОЛНАЯ ОЧИСТКА (все пункты)"
        echo "0) Выход"
        echo "----------------------------------------"
        read -p "Выберите действие [0-8]: " choice

        case $choice in
            1) clean_action "APT Cache" "sudo apt-get clean" ;;
            2) clean_action "Autoremove" "sudo apt-get autoremove -y" ;;
            3) clean_action "Thumbnails" "rm -rf ~/.cache/thumbnails/*" ;;
            4) clean_action "Journal Logs" "sudo journalctl --vacuum-size=100M" ;;
            5) clean_action "Old Kernels" "sudo apt-get autoremove --purge -y" ;;
            6) clean_action "Fix Broken" "sudo apt-get install -f -y" ;;
            7) clean_action "Docker" "docker system prune -f" ;;
            8) 
                clean_action "APT" "sudo apt-get clean"
                clean_action "Autoremove" "sudo apt-get autoremove -y"
                clean_action "Thumbnails" "rm -rf ~/.cache/thumbnails/*"
                clean_action "Logs" "sudo journalctl --vacuum-size=100M"
                clean_action "Kernels" "sudo apt-get autoremove --purge -y"
                clean_action "Docker" "docker system prune -f"
                ;;
            0) echo -e "${GREEN}Работа завершена.${NC}"; exit ;;
            *) echo -e "${RED}Неверный выбор!${NC}" ;;
        esac
        read -p "Нажмите Enter, чтобы вернуться в меню..."
    done
}

menu
