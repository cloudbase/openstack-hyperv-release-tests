#!/bin/bash
set -e

results_dir=${1:-`realpath reports`}
apache_sites_available_dir=/etc/apache2/sites-available
apache_sites_enabled_dir=/etc/apache2/sites-enabled
apache_conf_file=devstack-hyperv-results.conf

apt-get install -y apache2

cat <<EOF > $apache_sites_available_dir/$apache_conf_file
# sudo a2enmod headers
# sudo a2enmod deflate

Listen 8001
<VirtualHost *:8001>
	DocumentRoot $results_dir
	<Directory $results_dir>
		Options Indexes
		AllowOverride None
		Order allow,deny
		allow from all
		Require all granted

		AddEncoding gzip gz
		<FilesMatch "\.gz$">
			ForceType text/plain
			Header set Content-Encoding: gzip
		</FilesMatch>
	</Directory>
</VirtualHost>
EOF

ln -sf $apache_sites_available_dir/$apache_conf_file $apache_sites_enabled_dir/$apache_conf_file

service apache2 reload

