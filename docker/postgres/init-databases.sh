#!/bin/bash
# =============================================================================
# PostgreSQL Initialization Script
# Creates additional databases and users for Keycloak and Customer Self-Service
# The fineract_default database is auto-created via POSTGRES_DB env var
# =============================================================================
set -e

echo "Creating additional databases..."

# Create Fineract tenant store database (fineract_tenants)
# This is the meta-database that stores tenant connection info
# The main POSTGRES_DB (fineract_default) is the actual tenant data database
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL
    SELECT 'CREATE DATABASE fineract_tenants OWNER ${POSTGRES_USER}'
    WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'fineract_tenants')\gexec
EOSQL

echo "Fineract tenant store database 'fineract_tenants' created."

# Create Keycloak database and user
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL
    DO \$\$
    BEGIN
        IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = '${KEYCLOAK_DB_USER}') THEN
            CREATE ROLE ${KEYCLOAK_DB_USER} WITH LOGIN PASSWORD '${KEYCLOAK_DB_PASSWORD}';
        END IF;
    END
    \$\$;

    SELECT 'CREATE DATABASE ${KEYCLOAK_DB_NAME} OWNER ${KEYCLOAK_DB_USER}'
    WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = '${KEYCLOAK_DB_NAME}')\gexec

    GRANT ALL PRIVILEGES ON DATABASE ${KEYCLOAK_DB_NAME} TO ${KEYCLOAK_DB_USER};
EOSQL

echo "Keycloak database '${KEYCLOAK_DB_NAME}' created."

# Create Customer Self-Service database and user
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL
    DO \$\$
    BEGIN
        IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = '${CUSTOMER_REG_DB_USER}') THEN
            CREATE ROLE ${CUSTOMER_REG_DB_USER} WITH LOGIN PASSWORD '${CUSTOMER_REG_DB_PASSWORD}';
        END IF;
    END
    \$\$;

    SELECT 'CREATE DATABASE ${CUSTOMER_REG_DB_NAME} OWNER ${CUSTOMER_REG_DB_USER}'
    WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = '${CUSTOMER_REG_DB_NAME}')\gexec

    GRANT ALL PRIVILEGES ON DATABASE ${CUSTOMER_REG_DB_NAME} TO ${CUSTOMER_REG_DB_USER};
EOSQL

echo "Customer registration database '${CUSTOMER_REG_DB_NAME}' created."

# Create Asset Service database and user
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL
    DO \$\$
    BEGIN
        IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = '${ASSET_SERVICE_DB_USER}') THEN
            CREATE ROLE ${ASSET_SERVICE_DB_USER} WITH LOGIN PASSWORD '${ASSET_SERVICE_DB_PASSWORD}';
        END IF;
    END
    \$\$;

    SELECT 'CREATE DATABASE ${ASSET_SERVICE_DB_NAME} OWNER ${ASSET_SERVICE_DB_USER}'
    WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = '${ASSET_SERVICE_DB_NAME}')\gexec

    GRANT ALL PRIVILEGES ON DATABASE ${ASSET_SERVICE_DB_NAME} TO ${ASSET_SERVICE_DB_USER};
EOSQL

echo "Asset service database '${ASSET_SERVICE_DB_NAME}' created."
echo "All databases initialized successfully."
