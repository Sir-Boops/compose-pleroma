#!/bin/bash

# Clean the screen
clear

# See if we are running in prod or dev mode
echo "Hello! Would you like to run in 'prod' or 'dev' mode? ( Type your answer without the ' )"
echo ""
echo "If you're not sure just type 'prod'"
echo ""
read -p "MODE: " RUN_MODE
RUN_MODE=`echo $RUN_MODE | awk '{ print tolower($0) }'`
clear

# Make sure the user chose a run type
if [ "$RUN_MODE" != "prod" ] && [ "$RUN_MODE" != "dev" ]; then
  echo "You have to choose 'prod' or 'dev' !"
  echo "Exiting, no changes made"
  echo ""
  exit 1
fi

# Update the compose file
echo "Setting run mode in docker-compose.yml"
echo ""
sleep 1
sed -i "s/%RUN_MODE%/$RUN_MODE/" docker-compose.yml
clear

# Grab the docker-pleroma docker file
echo "Pulling required required repos"
echo ""
sleep 1
docker-compose pull --no-parallel
clear

# Create the uploads dir
echo "Creating uploads dir"
echo ""
sleep 1
mkdir uploads
chown 1000:1000 uploads
clear

# Init the database
echo "Initlizing the database"
echo ""
sleep 1
DB_NAME="db_`head /dev/urandom | tr -dc A-Za-z0-9 | head -c 13 ; echo ''`"
FULLPATH=`realpath .`
docker run -v $FULLPATH/postgres:/var/lib/postgresql/data --name $DB_NAME -d postgres:10.3-alpine
sleep 10
docker exec $DB_NAME psql -U postgres -c 'CREATE user pleroma;'
docker exec $DB_NAME psql -U postgres -c 'CREATE DATABASE pleroma_dev OWNER pleroma;'
docker exec $DB_NAME psql -U postgres -c "ALTER user pleroma with encrypted password 'pleroma';" pleroma_dev
docker exec $DB_NAME psql -U postgres -c 'ALTER USER pleroma WITH SUPERUSER;'
#docker exec $DB_NAME psql -U postgres -c "GRANT ALL ON ALL tables IN SCHEMA public TO pleroma;" pleroma_dev
#docker exec $DB_NAME psql -U postgres -c "GRANT ALL ON ALL sequences IN SCHEMA public TO pleroma;" pleroma_dev
#docker exec $DB_NAME psql -U postgres -c "CREATE EXTENSION citext;" pleroma_dev
#docker exec $DB_NAME psql -U postgres -c "CREATE EXTENSION IF NOT EXISTS pg_trgm;" pleroma_dev
docker stop $DB_NAME
docker rm $DB_NAME
clear

# Generate and copy the config file out
echo "Generating pleroma config!"
echo "READ CARFULLY"
echo "The Detebase hostname should be set to: postgres"
echo "The name of the database shoud be: pleroma_dev"
echo "The username for the database should be: pleroma"
echo "The password for the database should be: pleroma"
echo ""
sleep 1
COND_NAME="pleroma_`head /dev/urandom | tr -dc A-Za-z0-9 | head -c 13 ; echo ''`"
docker run -it --name $COND_NAME sirboops/pleroma ash -c 'mix pleroma.instance gen'
docker cp $COND_NAME:/opt/pleroma/config config
docker rm $COND_NAME
cp config/generated_config.exs config/prod.secret.exs
clear

echo "Done! Your pleroma instance has been setup and it ready to go!"
echo ""

echo "Pleroma has been setup to listen on '127.0.0.1:4000'"
echo ""
echo "For an nginx config example please see 'https://git.pleroma.social/pleroma/pleroma/blob/develop/installation/pleroma.nginx'"
echo ""
echo "Now type 'docker-compose up -d' to start your instance!"
echo ""
