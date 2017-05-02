#!/bin/sh
# (C) Copyright 2017 Hewlett Packard Enterprise Development LP

set -x

MYSQL_INIT_HOST=${MYSQL_INIT_HOST:-"mysql"}
MYSQL_INIT_PORT=${MYSQL_INIT_PORT:-"3306"}
MYSQL_INIT_USERNAME=${MYSQL_INIT_USERNAME:-"root"}
MYSQL_INIT_PASSWORD=${MYSQL_INIT_PASSWORD:-"secretmysql"}
MYSQL_INIT_SCHEMA_DATABASE=${MYSQL_INIT_DATABASE:-"mysql_init_schema"}

MYSQL_INIT_WAIT_RETRIES=${MYSQL_INIT_WAIT_RETRIES:-"24"}
MYSQL_INIT_WAIT_DELAY=${MYSQL_INIT_WAIT_DELAY:-"5"}

USER_SCRIPTS="/mysql-init.d"
UPGRADE_SCRIPTS="/mysql-upgrade.d"

echo "Waiting for MySQL to become available..."
success="false"
for i in $(seq $MYSQL_INIT_WAIT_RETRIES); do
  mysqladmin status \
      --host="$MYSQL_INIT_HOST" \
      --port=$MYSQL_INIT_PORT \
      --user="$MYSQL_INIT_USERNAME" \
      --password="$MYSQL_INIT_PASSWORD" \
      --connect_timeout=10
  if [ $? -eq 0 ]; then
    echo "MySQL is available, continuing..."
    success="true"
    break
  else
    echo "Connection attempt $i of $MYSQL_INIT_WAIT_RETRIES failed"
    sleep "$MYSQL_INIT_WAIT_DELAY"
  fi
done

if [ "$success" != "true" ]; then
    echo "Unable to reach MySQL database! Exiting..."
    sleep 1
    exit 1
fi

query="select major, minor, patch from schema_version order by id desc limit 1;"
version=$(echo "$query" | mysql \
    --host="$MYSQL_INIT_HOST" \
    --user="$MYSQL_INIT_USERNAME" \
    --port=$MYSQL_INIT_PORT \
    --password="$MYSQL_INIT_PASSWORD" \
    --silent \
    $MYSQL_INIT_SCHEMA_DATABASE)
if [ $? -eq 0 ]; then
  echo "MySQL has already been initialized! Current version: $version"

  # TODO apply upgrades
  echo "Updating not yet implemented!"
else
  echo "MySQL has not yet been initialized. Initial schemas will be applied."

  set -e

  for f in $USER_SCRIPTS/*.sql.j2; do
    if [ -e "$f" ]; then
      echo "Applying template: $f"
      python /template.py "$f" "$USER_SCRIPTS/$(basename "$f" .j2)"
    fi
  done

  for f in $USER_SCRIPTS/*.sql; do
    if [ -e "$f" ]; then
      echo "Running script: $f"
      mysql --host="$MYSQL_INIT_HOST" \
          --user="$MYSQL_INIT_USERNAME" \
          --port=$MYSQL_INIT_PORT \
          --password="$MYSQL_INIT_PASSWORD" < "$f"
    fi
  done

  if [ -n "$MYSQL_INIT_SET_PASSWORD" ]; then
    echo "Updating password for $MYSQL_INIT_USERNAME..."

    set +x
    mysqladmin password \
        --host="$MYSQL_INIT_HOST" \
        --port=$MYSQL_INIT_PORT \
        --user="$MYSQL_INIT_USERNAME" \
        --password="$MYSQL_INIT_PASSWORD" \
        "$MYSQL_INIT_SET_PASSWORD"
  elif [ "$MYSQL_INIT_RANDOM_PASSWORD" = "true" ]; then
    echo "Resetting $MYSQL_INIT_USERNAME password..."

    set +x
    pw=$(pwgen -1 32)
    mysqladmin password \
        --host="$MYSQL_INIT_HOST" \
        --port=$MYSQL_INIT_PORT \
        --user="$MYSQL_INIT_USERNAME" \
        --password="$MYSQL_INIT_PASSWORD" \
        "$pw"
    echo "GENERATED $MYSQL_INIT_USERNAME PASSWORD: $pw"
    MYSQL_INIT_PASSWORD="$pw"
  fi

  if [ "$MYSQL_INIT_DISABLE_REMOTE_ROOT" = "true" ]; then
    echo "Disabling remote root login..."
    mysql --host="$MYSQL_INIT_HOST" \
        --user="$MYSQL_INIT_USERNAME" \
        --port=$MYSQL_INIT_PORT \
        --password="$MYSQL_INIT_PASSWORD" < /disable-remote-root.sql
  fi
fi

echo "mysql-init exiting successfully"
