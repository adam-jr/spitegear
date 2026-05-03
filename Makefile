NETWORK = fnh_data_network
DB_CONTAINER = postgres
APP_CONTAINER = spitegear

build:
	docker build -t $(APP_CONTAINER) .

up-app:
	docker run -d --name $(APP_CONTAINER) \
		--network $(NETWORK) \
		--env-file $(HOME)/spitegear/.env \
		-e PGHOST=$(DB_CONTAINER) \
		-p 4001:4001 \
		$(APP_CONTAINER)

down-app:
	-docker stop $(APP_CONTAINER)
	-docker rm $(APP_CONTAINER)

down: down-app

deploy: build down-app up-app

.PHONY: build up-app down-app down deploy
