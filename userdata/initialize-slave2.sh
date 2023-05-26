#!/bin/bash
wget https://documentation-samples-4.obs.ap-southeast-3.myhuaweicloud.com/solution-as-code-moudle/deploy-a-highly-available-mha-mysql-cluster.tf/userdata/LinuxVMDataDiskAutoInitialize.sh
chmod +x LinuxVMDataDiskAutoInitialize.sh
yum install expect -y
/usr/bin/expect<<EOF
spawn ./LinuxVMDataDiskAutoInitialize.sh
expect "/dev/vdb and q to quit"
send "/dev/vdb\r"
expect "/mnt/data"
send "/datadisk\r"
expect eof
exit
EOF
rm -rf LinuxVMDataDiskAutoInitialize.sh

IPlist=('192.168.100.111' '192.168.100.112' '192.168.100.113')
for ip in "${IPlist[@]}"; do
    echo "start check $ip ..."
    while true; do
        status=$(curl -kv $ip:22)
        echo "check status $ip:$status ..."
        echo "$ip:$status"
        if [[ $status =~ SSH ]]; then
            echo "check ok! quit..."
            break
        else
            echo "wait 10s..."
            sleep 10
        fi
    done
done

ssh-keygen -t dsa -P '' -f /root/.ssh/id_dsa >/dev/null 2>&1
for ip in "${IPlist[@]}"; do
    echo "start copy id to $ip"
    /usr/bin/expect <<EOF
spawn ssh-copy-id -i /root/.ssh/id_dsa.pub root@$ip
expect {
"(yes/no)?" {send "yes\r"
expect "password:"
send "$1\r";exp_continue}
"password:" {send "$1\r"}
}
expect eof
exit
EOF
    echo "$ip finished!"
done

mkdir /datadisk/package/
wget -P /datadisk/package/ https://documentation-samples-4.obs.ap-southeast-3.myhuaweicloud.com/solution-as-code-moudle/deploy-a-highly-available-mha-mysql-cluster.tf/open-source-software/mysql-5.7.34-linux-glibc2.12-x86_64.tar.gz
mkdir -p /datadisk/db/mysql57/{data,logs}
tar -xvf /datadisk/package/mysql-5.7.34-linux-glibc2.12-x86_64.tar.gz -C /datadisk/db/mysql57/
mv /datadisk/db/mysql57/mysql-5.7.34-linux-glibc2.12-x86_64/ /datadisk/db/mysql57/mysql
echo -e "export PATH=/datadisk/db/mysql57/mysql/bin:\$PATH" >>/etc/profile
#shellcheck source=/dev/null
source /etc/profile

groupadd mysql
useradd -g mysql mysql
cat >/etc/my.cnf <<EOF
[mysqld]
user=mysql
server_id=113
port=3306
basedir=/datadisk/db/mysql57/mysql
datadir=/datadisk/db/mysql57/data
#character-set-server=utf8mb4
#collation-server=utf8mb4_general_ci
default-storage-engine=INNODB
socket=/tmp/mysql.sock
innodb_data_file_path=ibdata1:512M;ibdata2:512M:autoextend
innodb_autoextend_increment=64
autocommit=1
innodb_flush_log_at_trx_commit=1
innodb_flush_method=O_DIRECT
transaction-isolation=Read-Committed
log_error=/datadisk/db/mysql57/logs/mysqld.log
slow_query_log_file=/datadisk/db/mysql57/logs/slow.log
slow_query_log=1
long_query_time=0.1
log_queries_not_using_indexes
log_bin=/datadisk/db/mysql57/logs/mysql_bin
binlog_format=row
gtid-mode=on
enforce-gtid-consistency=true
log-slave-updates=1
[mysql]
port=3306
#default-character-set=utf8mb4
socket=/tmp/mysql.sock
prompt="> "
[client]
port=3306
#default-character-set=utf8mb4
socket=/tmp/mysql.sock
EOF

yum install -y libaio
sudo chown -R mysql:mysql /datadisk/db/mysql57/
mysqld --initialize-insecure --explicit_defaults_for_timestamp=true
cat >/etc/systemd/system/mysqld.service <<EOF
[Unit]
Description=MySQL Server
Documentation=man:mysqld(8)
Documentation=http://dev.mysql.com/doc/refman/en/using-systemd.html
After=network.target
After=syslog.target
[Install]
WantedBy=multi-user.target
[Service]
User=mysql
Group=mysql
ExecStart=/datadisk/db/mysql57/mysql/bin/mysqld --defaults-file=/etc/my.cnf
LimitNOFILE = 5000
EOF
systemctl start mysqld.service
systemctl enable mysqld.service
for ((i = 0; i < 10; i++)); do
    socket=$(ls /tmp/)
    if [[ $socket =~ mysql.sock ]]; then
        break
    else
        sleep 1
    fi
done

/usr/bin/expect <<EOF
spawn mysql -uroot
expect ">"
send "CHANGE MASTER TO\r"
expect "    ->"
send "MASTER_HOST='192.168.100.111',\r"
expect "    ->"
send "MASTER_USER='repl',\r"
expect "    ->"
send "MASTER_PASSWORD='$1',\r"
expect "    ->"
send "MASTER_PORT=3306,\r"
expect "    ->"
send "MASTER_CONNECT_RETRY=10,\r"
expect "    ->"
send "MASTER_AUTO_POSITION=1; \r"
expect ">"
send "START SLAVE;\r"
expect eof
exit
EOF

ln -s /datadisk/db/mysql57/mysql/bin/mysqlbinlog /usr/bin/mysqlbinlog
ln -s /datadisk/db/mysql57/mysql/bin/mysql /usr/bin/mysql

wget -P /datadisk/package/ https://documentation-samples-4.obs.ap-southeast-3.myhuaweicloud.com/solution-as-code-moudle/deploy-a-highly-available-mha-mysql-cluster.tf/open-source-software/mha4mysql-manager-0.56-0.el6.noarch.rpm
wget -P /datadisk/package/ https://documentation-samples-4.obs.ap-southeast-3.myhuaweicloud.com/solution-as-code-moudle/deploy-a-highly-available-mha-mysql-cluster.tf/open-source-software/mha4mysql-node-0.56-0.el6.noarch.rpm
wget -P /datadisk/package/ https://documentation-samples-4.obs.ap-southeast-3.myhuaweicloud.com/solution-as-code-moudle/deploy-a-highly-available-mha-mysql-cluster.tf/open-source-software/master_ip_failover
wget -P /datadisk/package/ https://documentation-samples-4.obs.ap-southeast-3.myhuaweicloud.com/solution-as-code-moudle/deploy-a-highly-available-mha-mysql-cluster.tf/open-source-software/master_online_change
wget -P /datadisk/package/ https://documentation-samples-4.obs.ap-southeast-3.myhuaweicloud.com/solution-as-code-moudle/deploy-a-highly-available-mha-mysql-cluster.tf/open-source-software/send_report

mkdir -p /datadisk/mha/{logs,scripts,conf}
mv /datadisk/package/{master_ip_failover,master_online_change,send_report} /datadisk/mha/scripts
yum install perl-DBD-MySQL -y
rpm -ivh /datadisk/package/mha4mysql-node-0.56-0.el6.noarch.rpm
yum install epel-release --nogpgcheck -y
yum install -y perl-Config-Tiny epel-release perl-Log-Dispatch perl-Parallel-ForkManager perl-Time-HiRes
rpm -ivh /datadisk/package/mha4mysql-manager-0.56-0.el6.noarch.rpm
cat >/datadisk/mha/conf/app1.cnf <<EOF
[server default]
ssh_user=root
manager_workdir=/datadisk/mha/logs/app1
manager_log=/datadisk/mha/logs/manager
user=mha
password=$1
master_binlog_dir=/datadisk/db/mysql57/3306/logs
repl_user=repl
repl_password=$1
ping_interval=3
master_ip_failover_script=/datadisk/mha/scripts/master_ip_failover
master_ip_online_change_script=/datadisk/mha/scripts/master_online_change
report_script=/datadisk/mha/scripts/send_report
[server1]
hostname=192.168.100.111
port=3306
[server2]
candidate_master=1
check_repl_delay=0
hostname=192.168.100.112
port=3306
[server3]
hostname=192.168.100.113
port=3306
EOF

eMailAddress=$2
sed -i "s/smtp service type/$7/" /datadisk/mha/scripts/send_report
sed -i "s/who will send this email/$2/" /datadisk/mha/scripts/send_report
sed -i "s/smtp login user/$2/" /datadisk/mha/scripts/send_report
sed -i "s/smtp authorization code/$3/" /datadisk/mha/scripts/send_report
sed -i "s/who will receive this email/$4/" /datadisk/mha/scripts/send_report

sed -i "s/virtual IP address\/virtual IP network segment/$5\/24/" /datadisk/mha/scripts/master_ip_failover
sed -i "s/network_card/eth0/g" /datadisk/mha/scripts/master_ip_failover

sed -i "s/virtual IP address\/virtual IP network segment/$5\/24/" /datadisk/mha/scripts/master_online_change
sed -i "s/network_card/eth0/g" /datadisk/mha/scripts/master_online_change
yum install -y dos2unix
dos2unix /datadisk/mha/scripts/{master_online_change,master_ip_failover,send_report}
chmod +x /datadisk/mha/scripts/{master_online_change,master_ip_failover,send_report}
nohup masterha_manager --conf=/datadisk/mha/conf/app1.cnf --remove_dead_master_conf --ignore_last_failover </dev/null >/datadisk/mha/logs/manager.log  2>&1 &

cat >>/etc/profile <<EOF
alias mha_app1_start="nohup masterha_manager --conf=/datadisk/mha/conf/app1.cnf --remove_dead_master_conf --ignore_last_failover  < /dev/null> /datadisk/mha/logs/manager.log 2>&1 &"
alias mha_app1_status="masterha_check_status --conf=/datadisk/mha/conf/app1.cnf"
alias mha_app1_stop="masterha_stop --conf=/datadisk/mha/conf/app1.cnf"
EOF
#shellcheck source=/dev/null
source /etc/profile
mha_app1_start
i=0
while ((i < 10)); do
    status=$(mha_app1_status)
    if [[ $status =~ running ]]; then
        break
    elif [[ mha_app1_status =~ stopped ]]; then
        mha_app1_start
        sleep 10
		((i++))
    fi
done