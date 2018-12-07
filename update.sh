#!/bin/bash
docker-compose pull --no-parallel
docker-compose down
docker-compose up -d
