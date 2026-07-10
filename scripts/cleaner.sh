#!/bin/bash

# ============================================================
#  ХИРУРГ СИСТЕМЫ v2.0 — безопасная очистка Debian 13 / Proxmox
# ============================================================

# ---------- Цвета ----------
GREEN='\033[0;32m'
LGREEN='\033[1;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
LRED='\033[1;31m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
BROWN='\033[0;33m'
WHITE='\033[1;37m'
GRAY='\033[1;30m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

# ---------- Спиннер ----------
spinner() {
    local pid=$1
    local delay=0.08
    local spinstr='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
    local i=0
    while kill -0 "$pid" 2>/dev/null; do
        i=$(( (i+1) % ${#spinstr} ))
        printf "\r${CYAN}   %s${NC} ${DIM}обработка...${NC}" "${spinstr:$i:1}"
        sleep $delay
    done
    printf "\r"
}

# ---------- Прогресс-бар ----------
progress_bar() {
    local percent=$1
    local width=30
    local filled=$(( percent * width / 100 ))
    local empty=$(( width - filled ))
    printf "${GRAY}["
    printf "${LGREEN}%0.s█" $(seq 1 $filled) 2>/dev/null
    printf "${GRAY}%0.s░" $(seq 1 $empty) 2>/dev/null
    printf "${GRAY}]${NC} ${BOLD}%d%%${NC}" "$percent"
}

# ---------- Получение свободного места в байтах ----------
get_free_bytes() {
    df --output=avail -B1 / | tail -1 | tr -d ' '
}

human_size() {
    numfmt --to=iec --suffix=B "$1" 2>/dev/null || echo "${1}B"
}

# ---------- Основная функция действия ----------
clean_action() {
    local task_name=$1
    local cmd=$2
    local icon=${3:-"🧹"}

    echo ""
    echo -e "${YELLOW}${BOLD}[+] ${icon}  Запуск: ${task_name}...${NC}"

    local before=$(get_free_bytes)

    ( eval "$cmd" > /tmp/clean_log_$$.txt 2>&1 ) &
    local pid=$!
    spinner "$pid"
    wait "$pid"
    local status=$?

    local after=$(get_free_bytes)
    local diff=$(( after - before ))

    if [ $status -eq 0 ]; then
        echo -ne "   "
        progress_bar 100
        echo ""
        if [ "$diff" -gt 0 ]; then
            echo -e "   ${GREEN}✔ Готово.${NC} Освобождено: ${LGREEN}${BOLD}$(human_size $diff)${NC}"
        else
            echo -e "   ${GREEN}✔ Готово.${NC} ${DIM}(мусора для этого шага не найдено)${NC}"
        fi
        echo -e "   ${DIM}Свободно на /: $(human_size $before) -> $(human_size $after)${NC}"
    else
        echo -e "   ${LRED}✘ ОШИБКА${NC} при выполнении: ${task_name}"
        echo -e "   ${GRAY}Подробности: /tmp/clean_log_$$.txt${NC}"
    fi
    rm -f /tmp/clean_log_$$.txt
}

# ---------- Заголовок с иллюстрацией ----------
draw_header() {
    clear
    local free=$(df -h / | awk 'NR==2 {print $4}')
    local used_pct=$(df / | awk 'NR==2 {print $5}' | tr -d '%')
    echo -e "${CYAN}${BOLD}"
    echo "  ╔══════════════════════════════════════════════════╗"
    echo "  ║           🩺  ХИРУРГ СИСТЕМЫ  v2.0               ║"
    echo "  ║        Debian 13 / Proxmox — безопасная чистка   ║"
    echo "  ╚══════════════════════════════════════════════════╝"
    echo -e "${NC}"
    echo -e "  ${WHITE}Диск /:${NC} свободно ${LGREEN}${BOLD}${free}${NC}   ${DIM}(занято ${used_pct}%)${NC}"
    echo -ne "  "
    progress_bar "$used_pct"
    echo -e "\n"
    echo -e "${BROWN}  ────────────────────────────────────────────────────${NC}"
}

# ---------- Безопасное удаление старых ядер ----------
clean_kernels() {
    echo ""
    echo -e "${YELLOW}${BOLD}[+] 🧬  Поиск старых ядер...${NC}"
    local current
    current=$(uname -r)
    local list
    list=$(dpkg --list | awk '/^ii  linux-image-[0-9]/{print $2}' | grep -v "$current")

    if [ -z "$list" ]; then
        echo -e "   ${GREEN}✔ Старых ядер не найдено. Система чистая.${NC}"
        return
    fi

    echo -e "   ${WHITE}Текущее ядро (не будет тронуто):${NC} ${LGREEN}${current}${NC}"
    echo -e "   ${WHITE}Найдены старые ядра:${NC}"
    echo "$list" | while read -r pkg; do
        echo -e "     ${RED}✘${NC} $pkg"
    done
    echo ""
    read -p "$(echo -e ${YELLOW}"   Удалить перечисленные ядра? [y/N]: "${NC})" confirm
    if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
        clean_action "Удаление старых ядер" "echo \"$list\" | xargs -r sudo apt-get purge -y" "🧬"
    else
        echo -e "   ${GRAY}Отменено пользователем.${NC}"
    fi
}

# ---------- Аудит безопасности (только отчёт, без удаления) ----------
security_audit() {
    echo ""
    echo -e "${MAGENTA}${BOLD}[🔍] Аудит небезопасно хранящихся файлов (без удаления)${NC}"
    echo -e "${GRAY}   ────────────────────────────────────────────${NC}"

    echo -e "${WHITE}   > Файлы с правами 777 в /etc:${NC}"
    sudo find /etc -xdev -perm -0777 -type f 2>/dev/null | sed 's/^/     ⚠ /' | head -20
    echo -e "${DIM}     (показаны первые 20 совпадений)${NC}"

    echo -e "${WHITE}   > Возможные пароли/секреты в конфигах (грубый поиск):${NC}"
    sudo grep -RIl -E "password\s*=|passwd\s*=|secret\s*=" /etc 2>/dev/null | sed 's/^/     ⚠ /' | head -20

    echo -e "${WHITE}   > SUID/SGID бинарники вне стандартных пакетов:${NC}"
    sudo find / -xdev -type f \( -perm -4000 -o -perm -2000 \) 2>/dev/null | sed 's/^/     ⚠ /' | head -20

    echo ""
    echo -e "${YELLOW}   Это только отчёт. Ничего не было удалено автоматически.${NC}"
}

# ---------- Полная очистка с общим прогрессом ----------
full_clean() {
    local steps=(
        "APT Cache|sudo apt-get clean|📦"
        "Autoremove|sudo apt-get autoremove -y|🧹"
        "Autoclean|sudo apt-get autoclean -y|📦"
        "Thumbnails|rm -rf ~/.cache/thumbnails/*|🖼️"
        "Journal Logs|sudo journalctl --vacuum-size=100M|📜"
        "Tmp Files|sudo find /tmp -type f -atime +3 -delete 2>/dev/null; sudo find /var/tmp -type f -atime +3 -delete 2>/dev/null|🗑️"
        "Orphaned Configs|sudo dpkg -l | awk '/^rc/ {print \$2}' | xargs -r sudo dpkg --purge|🧩"
        "Core Dumps|sudo rm -rf /var/crash/*; sudo find / -xdev -name 'core.*' -type f -delete 2>/dev/null|💥"
        "Editor Swap Files|sudo find / -xdev \( -name '*.swp' -o -name '*~' \) -type f -delete 2>/dev/null|✏️"
        "Old .deb Archives|sudo rm -f /var/cache/apt/archives/*.deb|📦"
        "Fix Broken|sudo apt-get install -f -y|🔧"
        "Docker Prune|command -v docker >/dev/null 2>&1 && docker system prune -f || true|🐳"
    )
    local total=${#steps[@]}
    local i=0
    for step in "${steps[@]}"; do
        i=$((i+1))
        IFS='|' read -r name cmd icon <<< "$step"
        echo -e "${GRAY}   Шаг $i из $total${NC}"
        clean_action "$name" "$cmd" "$icon"
    done
    echo ""
    clean_kernels
    echo ""
    echo -e "${LGREEN}${BOLD}   ══════════════════════════════════════${NC}"
    echo -e "${LGREEN}${BOLD}    ✔ ПОЛНАЯ ОЧИСТКА ЗАВЕРШЕНА              ${NC}"
    echo -e "${LGREEN}${BOLD}   ══════════════════════════════════════${NC}"
}

# ---------- Меню ----------
menu() {
    while true; do
        draw_header
        echo -e "  ${WHITE}${BOLD}Выберите действие:${NC}"
        echo ""
        echo -e "   ${CYAN}1)${NC} 📦  Очистить кэш APT"
        echo -e "   ${CYAN}2)${NC} 🧹  Autoremove (ненужные зависимости)"
        echo -e "   ${CYAN}3)${NC} 🖼️   Очистить кэш эскизов"
        echo -e "   ${CYAN}4)${NC} 📜  Урезать логи journald (до 100MB)"
        echo -e "   ${CYAN}5)${NC} 🧬  Безопасно удалить старые ядра"
        echo -e "   ${CYAN}6)${NC} 🔧  Исправить битые пакеты (apt -f)"
        echo -e "   ${CYAN}7)${NC} 🐳  Очистить Docker (системный кэш)"
        echo -e "   ${CYAN}8)${NC} 🗑️   Очистить /tmp и /var/tmp (старше 3 дн.)"
        echo -e "   ${CYAN}9)${NC} 🧩  Удалить orphaned config (rc-пакеты)"
        echo -e "  ${CYAN}10)${NC} 💥  Очистить core dumps / crash-репорты"
        echo -e "  ${CYAN}11)${NC} ✏️   Удалить editor swap-файлы (*.swp, *~)"
        echo -e "  ${CYAN}12)${NC} 📦  Удалить старые .deb из кэша apt"
        echo -e "  ${CYAN}13)${NC} 🔍  Аудит небезопасных файлов ${DIM}(без удаления)${NC}"
        echo ""
        echo -e "   ${LGREEN}${BOLD}8${NC}${GRAY} <- используйте пункт${NC} ${MAGENTA}${BOLD}99${NC} ${GRAY}для полной очистки${NC}"
        echo -e "  ${MAGENTA}${BOLD}99)${NC} 🩺  ${BOLD}ПОЛНАЯ ОЧИСТКА (все безопасные пункты)${NC}"
        echo -e "   ${RED}0)${NC}  Выход"
        echo -e "${BROWN}  ────────────────────────────────────────────────────${NC}"
        read -p "$(echo -e ${WHITE}${BOLD}"  Ваш выбор [0-13, 99]: "${NC})" choice

        case $choice in
            1) clean_action "APT Cache" "sudo apt-get clean" "📦" ;;
            2) clean_action "Autoremove" "sudo apt-get autoremove -y" "🧹" ;;
            3) clean_action "Thumbnails" "rm -rf ~/.cache/thumbnails/*" "🖼️" ;;
            4) clean_action "Journal Logs" "sudo journalctl --vacuum-size=100M" "📜" ;;
            5) clean_kernels ;;
            6) clean_action "Fix Broken" "sudo apt-get install -f -y" "🔧" ;;
            7) clean_action "Docker" "command -v docker >/dev/null 2>&1 && docker system prune -f || echo 'Docker не установлен'" "🐳" ;;
            8) clean_action "Tmp Files" "sudo find /tmp -type f -atime +3 -delete 2>/dev/null; sudo find /var/tmp -type f -atime +3 -delete 2>/dev/null" "🗑️" ;;
            9) clean_action "Orphaned Configs" "sudo dpkg -l | awk '/^rc/ {print \$2}' | xargs -r sudo dpkg --purge" "🧩" ;;
            10) clean_action "Core Dumps" "sudo rm -rf /var/crash/*; sudo find / -xdev -name 'core.*' -type f -delete 2>/dev/null" "💥" ;;
            11) clean_action "Editor Swap Files" "sudo find / -xdev \( -name '*.swp' -o -name '*~' \) -type f -delete 2>/dev/null" "✏️" ;;
            12) clean_action "Old .deb Archives" "sudo rm -f /var/cache/apt/archives/*.deb" "📦" ;;
            13) security_audit ;;
            99) full_clean ;;
            0)
                echo ""
                echo -e "${LGREEN}${BOLD}  Работа завершена. Система в порядке. 👋${NC}"
                echo ""
                exit ;;
            *) echo -e "${LRED}  Неверный выбор!${NC}" ;;
        esac

        echo ""
        read -p "$(echo -e ${GRAY}"  Нажмите Enter, чтобы вернуться в меню..."${NC})"
    done
}

menu
