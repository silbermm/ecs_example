APP_NAME ?= `grep 'app:' mix.exs | sed -e 's/\[//g' -e 's/ //g' -e 's/app://' -e 's/[:,]//g'`
APP_VSN ?= `grep 'version:' mix.exs | cut -d '"' -f2`
BUILD ?= `git rev-parse --short HEAD`

build_local:
	docker build --build-arg APP_VSN=$(APP_VSN) \
    --build-arg MIX_ENV=dev \
    --build-arg SECRET_KEY_BASE=$(SECRET_KEY_BASE) \
    -t $(APP_NAME):$(APP_VSN) .

build:
	docker build --build-arg APP_VSN=$(APP_VSN) \
    --build-arg MIX_ENV=prod \
    --build-arg SECRET_KEY_BASE=$(SECRET_KEY_BASE) \
    -t 686556766167.dkr.ecr.us-east-1.amazonaws.com/ecs_example_repo:$(APP_VSN)-$(BUILD) \
    -t 686556766167.dkr.ecr.us-east-1.amazonaws.com/ecs_example_repo:latest .

push:
	eval `aws ecr get-login --no-include-email --region us-east-1`
	docker push 686556766167.dkr.ecr.us-east-1.amazonaws.com/ecs_example_repo:$(APP_VSN)-$(BUILD)
	docker push 686556766167.dkr.ecr.us-east-1.amazonaws.com/ecs_example_repo:latest

deploy:
	./bin/ecs-deploy -c ecs_app_cluster -n ecs_app_service -i 686556766167.dkr.ecr.us-east-1.amazonaws.com/ecs_example_repo:$(APP_VSN)-$(BUILD) -r us-east-1 -t 300

