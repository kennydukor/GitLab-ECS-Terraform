.SILENT:

help:
	{ grep --extended-regexp '^[a-zA-Z_-]+:.*#[[:space:]].*$$' $(MAKEFILE_LIST) || true; } \
	| awk 'BEGIN { FS = ":.*#[[:space:]]*" } { printf "\033[1;32m%-14s\033[0m%s\n", $$1, $$2 }'

setup: # npm install + terraform init + create user + create ecr repository
	./make.sh setup

dev: # local development
	./make.sh dev

build-push: # build the production image + push to ecr
	./make.sh build-push
	
# tf-init: # terraform init
# 	./make.sh tf-init

tf-validate: # terraform validate
	./make.sh tf-validate

tf-apply: # terraform plan + terraform apply
	./make.sh tf-apply

tf-scale-up: # scale to 3
	./make.sh tf-scale-up

tf-scale-down: # scale to 1 (warn: target deregistration take time)
	./make.sh tf-scale-down

# tf-destroy: # terraform destroy
# 	./make.sh tf-destroy

destroy: # terraform destroy + delete user + delete ecr repository
	./make.sh destroy