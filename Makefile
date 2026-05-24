NETWORK = fnh_data_network
APP_CONTAINER = spitegear
CF_CONTAINER = cloudflared

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

up-tunnel:
	docker run -d --name $(CF_CONTAINER) \
		--network $(NETWORK) \
		--restart unless-stopped \
		cloudflare/cloudflared:latest \
		tunnel --no-autoupdate run \
		--token $$(cat $(HOME)/spitegear/.cf-tunnel-token)

down-tunnel:
	-docker stop $(CF_CONTAINER)
	-docker rm $(CF_CONTAINER)

down: down-app down-tunnel

deploy: build down-app up-app

remote:
	docker exec -it $(APP_CONTAINER) /app/bin/spitegear remote

.PHONY: build up-app down-app up-tunnel down-tunnel down deploy remote
