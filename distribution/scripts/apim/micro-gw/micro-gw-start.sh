#!/bin/bash
# Copyright 2019 WSO2 Inc. (http://wso2.org)
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
# ----------------------------------------------------------------------------
# Start WSO2 API Manager Micro Gateway
# ----------------------------------------------------------------------------

script_dir=$(dirname "$0")
default_label="echo-mgw"
label="$default_label"
default_heap_size="512m"
heap_size="$default_heap_size"

function usage() {
    echo ""
    echo "Usage: "
    echo "$0 [-m <heap_size>] [-n <label>] [-h]"
    echo "-m: The heap memory size of API Microgateway. Default: $default_heap_size."
    echo "-n: The identifier for the built Microgateway distribution. Default: $default_label."
    echo "-h: Display this help and exit."
    echo ""
}

while getopts "m:n:h" opt; do
    case "${opt}" in
    m)
        heap_size=${OPTARG}
        ;;
    n)
        label=${OPTARG}
        ;;
    h)
        usage
        exit 0
        ;;
    \?)
        usage
        exit 1
        ;;
    esac
done
shift "$((OPTIND - 1))"

if [[ -z $heap_size ]]; then
    echo "Please provide the heap size for the API Microgateway."
    exit 1
fi

if [[ -z $label ]]; then
    echo "Please provide the identifier for the built Microgateway distribution."
    exit 1
fi

#fix the download link
wget https://www.dropbox.com/s/mt93sivbgzbe0ut/wso2am-micro-gw-linux-3.0.2-SNAPSHOT.zip?dl=0 -O wso2am-micro-gw-linux-3.0.2-SNAPSHOT.zip
unzip wso2am-micro-gw-linux-3.0.2-SNAPSHOT.zip
mv wso2am-micro-gw-linux-3.0.2-SNAPSHOT runtime-mgw

if [ -e "/runtime-mgw/bin/gateway.pid" ]; then
    PID=$(cat "/runtime-mgw/bin/gateway.pid")
fi

if pgrep -f ballerina >/dev/null; then
    echo "Shutting down microgateway"
    pgrep -f ballerina | xargs kill -9
fi

echo "Waiting for microgateway to stop"
while true; do
    if ! pgrep -f ballerina >/dev/null; then
        echo "Microgateway stopped"
        break
    else
        sleep 10
    fi
done

# create a separate location to keep logs
if [ ! -d "/home/ubuntu/micro-gw-${label}" ]; then
  mkdir /home/ubuntu/micro-gw-${label}
  mkdir /home/ubuntu/micro-gw-${label}/logs
  mkdir /home/ubuntu/micro-gw-${label}/runtime
fi

log_files=(/home/ubuntu/micro-gw-${label}/logs/*)

if [ ${#log_files[@]} -gt 1 ]; then
    echo "Log files exists. Moving to /tmp"
    mv /home/ubuntu/micro-gw-${label}/logs/* /tmp/
fi

#create empty file to mount into docker
touch /home/ubuntu/micro-gw-${label}/logs/gc.log
touch /home/ubuntu/micro-gw-${label}/runtime/heap-dump.hprof
touch /home/ubuntu/micro-gw-${label}/logs/microgateway.log
chmod -R a+rw /home/ubuntu/micro-gw-${label}

echo "Enabling GC Logs"
export JAVA_OPTS="-Xms${heap_size} -Xmx${heap_size} -XX:+PrintGC -XX:+PrintGCDetails -XX:+PrintGCDateStamps -Xloggc:/home/ubuntu/micro-gw-${label}/logs/gc.log"
JAVA_OPTS+=" -XX:+HeapDumpOnOutOfMemoryError -XX:HeapDumpPath="/home/ubuntu/micro-gw-${label}/runtime/heap-dump.hprof""

jvm_dir=""
for dir in /usr/lib/jvm/jdk1.8*; do
    [ -d "${dir}" ] && jvm_dir="${dir}" && break
done
export JAVA_HOME="${jvm_dir}"

#overwrite the micro-gw.conf
echo "Overwriting micro-gw.conf"
echo $(ifconfig | grep "inet " | grep -v "127.0.0.1" | grep -v "172." |awk '{print $2}')
sh /home/ubuntu/apim/micro-gw/create-micro-gw-conf.sh -i $(ifconfig | grep "inet " | grep -v "127.0.0.1" | grep -v "172." |awk '{print $2}')

echo "Starting Microgateway"
pushd runtime-mgw/bin
(
    chmod a+x gateway
    bash gateway /home/ubuntu/${label}/target/${label}.jar >/dev/null &
)
popd

echo "Waiting for Microgateway to start"

n=0
until [ $n -ge 60 ]; do
    nc -zv localhost 9095 && break
    n=$(($n + 1))
    sleep 1
done

# Wait for another 5 seconds to make sure that the server is ready to accept API requests.
sleep 5
exit $exit_status
