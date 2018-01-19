#!/usr/bin/env bash
# set your own data
user=hadoop
hostname=www.mac-bigdata-%s.com
hostname1=01
hostname2=02
hostname3=03
HADOOP_HOME="/opt/modules/hadoop-2.5.0-cdh5.3.6"
ZOOKEEPER_HOME="/opt/modules/zookeeper-3.4.5-cdh5.3.6"

# get real hostname
real_hostname1=`echo $hostname|sed "s/%s/$hostname1/g"`
real_hostname2=`echo $hostname|sed "s/%s/$hostname2/g"`
real_hostname3=`echo $hostname|sed "s/%s/$hostname3/g"`
hosts=($real_hostname1 $real_hostname2 $real_hostname3)

# prepare for running
echo '------------------------------------------------------------------'
echo '00 preparing for running...'
echo '------------------------------------------------------------------'
# define start time
starttime=`date +'%Y-%m-%d %H:%M:%S'`
# define log file
LOG_DIR="`pwd`/logs"
if [ -r $LOG_DIR ]; then
    rm -rf $LOG_DIR
fi
if [ ! -r $LOG_DIR ]; then
  mkdir $LOG_DIR
fi
LOG_ERROR_FILE="$LOG_DIR/ha-check-error-`date "+%Y%m%d%H%M%S"`.log"
echo -e "error log file location : $LOG_ERROR_FILE\n"
# create log file
touch $LOG_ERROR_FILE
# total error number
error_number=0
# total check number
check_number=0
checkpoint_number=0

function showCheckPointOk() {
echo "[$host] checkpoint$checkpoint_number : $ck [ok]"
}

function showCheckPointError() {
echo "[$host] checkpoint$checkpoint_number : $ck [failed]"
    error_number=$((error_number+1))
    echo -e "$error_number\tcheckpoint$checkpoint_number\t[$host]\t$error_msg" >> $LOG_ERROR_FILE
}

function runEq() {
  if [ "$ret" = "$ext" ]; then
    showCheckPointOk
  else
    showCheckPointError
  fi
  check_number=$((check_number+1))
}

function runGtZero() {
    if [ $ret > 0 ]; then
        showCheckPointOk
    else
        showCheckPointError
    fi
    check_number=$((check_number+1))
}

echo '------------------------------------------------------------------'
echo '01 checking ssh...'
echo '------------------------------------------------------------------'
checkpoint_number=$((checkpoint_number+1))
for host in ${hosts[@]}
do
    for sub_host in ${hosts[@]}
    do
        ret=`ssh $user@$host ssh $user@$sub_host hostname 2> /dev/null`
        ext=$sub_host
        ck="ssh $sub_host"
        error_msg="\"$host\" ssh \"$sub_host\" failed,please check first!"
        if [ "$ret" == "$ext" ]; then
            showCheckPointOk
        else
            showCheckPointError
            echo -e $error_msg
            exit 1
        fi
        check_number=$((check_number+1))
    done
done
echo

echo '------------------------------------------------------------------'
echo '02 checking hostname...'
echo '------------------------------------------------------------------'
checkpoint_number=$((checkpoint_number+1))
for host in ${hosts[@]}
do
    ret=`ssh $user@$host "source /etc/profile;hostname 2> /dev/null"`
    ext="$host"
    ck="hostname"
    error_msg="hostname settings are incorrect!hostname=\"$ret\",expected=\"$host\""
    runEq
done
echo

echo '------------------------------------------------------------------'
echo '03 checking visudo...'
echo '------------------------------------------------------------------'
checkpoint_number=$((checkpoint_number+1))
for host in ${hosts[@]}
do
    ret=`ssh $user@$host "source /etc/profile;sudo -A echo 1 2> /dev/null"`
    ext="1"
    ck="visudo"
    error_msg="visudo settings are incorrect!login by root and add \"$user\tALL=(root)\tNOPASSWD:ALL\" after line 91"
    runEq
done
echo

echo '------------------------------------------------------------------'
echo '04 checking /etc/hosts...'
echo '------------------------------------------------------------------'
checkpoint_number=$((checkpoint_number+1))
for host in ${hosts[@]}
do
    for sub_host in ${hosts[@]}
    do
        ret=`ssh $user@$host "source /etc/profile;cat /etc/hosts 2> /dev/null|grep $sub_host|sed 's/[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}//g'|sed 's/[\t]//g'|sed 's/ //g' 2> /dev/null"`
        ck="/etc/hosts $sub_host"
        #check the first char
        first=${ret:0:1}
        if [ ! -z "$ret" -a ! -z "$first" -a "$first" != "#" ]; then
            showCheckPointOk
            elif [ "$first" = "#" ]; then
            error_msg="/etc/hosts settings are incorrect!\"$sub_host\" was set but contains an annotation(#)!"
            showCheckPointError
            else
            error_msg="/etc/hosts settings are incorrect!please add \"192.168.xxx.xxx\t$sub_host\" in /etc/hosts!"
            showCheckPointError
        fi
        check_number=$((check_number+1))
    done
done
echo

echo '------------------------------------------------------------------'
echo '05 checking iptables...'
echo '------------------------------------------------------------------'
checkpoint_number=$((checkpoint_number+1))
for host in ${hosts[@]}
do
    ret=`ssh $user@$host "source /etc/profile;sudo service iptables status 2> /dev/null|grep 'is not running' 2> /dev/null|wc -l 2> /dev/null"`
    ext="1"
    ck="iptables closed"
    error_msg="iptables settings are incorrect!please use \"sudo service iptables stop\" to stop iptables!"
    runEq
done
echo

echo '------------------------------------------------------------------'
echo '06 checking network...'
echo '------------------------------------------------------------------'
checkpoint_number=$((checkpoint_number+1))
for host in ${hosts[@]}
do
    ret=`ssh $user@$host "source /etc/profile;ping 180.97.33.108 -c 1 2>/dev/null|grep 'time=' 2>/dev/null|sed 's/.*time=//g' 2>/dev/null|sed 's/ ms//g' 2>/dev/null"`
    ck="network"
    error_msg="network settings are incorrect!please check if your network device is working!"
    runGtZero
done
echo

echo '------------------------------------------------------------------'
echo '07 checking dns...'
echo '------------------------------------------------------------------'
checkpoint_number=$((checkpoint_number+1))
for host in ${hosts[@]}
do
    ret=`ssh $user@$host "source /etc/profile;ping www.baidu.com -c 1 2>/dev/null|grep 'time=' 2>/dev/null|sed 's/.*time=//g' 2>/dev/null|sed 's/ ms//g' 2>/dev/null"`
    ck="dns"
    error_msg="dns settings are incorrect!please check your dns settings:\"vi /etc/resolv.conf\"!"
    runGtZero
done
echo

echo '------------------------------------------------------------------'
echo '08 checking selinux...'
echo '------------------------------------------------------------------'
checkpoint_number=$((checkpoint_number+1))
for host in ${hosts[@]}
do
    ret=`ssh $user@$host "source /etc/profile;cat /etc/sysconfig/selinux 2>/dev/null|grep '^SELINUX=' 2>/dev/null|sed 's/SELINUX=//g' 2>/dev/null"`
    ext="disabled"
    ck="selinux disabled"
    error_msg="selinux settings are incorrect!please set SELINUX=disabled!"
    runEq
done
echo

echo '------------------------------------------------------------------'
echo '09 checking JAVA_HOME...'
echo '------------------------------------------------------------------'
checkpoint_number=$((checkpoint_number+1))
for host in ${hosts[@]}
do
    ret=`ssh $user@$host "source /etc/profile;echo $JAVA_HOME 2>/dev/null|wc -L"`
    ck="JAVA_HOME"
    error_msg="JAVA_HOME settings are incorrect!please download JDK and set JAVA_HOME environment!"
    runGtZero
done
echo

echo '------------------------------------------------------------------'
echo '10 checking java and javac...'
echo '------------------------------------------------------------------'
checkpoint_number=$((checkpoint_number+1))
for host in ${hosts[@]}
do
    # create test java files
    JAVA_FILE="Test.java"
    JAVA_FILE_PATH="/home/$user/$JAVA_FILE"
    CLASS_FILE="Test.class"
    CLASS_FILE_PATH="/home/$user/$CLASS_FILE"
    JAVA_CLASS="Test"
    JAVA_CODE="public class Test{public static void main(String[] args){System.out.println(\"Hello World\");}}"
    # send file to test host
    touch $JAVA_FILE; echo $JAVA_CODE > $JAVA_FILE; scp -r $JAVA_FILE $user@$host:$JAVA_FILE_PATH 1>/dev/null 2>/dev/null
    # test if java can work
    ret=`ssh $user@$host "source /etc/profile;javac $JAVA_FILE 2>/dev/null;java $JAVA_CLASS 2>/dev/null"`
    ext="Hello World"
    ck="java & javac"
    error_msg="java settings are incorrect!your java cannot work!"
    runEq
    # remove test java files
    rm -rf $JAVA_FILE;ssh $user@$host "source /etc/profile;rm -rf $JAVA_FILE_PATH $CLASS_FILE_PATH"
done
echo

echo '------------------------------------------------------------------'
echo '11 checking hadoop-env.sh...'
echo '------------------------------------------------------------------'
checkpoint_number=$((checkpoint_number+1))
for host in ${hosts[@]}
do
    ret=`ssh $user@$host "source /etc/profile;cat $HADOOP_HOME/etc/hadoop/hadoop-env.sh 2>/dev/null|grep JAVA_HOME|grep '^export'|sed 's/.*JAVA_HOME=//g'"`
    ext=`ssh $user@$host "source /etc/profile;echo $JAVA_HOME"`
    ck="hadoop-env.sh"
    error_msg="hadoop settings are incorrect!please check JAVA_HOME in hadoop-env.sh!"
    runEq
done
echo

echo '------------------------------------------------------------------'
echo '12 checking mapred-env.sh...'
echo '------------------------------------------------------------------'
checkpoint_number=$((checkpoint_number+1))
for host in ${hosts[@]}
do
    ret=`ssh $user@$host "source /etc/profile;cat $HADOOP_HOME/etc/hadoop/mapred-env.sh 2>/dev/null|grep JAVA_HOME|grep '^export'|sed 's/.*JAVA_HOME=//g'"`
    ext=`ssh $user@$host "source /etc/profile;echo $JAVA_HOME"`
    ck="mapred-env.sh"
    error_msg="hadoop settings are incorrect!please check JAVA_HOME in mapred-env.sh!"
    runEq
done
echo

echo '------------------------------------------------------------------'
echo '13 checking yarn-env.sh...'
echo '------------------------------------------------------------------'
checkpoint_number=$((checkpoint_number+1))
for host in ${hosts[@]}
do
    ret=`ssh $user@$host "source /etc/profile;cat $HADOOP_HOME/etc/hadoop/yarn-env.sh 2>/dev/null|grep JAVA_HOME|grep '^export'|sed 's/.*JAVA_HOME=//g'"`
    ext=`ssh $user@$host "source /etc/profile;echo $JAVA_HOME"`
    ck="yarn-env.sh"
    error_msg="hadoop settings are incorrect!please check JAVA_HOME in yarn-env.sh!"
    runEq
done
echo

# install xmllint

echo '------------------------------------------------------------------'
echo '14 checking core-site.xml...'
echo '------------------------------------------------------------------'
checkpoint_number=$((checkpoint_number+1))
for host in ${hosts[@]}
do
    ret=`ssh $user@$host "source /etc/profile;cat $HADOOP_HOME/etc/hadoop/yarn-env.sh 2>/dev/null|grep JAVA_HOME|grep '^export'|sed 's/.*JAVA_HOME=//g'"`
    ext=`ssh $user@$host "source /etc/profile;echo $JAVA_HOME"`
    ck="core-site.xml"
    error_msg="hadoop settings are incorrect!please check JAVA_HOME in yarn-env.sh!"
    runEq
done
echo

# remove xmllint

# calculate cost time
endtime=`date +'%Y-%m-%d %H:%M:%S'`
start_seconds=$(date --date="$starttime" +%s);
end_seconds=$(date --date="$endtime" +%s);

# handle zero file bug
ZERO_FILE=`pwd`/0
if [ -r "$ZERO_FILE" ]; then
    rm -rf $ZERO_FILE
fi

echo '------------------------------------------------------------------'
echo 'your setting error list, please check...'
echo '------------------------------------------------------------------'
if [ `cat $LOG_ERROR_FILE |wc -l` == 0 ]; then
    echo 'empty'
else
    cat $LOG_ERROR_FILE
fi
echo

echo '------------------------------------------------------------------'
echo 'total statistics'
echo '------------------------------------------------------------------'
echo "start time : $starttime"
echo "end time : $endtime"
echo "elapsed time : $((end_seconds-start_seconds))s"
echo "total checkpoint number : $checkpoint_number"
echo "total check times : $check_number"
echo "total failed times : $error_number"
pass_rate=$(($((check_number-error_number))*100/check_number))
printf "passing rate : %d%%\n" $pass_rate
if [ $pass_rate -eq 100 ]; then
echo "awesome!!!"
elif [ $pass_rate -lt 100 -a $pass_rate -ge 90 ]; then
echo "good!"
elif [ $pass_rate -lt 90 -a $pass_rate -ge 60 ]; then
echo "just right..."
elif [ $pass_rate -lt 60 ]; then
echo "embarrassing..."
fi
echo '------------------------------------------------------------------'
echo

echo '------------------------------------------------------------------'
echo 'checking task finished!have fun!^_^'
echo 'powered by xiadongshan@china nanjing'
echo 'you can contact me with QQ=247765564'
echo '------------------------------------------------------------------'

