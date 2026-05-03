NETWORK = fnh_data_network
APP_CONTAINER = spitegear

build:
	docker build -t $(APP_CONTAINER) .

up-app:
	docker run -d --name $(APP_CONTAINER) \
		--network $(NETWORK) \
		--restart unless-stopped \
		--env-file $(HOME)/spitegear/.env \
		-p 4001:4001 \
		$(APP_CONTAINER)

down-app:
	-docker stop $(APP_CONTAINER)
	-docker rm $(APP_CONTAINER)

down: down-app

deploy: build down-app up-app

remote:
	docker exec -it $(APP_CONTAINER) /app/bin/spitegear remote

.PHONY: build up-app down-app down deploy remote
