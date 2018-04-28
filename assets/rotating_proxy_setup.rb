#!/usr/bin/env ruby
require 'optparse'
require 'erb'

def which(executable)
  path = `which #{executable}`.strip
  if path == ""
    return nil 
  else
    return path
  end
end

def whoami
  return `whoami`.strip
end


options = {}
options[:tor_instances] = 1
options[:monit_exec] = which('monit')
options[:delegated_exec] = which('delegated')
options[:tor_exec] = which('tor')
options[:haproxy_exec] = which('haproxy')
options[:haproxy_port] = 3218
options[:start_port] = 40200
options[:monit_web] = true
options[:monit_web_port] = 3219
options[:run_as_user] = whoami




parser = OptionParser.new do |opts|
  opts.banner = "Usage: rotating_proxy_setup.rb <working-dir> [options]"
  opts.on("-i", "--tor-instances NUMBER", "Number of Tor instances [#{options[:tor_instances]}]") do |number|
    options[:tor_instances] = number.to_i
  end
  opts.on("--run-as-user USER", "Run processes as user [#{options[:run_as_user]}]") do |user|
    options[:run_as_user] = user
  end  
  opts.on("--monit-exec PATH", "Path to monit executable [#{options[:monit_exec]}]") do |path|
    options[:monit_exec] = path
  end
  opts.on("--delegated-exec PATH", "Path to delegated executable [#{options[:delegated_exec]}]") do |path|
    options[:delegated_exec] = path
  end
  opts.on("--tor-exec PATH", "Path to tor executable [#{options[:tor_exec]}]") do |path|
    options[:tor_exec] = path
  end
  opts.on("--haproxy-exec PATH", "Path to haproxy executable [#{options[:haproxy_exec]}]") do |path|
    options[:haproxy_exec] = path
  end
  opts.on("-p", "--haproxy-port PORT", "HAProxy Port [#{options[:haproxy_port]}]") do |port|
    options[:haproxy_port] = port.to_i
  end
  opts.on("-P", "--start-port PORT", "Start port (end_port = start_port + tor_instances*2) [#{options[:start_port]}]") do |port|
    options[:start_port] = port.to_i
  end
  opts.on("--monit-web-port PORT", "Monit Web Interface Port [#{options[:monit_web_port]}]") do |port|
    options[:monit_web_port] = port.to_i
  end
  opts.on_tail("--[no-]monit-web", "Enable/ Disable Monit Web Interface [#{options[:monit_web] ? 'enabled' : 'disabled'}]") do |bool|
    options[:monit_web] = bool
  end
  opts.on_tail("-h", "--help", "Show this message") do
    puts opts
    exit
  end
end
parser.parse!

options[:working_dir] = ARGV[0] || nil
if options[:working_dir].nil? 
  raise("Please specify working dir!")
else
  options[:working_dir] = File.absolute_path(options[:working_dir])  
  raise("Directory '#{options[:working_dir]}' does not exist! Please create it first.") unless File.exist?(options[:working_dir])
end

raise("At least 1 Tor instance is required") unless options[:tor_instances] > 0
raise("'monit' executable not found in '#{options[:monit_exec]}'") if options[:monit_exec].nil? or not File.exists?(options[:monit_exec])
raise("'tor' executable not found in '#{options[:tor_exec]}'") if options[:tor_exec].nil? or not File.exists?(options[:tor_exec])
raise("'haproxy' executable not found in '#{options[:haproxy_exec]}'") if options[:haproxy_exec].nil? or not File.exists?(options[:haproxy_exec])
raise("'delegated' executable not found in '#{options[:delegated_exec]}'") if options[:delegated_exec].nil? or not File.exists?(options[:delegated_exec])
raise("Invalid haproxy_port") unless options[:haproxy_port] > 0
raise("Invalid start_port") unless options[:start_port] > 0
raise("Invalid monit_web_port") unless options[:monit_web_port] > 0
raise("Missing run_as_user") if options[:run_as_user] == "" or options[:run_as_user].nil?

# create delegated -> tor port mapping
tor_delegated_map = []
options[:tor_instances].times.each do |i|
  tor_port = options[:start_port] + i * 2
  delegated_port = options[:start_port] + i * 2 + 1
  tor_delegated_map << {:tor => tor_port, :delegated => delegated_port}
end


haproxy_config_template = <<EOF
# http://cbonte.github.io/haproxy-dconv/configuration-1.5.html
global
  daemon
  maxconn 256
 
defaults
  mode http
  timeout connect 5s
  timeout client 60s
  timeout server 60s

# listen stats *:1936
#   mode            http
#   log             global
#   maxconn 10
#   clitimeout      100s
#   srvtimeout      100s
#   contimeout      100s
#   timeout queue   100s
#   stats enable
#   stats hide-version
#   stats refresh 30s
#   stats show-node
#   stats auth admin:admin123
#   stats uri /haproxy?stats
 
frontend rotate_proxies
  bind *:<%= options[:haproxy_port] %>
  default_backend tor
  option http_proxy
 
backend tor
  option http_proxy
  balance leastconn # http://cbonte.github.io/haproxy-dconv/configuration-1.5.html#balance

  <% tor_delegated_map.each do |m| %>
  server delegated<%= m[:delegated] %> 127.0.0.1:<%= m[:delegated] %>
  <% end %>
EOF

directories = %w(etc pids logs logs/tor logs/delegated tor-data delegated-data)
monit_config_template = <<EOF
# http://mmonit.com/monit/documentation

set daemon 30
# set pidfile <%= options[:working_dir] %>/pids/monit.pid
# set logfile <%= options[:working_dir] %>/logs/monit.log

<% if options[:monit_web] %>
set httpd 
  port <%= options[:monit_web_port] %> 
  allow cleartext #{options[:working_dir]}/etc/monit_htpasswd
<% end %>


# check directories
<% directories.each do |dir| %>
check directory <%= dir %> with path <%= options[:working_dir] %>/<%= dir %>
  if does not exist then exec "/bin/bash -c 'mkdir -p <%= options[:working_dir] %>/<%= dir %>'"
<% end %>


# tor
<% tor_delegated_map.each do |m| %>
check process tor<%= m[:tor] %> with pidfile <%= options[:working_dir] %>/pids/tor<%= m[:tor] %>.pid
  group proxy
  start program = "/bin/bash -c '<%= options[:tor_exec] %> \
    --SocksPort <%= m[:tor] %> \
    --NewCircuitPeriod 30  \
    --DataDirectory <%= options[:working_dir] %>/tor-data/tor<%= m[:tor] %> \
    --PidFile <%= options[:working_dir] %>/pids/tor<%= m[:tor] %>.pid \
    --Log \"warn file  <%= options[:working_dir] %>/logs/tor/tor<%= m[:tor] %>.log\" \
    --RunAsDaemon 1'"
  stop program  = "/bin/bash -c '/bin/kill -s SIGTERM $(cat <%= options[:working_dir] %>/pids/tor<%= m[:tor] %>.pid)'" 
  if mem > 32 MB for 3 cycles then restart
  if cpu > 30% for 5 cycles then restart
<% end %>
 
# delegated
# http://www.delegate.org/delegate/Manual.htm
<% tor_delegated_map.each do |m| %>
check process delegated<%= m[:delegated] %> with pidfile <%= options[:working_dir] %>/pids/delegated<%= m[:delegated] %>.pid
  group proxy
  start program = "/bin/bash -c '<%= options[:delegated_exec] %> \
    -P<%= m[:delegated] %> \
    SERVER=http \
    DGROOT=<%= options[:working_dir] %>/delegated-data/<%= m[:delegated] %> \
    SOCKS=127.0.0.1:<%= m[:tor] %> \
    PIDFILE=<%= options[:working_dir] %>/pids/delegated<%= m[:delegated] %>.pid \
    LOGFILE=<%= options[:working_dir] %>/logs/delegated/delegated<%= m[:delegated] %>.log \
    ADMIN=example@example.com \
    HTTPCONF=kill-qhead:Via'" \
    as uid <%= options[:run_as_user] %> and gid <%= options[:run_as_user] %>
  stop program  = "/bin/bash -c '/bin/kill -s SIGTERM $(cat <%= options[:working_dir] %>/pids/delegated<%= m[:delegated] %>.pid)'"
  if mem > 8 MB for 3 cycles then restart
  if cpu > 30% for 5 cycles then restart
  depends on tor<%= m[:tor] %>
<% end %>

# haproxy
check process haproxy with pidfile <%= options[:working_dir] %>/pids/haproxy.pid
  group proxy
  start program = "/bin/bash -c '<%= options[:haproxy_exec] %> \
    -f <%= options[:working_dir] %>/etc/haproxy.cfg \
    -p <%= options[:working_dir] %>/pids/haproxy.pid'" \
    as uid <%= options[:run_as_user] %> and gid <%= options[:run_as_user] %>
  stop program  = "/bin/bash -c '/bin/kill $(cat <%= options[:working_dir] %>/pids/haproxy.pid)'"
  if mem > 8 MB for 3 cycles then restart
  if cpu > 40% for 5 cycles then restart
  depends on <%= tor_delegated_map.collect{|m| "tor" + m[:tor].to_s }.join(', ') %>, <%= tor_delegated_map.collect{|m| "delegated" + m[:delegated].to_s }.join(', ') %>


# monitor monitrc to restart monit itself on changes
check file monitrc with path <%= options[:working_dir] %>/etc/monitrc
  if changed md5 checksum
    then exec "/bin/bash -c '<%= options[:monit_exec] %> -c <%= options[:working_dir] %>/etc/monitrc reload'"


# monitor haproxy.cfg to restart haproxy on changes
check file haproxy.cfg with path <%= options[:working_dir] %>/etc/haproxy.cfg
  if changed md5 checksum
    then exec "/bin/bash -c '<%= options[:haproxy_exec] %> \
      -f <%= options[:working_dir] %>/etc/haproxy.cfg \
      -p <%= options[:working_dir] %>/pids/haproxy.pid \
      -sf $(cat <%= options[:working_dir] %>/pids/haproxy.pid)'"


# include some more config files ending with *.monitrc
# make sure all files are chmod 0600!
include <%= options[:working_dir] %>/etc/*.monitrc

EOF



haproxy_config = ERB.new(haproxy_config_template).result
monit_config = ERB.new(monit_config_template).result

directories.each do |dir|
  Dir.mkdir("#{options[:working_dir]}/#{dir}") unless Dir.exists?("#{options[:working_dir]}/#{dir}")
end

File.open("#{options[:working_dir]}/etc/haproxy.cfg", 'w') do |f|
  f.write(haproxy_config)
end

File.open("#{options[:working_dir]}/etc/monitrc", 'w') do |f|
  f.write(monit_config)
end
File.chmod(0600, "#{options[:working_dir]}/etc/monitrc") # required by monit

# create random password for monit web interface if non exists
unless File.exists?("#{options[:working_dir]}/etc/monit_htpasswd")
  password = rand(36**7...36**8).to_s(36)
  File.open("#{options[:working_dir]}/etc/monit_htpasswd", "w") do |f|
    f.write("admin:#{password}\n")
  end
  File.chmod(0600, "#{options[:working_dir]}/etc/monit_htpasswd")
  puts "#{options[:working_dir]}/etc/monit_htpasswd created. Please look up your monit web interface credentials in this file."
end



puts "Done."
