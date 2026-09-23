# Ride App developer entry points. Run `make help` for the list.
.DEFAULT_GOAL := help
SHELL := /bin/bash

.PHONY: help ci ci-fast test-backend test-e2e test-flutter analyze build-web shots load-rest load-ride up down logs migrate

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN{FS=":.*?## "}{printf "  \033[36m%-14s\033[0m %s\n",$$1,$$2}'

ci: ## Full local CI gate (backend unit+e2e, flutter analyze+test)
	./tools/ci.sh

ci-fast: ## Local CI gate without e2e (quick inner loop)
	./tools/ci.sh --fast

# The dev container pins NODE_ENV=development, so jest does NOT default it to
# `test` the way it does in CI — which leaves the per-IP rate limiter live and
# fails the suites on 429s that have nothing to do with the code. Setting the
# flag explicitly makes the local gate agree with CI.
test-backend: ## Backend unit tests (in container)
	docker exec -e THROTTLE_DISABLED=true ubernav_backend npx jest --ci

test-e2e: ## Backend e2e tests (in container)
	docker exec -e THROTTLE_DISABLED=true ubernav_backend npm run test:e2e

test-flutter: ## Flutter widget/bloc tests
	@for d in packages/* apps/*; do [ -d "$$d/test" ] && (cd "$$d" && flutter test) || true; done

analyze: ## Flutter static analysis
	flutter analyze

shots: ## Headless visual+health check — screenshots all 3 apps to tools/visual-check/shots/
	cd tools/visual-check && node capture.mjs

load-rest: ## REST hot-path load test (env: CONC, DURATION_S)
	cd tools/load-test && npm install --silent && npm run rest

load-ride: ## Realistic end-to-end ride load test (env: DRIVERS, CONC, RIDES)
	cd tools/load-test && npm install --silent && npm run ride

# This box's LAN address, resolved at run time. It used to be hardcoded to
# 192.168.1.48, which is no longer this machine — override with `make build-web
# LAN_IP=1.2.3.4` if the guess is wrong.
LAN_IP ?= $(shell hostname -I | tr ' ' '\n' | grep -m1 '^192\.168\.' || echo localhost)

build-web: ## Release-build all three web apps (env: LAN_IP)
	@echo "building against http://$(LAN_IP):3000/api/v1"
	@for a in rider_app driver_app admin_app; do \
		(cd apps/$$a && flutter build web --release --pwa-strategy=none \
			--dart-define=API_BASE_URL=http://$(LAN_IP):3000/api/v1); done

up: ## Start the Docker stack
	cd infra && docker compose up -d

down: ## Stop the Docker stack
	cd infra && docker compose down

logs: ## Tail backend logs
	docker logs -f ubernav_backend

migrate: ## Create/apply a Prisma migration (NAME=your_migration)
	docker exec ubernav_backend npx prisma migrate dev --name $(NAME)

BACKUP_DIR ?= /var/backups/ridevela
DB_PG = docker run --rm --network infra_default -e PGHOST=postgres -e PGUSER=ubernav \
	-e PGPASSWORD=$${PGPASSWORD:-ubernav} -e PGDATABASE=ubernav \
	-v $(CURDIR)/infra/backup:/scripts:ro -v $(BACKUP_DIR):/backups postgis/postgis:16-3.4

backup-db: ## One verified Postgres backup of the dev DB into BACKUP_DIR (see infra/backup/README.md)
	$(DB_PG) /scripts/pg-backup.sh

restore-db: ## Restore DUMP=<file under BACKUP_DIR> into TARGET=<scratch db name>
	$(DB_PG) /scripts/pg-restore.sh /backups/$(patsubst $(BACKUP_DIR)/%,%,$(DUMP)) $(TARGET)
