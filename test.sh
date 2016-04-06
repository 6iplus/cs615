#!/bin/bash

###aws ec2 delete-security-group --group-name EC2-BACKUP-sg
#create the security group
###sg_result="$(aws ec2 create-security-group --group-name EC2-BACKUP-sg --description "ec2" --output text)"
#echo $sg_result
###sg_id="null"
###if [[ $sg_result == *"true"* ]]
###then
###        sg_id="$(echo $sg_result | cut -d' ' -f1)";
###fi
###echo $sg_id
###echo $sg_id
###aws ec2 authorize-security-group-ingress --group-name EC2-BACKUP-sg --protocol tcp --port 22 --cidr 0.0.0.0/0
sg_id="sg-d2c4e7aa"
instance_id="$(aws ec2 run-instances --image-id ami-7b386c11 --security-group-ids $sg_id --count 1 --instance-type t1.micro --key-name aaa --query 'Instances[0].InstanceId' --output text)"

echo $instance_id
instance_ip="$(aws ec2 describe-instances --instance-ids $instance_id --query 'Reservations[0].Instances[0].PublicIpAddress' --output text)"

echo $instance_ip

sleep 1

ssh_output="$(ssh-keyscan -t ssh-rsa $instance_ip)"
while [[ $ssh_output == "" ]]; do
echo "retry"
ssh_output="$(ssh-keyscan -t ssh-rsa $instance_ip)"
sleep 5
done
echo $ssh_output
key_from_scan="$(ssh-keyscan -t ssh-rsa $instance_ip | cut -d " "  -f 3)"
key_from_console="$(aws ec2 get-console-output --instance-id $instance_id | grep ssh-rsa | tail -n1 | cut -d ' '  -f 2)"

echo $key_from_scan
echo $key_from_console
echo "dddddd"
#ssh -o ConnectTimeout=1  ubuntu@$instance_ip -i aaa.pem
#aws ec2 stop-instances  --instance-ids $instance_id
