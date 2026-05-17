#!/usr/bin/env bash
# Inside-container init: write configs, format namenode, start daemons.
# Idempotent — safe to re-run; daemons will just say "already running".

set -euo pipefail

CONF=/opt/hadoop/etc/hadoop

cat > "$CONF/core-site.xml" <<'EOF'
<?xml version="1.0"?>
<configuration>
  <property><name>fs.defaultFS</name><value>hdfs://localhost:9000</value></property>
  <property><name>hadoop.tmp.dir</name><value>/tmp/hadoop-data</value></property>
</configuration>
EOF

cat > "$CONF/hdfs-site.xml" <<'EOF'
<?xml version="1.0"?>
<configuration>
  <property><name>dfs.replication</name><value>1</value></property>
  <property><name>dfs.permissions.enabled</name><value>false</value></property>
</configuration>
EOF

cat > "$CONF/mapred-site.xml" <<'EOF'
<?xml version="1.0"?>
<configuration>
  <property><name>mapreduce.framework.name</name><value>yarn</value></property>
  <property><name>yarn.app.mapreduce.am.env</name><value>HADOOP_MAPRED_HOME=/opt/hadoop</value></property>
  <property><name>mapreduce.map.env</name>      <value>HADOOP_MAPRED_HOME=/opt/hadoop</value></property>
  <property><name>mapreduce.reduce.env</name>   <value>HADOOP_MAPRED_HOME=/opt/hadoop</value></property>
  <property><name>mapreduce.application.classpath</name>
    <value>/opt/hadoop/share/hadoop/mapreduce/*:/opt/hadoop/share/hadoop/mapreduce/lib/*</value>
  </property>
</configuration>
EOF

cat > "$CONF/yarn-site.xml" <<'EOF'
<?xml version="1.0"?>
<configuration>
  <property><name>yarn.nodemanager.aux-services</name><value>mapreduce_shuffle</value></property>
  <property><name>yarn.nodemanager.env-whitelist</name>
    <value>JAVA_HOME,HADOOP_COMMON_HOME,HADOOP_HDFS_HOME,HADOOP_CONF_DIR,CLASSPATH_PREPEND_DISTCACHE,HADOOP_YARN_HOME,HADOOP_HOME,LANG,TZ</value>
  </property>
  <property><name>yarn.nodemanager.resource.memory-mb</name><value>4096</value></property>
  <property><name>yarn.scheduler.maximum-allocation-mb</name><value>4096</value></property>
  <property><name>yarn.app.mapreduce.am.resource.mb</name><value>1024</value></property>
  <property><name>mapreduce.map.memory.mb</name><value>512</value></property>
  <property><name>mapreduce.reduce.memory.mb</name><value>512</value></property>
</configuration>
EOF

if pgrep -f 'hdfs.server.namenode.NameNode' >/dev/null; then
    echo "[init] namenode already up; skipping format"
elif compgen -G '/tmp/hadoop-*/dfs/name/current/VERSION' >/dev/null; then
    echo "[init] namenode fs image already present; skipping format"
else
    echo "[init] formatting namenode"
    hdfs namenode -format -force -nonInteractive >/dev/null
fi

start_if_missing() {
    local kind=$1 daemon=$2 cls=$3
    if pgrep -f "$cls" >/dev/null; then
        echo "[init] $daemon already up"
    else
        echo "[init] starting $daemon"
        $kind --daemon start "$daemon"
        sleep 1
    fi
}

start_if_missing hdfs namenode     'hdfs.server.namenode.NameNode'
start_if_missing hdfs datanode     'hdfs.server.datanode.DataNode'
start_if_missing yarn resourcemanager 'yarn.server.resourcemanager.ResourceManager'
start_if_missing yarn nodemanager     'yarn.server.nodemanager.NodeManager'

# Settle, then create base dirs
sleep 2
hdfs dfs -mkdir -p /user/hadoop /input /output 2>/dev/null || true

echo "[init] HDFS report:"
hdfs dfsadmin -report 2>/dev/null | grep -E '^(Configured Capacity|Live datanodes)'
echo "[init] ready"
