#!/bin/bash

# ==============================
# GitCloud backup script
# ==============================

SRC="/home/gitcloud/database/serwer-ad"
DEST="/home/gitcloud/backup-database"

TIMESTAMP=$(date +"%Y-%m-%d_%H-%M-%S")
BACKUP_DIR="$DEST/backup-$TIMESTAMP"

# создаём каталог под конкретный бэкап
mkdir -p "$BACKUP_DIR"

# копирование с сохранением прав, владельцев, ссылок
rsync -a --delete-delay "$SRC/" "$BACKUP_DIR/"

# лог (не обязательно, но полезно)
echo "$(date +"%Y-%m-%d %H:%M:%S") backup created: $BACKUP_DIR" >> "$DEST/backup.log"
