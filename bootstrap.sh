#!/bin/bash

# See if we are running in prod or dev mode
echo ""
echo ""
echo "Hello! Would you like to run in 'prod' or 'dev' mode? ( Type your answer without the ' )"
echo ""
echo "If you're not sure just type 'prod'"
echo ""
read -p "MODE: " RUN_MODE
RUN_MODE=`echo $RUN_MODE | awk '{ print tolower($0) }'`

# See if we are starting using TOR
echo ""
echo ""
echo "Will you be running this instance on the 'clearnet' or 'darknet' ? ( Type your answer without the ' )"
echo ""
echo "If you're not sure just type 'clearnet'"
echo ""
read -p "NET_TYPE: " NET_TYPE
NET_TYPE=`echo $NET_TYPE | awk '{ print tolower($0) }'`

# Make sure the user chose a run type
if [ $RUN_MODE != "prod" ] && [ $RUN_MODE != "dev" ]; then
    echo ""
    echo "You have to choose 'prod' or 'dev' !"
    echo "Exiting, no changes made"
    echo ""
    exit 1
fi

# Make sure the user chose a network type
if [ $NET_TYPE != "clearnet" ] && [ $NET_TYPE != "darknet" ]; then
    echo ""
    echo "You have to choose 'clearnet' or 'darknet' !"
    echo "Exiting, no changes made"
    echo ""
    exit 1
fi

# Copy out the needed docker-compose.yml file
if [ $NET_TYPE == "darknet" ]; then
    cp compose-scripts/darknet.yml docker-compose.yml
else
    cp compose-scripts/clearnet.yml docker-compose.yml
fi

# Update the compose file
sed -i "s/%RUN_MODE%/$RUN_MODE/" docker-compose.yml

# Grab the docker-pleroma docker file
git clone https://git.sergal.org/Sir-Boops/docker-pleroma

# Should we clone the tor image?
if [ $NET_TYPE == "darknet" ]; then
    git clone https://git.sergal.org/Sir-Boops/docker-tor
    git clone https://git.sergal.org/Sir-Boops/docker-privoxy
fi

# Build the the docker-pleroma image and get the ID
PLEROMA_NAME="pleroma:`head /dev/urandom | tr -dc A-Za-z0-9 | head -c 13 ; echo ''`"
docker build -t $PLEROMA_NAME docker-pleroma/

# Build the extras for the darknet
if [ $NET_TYPE == "darknet" ]; then
    TOR_NAME="tor:`head /dev/urandom | tr -dc A-Za-z0-9 | head -c 13 ; echo ''`"
    docker build -t $TOR_NAME docker-tor/
    docker build docker-privoxy/
fi

# Generate and copy the config file out
COND_NAME="pleroma_`head /dev/urandom | tr -dc A-Za-z0-9 | head -c 13 ; echo ''`"
docker run -it --name $COND_NAME $PLEROMA_NAME ash -c 'cd /opt/pleroma && mix generate_config'
docker cp $COND_NAME:/opt/pleroma/config config
docker rm $COND_NAME

# Create the uploads dir
mkdir uploads
chown 1000:1000 uploads

# Setup the tor config if need be
if [ $NET_TYPE == "darknet" ]; then
    COND_TOR_NAME="tor_`head /dev/urandom | tr -dc A-Za-z0-9 | head -c 13 ; echo ''`"
    docker run -it --name $COND_TOR_NAME -d $TOR_NAME
    docker cp $COND_TOR_NAME:/opt/tor/etc/tor .
    docker stop $COND_TOR_NAME
    docker rm $COND_TOR_NAME
    echo "HiddenServiceDir /opt/tor/var/lib/tor/pleroma_service/" >> tor/torrc
    echo "HiddenServicePort 80 pleroma:4000" >> tor/torrc
fi

# Copy out the .onion keys
if [ $NET_TYPE == "darknet" ]; then
    COND_TOR_NAME="tor_`head /dev/urandom | tr -dc A-Za-z0-9 | head -c 13 ; echo ''`"
    CONF_PATH=`realpath tor`
    docker run -it --name $COND_TOR_NAME --add-host "pleroma:127.0.0.1" -v $CONF_PATH:/opt/tor/etc/tor -d $TOR_NAME
    sleep 10
    docker cp $COND_TOR_NAME:/opt/tor/var/lib/tor/pleroma_service .
    docker stop $COND_TOR_NAME
    docker rm $COND_TOR_NAME
    chown 1000:1000 pleroma_service
fi

# Setup the http proxy
if [ $NET_TYPE == "darknet" ]; then
    # Create the Privoxy config
    echo "listen-address  0.0.0.0:8118" > priv-config
    echo "forward-socks5t .  tor:9050    ." >> priv-config

    echo "" >> config/generated_config.exs
    echo "config :pleroma, :http," >> config/generated_config.exs
    echo '  proxy_url: "privoxy:8118"' >> config/generated_config.exs
fi

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
if [ $NET_TYPE == "darknet" ]; then
    sed -i '0,/.*url.*/s/.*url.*/   url: [host: "'`cat pleroma_service/hostname`'", scheme: "http", port: 80],/' config/generated_config.exs
fi
cp config/generated_config.exs config/`echo $RUN_MODE`.secret.exs
