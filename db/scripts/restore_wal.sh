#!/bin/sh
# Восстановление WAL из зашифрованного архива (обратная операция archive_wal.sh).
set -eu

fname="${1:?}"
dest="${2:?}"
archive_dir="${PGARCHIVE:-/var/lib/postgresql/archive}"
password="${WAL_ARCHIVE_PASSWORD:-adf6e743750b4387c96e06f27f39cc1f48eeb753e2d737cdbad09b798138b407}"

enc="${archive_dir}/${fname}.gz.enc"
if [ ! -f "${enc}" ]; then
  # Для .history и ещё не заархивированных сегментов PostgreSQL ожидает ненулевой код.
  echo "restore_wal: missing archive ${enc}" >&2
  exit 1
fi

openssl enc -d -aes-256-cbc -pass "pass:${password}" -in "${enc}" | gunzip > "${dest}"
chmod 0600 "${dest}"
