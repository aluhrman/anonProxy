# anonProxy
Docker deployable high throughput anonymization proxy using tor, delegated, haproxy, and monit.

## Why?
Say you need to scrape a website anonymously, or surf the internet via tor but don't want to deal with the high latency of the tor network. Enter anonProxy! You can now run X number of tor circuits simultaneously and balance your traffic over them! Its reliable, easy to deploy, and best of all anonymous!

## How to do I deploy it?
You will need Docker and docker-compose just run:

`docker-compose up -d`

Conversely, you can include it in your own docker-compose.yml to use it within your infrastructure.

Once the proxy is deployed you can point your web browser or systems at a local http proxy hosted on port 2605 (127.0.0.1:2605)

## Tweaking
The current setup will create 15 individual tor circuits but you may modify the `i` variable in `Dockerfile` to run more or less circuits. 

Also the `p` variable defines what port to setup up the http proxy on, if you change this make sure to also modify the `EXPOSE` variable in the `Dockerfile`. Haproxy, delegated, and monit will be modified acordingly.

`RUN mkdir /opt/aproxy && /tmp/rotating_proxy_setup.rb /opt/aproxy -i 15 -p 2605`

## Credits
Setup was inspired by

* http://blog.databigbang.com/running-your-own-anonymous-rotating-proxies/
* https://github.com/mattes/rotating-proxy
