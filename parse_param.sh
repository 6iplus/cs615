#!/bin/bash
TEMP=`getopt -o v:m:h -n 'example.bash' -- "$@"`

if [ $? != 0 ] ; then echo "Terminating..."  ; exit 1 ; fi

eval set -- "$TEMP"


volume_flag=false
volume_id="vol-000000"
backup_method="dd"
v_count=0
h_count=0
m_count=0
while true ; do
	case "$1" in
		-h) echo "String to print" ; exit 0 ;;
		-v)	volume_flag=true 
			case "$2" in
				vol-*) volume_id=$2; shift 2 ;;
				*)  echo "\`$2' is not a valid volume id" ; exit 1 ;;
			esac ;;
		-m)         
                        case "$2" in
                                dd) backup_method="dd";echo "dd" ; shift 2 ;;
                                rsync) backup_method="rsync" ;echo "rsync"; shift 2 ;;
				*) echo "Please specify the right method, dd or rsync" ; exit 0 ;;
                        esac ;;
		--) shift ; break ;;
		*) echo "Arg  error!" ; exit 1 ;;
	esac
done

echo ${#arg[@]}
echo "Remaining arguments:"
for arg do echo '--> '"\`$arg'" ; done

ssh_env_flag=false
ssh_flag=""
if [ -z "$EC2_BACKUP_FLAGS_SSH" ]; then
	ssh_env_flag=false
	
else
	ssh_env_flag=true
	ssh_flag=$(printenv EC2_BACKUP_FLAGS_SSH)
	
fi



#echo $volume_id
volume_region=""
if "$volume_flag"  ; then
	volume_state=$(aws ec2 describe-volumes --volume-id $volume_id --output text --query 'Volumes[0].State')
	if [ $? != 0 ] ; then echo "Volume does not exist"  ; exit 1 ; fi
	if [ $volume_state != "available"  ] ; then echo "Volume does not available"  ; exit 1 ; fi

	volume_region=$(aws ec2 describe-volumes --volume-id $volume_id --output text --query 'Volumes[0].AvailabilityZone')
	if [ $? != 0 ] ; then echo "Region error"  ; exit 1 ; fi
	echo $volume_region
fi

#exit 0
#testing the validity of the volume


#create the instace of ami-speicified, read EC2_BACKUP_FLAGS_AWS
#aws_flags="$(printenv EC2_BACKUP_FLAGS_AWS)"

#create the security group
sg_result="$(aws ec2 create-security-group --group-name EC2-BACKUP-sg --description "ec2" --output text)"
sg_id="null"
if [[ $sg_result == *"true"* ]]
then
	echo "if"
        sg_id="$(echo $sg_result | cut -d' ' -f1)";
elif [[ $sg_result == "" ]]
then	
	sg_id="$(aws ec2 describe-security-groups --group-names EC2-BACKUP-sg --output text --query 'SecurityGroups[*].{Name:GroupId}')"	
else 
	echo "unknown error in security group"
	exit 0
fi
echo $sg_id
sg_result=$(aws ec2 authorize-security-group-ingress --group-name EC2-BACKUP-sg --protocol tcp --port 22 --cidr 0.0.0.0/0)

instance_id="$(aws ec2 run-instances --image-id  ami-fce3c696 --security-group-ids $sg_id --count 1 --instance-type t2.micro --key-name aaa --placement AvailabilityZone=$volume_region --query 'Instances[0].InstanceId' --output text)"

echo $instance_id
instance_ip="$(aws ec2 describe-instances --instance-ids $instance_id --query 'Reservations[0].Instances[0].PublicIpAddress' --output text)"

echo $instance_ip

sleep 1

i_so="$(aws ec2 describe-instance-status --instance-ids $instance_id --output text)"
while [[ $i_so == "" ]]; do
sleep 5
echo "again"
i_so="$(aws ec2 describe-instance-status --instance-ids $instance_id --output text)"
done


while [[ $i_so == *"initializing"* ]]; do
echo "retry"
i_so="$(aws ec2 describe-instance-status --instance-ids $instance_id --output text)"
sleep 30
done

key_from_console="$(aws ec2 get-console-output --instance-id $instance_id | grep ecdsa-sha2-nistp256 | tail -n1 | cut -d ' '  -f 2)"
while [[ $key_from_console == "" ]]; do
echo "retryget"
key_from_console="$(aws ec2 get-console-output --instance-id $instance_id | grep ecdsa-sha2-nistp256 | tail -n1 | cut -d ' '  -f 2)"
sleep 30
done


key_from_console="$(aws ec2 get-console-output --instance-id $instance_id | grep ecdsa-sha2-nistp256 | tail -n1 | cut -d ' '  -f 2)"
key_type="ecdsa-sha2-nistp256"
entry_to_add=$instance_ip" "$key_type" "$key_from_console
echo $entry_to_add >> ~/.ssh/known_hosts
ssh ubuntu@$instance_ip -o BatchMode=yes -i aaa.pem
