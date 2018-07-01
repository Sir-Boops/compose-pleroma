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

# See if we are starting using TOR
echo "Will you be running this instance on the 'clearnet' or 'darknet' ? ( Type your answer without the ' )"
echo ""
echo "If you're not sure just type 'clearnet'"
echo ""
read -p "Network Type: " NET_TYPE
NET_TYPE=`echo $NET_TYPE | awk '{ print tolower($0) }'`
clear

# Make sure the user chose a run type
if [ "$RUN_MODE" != "prod" ] && [ "$RUN_MODE" != "dev" ]; then
    echo "You have to choose 'prod' or 'dev' !"
    echo "Exiting, no changes made"
    echo ""
    exit 1
fi

# Make sure the user chose a network type
if [ "$NET_TYPE" != "clearnet" ] && [ "$NET_TYPE" != "darknet" ]; then
    echo "You have to choose 'clearnet' or 'darknet' !"
    echo "Exiting, no changes made"
    echo ""
    exit 1
fi

# If using TOR check what onion version we are going to be using
if [ "$NET_TYPE" == "darknet" ]; then
    echo "Do you wish to use a 'v2' or a 'v3' onion address ? ( Type your answer without the ' )"
    echo ""
    echo "If you're not sure just type 'v3'"
    echo ""
    read -p "Onion Type: " ONION_TYPE
    ONION_TYPE=`echo $ONION_TYPE | awk '{ print tolower($0) }'`
    clear
fi

# Make sure the user typed something sane for ONION_TYPE
if [ "$NET_TYPE" == "darknet" ]; then
  if [ "$ONION_TYPE" != "v2" ] && [ "$ONION_TYPE" != "v3" ]; then
    echo "You have to choose 'v2' or 'v3' !"
    echo "Exiting no changes made"
    echo ""
    exit 1
  fi
fi

# Copy out the needed docker-compose.yml file
echo "Copying docker-compose.yml config"
echo ""
sleep 1
if [ "$NET_TYPE" == "darknet" ]; then
    cp compose-scripts/darknet.yml docker-compose.yml
else
    cp compose-scripts/clearnet.yml docker-compose.yml
fi
clear

# Update the compose file
echo "Setting run mode in docker-compose.yml"
echo ""
sleep 1
sed -i "s/%RUN_MODE%/$RUN_MODE/" docker-compose.yml
clear

# Grab the docker-pleroma docker file
echo "Cloning required repos"
echo ""
sleep 1
git clone https://git.sergal.org/Sir-Boops/docker-pleroma

# Should we clone the tor image?
if [ "$NET_TYPE" == "darknet" ]; then
    git clone https://git.sergal.org/Sir-Boops/docker-tor
    git clone https://git.sergal.org/Sir-Boops/docker-privoxy
fi
clear

# Build the the docker-pleroma image and get the ID
echo "Building required docker containers"
echo ""
sleep 1
PLEROMA_NAME="pleroma:`head /dev/urandom | tr -dc A-Za-z0-9 | head -c 13 ; echo ''`"
docker build -t $PLEROMA_NAME docker-pleroma/

# Build the extras for the darknet
if [ "$NET_TYPE" == "darknet" ]; then
    TOR_NAME="tor:`head /dev/urandom | tr -dc A-Za-z0-9 | head -c 13 ; echo ''`"
    docker build -t $TOR_NAME docker-tor/
fi
clear

# Generate and copy the config file out
echo "Generating pleroma config!"
echo ""
if [ "$NET_TYPE" == "darknet" ]; then
    echo "Since you're using TOR type anything you want for the URL"
fi
echo ""
sleep 5
COND_NAME="pleroma_`head /dev/urandom | tr -dc A-Za-z0-9 | head -c 13 ; echo ''`"
docker run -it --name $COND_NAME $PLEROMA_NAME ash -c 'cd /opt/pleroma && mix generate_config'
docker cp $COND_NAME:/opt/pleroma/config config
docker rm $COND_NAME
clear

# Create the uploads dir
echo "Creating uploads dir"
echo ""
sleep 1
mkdir uploads
chown 1000:1000 uploads
clear

# Setup the tor config if need be
if [ "$NET_TYPE" == "darknet" ]; then
    echo "Creating tor config"
    echo ""
    sleep 1
    COND_TOR_NAME="tor_`head /dev/urandom | tr -dc A-Za-z0-9 | head -c 13 ; echo ''`"
    docker run -it --name $COND_TOR_NAME -d $TOR_NAME
    docker cp $COND_TOR_NAME:/opt/tor/etc/tor .
    docker stop $COND_TOR_NAME
    docker rm $COND_TOR_NAME
    echo "HiddenServiceDir /opt/tor/var/lib/tor/pleroma_service/" >> tor/torrc
    if [ "$ONION_TYPE" == "v3" ]; then
        echo "HiddenServiceVersion 3" >> tor/torrc
    fi
    echo "HiddenServicePort 80 pleroma:4000" >> tor/torrc
    clear
fi

# Copy out the .onion keys
if [ "$NET_TYPE" == "darknet" ]; then
    echo "Generating onion address"
    echo ""
    sleep 1
    COND_TOR_NAME="tor_`head /dev/urandom | tr -dc A-Za-z0-9 | head -c 13 ; echo ''`"
    CONF_PATH=`realpath tor`
    docker run -it --name $COND_TOR_NAME --add-host "pleroma:127.0.0.1" -v $CONF_PATH:/opt/tor/etc/tor -d $TOR_NAME
    sleep 10
    docker cp $COND_TOR_NAME:/opt/tor/var/lib/tor/pleroma_service .
    docker stop $COND_TOR_NAME
    docker rm $COND_TOR_NAME
    chown 1000:1000 -R pleroma_service
    chmod 700 pleroma_service
    chmod 770 pleroma_service/*
    clear
fi

# Setup the http proxy
if [ "$NET_TYPE" == "darknet" ]; then
    echo "Creating privoxy config"
    echo ""
    sleep 1
    # Create the Privoxy config
    echo "listen-address  0.0.0.0:8118" > priv-config
    echo "forward-socks5t .  tor:9050    ." >> priv-config

    echo "" >> config/generated_config.exs
    echo "config :pleroma, :http," >> config/generated_config.exs
    echo '  proxy_url: "privoxy:8118"' >> config/generated_config.exs
    clear
fi

# Init the database
echo "Initlizing the database"
echo ""
sleep 1
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
clear

# Get the config ready
echo "Setting config options"
echo ""
sleep 1
sed -i '/password:/c\  password: "pleroma",' config/generated_config.exs
sed -i '/hostname:/c\  hostname: "postgres",' config/generated_config.exs
if [ "$NET_TYPE" == "darknet" ]; then
    sed -i '0,/.*url.*/s/.*url.*/   url: [host: "'`cat pleroma_service/hostname`'", scheme: "http", port: 80],/' config/generated_config.exs
fi
cp config/generated_config.exs config/`echo $RUN_MODE`.secret.exs
clear

echo "Done! Your pleroma instance has been setup and it ready to go!"
echo ""
if [ "$NET_TYPE" == "darknet" ]; then
    echo "Your onion address is: `cat pleroma_service/hostname`"
    echo ""
fi

if  [ "$NET_TYPE" == "clearnet" ]; then
    echo "Pleroma has been setup to listen on '127.0.0.1:4000'"
    echo ""
    echo "For an nginx config example please see 'https://git.pleroma.social/pleroma/pleroma/blob/develop/installation/pleroma.nginx'"
    echo ""
fi
echo "Now type 'docker-compose up -d' to start your instance!"
echo ""
