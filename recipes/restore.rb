#Determine if we're using a remote file or a local file.
if (URI(node[:chef_server_populator][:restore][:file]).scheme)
  remote_file node[:chef_server_populator][:restore][:local_path] do
    source node[:chef_server_populator][:restore][:file]
  end
  file = node[:chef_server_populator][:restore][:local_path]
else
  file = node[:chef_server_populator][:restore][:file]
end

file '/etc/chef/client.pem' do
  action :nothing
end

ruby_block 'set admin public key' do
  block do
    execute_r = run_context.resource_collection.find(:execute => 'update local client')
    execute_r.command "/opt/chef-server/embedded/bin/psql -d opscode_chef -c \"update osc_users set public_key=E'#{%x{openssl rsa -in /etc/chef-server/admin.pem -pubout}}' where username='admin'\""
  end
end

execute 'backup chef server stop' do
  command "chef-server-ctl stop erchef"
  creates '/etc/chef-server/restore.json'
end

#Drop and Restore entire chef database from file
execute 'dropping chef database' do
  command '/opt/chef-server/embedded/bin/dropdb opscode_chef'
  user 'opscode-pgsql'
  creates '/etc/chef-server/restore.json'
end

execute 'restoring chef data' do
  command "/opt/chef-server/embedded/bin/pg_restore --create --dbname=postgres #{file}"
  user 'opscode-pgsql'
  creates '/etc/chef-server/restore.json'
end

execute 'update local client' do
  command "/opt/chef-server/embedded/bin/psql -d opscode_chef -c \"update osc_users set public_key=E'#{%x{openssl rsa -in /etc/chef-server/admin.pem -pubout}}' where username='admin'\""
  user 'opscode-pgsql'
  creates '/etc/chef-server/restore.json'
  notifies :delete, 'file[/etc/chef/client.pem]'
end

execute 'backup chef server start' do
  command "chef-server-ctl start erchef"
  creates '/etc/chef-server/restore.json'
end

directory '/etc/chef-server'

file '/etc/chef-server/restore.json' do
  content JSONCompat.to_json_pretty(:date => Time.now.to_i,
                                    :file => file)
end
