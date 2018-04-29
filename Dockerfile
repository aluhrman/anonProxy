FROM ubuntu:trusty

#Update and install wget
RUN apt-get update && apt-get install -y wget gnupg2

# Download and install delegated
RUN cd /tmp && wget http://www.delegate.org/ftp/pub/DeleGate/beta/bin-latest9/old/fc6_64-dg.gz && gunzip fc6_64-dg.gz && mv fc6_64-dg /usr/local/bin/delegated && chmod +x /usr/local/bin/delegated

# Add tor sources
RUN echo 'deb http://deb.torproject.org/torproject.org trusty main' | tee /etc/apt/sources.list.d/torproject.list

# Add gpg key for tor sources
RUN gpg --keyserver keyserver.ubuntu.com --recv A3C4F0F979CAA22CDBA8F512EE8CBC9E886DDD89 && gpg --export A3C4F0F979CAA22CDBA8F512EE8CBC9E886DDD89 | apt-key add -

# Install Packages
RUN apt-get update && apt-get install -y haproxy monit ruby tor

# Stop and remove tor service in the event it's running
RUN service tor stop && update-rc.d -f tor remove

# Copy install script into container
COPY assets/rotating_proxy_setup.rb /tmp/

# Make install script executable
RUN chmod +x /tmp/rotating_proxy_setup.rb

# Setup proxy (modify i for more or less circuits)
RUN mkdir /opt/aproxy && /tmp/rotating_proxy_setup.rb /opt/aproxy -i 15 -p 2605 

RUN chown -R root:root /opt/aproxy && chmod -R 777 /opt/aproxy && cp /opt/aproxy/etc/monitrc /etc/monit/monitrc && cp /opt/aproxy/etc/monit_htpasswd /etc/monit/

# Expose proxy port
EXPOSE 2605

# Restart proxy service
CMD ["monit", "-Ic", "/etc/monit/monitrc"]
