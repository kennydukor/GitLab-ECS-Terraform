#!/bin/bash

#
# variables
#

# AWS variables
AWS_PROFILE=default
AWS_REGION=eu-west-3
# project name
PROJECT_NAME=gitlab-ecs-terraform


# the directory containing the script file
dir="$(cd "$(dirname "$0")"; pwd)"
cd "$dir"


log()   { echo -e "\e[30;47m ${1^^} \e[0m ${@:2}"; }        # $1 uppercase background white
info()  { echo -e "\e[48;5;28m ${1^^} \e[0m ${@:2}"; }      # $1 uppercase background green
warn()  { echo -e "\e[48;5;202m ${1^^} \e[0m ${@:2}" >&2; } # $1 uppercase background orange
error() { echo -e "\e[48;5;196m ${1^^} \e[0m ${@:2}" >&2; } # $1 uppercase background red


# log $1 in underline then $@ then a newline
under() {
    local arg=$1
    shift
    echo -e "\033[0;4m${arg}\033[0m ${@}"
    echo
}

usage() {
    under usage 'call the Makefile directly: make dev
      or invoke this file directly: ./make.sh dev'
}

#
# npm install + terraform init + create user + create ecr repository
#
setup() {
    cd "$dir/website"
    npm install

    tf-init

    user-create
    ecr-create
}

# terraform init
tf-init() {
    cd "$dir/infra"
    terraform init
}

user-create() {
    # check if user already exists (return something if user exists, otherwise return nothing)
    local exists=$(aws iam list-user-policies \
        --user-name $PROJECT_NAME \
        --profile $AWS_PROFILE \
        2>/dev/null)
        
    [[ -n "$exists" ]] && { error abort user $PROJECT_NAME already exists; return; }

    # create a user named $PROJECT_NAME
    log create iam user $PROJECT_NAME
    aws iam create-user \
        --user-name $PROJECT_NAME \
        --profile $AWS_PROFILE \
        1>/dev/null

    aws iam attach-user-policy \
        --user-name $PROJECT_NAME \
        --policy-arn arn:aws:iam::aws:policy/PowerUserAccess \
        --profile $AWS_PROFILE

    aws iam attach-user-policy \
        --user-name $PROJECT_NAME \
        --policy-arn arn:aws:iam::aws:policy/IAMFullAccess \
        --profile $AWS_PROFILE

    # Ok with the 2 below
    # arn:aws:iam::aws:policy/PowerUserAccess
    # arn:aws:iam::aws:policy/IAMFullAccess

    # ... or Ok with the 5 below
    # arn:aws:iam::aws:policy/AmazonEC2FullAccess
    # arn:aws:iam::aws:policy/IAMFullAccess
    # arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryFullAccess
    # arn:aws:iam::aws:policy/CloudWatchFullAccess
    # arn:aws:iam::aws:policy/AmazonECS_FullAccess

    local key=$(aws iam create-access-key \
        --user-name $PROJECT_NAME \
        --query 'AccessKey.{AccessKeyId:AccessKeyId,SecretAccessKey:SecretAccessKey}' \
        --profile $AWS_PROFILE \
        2>/dev/null)

    local AWS_ACCESS_KEY_ID=$(echo "$key" | jq '.AccessKeyId' --raw-output)
    log AWS_ACCESS_KEY_ID $AWS_ACCESS_KEY_ID
    
    local AWS_SECRET_ACCESS_KEY=$(echo "$key" | jq '.SecretAccessKey' --raw-output)
    log AWS_SECRET_ACCESS_KEY $AWS_SECRET_ACCESS_KEY

    # envsubst tips : https://unix.stackexchange.com/a/294400
    # create .key file
    cd "$dir"
    # export variables for envsubst
    export AWS_ACCESS_KEY_ID
    export AWS_SECRET_ACCESS_KEY
    envsubst < .key.tmpl > .key

    info created file .key
}

ecr-create() {
    local repo=$(aws ecr describe-repositories \
        --repository-names $PROJECT_NAME \
        --region $AWS_REGION \
        --profile $AWS_PROFILE \
        2>/dev/null)
    [[ -n "$repo" ]] && { warn warn repository already exists; return; }

    REPOSITORY_URI=$(aws ecr create-repository \
        --repository-name $PROJECT_NAME \
        --query 'repository.repositoryUri' \
        --region $AWS_REGION \
        --profile $AWS_PROFILE \
        --output text \
        2>/dev/null)

    log REPOSITORY_URI $REPOSITORY_URI

    # envsubst tips : https://unix.stackexchange.com/a/294400
    # create .ecr file
    cd "$dir"
    # export variables for envsubst
    export REPOSITORY_URI
    envsubst < .ecr.tmpl > .ecr

    info created file .ecr
}



# build the production image + push to ecr
build-push() {
    docker-build
    ecr-push
}

docker-build() {
    cd "$dir/website"
    SHA=$(git rev-parse --short HEAD)
    echo $SHA
    docker image build \
        --tag $PROJECT_NAME:latest \
        --tag $PROJECT_NAME:$SHA \
        .
}

# push to ecr
ecr-push() {
    SHA=$(git rev-parse --short HEAD)
    echo $SHA

    local online=$(aws ecr describe-images \
        --repository-name $PROJECT_NAME \
        --image-ids imageTag=$SHA \
        --region $AWS_REGION \
        --profile $AWS_PROFILE \
        2>/dev/null)
    [[ -n "$online" ]] && { warn abort $PROJECT_NAME:$SHA already on repository; return; }

    local image=$(docker images \
        --format '{{.Repository}}:{{.Tag}}' \
        | grep ^$PROJECT_NAME:$SHA)
    [[ -z "$image" ]] && { warn warn image $PROJECT_NAME:$SHA not found; return; }

    REPOSITORY_URI=$(aws ecr describe-repositories \
        --query "repositories[?repositoryName == '$PROJECT_NAME'].repositoryUri" \
        --region $AWS_REGION \
        --profile $AWS_PROFILE \
        --output text)
    [[ -z "$REPOSITORY_URI" ]] && { warn warn no repository found; return; }
    log REPOSITORY_URI $REPOSITORY_URI

    # root account id
    ACCOUNT_ID=$(aws sts get-caller-identity \
        --query 'Account' \
        --profile $AWS_PROFILE \
        --output text)
    log ACCOUNT_ID $ACCOUNT_ID

    # add login data into /home/$USER/.docker/config.json
    aws ecr get-login-password \
        --region $AWS_REGION \
        --profile $AWS_PROFILE \
        | docker login \
        --username AWS \
        --password-stdin $ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com

    docker tag $PROJECT_NAME:latest $REPOSITORY_URI:$SHA
    docker tag $PROJECT_NAME:latest $REPOSITORY_URI:latest

    log push $REPOSITORY_URI:$SHA
    docker push $REPOSITORY_URI:$SHA
    docker push $REPOSITORY_URI:latest
}

# local development
dev() {
    cd "$dir/website"
    NODE_ENV=development PORT=3000 node .
}

# terraform validate
tf-validate() {
    cd "$dir/infra"
    terraform fmt -recursive
	terraform validate
}

# terraform plan + terraform apply
tf-apply() {
    source "$dir/.ecr"
    export TF_VAR_ecr_image=$REPOSITORY_URI:latest
    source "$dir/.key"
    export TF_VAR_AWS_ACCESS_KEY_ID=$AWS_ACCESS_KEY_ID
    export TF_VAR_AWS_SECRET_ACCESS_KEY=$AWS_SECRET_ACCESS_KEY
    log TF_VAR_ecr_image $TF_VAR_ecr_image
    log TF_VAR_AWS_ACCESS_KEY_ID $TF_VAR_AWS_ACCESS_KEY_ID
    log TF_VAR_AWS_SECRET_ACCESS_KEY $TF_VAR_AWS_SECRET_ACCESS_KEY
    cd "$dir/infra"
    terraform plan
    terraform apply -auto-approve
}

# scale to 3
tf-scale-up() {
    export TF_VAR_desired_count=3
    tf-apply
}

# scale to 1 (warn: target deregistration take time)
tf-scale-down() {
    export TF_VAR_desired_count=1
    tf-apply
}

# terraform destroy
tf-destroy() {
    source "$dir/.ecr"
    export TF_VAR_ecr_image=$REPOSITORY_URI:latest
    source "$dir/.key"
    export TF_VAR_AWS_ACCESS_KEY_ID=$AWS_ACCESS_KEY_ID
    export TF_VAR_AWS_SECRET_ACCESS_KEY=$AWS_SECRET_ACCESS_KEY
    log TF_VAR_ecr_image $TF_VAR_ecr_image
    log TF_VAR_AWS_ACCESS_KEY_ID $TF_VAR_AWS_ACCESS_KEY_ID
    log TF_VAR_AWS_SECRET_ACCESS_KEY $TF_VAR_AWS_SECRET_ACCESS_KEY
    cd "$dir/infra"
    terraform destroy -auto-approve
}


#
# terraform destroy + delete user + delete ecr repository
#
destroy() {
    tf-destroy
    user-delete
    ecr-delete
}

user-delete() {
    # check if user already exists (return something if user exists, otherwise return nothing)
    local exists=$(aws iam list-user-policies \
        --user-name $PROJECT_NAME \
        --profile $AWS_PROFILE \
        2>/dev/null)
        
    [[ -z "$exists" ]] && { error abort "user $PROJECT_NAME do not exists"; return; }

    # delete a user named $PROJECT_NAME
    log delete iam user $PROJECT_NAME

    aws iam detach-user-policy \
        --user-name $PROJECT_NAME \
        --policy-arn arn:aws:iam::aws:policy/PowerUserAccess \
        --profile $AWS_PROFILE \
        2>/dev/null

    source "$dir/.key"
    aws iam delete-access-key \
        --user-name $PROJECT_NAME \
        --access-key-id $AWS_ACCESS_KEY_ID \
        2>/dev/null

    aws iam delete-user \
        --user-name $PROJECT_NAME \
        --profile $AWS_PROFILE \
        2>/dev/null

    rm --force "$dir/.key"

    info deleted file .key
}

ecr-delete() {
    local repo=$(aws ecr describe-repositories \
        --repository-names $PROJECT_NAME \
        --region $AWS_REGION \
        --profile $AWS_PROFILE \
        2>/dev/null)
    [[ -z "$repo" ]] && { warn warn no repository found; return; }

    aws ecr delete-repository \
        --repository-name $PROJECT_NAME \
        --force \
        --region $AWS_REGION \
        --profile $AWS_PROFILE \
        1>/dev/null

    rm --force "$dir/.ecr"

    info deleted ecr repository
}


# if `$1` is a function, execute it. Otherwise, print usage
# compgen -A 'function' list all declared functions
# https://stackoverflow.com/a/2627461
FUNC=$(compgen -A 'function' | grep $1)
[[ -n $FUNC ]] && { info execute $1; eval $1; } || usage;
exit 0
