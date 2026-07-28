NETWORK = fnh_data_network
APP_CONTAINER = spitegear
CF_CONTAINER = cloudflared
WARP_CONTAINER = warp
PRIVOXY_CONTAINER = privoxy

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

# Cloudflare WARP client in SOCKS5 proxy mode, used to give outbound
# wargear.net requests an alternate egress IP. See deploy/privoxy for the
# HTTP-proxy front end that spitegear's Req client actually talks to.
up-warp:
	docker run -d --name $(WARP_CONTAINER) \
		--network $(NETWORK) \
		--restart unless-stopped \
		-e WARP_SLEEP=5 \
		-e GOST_ARGS="-L :1080 -F=127.0.0.1:40000" \
		--cap-add MKNOD --cap-add AUDIT_WRITE --cap-add NET_ADMIN \
		--sysctl net.ipv6.conf.all.disable_ipv6=0 \
		--sysctl net.ipv4.conf.all.src_valid_mark=1 \
		-v $(HOME)/spitegear/warp-data:/var/lib/cloudflare-warp \
		caomingjun/warp

down-warp:
	-docker stop $(WARP_CONTAINER)
	-docker rm $(WARP_CONTAINER)

build-privoxy:
	docker build -t $(PRIVOXY_CONTAINER) deploy/privoxy

# Bridges plain HTTP-proxy requests to warp's SOCKS5 port. Requires
# up-warp to already be running on the same network.
up-privoxy: build-privoxy
	docker run -d --name $(PRIVOXY_CONTAINER) \
		--network $(NETWORK) \
		--restart unless-stopped \
		$(PRIVOXY_CONTAINER)

down-privoxy:
	-docker stop $(PRIVOXY_CONTAINER)
	-docker rm $(PRIVOXY_CONTAINER)

down: down-app down-tunnel down-warp down-privoxy

deploy: build down-app up-app

remote:
	docker exec -it $(APP_CONTAINER) /app/bin/spitegear remote

.PHONY: build up-app down-app up-tunnel down-tunnel up-warp down-warp \
	build-privoxy up-privoxy down-privoxy down deploy remote
