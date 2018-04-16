#!/bin/bash

# See if we are running in prod or dev mode
echo ""
echo ""
echo "Hello! Would you like to run in 'prod' or 'dev' mode? ( Type your answer without the ' )"
echo ""
echo "If you're not sure just type 'prod'"
echo ""
read -p "MODE: " RUN_MODE
RUN_MODE=`echo $RUN_MODE | awk '{ print toupper($0) }'`

# Make sure the user input something sane
if [ $RUN_MODE != "PROD" ] && [ $RUN_MODE != "DEV" ]; then
    echo ""
    echo "You have to choose 'prod' or 'dev'!"
    echo "Exiting, no changes made"
    echo ""
    exit 1
fi

# Update the compose file
sed -i "s/%RUN_MODE%/$RUN_MODE/" docker-compose.yml

# Grab the docker-pleroma docker file
git clone https://git.sergal.org/Sir-Boops/docker-pleroma

# Build the the docker-pleroma image and get the ID
PLEROMA_NAME="pleroma:`head /dev/urandom | tr -dc A-Za-z0-9 | head -c 13 ; echo ''`"
docker build -t $PLEROMA_NAME docker-pleroma/

# Generate and copy the config file out
COND_NAME="pleroma_`head /dev/urandom | tr -dc A-Za-z0-9 | head -c 13 ; echo ''`"
docker run -it --name $COND_NAME $PLEROMA_NAME ash -c 'su - -s /bin/ash pleroma -c "cd /opt/pleroma && mix generate_config"'
docker cp $COND_NAME:/opt/pleroma/config config
docker rm $COND_NAME

# Create the uploads dir
mkdir uploads
chown 1000:1000 uploads

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
cp config/generated_config.exs config/`echo $RUN_MODE | awk '{ print tolower($0) }'`.secret.exs
