#!/bin/sh
set -eu

# 与模板内数据库启动命令一致：把平台随机种子转换成应用要求的 48 位十六进制密码。
: "${CPR_POSTGRES_SEED:?CPR_POSTGRES_SEED is required}"
: "${CPR_REDIS_SEED:?CPR_REDIS_SEED is required}"
CPR_DATABASE_PASSWORD=$(printf '%s' "$CPR_POSTGRES_SEED" | sha256sum | cut -c 1-48)
CPR_REDIS_PASSWORD=$(printf '%s' "$CPR_REDIS_SEED" | sha256sum | cut -c 1-48)
export CPR_DATABASE_PASSWORD CPR_REDIS_PASSWORD
unset CPR_POSTGRES_SEED CPR_REDIS_SEED

# 新挂载卷可能归 root 所有；只初始化约定目录，业务进程仍以 cpr 身份运行。
install -d -m 0700 -o cpr -g cpr /app/.runtime/data /app/.runtime/logs
exec gosu cpr "$@"
