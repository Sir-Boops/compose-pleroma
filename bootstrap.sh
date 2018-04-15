#!/bin/bash

# Grab the docker-pleroma docker file
git clone https://git.sergal.org/Sir-Boops/docker-pleroma
cd docker-pleroma 
git checkout 530a3a666f2e85eed5366a9b2921405ac85c6315
cd ..

# Build the the docker-pleroma image and get the ID
PLEROMA_NAME="pleroma:`head /dev/urandom | tr -dc A-Za-z0-9 | head -c 13 ; echo ''`"
docker build -t $PLEROMA_NAME docker-pleroma/

# Generate and copy the config file out
COND_NAME="pleroma_`head /dev/urandom | tr -dc A-Za-z0-9 | head -c 13 ; echo ''`"
docker run -it --name $COND_NAME $PLEROMA_NAME ash -c 'cd /opt/pleroma && mix generate_config'
docker cp $COND_NAME:/opt/pleroma/config config
docker rm $COND_NAME

# Init the database
DB_NAME="db_`head /dev/urandom | tr -dc A-Za-z0-9 | head -c 13 ; echo ''`"
FULLPATH=`realpath .`
docker run -v $FULLPATH/postgres:/var/lib/postgresql/data --name $DB_NAME -d postgres:10.3-alpine
sleep 10
docker exec $DB_NAME psql -U postgres -c 'CREATE user pleroma;'
docker exec $DB_NAME psql -U postgres -c 'CREATE DATABASE pleroma_dev OWNER pleroma'
docker exec $DB_NAME psql -U postgres -c "ALTER user pleroma with encrypted password 'pleroma';" pleroma_dev
docker exec $DB_NAME psql -U postgres -c "GRANT ALL ON ALL tables IN SCHEMA public TO pleroma;" pleroma_dev
docker exec $DB_NAME psql -U postgres -c "GRANT ALL ON ALL sequences IN SCHEMA public TO pleroma;" pleroma_dev
docker exec $DB_NAME psql -U postgres -c "CREATE EXTENSION citext;" pleroma_dev
docker stop $DB_NAME
docker rm $DB_NAME

# Get the config ready
sed -i '/password:/c\  password: "pleroma",' config/generated_config.exs
sed -i '/hostname:/c\  hostname: "postgres",' config/generated_config.exs
cp config/generated_config.exs config/dev.secret.exs
