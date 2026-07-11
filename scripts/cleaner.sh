#!/bin/bash

# ============================================================
#  ХИРУРГ СИСТЕМЫ v2.1 — безопасная очистка + точки восстановления
#  Debian 13 / Proxmox
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

RESTORE_DIR="/var/backups/system-surgeon"

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
    echo "  ║           🩺  ХИРУРГ СИСТЕМЫ  v2.1               ║"
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

# ---------- Точки восстановления ----------
detect_lvm_root() {
    local src
    src=$(df --output=source / 2>/dev/null | tail -1)
    echo "$src" | grep -q "/dev/mapper/" && \
    lvs --noheadings -o vg_name,lv_name "$src" 2>/dev/null
}

create_restore_point() {
    echo ""
    echo -e "${MAGENTA}${BOLD}[💾] Создание точки восстановления${NC}"
    echo -e "${GRAY}   ────────────────────────────────────────────${NC}"

    sudo mkdir -p "$RESTORE_DIR"
    local ts
    ts=$(date +%Y%m%d_%H%M%S)
    local point_dir="$RESTORE_DIR/$ts"
    sudo mkdir -p "$point_dir"

    echo -e "${WHITE}   Метка точки:${NC} ${LGREEN}$ts${NC}"

    local lvinfo
    lvinfo=$(detect_lvm_root)
    if [ -n "$lvinfo" ]; then
        local vg lv
        vg=$(echo "$lvinfo" | awk '{print $1}')
        lv=$(echo "$lvinfo" | awk '{print $2}')
        echo -e "${WHITE}   Обнаружен LVM том:${NC} $vg/$lv"
        read -p "$(echo -e ${YELLOW}"   Создать LVM snapshot тома (рекомендуется)? [Y/n]: "${NC})" use_lvm
        if [[ "$use_lvm" != "n" && "$use_lvm" != "N" ]]; then
            local snap_name="snap_${lv}_${ts}"
            if sudo lvcreate -L 2G -s -n "$snap_name" "/dev/$vg/$lv" > /tmp/lvm_log_$$.txt 2>&1; then
                echo "$vg/$snap_name" | sudo tee "$point_dir/lvm_snapshot.txt" > /dev/null
                echo -e "   ${GREEN}✔ LVM snapshot создан:${NC} $vg/$snap_name"
            else
                echo -e "   ${LRED}✘ Не удалось создать LVM snapshot${NC} (см. /tmp/lvm_log_$$.txt), продолжаем без него"
            fi
        fi
    fi

    echo -e "${WHITE}   Сохраняю /etc...${NC}"
    sudo tar -czf "$point_dir/etc-backup.tar.gz" -C / etc 2>/tmp/etc_log_$$.txt
    rm -f /tmp/etc_log_$$.txt

    echo -e "${WHITE}   Сохраняю список пакетов dpkg...${NC}"
    dpkg --get-selections | sudo tee "$point_dir/dpkg-selections.txt" > /dev/null

    echo -e "${WHITE}   Сохраняю список ядер...${NC}"
    dpkg --list | awk '/^ii  linux-image-[0-9]/{print $2}' | sudo tee "$point_dir/kernels.txt" > /dev/null

    echo -e "${WHITE}   Сохраняю снимок Docker (если есть)...${NC}"
    if command -v docker >/dev/null 2>&1; then
        docker ps -a --format '{{.Names}}\t{{.Image}}' | sudo tee "$point_dir/docker-containers.txt" > /dev/null
    fi

    echo "$(date)" | sudo tee "$point_dir/created_at.txt" > /dev/null

    echo ""
    echo -e "   ${GREEN}✔ Точка восстановления создана:${NC} ${LGREEN}${BOLD}$point_dir${NC}"
}

list_restore_points() {
    sudo mkdir -p "$RESTORE_DIR"
    local points
    points=$(ls -1 "$RESTORE_DIR" 2>/dev/null | sort -r)
    if [ -z "$points" ]; then
        echo -e "   ${GRAY}Точек восстановления пока нет.${NC}"
        return 1
    fi
    echo -e "${WHITE}   Доступные точки восстановления:${NC}"
    local i=0
    while IFS= read -r p; do
        i=$((i+1))
        local created
        created=$(sudo cat "$RESTORE_DIR/$p/created_at.txt" 2>/dev/null)
        echo -e "     ${CYAN}$i)${NC} $p ${DIM}($created)${NC}"
    done <<< "$points"
}

rollback_restore_point() {
    echo ""
    echo -e "${MAGENTA}${BOLD}[⏪] Откат к точке восстановления${NC}"
    echo -e "${GRAY}   ────────────────────────────────────────────${NC}"

    sudo mkdir -p "$RESTORE_DIR"
    local points
    points=$(ls -1 "$RESTORE_DIR" 2>/dev/null | sort -r)
    if [ -z "$points" ]; then
        echo -e "   ${LRED}Точек восстановления нет. Сначала создайте её (пункт 14).${NC}"
        return
    fi

    local arr=()
    local i=0
    while IFS= read -r p; do
        i=$((i+1))
        arr+=("$p")
        local created
        created=$(sudo cat "$RESTORE_DIR/$p/created_at.txt" 2>/dev/null)
        echo -e "     ${CYAN}$i)${NC} $p ${DIM}($created)${NC}"
    done <<< "$points"

    read -p "$(echo -e ${YELLOW}"   Номер точки для отката (0 - отмена): "${NC})" idx
    [ "$idx" = "0" ] && return
    local chosen="${arr[$((idx-1))]}"
    if [ -z "$chosen" ]; then
        echo -e "   ${LRED}Неверный номер.${NC}"
        return
    fi

    local point_dir="$RESTORE_DIR/$chosen"
    echo ""
    echo -e "${RED}${BOLD}   ВНИМАНИЕ: это восстановит /etc и список пакетов на момент $chosen${NC}"
    read -p "$(echo -e ${YELLOW}"   Подтвердите откат [y/N]: "${NC})" confirm
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        echo -e "   ${GRAY}Отменено.${NC}"
        return
    fi

    if [ -f "$point_dir/lvm_snapshot.txt" ]; then
        local snap
        snap=$(cat "$point_dir/lvm_snapshot.txt")
        echo -e "${WHITE}   Обнаружен LVM snapshot:${NC} $snap"
        echo -e "   ${YELLOW}Для полного отката корневого тома через LVM snapshot требуется${NC}"
        echo -e "   ${YELLOW}загрузка с Live-CD/rescue и выполнение lvconvert --merge.${NC}"
        echo -e "   ${YELLOW}Автоматический merge на работающей системе невозможен для root-тома.${NC}"
        echo -e "   ${GRAY}Snapshot сохранён и доступен: $snap${NC}"
    fi

    if [ -f "$point_dir/etc-backup.tar.gz" ]; then
        echo -e "${WHITE}   Восстанавливаю /etc...${NC}"
        sudo tar -xzf "$point_dir/etc-backup.tar.gz" -C / 2>/tmp/restore_log_$$.txt &
        local pid=$!
        spinner "$pid"
        wait "$pid"
        rm -f /tmp/restore_log_$$.txt
        echo -e "   ${GREEN}✔ /etc восстановлен${NC}"
    fi

    if [ -f "$point_dir/dpkg-selections.txt" ]; then
        echo -e "${WHITE}   Восстанавливаю список пакетов dpkg...${NC}"
        read -p "$(echo -e ${YELLOW}"   Выполнить apt-get dselect-upgrade для установки/удаления пакетов? [y/N]: "${NC})" do_pkgs
        if [[ "$do_pkgs" == "y" || "$do_pkgs" == "Y" ]]; then
            sudo dpkg --set-selections < "$point_dir/dpkg-selections.txt"
            sudo apt-get dselect-upgrade -y
        fi
    fi

    echo ""
    echo -e "${LGREEN}${BOLD}   ✔ ОТКАТ ЗАВЕРШЁН${NC}"
    echo -e "${YELLOW}   Рекомендуется перезагрузить систему.${NC}"
}

delete_restore_point() {
    echo ""
    echo -e "${MAGENTA}${BOLD}[🗑️ ] Удаление точки восстановления${NC}"
    echo -e "${GRAY}   ────────────────────────────────────────────${NC}"

    sudo mkdir -p "$RESTORE_DIR"
    local points
    points=$(ls -1 "$RESTORE_DIR" 2>/dev/null | sort -r)
    if [ -z "$points" ]; then
        echo -e "   ${GRAY}Точек восстановления нет.${NC}"
        return
    fi

    local arr=()
    local i=0
    while IFS= read -r p; do
        i=$((i+1))
        arr+=("$p")
        echo -e "     ${CYAN}$i)${NC} $p"
    done <<< "$points"

    read -p "$(echo -e ${YELLOW}"   Номер точки для удаления (0 - отмена): "${NC})" idx
    [ "$idx" = "0" ] && return
    local chosen="${arr[$((idx-1))]}"
    [ -z "$chosen" ] && { echo -e "   ${LRED}Неверный номер.${NC}"; return; }

    local point_dir="$RESTORE_DIR/$chosen"
    if [ -f "$point_dir/lvm_snapshot.txt" ]; then
        local snap
        snap=$(cat "$point_dir/lvm_snapshot.txt")
        read -p "$(echo -e ${YELLOW}"   Удалить также LVM snapshot $snap? [y/N]: "${NC})" del_lvm
        if [[ "$del_lvm" == "y" || "$del_lvm" == "Y" ]]; then
            sudo lvremove -f "/dev/$snap" 2>/dev/null
        fi
    fi
    sudo rm -rf "$point_dir"
    echo -e "   ${GREEN}✔ Точка $chosen удалена.${NC}"
}

restore_points_menu() {
    while true; do
        echo ""
        echo -e "${WHITE}${BOLD}   Управление точками восстановления:${NC}"
        list_restore_points
        echo ""
        echo -e "   ${CYAN}1)${NC} Создать новую точку"
        echo -e "   ${CYAN}2)${NC} Откатиться к точке"
        echo -e "   ${CYAN}3)${NC} Удалить точку"
        echo -e "   ${CYAN}0)${NC} Назад"
        read -p "$(echo -e ${WHITE}${BOLD}"   Выбор: "${NC})" sub
        case $sub in
            1) create_restore_point ;;
            2) rollback_restore_point ;;
            3) delete_restore_point ;;
            0) return ;;
            *) echo -e "${LRED}   Неверный выбор!${NC}" ;;
        esac
    done
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
        echo -e "  ${CYAN}14)${NC} 💾  ${BOLD}Точки восстановления (создать/откат/удалить)${NC}"
        echo ""
        echo -e "   ${LGREEN}${BOLD}14${NC}${GRAY} <- создайте точку ${NC}${GRAY}перед${NC} ${MAGENTA}${BOLD}99${NC}${GRAY} для безопасности${NC}"
        echo -e "  ${MAGENTA}${BOLD}99)${NC} 🩺  ${BOLD}ПОЛНАЯ ОЧИСТКА (все безопасные пункты)${NC}"
        echo -e "   ${RED}0)${NC}  Выход"
        echo -e "${BROWN}  ────────────────────────────────────────────────────${NC}"
        read -p "$(echo -e ${WHITE}${BOLD}"  Ваш выбор [0-14, 99]: "${NC})" choice

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
            14) restore_points_menu ;;
            99)
                read -p "$(echo -e ${YELLOW}"   Создать точку восстановления перед очисткой? [Y/n]: "${NC})" pre_snap
                if [[ "$pre_snap" != "n" && "$pre_snap" != "N" ]]; then
                    create_restore_point
                fi
                full_clean
                ;;
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
