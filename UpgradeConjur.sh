#!/bin/bash  

read -p "Enter the FQDN of the Current Conjur Master: " MASTER_OLD
read -p "Enter the FQDN of the New Conjur Master: " MASTER_NEW
read -p "Enter the original Docker container name: " CONTAINER_OLD
read -p "Enter the new Docker container name: " CONTAINER_NEW
read -p "Enter the Docker image tag: " TAG
read -p "Enter the cluster name: " CLUSTER
read -p "Enter the full path to the Docker image file name: " IMAGE
read -p "Enter the FQDN of the remaining standby: " STANDBY
read -p "Enter the FQDN of the first follower: " FOLLOWER1
read -p "Enter the FQDN of the second follower: " FOLLOWER2

#
#  Stop Postgres Replication on all nodes
#

ssh $MASTER_NEW "docker exec $CONTAINER_OLD evoke replication stop"
ssh $STANDBY "docker exec $CONTAINER_OLD evoke replication stop"
ssh $FOLLOWER1 "docker exec $CONTAINER_OLD evoke replication stop"
ssh $FOLLOWER2 "docker exec $CONTAINER_OLD evoke replication stop"

#
# Upgrade the first standby to become the new Master
#

ssh $MASTER_OLD "docker exec $CONTAINER_OLD evoke cluster member remove $MASTER_NEW"
ssh $MASTER_NEW "docker load -i $IMAGE"
ssh $MASTER_NEW "docker rm -f $CONTAINER_OLD"
ssh $MASTER_NEW "docker run --name $CONTAINER_NEW -d --restart=always --security-opt seccomp:unconfined -v "/opt/conjur/backup:/opt/conjur/backup" -p "443:443" -p "636:636" -p "5432:5432" -p "1999:1999" registry.tld/conjur-appliance:$TAG"
ssh $MASTER_OLD "docker exec $CONTAINER_OLD evoke seed standby $MASTER_NEW $MASTER_OLD" | ssh $MASTER_NEW "docker exec -i $CONTAINER_NEW evoke unpack seed -" 
ssh $MASTER_NEW "docker cp master.key $CONTAINER_NEW:/opt/conjur"
ssh $MASTER_NEW "docker exec $CONTAINER_NEW evoke keys exec -m /opt/conjur/master.key -- evoke configure standby"
ssh $MASTER_OLD "docker exec $CONTAINER_OLD evoke cluster member add $MASTER_NEW"
ssh $MASTER_NEW "docker exec $CONTAINER_NEW evoke cluster enroll --reenroll -n $MASTER_NEW -m $MASTER_OLD $CLUSTER"

#
# Upgrade the second standby
#

ssh $MASTER_OLD "docker exec $CONTAINER_OLD evoke cluster member remove $STANDBY"
ssh $STANDBY "docker load -i $IMAGE"
ssh $STANDBY "docker rm -f $CONTAINER_OLD"
ssh $STANDBY "docker run --name $CONTAINER_NEW -d --restart=always --security-opt seccomp:unconfined -v "/opt/conjur/backup:/opt/conjur/backup" -p "443:443" -p "636:636" -p "5432:5432" -p "1999:1999" registry.tld/conjur-appliance:$TAG"
ssh $MASTER_OLD "docker exec $CONTAINER_OLD evoke seed standby $STANDBY $MASTER_OLD" | ssh $STANDBY "docker exec -i $CONTAINER_NEW evoke unpack seed -"
ssh $STANDBY "docker cp master.key $CONTAINER_NEW:/opt/conjur"
ssh $STANDBY "docker exec $CONTAINER_NEW evoke keys exec -m /opt/conjur/master.key -- evoke configure standby"
ssh $MASTER_OLD "docker exec $CONTAINER_OLD evoke cluster member add $STANDBY"
ssh $STANDBY "docker exec $CONTAINER_NEW evoke cluster enroll --reenroll -n $STANDBY -m $MASTER_OLD $CLUSTER"
ssh $standby "docker stop $CONTAINER_NEW" #This is to force failover and ensure that $MASTER_NEW is the actual master node



#
# Promote the new Master 
#

ssh $MASTER_OLD "docker stop $CONTAINER_OLD"
ssh $MASTER_NEW "docker exec $CONTAINER_NEW evoke role promote"

#
# Redeploy the final standby
#

ssh $MASTER_OLD "docker load -i $IMAGE"
ssh $MASTER_OLD "docker rm -f $CONTAINER_OLD"
ssh $MASTER_OLD "docker run --name $CONTAINER_NEW -d --restart=always --security-opt seccomp:unconfined -v "/opt/conjur/backup:/opt/conjur/backup" -p "443:443" -p "636:636" -p "5432:5432" -p "1999:1999" registry.tld/conjur-appliance:$TAG"
ssh $MASTER_NEW "docker exec $CONTAINER_NEW evoke seed standby $MASTER_OLD $MASTER_NEW" | ssh $MASTER_OLD "docker exec -i $CONTAINER_NEW evoke unpack seed -"
ssh $MASTER_OLD "docker cp master.key $CONTAINER_NEW:/opt/conjur"
ssh $MASTER_OLD "docker exec $CONTAINER_NEW evoke keys exec -m /opt/conjur/master.key -- evoke configure standby"
ssh $MASTER_NEW "docker exec $CONTAINER_NEW evoke cluster member add $MASTER_OLD"
ssh $MASTER_OLD "docker exec $CONTAINER_NEW evoke cluster enroll --reenroll -n $MASTER_OLD -m $MASTER_NEW $CLUSTER"

#
# Start the container on standby
#

ssh $standby "docker start $CONTAINER_NEW"


