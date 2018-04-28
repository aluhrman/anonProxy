# anonProxy
Docker deployable high throughput anonymization proxy using tor, delegated, haproxy, and monit.

# Why?
Say you need to scrape a website anonymously, or surf the internet via tor but don't want to deal with the high latency of the tor network. Enter anonProxy! You can now run X number of tor circuits simultaneously and balance your traffic over them! Its reliable, easy to deploy, and best of all anonymous!

# How to do I deploy it?
You will need Docker and Docker-Compse

`$docker-compose up`

