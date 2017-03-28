#!/bin/bash

function install_nova()
{
    cp /etc/nova/nova.conf /etc/nova/nova.conf.autoback-$(date +%Y%m%d%H%M%S)
    cp /etc/nova/nova-compute.conf /etc/nova/nova-compute.conf.autoback-$(date +%Y%m%d%H%M%S)
    cp ./nova/nova.conf /etc/nova/nova.conf
    sed -i "s/MIP/${3}/g"  /etc/nova/nova.conf
    sed -i "s/CIP/${4}/g"  /etc/nova/nova.conf
    cat /proc/cpuinfo |egrep '(vmx|svm)' >> /dev/null
    if [ $? -ne 0 ];then
        sed -i 's/kvm/qemu/g' /etc/nova/nova-compute.conf
    fi
    service nova-compute restart
}

function install_neutron()
{
    cp /etc/neutron/neutron.conf /etc/neutron/neutron.conf.autoback-$(date +%Y%m%d%H%M%S)
    cp /etc/neutron/plugins/ml2/ml2_conf.ini /etc/neutron/plugins/ml2/ml2_conf.ini.autoback-$(date +%Y%m%d%H%M%S)
    cp /etc/neutron/plugins/ml2/openvswitch_agent.ini /etc/neutron/plugins/ml2/openvswitch_agent.ini.autoback-$(date +%Y%m%d%H%M%S)
    cp ./neutron/neutron.conf /etc/neutron/neutron.conf
    cp ./neutron/ml2_conf.ini /etc/neutron/plugins/ml2/ml2_conf.ini
    cp ./neutron/openvswitch_agent.ini /etc/neutron/plugins/ml2/openvswitch_agent.ini
    cp ./neutron/policy.json /etc/neutron/policy.json
    sed -i "s/MIP/$3/g" /etc/neutron/plugins/ml2/openvswitch_agent.ini
    service openvswitch-switch restart
    service neutron-openvswitch-agent restart
}

function install_cinder()
{
    cp /etc/cinder/cinder.conf /etc/cinder/cinder.conf.autoback-$(date +%Y%m%d%H%M%S)
    cp ./cinder/cinder.conf /etc/cinder/cinder.conf
    sed -i "s/MIP/${3}/g"  /etc/cinder/cinder.conf
    pvcreate /dev/sdb
    vgcreate cinder-volumes /dev/sdb
    service tgt restart
    service cinder-volume restart
}


MysqlUser=root
MysqlPass=kx123
ManageEth="enp3s0f0"
#ManageEth="eth0"
ManageIP=$(ifconfig ${ManageEth}|grep "inet addr" |awk '{print $2}'|awk -F: '{print $2}')
Manage_Netmask=$(ifconfig ${ManageEth}|grep "inet addr"|awk '{print $4}'|awk -F: '{print $2}')
Manage_Gateway=$(ip r|grep "default via"|awk '{print $3}')
ControllerIP=$(cat /etc/hosts|grep controller|awk '{print $1}')

if [ -z $ManageIP ];then
    echo "cann't get ip from $ManageEth"
    exit 1
fi

if [ -z $ControllerIP ];then
    echo "cann't get controllerip from /etc/hosts...please config controllerip in /etc/hosts"
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
apt-get -y install nova-compute neutron-server neutron-plugin-ml2 neutron-linuxbridge-agent openvswitch-common openvswitch-switch neutron-openvswitch-agent python-neutron-lbaas neutron-lbaas-common neutron-lbaasv2-agent cinder-volume

dpkg -i ./deb/*.deb

install_nova $MysqlUser $MysqlPass $ManageIP $ControllerIP
install_neutron $MysqlUser $MysqlPass $ManageIP
install_cinder $MysqlUser $MysqlPass $ManageIP

cp ./env/rc.local /etc/rc.local
