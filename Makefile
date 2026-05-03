NETWORK = spitegear_network
DB_CONTAINER = spitegear_postgres
APP_CONTAINER = spitegear

create-network:
	docker network create $(NETWORK) || true

pull-db:
	docker pull postgres:16

up-db: pull-db create-network
	docker run -d --name $(DB_CONTAINER) \
		--network $(NETWORK) \
		-e POSTGRES_USER=postgres \
		-e POSTGRES_PASSWORD=postgres \
		-e POSTGRES_DB=spitegear_dev \
		-v spitegear_dev_data:/var/lib/postgresql \
		-p 5433:5432 \
		postgres:16

build:
	docker build -t $(APP_CONTAINER) .

up-app: create-network
	docker run -d --name $(APP_CONTAINER) \
		--network $(NETWORK) \
		--env-file $(HOME)/spitegear/.env \
		-e PGHOST=$(DB_CONTAINER) \
		-p 4001:4001 \
		$(APP_CONTAINER)

down-app:
	-docker stop $(APP_CONTAINER)
	-docker rm $(APP_CONTAINER)

down-db:
	-docker stop $(DB_CONTAINER)
	-docker rm $(DB_CONTAINER)

down: down-app down-db

deploy: build down-app up-app

.PHONY: create-network pull-db up-db build up-app down-app down-db down deploy
