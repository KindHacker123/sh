#!/bin/bash
#作者：XiTong
#rsync+inotify一键实时同步
echo -e "\033[33m欢迎使用实时同步工具\033[0m\n-----------------------\n\033[34m本工具还在不断完善\033[0m\n\033[36m说明：只需输入一些客户端信息以及相关目录方可同步(输入信息时一定要确保输入正确)\n自动检测依赖的软件包并安装\n自动开启相关依赖服务\n请提前配置防火墙与安全策略防止同步失败\033[0m\n------------------------"
echo "------------------------"
read -p "请输入客户端的IP：" ip
echo "------------------------"
read -s -p "请输入客户端的密码：" passwd
masterip=$(ip addr show ens33 | grep 'inet ' | awk '{print $2}' | cut -d '/' -f 1)
#检测私钥公钥
while true
do
check=$(ls /root/.ssh/ | grep id_rsa | wc -l)
if [ $check = 2 ]; then
	echo -e "\033[33m已有私钥公钥文件，即将进行下一步...\033[0m"
	break
else
	echo "检测到未有私钥公钥文件，即将生成公钥于私钥..."
	cd ~
	ssh-keygen
fi
done
while true
do
echo "即将进入配置免密登录界面..."
echo "------------------------"
ssh-copy-id -i /root/.ssh/id_rsa.pub root@$ip
checkpub=$(echo $?)
if [ $checkpub = 0 ]; then
	echo -e "\033[33m免密登录设置成功，即将进行下一步...\033[0m"
	break
else
	echo -e "\033[31m免密设置失败，请检查密码是否正确...\033[0m"
fi
done
#检测rsync
while true
do
	rpm -q rsync &> /dev/null
	checkrs=$(echo $?)
	if [ $checkrs = 0 ]; then
		echo -e "\033[33mrsync已安装，即将进行下一步...\033[0m"
		break
	else	
		echo "检测到rsync未安装，即将安装rsync..."
		yum install rsync -y &> /dev/null
fi
done
#检测inotify
while true
do
	checkep=$(ls /etc/yum.repos.d/ | grep epel | wc -l)
	if [ $checkep -gt 0 ]; then
		echo -e "\033[33mepel源已安装，即将进行下一步...\033[0m" &> /dev/null
		rpm -q inotify-tools &> /dev/null
		checkin=$(echo $?)
		if [ $checkin = 0 ]; then
			echo -e "\033[33minotify已安装，即将进行下一步...\033[0m"
			break
		else
			echo "检测到未安装inotify，即将安装inotify..."
			yum install inotify-tools -y &> /dev/null
		fi
	else
		rpm -q inotify-tools &> /dev/null
		checkin=$(echo $?)
		if [ $checkin = 0 ]; then
			echo -e "\033[33minotify已安装，即将进行下一步...\033[0m"
			break
		else
			echo "检测到未安装inotify，即将安装inotify..."
			yum -y install epel-release &> /dev/null
			yum install inotify-tools -y &> /dev/null
	fi	
fi
done
#检测客户端是否安装
while true
do
ssh root@$ip 'rpm -q rsync'
checkcin=$(echo $?)
if [ $checkcin = 0 ]; then
	echo -e "\033[33m客户端已经安装rsync...\033[0m"
	break
else
	echo "检测到客户端未安装rsync，即将进行安装..."
	ssh root@$ip 'yum install -y rsync'
fi
done	
echo "------------------------"
read -p "请输入要同步的本地目录：" dd
echo "------------------------"
read -p "请输入要同步的客户端目录：" dds
echo "------------------------"
#创建文件导入客户端
echo -e "# /etc/rsyncd: configuration file for rsync daemon mode

# See rsyncd.conf man page for more options.

# configuration example:

# uid = nobody
# gid = nobody
# use chroot = yes
# max connections = 4
# pid file = /var/run/rsyncd.pid
# exclude = lost+found/
# transfer logging = yes
# timeout = 900
# ignore nonreadable = yes
# dont compress   = *.gz *.tgz *.zip *.z *.Z *.rpm *.deb *.bz2

# [ftp]
#        path = /home/ftp
#        comment = ftp export area\nuid = nobody\ngid = nobody\nuse chroot = no\nmax connections = 10\npid file = /var/run/rsyncd.pid\nlock file = /var/run/rsync.lock\nlog file = /var/log/rsyncd.log\n\n[web1]\npath = $dds\ncomment = web1\nread only = no\nwrite only = no\nhosts allow = $masterip\nhosts deny = *\nuid = root\ngid = root\nauth users = web1user\nsecrets file = /opt/web1.pass" > /opt/.rsync.conf
scp /opt/.rsync.conf $ip:/etc/rsyncd.conf
checkcp=$(echo $?)
if [ $checkcp = 0 ]; then
	echo -e "\033[33m客户端文件导入成功...\033[0m"
	#创建密码文件
	echo "123456" > /opt/rsyncd.secrets
	chmod 600 /opt/rsyncd.secrets
	ssh root@$ip 'echo "web1user:123456" > /opt/web1.pass'
	ssh root@$ip 'chmod 600 /opt/web1.pass'
	echo "正在启动客户端rsyncd服务..."
	ssh root@$ip 'systemctl start rsyncd'
	echo "正在启动服务端rsyncd服务..."
	systemctl restart rsyncd
	checkre=$(echo $?)
	if [ $checkre = 0 ]; then
		echo -e "\033[33m服务启动成功，进入同步信息界面：\033[0m\n---------------------------------"
	else
		echo -e "\033[31m服务启动失败...\033[0m"
	fi
	
#配置服务端
host1=$ip
src=$dd
dst1=web1
user1=web1user

/usr/bin/inotifywait -mrq --timefmt '%d/%m/%y %H:%M' --format '%T %w%f%e' -e modify,delete,create,attrib $src \
| while read files
do
/usr/bin/rsync -vzrtopg --delete --progress --password-file=/opt/rsyncd.secrets $src $user1@$host1::$dst1
done
else
	echo -e "\033[31m客户端文件导入失败...\033[0m"
fi
