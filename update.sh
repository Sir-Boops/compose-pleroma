#!/bin/bash

docker-compose down
cd docker-pleroma && git pull && cd ..

if [ -d "docker-tor" ]; then
    cd docker-tor && git pull && cd ..
fi

if [ -d "docker-privoxy" ]; then
    cd docker-privoxy && git pull && cd ..
fi

docker-compose up -d --build
