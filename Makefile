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
