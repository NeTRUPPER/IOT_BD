#!/bin/sh
set -eu

fname="${1:?}"
walpath="${2:?}"
archive_dir="${PGARCHIVE:-/var/lib/postgresql/archive}"
password="${WAL_ARCHIVE_PASSWORD:-adf6e743750b4387c96e06f27f39cc1f48eeb753e2d737cdbad09b798138b407}"

mkdir -p "${archive_dir}"
gzip -c "${walpath}" | openssl enc -aes-256-cbc -salt -pass "pass:${password}" \
  -out "${archive_dir}/${fname}.gz.enc"
