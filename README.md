# Compose-pleroma

This script will automatically build and initialize a basic pleroma install 

## What you need
All you need to use this script is
* bash
* docker
* docker-compose ( That can handle v3 composer files )
* git

## Installing

!! Currently on installs in dev mode !!

1. `git clone https://git.sergal.org/Sir-Boops/compose-pleroma`
2. `cd compose-pleroma`
3. `./bootstrap.sh`
4. `docker-compose up`
5. Open a web browser and goto `127.0.0.1:4000` to see the new instance!

## Updating
To update simply `cd` into the `docker-pleroma` folder and run `git pull`

Once that is completed `cd` back to the root folder `compose-pleroma` and simply run `docker-compose up --build`

That's it you're now up to date!

