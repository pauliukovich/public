#!/bin/bash

# ============================================================
#  BACKUP MANAGER v1.0 — управление бэкапами через Timeshift
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

TIMESHIFT_CONF="/etc/timeshift/timeshift.json"

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

human_size() {
    numfmt --to=iec --suffix=B "$1" 2>/dev/null || echo "${1}B"
}

# ---------- Заголовок ----------
draw_header() {
    clear
    local free=$(df -h / | awk 'NR==2 {print $4}')
    echo -e "${CYAN}${BOLD}"
    echo "  ╔══════════════════════════════════════════════════╗"
    echo "  ║         💾  BACKUP MANAGER  v1.0                 ║"
    echo "  ║          Timeshift — управление бэкапами         ║"
    echo "  ╚══════════════════════════════════════════════════╝"
    echo -e "${NC}"
    echo -e "  ${WHITE}Диск /:${NC} свободно ${LGREEN}${BOLD}${free}${NC}"
    if command -v timeshift >/dev/null 2>&1; then
        echo -e "  ${WHITE}Timeshift:${NC} ${GREEN}установлен${NC}"
    else
        echo -e "  ${WHITE}Timeshift:${NC} ${LRED}не установлен${NC}"
    fi
    echo -e "${BROWN}  ────────────────────────────────────────────────────${NC}"
}

# ---------- Проверка и установка Timeshift ----------
check_timeshift() {
    if ! command -v timeshift >/dev/null 2>&1; then
        echo ""
        echo -e "${YELLOW}${BOLD}   Timeshift не установлен.${NC}"
        read -p "$(echo -e ${YELLOW}"   Установить Timeshift сейчас? [Y/n]: "${NC})" install_confirm
        if [[ "$install_confirm" != "n" && "$install_confirm" != "N" ]]; then
            install_timeshift
        else
            return 1
        fi
    fi
    return 0
}

install_timeshift() {
    echo ""
    echo -e "${YELLOW}${BOLD}[+] 📥  Установка Timeshift...${NC}"
    ( sudo apt-get update && sudo apt-get install -y timeshift ) > /tmp/ts_install_log_$$.txt 2>&1 &
    local pid=$!
    spinner "$pid"
    wait "$pid"
    local status=$?
    if [ $status -eq 0 ] && command -v timeshift >/dev/null 2>&1; then
        echo -e "   ${GREEN}✔ Timeshift успешно установлен.${NC}"
        rm -f /tmp/ts_install_log_$$.txt
        first_time_setup
    else
        echo -e "   ${LRED}✘ Ошибка установки.${NC} Подробности: /tmp/ts_install_log_$$.txt"
    fi
}

# ---------- Первичная настройка ----------
first_time_setup() {
    echo ""
    echo -e "${MAGENTA}${BOLD}[⚙️ ] Первичная настройка Timeshift${NC}"
    echo -e "${GRAY}   ────────────────────────────────────────────${NC}"

    if [ -f "$TIMESHIFT_CONF" ]; then
        echo -e "   ${GREEN}Конфигурация уже существует, пропускаем.${NC}"
        return
    fi

    echo -e "${WHITE}   Выберите режим снапшотов:${NC}"
    echo -e "     ${CYAN}1)${NC} RSYNC ${DIM}(универсальный, работает на любой ФС, включая ext4)${NC}"
    echo -e "     ${CYAN}2)${NC} BTRFS ${DIM}(только если корень на BTRFS, быстрее и компактнее)${NC}"
    read -p "$(echo -e ${YELLOW}"   Выбор [1-2, по умолчанию 1]: "${NC})" mode_choice

    local fstype="rsync"
    local root_fs
    root_fs=$(df --output=fstype / | tail -1 | tr -d ' ')

    if [ "$mode_choice" = "2" ]; then
        if [ "$root_fs" != "btrfs" ]; then
            echo -e "   ${LRED}Корень не на BTRFS (обнаружено: $root_fs). Используем RSYNC.${NC}"
        else
            fstype="btrfs"
        fi
    fi

    echo -e "${WHITE}   Инициализация ($fstype)...${NC}"
    sudo timeshift --btrfs 2>/dev/null || true

    # Первый запуск через CLI создаёт базовый json конфиг
    sudo mkdir -p /etc/timeshift
    if [ ! -f "$TIMESHIFT_CONF" ]; then
        sudo tee "$TIMESHIFT_CONF" > /dev/null << EOF
{
  "backup_device_uuid" : "",
  "parent_device_uuid" : "",
  "do_first_run" : "false",
  "btrfs_mode" : "$([ "$fstype" = "btrfs" ] && echo true || echo false)",
  "include_btrfs_home_for_backup" : "false",
  "include_btrfs_home_for_restore" : "false",
  "stop_cron_emails" : "true",
  "schedule_monthly" : "false",
  "schedule_weekly" : "false",
  "schedule_daily" : "false",
  "schedule_hourly" : "false",
  "schedule_boot" : "false",
  "count_monthly" : "2",
  "count_weekly" : "3",
  "count_daily" : "5",
  "count_hourly" : "6",
  "count_boot" : "5",
  "snapshot_size" : "0",
  "snapshot_count" : "0",
  "exclude" : [],
  "exclude-apps" : []
}
EOF
    fi

    echo -e "   ${GREEN}✔ Базовая конфигурация создана.${NC}"
    echo -e "${YELLOW}   Рекомендуется указать место хранения снапшотов (пункт меню 8),${NC}"
    echo -e "${YELLOW}   если хотите хранить их не на корневом разделе.${NC}"
}

# ---------- Создание снапшота ----------
create_snapshot() {
    check_timeshift || return
    echo ""
    echo -e "${MAGENTA}${BOLD}[💾] Создание снапшота${NC}"
    echo -e "${GRAY}   ────────────────────────────────────────────${NC}"
    read -p "$(echo -e ${WHITE}"   Комментарий к снапшоту (можно оставить пустым): "${NC})" comment

    local before after diff
    before=$(df --output=avail -B1 / | tail -1 | tr -d ' ')

    echo -e "${WHITE}   Создаю снапшот...${NC}"
    if [ -n "$comment" ]; then
        sudo timeshift --create --comments "$comment" --yes > /tmp/ts_create_log_$$.txt 2>&1 &
    else
        sudo timeshift --create --yes > /tmp/ts_create_log_$$.txt 2>&1 &
    fi
    local pid=$!
    spinner "$pid"
    wait "$pid"
    local status=$?

    after=$(df --output=avail -B1 / | tail -1 | tr -d ' ')
    diff=$(( before - after ))

    if [ $status -eq 0 ]; then
        echo -e "   ${GREEN}✔ Снапшот успешно создан.${NC}"
        echo -e "   ${DIM}Занято на диске снапшотом: ~$(human_size $diff)${NC}"
    else
        echo -e "   ${LRED}✘ Ошибка создания снапшота.${NC}"
        echo -e "   ${GRAY}Подробности:${NC}"
        tail -15 /tmp/ts_create_log_$$.txt | sed 's/^/     /'
    fi
    rm -f /tmp/ts_create_log_$$.txt
}

# ---------- Список снапшотов ----------
list_snapshots() {
    check_timeshift || return
    echo ""
    echo -e "${MAGENTA}${BOLD}[📋] Список снапшотов${NC}"
    echo -e "${GRAY}   ────────────────────────────────────────────${NC}"
    sudo timeshift --list 2>/dev/null | sed 's/^/   /'
}

# ---------- Получить массив снапшотов (для выбора) ----------
get_snapshot_array() {
    sudo timeshift --list 2>/dev/null | grep -E "^\s*[0-9]+\s*>" | awk -F">" '{print $2}' | awk '{print $1}'
}

# ---------- Восстановление снапшота ----------
restore_snapshot() {
    check_timeshift || return
    echo ""
    echo -e "${MAGENTA}${BOLD}[⏪] Восстановление из снапшота${NC}"
    echo -e "${GRAY}   ────────────────────────────────────────────${NC}"

    list_snapshots

    local snaps=()
    local i=0
    while IFS= read -r s; do
        [ -z "$s" ] && continue
        i=$((i+1))
        snaps+=("$s")
    done < <(get_snapshot_array)

    if [ ${#snaps[@]} -eq 0 ]; then
        echo -e "   ${LRED}Снапшотов не найдено.${NC}"
        return
    fi

    echo ""
    echo -e "${WHITE}   Доступные снапшоты для восстановления:${NC}"
    local idx=0
    for s in "${snaps[@]}"; do
        idx=$((idx+1))
        echo -e "     ${CYAN}$idx)${NC} $s"
    done

    read -p "$(echo -e ${YELLOW}"   Номер снапшота для восстановления (0 - отмена): "${NC})" choice
    [ "$choice" = "0" ] && return
    local chosen="${snaps[$((choice-1))]}"
    if [ -z "$chosen" ]; then
        echo -e "   ${LRED}Неверный номер.${NC}"
        return
    fi

    echo ""
    echo -e "${RED}${BOLD}   ВНИМАНИЕ: Система будет восстановлена до состояния снапшота $chosen${NC}"
    echo -e "${RED}${BOLD}   Потребуется перезагрузка. Все изменения после этой точки будут потеряны.${NC}"
    read -p "$(echo -e ${YELLOW}"   Введите 'ПОДТВЕРЖДАЮ' для продолжения: "${NC})" confirm
    if [ "$confirm" != "ПОДТВЕРЖДАЮ" ]; then
        echo -e "   ${GRAY}Отменено.${NC}"
        return
    fi

    echo -e "${WHITE}   Запускаю восстановление...${NC}"
    echo -e "${YELLOW}   Timeshift запросит интерактивное подтверждение и может перезагрузить систему.${NC}"
    sudo timeshift --restore --snapshot "$chosen"
}

# ---------- Удаление снапшота ----------
delete_snapshot() {
    check_timeshift || return
    echo ""
    echo -e "${MAGENTA}${BOLD}[🗑️ ] Удаление снапшота${NC}"
    echo -e "${GRAY}   ────────────────────────────────────────────${NC}"

    list_snapshots

    local snaps=()
    local i=0
    while IFS= read -r s; do
        [ -z "$s" ] && continue
        i=$((i+1))
        snaps+=("$s")
    done < <(get_snapshot_array)

    if [ ${#snaps[@]} -eq 0 ]; then
        echo -e "   ${LRED}Снапшотов не найдено.${NC}"
        return
    fi

    echo ""
    local idx=0
    for s in "${snaps[@]}"; do
        idx=$((idx+1))
        echo -e "     ${CYAN}$idx)${NC} $s"
    done

    read -p "$(echo -e ${YELLOW}"   Номер снапшота для удаления (0 - отмена): "${NC})" choice
    [ "$choice" = "0" ] && return
    local chosen="${snaps[$((choice-1))]}"
    [ -z "$chosen" ] && { echo -e "   ${LRED}Неверный номер.${NC}"; return; }

    read -p "$(echo -e ${YELLOW}"   Удалить снапшот $chosen? [y/N]: "${NC})" confirm
    if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
        sudo timeshift --delete --snapshot "$chosen" --yes
        echo -e "   ${GREEN}✔ Снапшот удалён.${NC}"
    else
        echo -e "   ${GRAY}Отменено.${NC}"
    fi
}

# ---------- Настройка расписания ----------
configure_schedule() {
    check_timeshift || return
    if [ ! -f "$TIMESHIFT_CONF" ]; then
        first_time_setup
    fi

    echo ""
    echo -e "${MAGENTA}${BOLD}[⏰] Настройка расписания бэкапов${NC}"
    echo -e "${GRAY}   ────────────────────────────────────────────${NC}"
    echo -e "${WHITE}   Текущее расписание:${NC}"
    show_current_schedule
    echo ""
    echo -e "${WHITE}   Что настроить?${NC}"
    echo -e "     ${CYAN}1)${NC} Ежедневный бэкап"
    echo -e "     ${CYAN}2)${NC} Еженедельный бэкап"
    echo -e "     ${CYAN}3)${NC} Ежемесячный бэкап"
    echo -e "     ${CYAN}4)${NC} Ежечасный бэкап"
    echo -e "     ${CYAN}5)${NC} Бэкап при загрузке системы"
    echo -e "     ${CYAN}6)${NC} Отключить всё расписание"
    echo -e "     ${CYAN}0)${NC} Назад"
    read -p "$(echo -e ${YELLOW}"   Выбор: "${NC})" sched_choice

    case $sched_choice in
        1) toggle_schedule "daily" "Ежедневный" ;;
        2) toggle_schedule "weekly" "Еженедельный" ;;
        3) toggle_schedule "monthly" "Ежемесячный" ;;
        4) toggle_schedule "hourly" "Ежечасный" ;;
        5) toggle_schedule "boot" "При загрузке" ;;
        6) disable_all_schedules ;;
        0) return ;;
        *) echo -e "${LRED}   Неверный выбор!${NC}" ;;
    esac
}

show_current_schedule() {
    if [ ! -f "$TIMESHIFT_CONF" ]; then
        echo -e "     ${GRAY}Конфигурация не найдена.${NC}"
        return
    fi
    local daily weekly monthly hourly boot cd cw cm ch cb
    daily=$(grep -o '"schedule_daily" *: *"[^"]*"' "$TIMESHIFT_CONF" | grep -o 'true\|false')
    weekly=$(grep -o '"schedule_weekly" *: *"[^"]*"' "$TIMESHIFT_CONF" | grep -o 'true\|false')
    monthly=$(grep -o '"schedule_monthly" *: *"[^"]*"' "$TIMESHIFT_CONF" | grep -o 'true\|false')
    hourly=$(grep -o '"schedule_hourly" *: *"[^"]*"' "$TIMESHIFT_CONF" | grep -o 'true\|false')
    boot=$(grep -o '"schedule_boot" *: *"[^"]*"' "$TIMESHIFT_CONF" | grep -o 'true\|false')
    cd=$(grep -o '"count_daily" *: *"[0-9]*"' "$TIMESHIFT_CONF" | grep -o '[0-9]*')
    cw=$(grep -o '"count_weekly" *: *"[0-9]*"' "$TIMESHIFT_CONF" | grep -o '[0-9]*')
    cm=$(grep -o '"count_monthly" *: *"[0-9]*"' "$TIMESHIFT_CONF" | grep -o '[0-9]*')
    ch=$(grep -o '"count_hourly" *: *"[0-9]*"' "$TIMESHIFT_CONF" | grep -o '[0-9]*')
    cb=$(grep -o '"count_boot" *: *"[0-9]*"' "$TIMESHIFT_CONF" | grep -o '[0-9]*')

    print_status() {
        local name=$1 val=$2 cnt=$3
        if [ "$val" = "true" ]; then
            echo -e "     ${GREEN}✔ $name${NC} ${DIM}(хранить последних: $cnt)${NC}"
        else
            echo -e "     ${GRAY}✘ $name — выключено${NC}"
        fi
    }
    print_status "Ежечасный" "$hourly" "$ch"
    print_status "Ежедневный" "$daily" "$cd"
    print_status "Еженедельный" "$weekly" "$cw"
    print_status "Ежемесячный" "$monthly" "$cm"
    print_status "При загрузке" "$boot" "$cb"
}

toggle_schedule() {
    local key=$1
    local label=$2
    local current
    current=$(grep -o "\"schedule_${key}\" *: *\"[^\"]*\"" "$TIMESHIFT_CONF" | grep -o 'true\|false')

    if [ "$current" = "true" ]; then
        read -p "$(echo -e ${YELLOW}"   $label бэкап включён. Выключить? [y/N]: "${NC})" confirm
        if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
            sudo sed -i "s/\"schedule_${key}\" *: *\"true\"/\"schedule_${key}\" : \"false\"/" "$TIMESHIFT_CONF"
            echo -e "   ${GREEN}✔ $label бэкап выключен.${NC}"
        fi
    else
        read -p "$(echo -e ${YELLOW}"   Сколько последних снапшотов хранить для '$label'? [по умолчанию 5]: "${NC})" count
        count=${count:-5}
        sudo sed -i "s/\"schedule_${key}\" *: *\"false\"/\"schedule_${key}\" : \"true\"/" "$TIMESHIFT_CONF"
        sudo sed -i "s/\"count_${key}\" *: *\"[0-9]*\"/\"count_${key}\" : \"${count}\"/" "$TIMESHIFT_CONF"
        echo -e "   ${GREEN}✔ $label бэкап включён.${NC} ${DIM}Хранить: $count${NC}"
    fi
    sudo systemctl restart cron 2>/dev/null
}

disable_all_schedules() {
    read -p "$(echo -e ${YELLOW}"   Отключить всё автоматическое расписание? [y/N]: "${NC})" confirm
    if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
        for key in daily weekly monthly hourly boot; do
            sudo sed -i "s/\"schedule_${key}\" *: *\"true\"/\"schedule_${key}\" : \"false\"/" "$TIMESHIFT_CONF"
        done
        echo -e "   ${GREEN}✔ Всё расписание отключено.${NC}"
    fi
}

# ---------- Настройка места хранения ----------
configure_storage() {
    check_timeshift || return
    echo ""
    echo -e "${MAGENTA}${BOLD}[💽] Настройка устройства хранения снапшотов${NC}"
    echo -e "${GRAY}   ────────────────────────────────────────────${NC}"
    echo -e "${WHITE}   Доступные разделы:${NC}"
    lsblk -o NAME,SIZE,FSTYPE,MOUNTPOINT,UUID | sed 's/^/     /'
    echo ""
    read -p "$(echo -e ${WHITE}"   Введите UUID раздела для хранения снапшотов (Enter - оставить текущий): "${NC})" uuid
    if [ -n "$uuid" ]; then
        sudo sed -i "s/\"backup_device_uuid\" *: *\"[^\"]*\"/\"backup_device_uuid\" : \"${uuid}\"/" "$TIMESHIFT_CONF"
        echo -e "   ${GREEN}✔ Устройство хранения обновлено.${NC}"
    else
        echo -e "   ${GRAY}Оставлено без изменений.${NC}"
    fi
}

# ---------- Информация о занятом месте ----------
show_disk_usage() {
    check_timeshift || return
    echo ""
    echo -e "${MAGENTA}${BOLD}[📊] Использование места снапшотами${NC}"
    echo -e "${GRAY}   ────────────────────────────────────────────${NC}"
    local snap_dir="/timeshift"
    if [ -d "$snap_dir" ]; then
        sudo du -sh "$snap_dir" 2>/dev/null | sed 's/^/   Всего занято: /'
        echo ""
        echo -e "${WHITE}   Детализация по снапшотам:${NC}"
        sudo du -sh "$snap_dir"/snapshots/*/ 2>/dev/null | sed 's/^/     /'
    else
        echo -e "   ${GRAY}Директория снапшотов не найдена (возможно, другое устройство хранения).${NC}"
    fi
}

# ---------- Проверка целостности cron ----------
verify_cron() {
    echo ""
    echo -e "${MAGENTA}${BOLD}[✅] Проверка службы Cron для Timeshift${NC}"
    echo -e "${GRAY}   ────────────────────────────────────────────${NC}"
    if systemctl is-active --quiet cron; then
        echo -e "   ${GREEN}✔ Служба cron активна.${NC}"
    else
        echo -e "   ${LRED}✘ Служба cron не активна!${NC} Автоматические бэкапы работать не будут."
        read -p "$(echo -e ${YELLOW}"   Запустить cron? [Y/n]: "${NC})" start_cron
        if [[ "$start_cron" != "n" && "$start_cron" != "N" ]]; then
            sudo systemctl enable --now cron
            echo -e "   ${GREEN}✔ Cron запущен и добавлен в автозагрузку.${NC}"
        fi
    fi
}

# ---------- Меню ----------
menu() {
    while true; do
        draw_header
        echo -e "  ${WHITE}${BOLD}Выберите действие:${NC}"
        echo ""
        echo -e "   ${CYAN}1)${NC} 📥  Установить Timeshift"
        echo -e "   ${CYAN}2)${NC} ⚙️   Первичная настройка"
        echo -e "   ${CYAN}3)${NC} 💾  Создать снапшот сейчас"
        echo -e "   ${CYAN}4)${NC} 📋  Список снапшотов"
        echo -e "   ${CYAN}5)${NC} ⏪  Восстановить из снапшота"
        echo -e "   ${CYAN}6)${NC} 🗑️   Удалить снапшот"
        echo -e "   ${CYAN}7)${NC} ⏰  Настроить расписание (ежедн./еженед./ежемес.)"
        echo -e "   ${CYAN}8)${NC} 💽  Настроить устройство хранения"
        echo -e "   ${CYAN}9)${NC} 📊  Использование места снапшотами"
        echo -e "  ${CYAN}10)${NC} ✅  Проверить службу Cron"
        echo -e "   ${RED}0)${NC}  Выход"
        echo -e "${BROWN}  ────────────────────────────────────────────────────${NC}"
        read -p "$(echo -e ${WHITE}${BOLD}"  Ваш выбор [0-10]: "${NC})" choice

        case $choice in
            1) install_timeshift ;;
            2) first_time_setup ;;
            3) create_snapshot ;;
            4) list_snapshots ;;
            5) restore_snapshot ;;
            6) delete_snapshot ;;
            7) configure_schedule ;;
            8) configure_storage ;;
            9) show_disk_usage ;;
            10) verify_cron ;;
            0)
                echo ""
                echo -e "${LGREEN}${BOLD}  Работа завершена. 👋${NC}"
                echo ""
                exit ;;
            *) echo -e "${LRED}  Неверный выбор!${NC}" ;;
        esac

        echo ""
        read -p "$(echo -e ${GRAY}"  Нажмите Enter, чтобы вернуться в меню..."${NC})"
    done
}

# ---------- Точка входа ----------
if [ "$EUID" -eq 0 ]; then
    echo -e "${YELLOW}Скрипт лучше запускать от обычного пользователя с sudo, а не от root напрямую.${NC}"
fi

menu
