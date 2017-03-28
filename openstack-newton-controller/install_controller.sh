#!/bin/bash

function init_env()
{
    echo controller > /etc/hostname
    hostname controller
    cp ./env/hosts /etc/hosts
    sed -i "s/MIP/$1/g" /etc/hosts
    killall -9 epmd rabbitmq-server beam.smp

    cp ./env/99-openstack.cnf /etc/mysql/mariadb.conf.d/
    service mysql restart
    mysql -uroot -e "set password for 'root'@'localhost'=password('kx123');"    

    cp /etc/memcached.conf /etc/memcached.conf.autoback-$(date +%Y%m%d%H%M%S)
    cp /etc/openstack-dashboard/local_settings.py /etc/openstack-dashboard/local_settings.py.autoback-$(date +%Y%m%d%H%M%S)
    cp ./env/memcached.conf /etc/memcached.conf
    cp ./env/local_settings.py /etc/openstack-dashboard/local_settings.py
    service memcached restart

    service rabbitmq-server restart
    rabbitmqctl add_user openstack rabbit
    rabbitmqctl set_permissions openstack ".*" ".*" ".*"
}

function install_keystone()
{
    mysql -u$1 -p$2 -e "create database keystone"
    mysql -u$1 -p$2 -e "GRANT ALL PRIVILEGES ON keystone.* TO 'keystone'@'localhost' IDENTIFIED BY 'keystone'";
    mysql -u$1 -p$2 -e "GRANT ALL PRIVILEGES ON keystone.* TO 'keystone'@'%' IDENTIFIED BY 'keystone'";
    cp /etc/keystone/keystone.conf /etc/keystone/keystone.conf.autoback-$(date +%Y%m%d%H%M%S)
    cp ./keystone/keystone.conf /etc/keystone/keystone.conf
    su -s /bin/sh -c "keystone-manage db_sync" keystone
    keystone-manage fernet_setup --keystone-user keystone --keystone-group keystone
    keystone-manage credential_setup --keystone-user keystone --keystone-group keystone
    keystone-manage bootstrap --bootstrap-password admin \
  --bootstrap-admin-url http://controller:35357/v3/ \
  --bootstrap-internal-url http://controller:35357/v3/ \
  --bootstrap-public-url http://controller:5000/v3/ \
  --bootstrap-region-id RegionOne

    cp /etc/apache2/apache2.conf /etc/apache2/apache2.conf.autoback-$(date +%Y%m%d%H%M%S)
    cp ./keystone/apache2.conf /etc/apache2/apache2.conf
    service apache2 restart
    rm -f /var/lib/keystone/keystone.db
    export OS_USERNAME=admin
    export OS_PASSWORD=admin
    export OS_PROJECT_NAME=admin
    export OS_USER_DOMAIN_NAME=Default
    export OS_PROJECT_DOMAIN_NAME=Default
    export OS_AUTH_URL=http://controller:35357/v3
    export OS_IDENTITY_API_VERSION=3
    openstack project create --domain default --description "Service Project" service
    openstack project create --domain default --description "Demo Project" demo
    openstack user create --domain default --password demo demo
    openstack role create user
    openstack role add --project demo --user demo user

    cp ./keystone/admin-openrc.sh /root/
    unset OS_AUTH_URL OS_PASSWORD
    echo "Keystone install ok..."
}

function install_glance()
{
    mysql -u$1 -p$2 -e "create database glance"
    mysql -u$1 -p$2 -e "GRANT ALL PRIVILEGES ON glance.* TO 'glance'@'localhost' IDENTIFIED BY 'glance'";
    mysql -u$1 -p$2 -e "GRANT ALL PRIVILEGES ON glance.* TO 'glance'@'%' IDENTIFIED BY 'glance'";
    source /root/admin-openrc.sh
    openstack user create --domain default  --password glance glance
    openstack role add --project service --user glance admin
    openstack service create --name glance --description "OpenStack Image" image
    openstack endpoint create --region RegionOne image public http://controller:9292
    openstack endpoint create --region RegionOne image internal http://controller:9292
    openstack endpoint create --region RegionOne image admin http://controller:9292
    cp /etc/glance/glance-api.conf /etc/glance/glance-api.conf.autoback-$(date +%Y%m%d%H%M%S)
    cp /etc/glance/glance-registry.conf /etc/glance/glance-registry.conf.autoback-$(date +%Y%m%d%H%M%S)
    cp ./glance/glance-api.conf /etc/glance/glance-api.conf
    cp ./glance/glance-registry.conf /etc/glance/glance-registry.conf
    su -s /bin/sh -c "glance-manage db_sync" glance
    service glance-api restart
    service glance-registry restart
}

function install_nova()
{
    mysql -u$1 -p$2 -e "create database nova_api"
    mysql -u$1 -p$2 -e "create database nova"
    mysql -u$1 -p$2 -e "GRANT ALL PRIVILEGES ON nova_api.* TO 'nova'@'localhost' IDENTIFIED BY 'nova'";
    mysql -u$1 -p$2 -e "GRANT ALL PRIVILEGES ON nova.* TO 'nova'@'localhost' IDENTIFIED BY 'nova'";
    mysql -u$1 -p$2 -e "GRANT ALL PRIVILEGES ON nova_api.* TO 'nova'@'%' IDENTIFIED BY 'nova'";
    mysql -u$1 -p$2 -e "GRANT ALL PRIVILEGES ON nova.* TO 'nova'@'%' IDENTIFIED BY 'nova'";
    source /root/admin-openrc.sh
    openstack user create --domain default  --password nova nova
    openstack role add --project service --user nova admin
    openstack service create --name nova --description "OpenStack Compute" compute
    openstack endpoint create --region RegionOne compute public http://controller:8774/v2.1/%\(tenant_id\)s
    openstack endpoint create --region RegionOne compute internal http://controller:8774/v2.1/%\(tenant_id\)s
    openstack endpoint create --region RegionOne compute admin http://controller:8774/v2.1/%\(tenant_id\)s
    cp /etc/nova/nova.conf /etc/nova/nova.conf.autoback-$(date +%Y%m%d%H%M%S)
    cp /etc/nova/nova-compute.conf /etc/nova/nova-compute.conf.autoback-$(date +%Y%m%d%H%M%S)
    cp ./nova/nova.conf /etc/nova/nova.conf
    sed -i "s/MIP/${3}/g"  /etc/nova/nova.conf
    cat /proc/cpuinfo |egrep '(vmx|svm)' >> /dev/null
    if [ $? -ne 0 ];then
        sed -i 's/kvm/qemu/g' /etc/nova/nova-compute.conf
    fi
    su -s /bin/sh -c "nova-manage api_db sync" nova
    su -s /bin/sh -c "nova-manage db sync" nova
    service nova-api restart
    service nova-consoleauth restart
    service nova-scheduler restart
    service nova-conductor restart
    service nova-novncproxy restart
    service nova-compute restart
}

function install_neutron()
{
    mysql -u$1 -p$2 -e "create database neutron"
    mysql -u$1 -p$2 -e "GRANT ALL PRIVILEGES ON neutron.* TO 'neutron'@'localhost' IDENTIFIED BY 'neutron'";
    mysql -u$1 -p$2 -e "GRANT ALL PRIVILEGES ON neutron.* TO 'neutron'@'%' IDENTIFIED BY 'neutron'";
    source /root/admin-openrc.sh
    openstack user create --domain default  --password neutron neutron
    openstack role add --project service --user neutron admin
    openstack service create --name neutron --description "OpenStack Networking" network
    openstack endpoint create --region RegionOne network public http://controller:9696
    openstack endpoint create --region RegionOne network internal http://controller:9696
    openstack endpoint create --region RegionOne network admin http://controller:9696
    cp /etc/neutron/neutron.conf /etc/neutron/neutron.conf.autoback-$(date +%Y%m%d%H%M%S)
    cp /etc/neutron/l3_agent.ini /etc/neutron/l3_agent.ini.autoback-$(date +%Y%m%d%H%M%S)
    cp /etc/neutron/dhcp_agent.ini /etc/neutron/dhcp_agent.ini.autoback-$(date +%Y%m%d%H%M%S)
    cp /etc/neutron/metadata_agent.ini /etc/neutron/metadata_agent.ini.autoback-$(date +%Y%m%d%H%M%S)
    cp /etc/neutron/plugins/ml2/ml2_conf.ini /etc/neutron/plugins/ml2/ml2_conf.ini.autoback-$(date +%Y%m%d%H%M%S)
    cp /etc/neutron/plugins/ml2/openvswitch_agent.ini /etc/neutron/plugins/ml2/openvswitch_agent.ini.autoback-$(date +%Y%m%d%H%M%S)
    cp ./neutron/neutron.conf /etc/neutron/neutron.conf
    cp ./neutron/l3_agent.ini /etc/neutron/l3_agent.ini
    cp ./neutron/dhcp_agent.ini /etc/neutron/dhcp_agent.ini
    cp ./neutron/metadata_agent.ini /etc/neutron/metadata_agent.ini
    cp ./neutron/ml2_conf.ini /etc/neutron/plugins/ml2/ml2_conf.ini
    cp ./neutron/openvswitch_agent.ini /etc/neutron/plugins/ml2/openvswitch_agent.ini
    cp ./neutron/policy.json /etc/neutron/policy.json
    sed -i "s/MIP/$3/g" /etc/neutron/plugins/ml2/openvswitch_agent.ini
    su -s /bin/sh -c "neutron-db-manage --config-file /etc/neutron/neutron.conf --config-file /etc/neutron/plugins/ml2/ml2_conf.ini upgrade head" neutron
    service openvswitch-switch restart
    service nova-api restart
    service neutron-server restart
    service neutron-dhcp-agent restart
    service neutron-metadata-agent restart
    service neutron-l3-agent restart
    cp ./neutron/interfaces /etc/network/interfaces
    cp ./neutron/enp3s0f0.cfg /etc/network/interfaces.d/enp3s0f0.cfg
    cp ./neutron/br-public.cfg /etc/network/interfaces.d/
    sed -i "s/manageip/$3/g" /etc/network/interfaces.d/br-public.cfg
    sed -i "s/managenetmask/$4/g" /etc/network/interfaces.d/br-public.cfg
    sed -i "s/managegateway/$5/g" /etc/network/interfaces.d/br-public.cfg
    ifconfig enp3s0f0 0;ovs-vsctl add-br br-public;ovs-vsctl add-port br-public enp3s0f0;ifconfig br-public $3 netmask $4;route add default gateway $5
    service neutron-openvswitch-agent restart
}

function install_cinder()
{
    mysql -u$1 -p$2 -e "create database cinder"
    mysql -u$1 -p$2 -e "GRANT ALL PRIVILEGES ON cinder.* TO 'cinder'@'localhost' IDENTIFIED BY 'cinder'";
    mysql -u$1 -p$2 -e "GRANT ALL PRIVILEGES ON cinder.* TO 'cinder'@'%' IDENTIFIED BY 'cinder'";
    source /root/admin-openrc.sh
    openstack user create --domain default  --password cinder cinder
    openstack role add --project service --user cinder admin
    openstack service create --name cinder --description "OpenStack Block Storage" volume
    openstack service create --name cinderv2 --description "OpenStack Block Storage" volumev2
    openstack endpoint create --region RegionOne volume public http://controller:8776/v1/%\(tenant_id\)s
    openstack endpoint create --region RegionOne volume internal http://controller:8776/v1/%\(tenant_id\)s
    openstack endpoint create --region RegionOne volume admin http://controller:8776/v1/%\(tenant_id\)s
    openstack endpoint create --region RegionOne volumev2 public http://controller:8776/v2/%\(tenant_id\)s
    openstack endpoint create --region RegionOne volumev2 internal http://controller:8776/v2/%\(tenant_id\)s
    openstack endpoint create --region RegionOne volumev2 admin http://controller:8776/v2/%\(tenant_id\)s
    cp /etc/cinder/cinder.conf /etc/cinder/cinder.conf.autoback-$(date +%Y%m%d%H%M%S)
    cp ./cinder/cinder.conf /etc/cinder/cinder.conf
    sed -i "s/MIP/${3}/g"  /etc/cinder/cinder.conf
    su -s /bin/sh -c "cinder-manage db sync" cinder
    service cinder-scheduler restart
    service cinder-api restart
    pvcreate /dev/sdb
    vgcreate cinder-volumes /dev/sdb
    service tgt restart
    service cinder-volume restart
}


MysqlUser=root
MysqlPass=kx123
ManageEth="enp3s0f0"
ManageIP=$(ifconfig ${ManageEth}|grep "inet addr" |awk '{print $2}'|awk -F: '{print $2}')
Manage_Netmask=$(ifconfig ${ManageEth}|grep "inet addr"|awk '{print $4}'|awk -F: '{print $2}')
Manage_Gateway=$(ip r|grep "default via"|awk '{print $3}')

if [ -z $ManageIP ];then
    echo "cann't get ip from $ManageEth"
    exit 1
fi

ps aux|grep apt|grep -v grep|awk '{print $2}'>/home/apt_proc.txt
cat /home/apt_proc.txt | while read line
do
    kill -9 $line
done

dpkg -i sihua-newton-apt-source-20170324.deb
if [ $? -ne 0 ];then
    echo "dpkg status database is locked by another process..."
    echo "please try again..."
    exit 1
fi
apt update
apt-get -y install python-openstackclient mariadb-server python-pymysql mongodb-server mongodb-clients python-pymongo rabbitmq-server memcached python-memcache keystone glance nova-api nova-conductor nova-consoleauth nova-novncproxy nova-scheduler nova-compute neutron-server neutron-plugin-ml2 neutron-linuxbridge-agent neutron-l3-agent neutron-dhcp-agent neutron-metadata-agent openvswitch-common openvswitch-switch neutron-openvswitch-agent python-neutron-lbaas neutron-lbaas-common neutron-lbaasv2-agent openstack-dashboard cinder-api cinder-scheduler cinder-volume

dpkg -i ./deb/*.deb

init_env $ManageIP
install_keystone $MysqlUser $MysqlPass
install_glance $MysqlUser $MysqlPass
install_nova $MysqlUser $MysqlPass $ManageIP
install_neutron $MysqlUser $MysqlPass $ManageIP $Manage_Netmask $Manage_Gateway
install_cinder $MysqlUser $MysqlPass $ManageIP

cp ./env/rc.local /etc/rc.local
