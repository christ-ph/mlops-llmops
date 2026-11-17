#!/usr/bin/env bash
# scripts/setup_ci.sh
# Crée la CI GitHub Actions (lint + tests) et un Makefile de commandes de référence.
# Idempotent : un fichier existant est ignoré, sauf avec --force
# (dans ce cas il est sauvegardé en <fichier>.bak.<horodatage> avant remplacement).
# Usage : bash scripts/setup_ci.sh [--force]
set -euo pipefail

FORCE=0
if [ "${1:-}" = "--force" ]; then
  FORCE=1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
STAMP="$(date +%Y%m%d-%H%M%S)"

if [ ! -d "$ROOT_DIR/backend/app" ]; then
  echo "✖ Lance ce script depuis le projet (scripts/setup_ci.sh)." >&2
  exit 1
fi

write_file() {
  local path="$1"
  local rel="${path#"$ROOT_DIR"/}"
  if [ -e "$path" ]; then
    if [ "$FORCE" -eq 1 ]; then
      cp "$path" "$path.bak.$STAMP"
      cat >"$path"
      echo "♻  remplacé    : $rel (backup : $rel.bak.$STAMP)"
    else
      cat >/dev/null
      echo "⏭  existe déjà : $rel (utilise --force pour remplacer, avec backup)"
    fi
  else
    mkdir -p "$(dirname "$path")"
    cat >"$path"
    echo "✔  créé        : $rel"
  fi
}

# ------------------------------------------------------------ GitHub Actions
write_file "$ROOT_DIR/.github/workflows/ci.yml" <<'EOF'
name: CI

on:
  push:
    branches: [main]
  pull_request:

permissions:
  contents: read

concurrency:
  group: ci-${{ github.ref }}
  cancel-in-progress: true

jobs:
  backend:
    name: Lint et tests (backend)
    runs-on: ubuntu-latest
    timeout-minutes: 15
    defaults:
      run:
        working-directory: backend
    env:
      # Valeurs jetables, propres à la CI (aucun vrai secret ici)
      APP_ENV: testing
      DATABASE_URL: sqlite:///./ci.db
      SECRET_KEY: ci-secret
      JWT_SECRET_KEY: ci-jwt-secret
    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Installer uv
        uses: astral-sh/setup-uv@v5
        with:
          enable-cache: true
          cache-dependency-glob: backend/uv.lock

      - name: Installer Python (version de .python-version)
        run: uv python install

      - name: Installer les dépendances (lockfile figé)
        run: uv sync --frozen

      - name: Lint (ruff)
        run: uv run ruff check .

      - name: Tests (pytest)
        run: uv run pytest tests/ -v
EOF

# ------------------------------------------------------------------ Makefile
write_file "$ROOT_DIR/Makefile" <<'EOF'
# Commandes de référence. `make help` pour la liste.
# RECIPEPREFIX évite les tabulations obligatoires dans les recettes.
.RECIPEPREFIX = >
.DEFAULT_GOAL := help
.PHONY: help install lint test check train api mlflow-ui reset-mlflow

EXPERIMENTS := $(abspath experiments)

help: ## Affiche cette aide
> @grep -E '^[a-z-]+:.*## ' $(MAKEFILE_LIST) | awk -F ':.*## ' '{printf "  %-14s %s\n", $$1, $$2}'

install: ## Installe les dépendances (uv sync)
> cd backend && uv sync

lint: ## Lint avec ruff
> cd backend && uv run ruff check .

test: ## Lance les tests pytest
> cd backend && uv run pytest tests/ -v

check: lint test ## Lint + tests (comme la CI)

train: ## Entraîne les 3 modèles et promeut le champion
> cd backend && uv run python ../scripts/train.py --model all

api: ## Lance l'API Flask sur le port 5000
> cd backend && uv run flask --app app run --port 5000

mlflow-ui: ## Ouvre l'UI MLflow
> cd backend && uv run mlflow ui --backend-store-uri "sqlite:///$(EXPERIMENTS)/mlflow.db"

reset-mlflow: ## SUPPRIME la base et les artefacts MLflow (repart de v1)
> rm -f experiments/mlflow.db
> rm -rf experiments/artifacts
EOF

# ------------------------------------------------------------- vérifications
echo
echo "Vérifications :"

if [ ! -d "$ROOT_DIR/.git" ]; then
  echo "  ⚠ Pas de dépôt Git ici : fais 'git init' à la racine du projet."
elif ! git -C "$ROOT_DIR" ls-files --error-unmatch backend/uv.lock >/dev/null 2>&1; then
  echo "  ⚠ backend/uv.lock n'est pas suivi par Git : 'git add backend/uv.lock' (sinon 'uv sync --frozen' échoue en CI)."
else
  echo "  ✔ backend/uv.lock est suivi par Git."
fi

if ! grep -qs "ruff" "$ROOT_DIR/backend/pyproject.toml"; then
  echo "  ⚠ ruff absent de pyproject.toml : cd backend && uv add --dev ruff"
else
  echo "  ✔ ruff déclaré dans pyproject.toml."
fi

cat <<'EOF'

Terminé. Ensuite :
  make check                      # lint + tests en local, comme la CI
  git add .github Makefile scripts/setup_ci.sh
  git commit -m "ci: add GitHub Actions workflow and Makefile"
  git push                        # puis onglet Actions sur GitHub

Badge pour le README (remplace <user>/<repo>) :
  ![CI](https://github.com/<user>/<repo>/actions/workflows/ci.yml/badge.svg)
EOF
