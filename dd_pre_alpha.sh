#!/bin/bash
TEMP=`getopt -o v:m:h -n 'example.bash' -- "$@"`

if [ $? != 0 ] ; then echo "Terminating..."  ; exit 1 ; fi

eval set -- "$TEMP"

pem_file_path='/home/rding6/devenv-key.pem' #todo
key_name='devenv-key' #todo
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
volume_zone=""
if "$volume_flag"  ; then
	volume_state=$(aws ec2 describe-volumes --volume-id $volume_id --output text --query 'Volumes[0].State')
	if [ $? != 0 ] ; then echo "Volume does not exist"  ; exit 1 ; fi
	if [ $volume_state != "available"  ] ; then echo "Volume does not available"  ; exit 1 ; fi

	volume_zone=$(aws ec2 describe-volumes --volume-id $volume_id --output text --query 'Volumes[0].AvailabilityZone')
	if [ $? != 0 ] ; then echo "Region error"  ; exit 1 ; fi
	echo $volume_zone
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

instance_id="$(aws ec2 run-instances --image-id  ami-fce3c696 --security-group-ids $sg_id --count 1 --instance-type t2.micro --key-name $key_name --placement AvailabilityZone=$volume_zone --query 'Instances[0].InstanceId' --output text)"

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

key_from_console="$(aws ec2 get-console-output --instance-id $instance_id --output text | grep ecdsa-sha2-nistp256 | tail -n1 | cut -d ' '  -f 2)"
while [[ $key_from_console == "" ]]; do
echo "retryget"
key_from_console="$(aws ec2 get-console-output --instance-id $instance_id --output text | grep ecdsa-sha2-nistp256 | tail -n1 | cut -d ' '  -f 2)"
sleep 30
done


key_from_console="$(aws ec2 get-console-output --instance-id $instance_id --output text | grep ecdsa-sha2-nistp256 | tail -n1 | cut -d ' '  -f 2)"
key_type="ecdsa-sha2-nistp256"
entry_to_add=$instance_ip" "$key_type" "$key_from_console
echo $entry_to_add >> ~/.ssh/known_hosts


#ssh ubuntu@$instance_ip -o BatchMode=yes -i aaa.pem


#rsh_remote_host='rsh ubuntu@54.173.211.173 -i /home/rding6/devenv-key.pem' 
rsh_remote_host="rsh ubuntu@$instance_ip -i $pem_file_path"
cur_dir='.'
#my_instance_id='i-ace2f836'
#my_volume_id='vol-6110f0b0'
my_instance_id=$instance_id
my_volume_id=$volume_id
device_name=''

get_next_avaliable_device_name() {
    last_device_name=$($rsh_remote_host sudo lsblk | awk '{print $1}' | tail -1)
    if [ 'xvdz' = $last_device_name ]
    then
        return 2
    fi
    device_names=('└─xvda1' 'xvdb' 'xvdc' 'xvdd' 'xvde' 'xvdf' 'xvdg' 'xvdh' 'xvdi' 'xvdj' 'xvdk' 'xvdl' 'xvdm' 'xvdn' 'xvdo' 'xvdp' 'xvdq' 'xvdr' 'xvds' 'xvdt' 'xvdu' 'xvdv' 'xvdw' 'xvdx' 'xvdy' 'xvdz')
    i=0
    for (( ; i < 25; i++)); do
        if [ $last_device_name = ${device_names[$i]} ]
        then
            break;
        fi
    done
    device_name=${device_names[$(($i+1))]} 
    if [ -z $device_name ]
    then
        return 2
    else
        echo "/dev/$device_name"
    fi
    return 0
}



get_volume_size_by_dir_size() {
    size=$(($1*2/(1024*1024)))
    if [ $size = 0 ]
        then echo 1 
        else echo $size 
    fi
}

get_cur_dir_size() {
    du -s $cur_dir | awk '{print $1;}'
}

create_volume(){
    if [ -z $my_volume_id ]
    then
        # Zero-length var
        echo 'no volume_id sepcified, try to create a new volume'
        volume_id=$(aws ec2 create-volume --size $1  --availability-zone $volume_zone --volume-type gp2 --output text --query 'VolumeId')
        echo "successfully created volume, its volume_id: $volume_id"

    else
        state=$(aws ec2 describe-volumes --volume-id $my_volume_id --output text --query 'Volumes[0].State')
        if [ $state = 'available' ]
        then
            echo "the volume: $volume_id is now available"
            return 0
        fi

        volume_id=$my_volume_id
        echo "volume_id $volume_id sepcified, try to detach it and make it available"
        aws ec2 detach-volume --volume-id $volume_id
    fi

    for i in `seq 1 10`;
    do
        state=$(aws ec2 describe-volumes --volume-id $volume_id --output text --query 'Volumes[0].State')
        if [ $? -ne 0 ]
        then
            return 2
        fi

        if [ $state = 'available' ]
        then
            echo "the volume: $volume_id is now available"
            my_volume_id=$volume_id
            return 0
        else
            sleep 1
            echo "waiting until the volume become available, $i seconds past"
        fi
    done
    return  2
}

attach_volume(){
    device_name=$(get_next_avaliable_device_name)
    echo "our volume will be attached to $device_name"
    if [ $? -ne 0 ]
        then
            return 2
    fi


    for i in `seq 1 10`;
    do
        state=$(aws ec2 describe-volumes --volume-id $1 --output text --query 'Volumes[0].State')
        if [ $state = 'available' ]
        then
            echo "attaching $1 to $2 $device_name"
            aws ec2 attach-volume --volume-id $1 --instance-id $2 --device $device_name
        else
            sleep 1
            echo 'wait for attached or in-use state'
            if [ $state = 'in-use' ]
            then
                echo 'state changed to in-use'
                return 0;
            else
                return 1;
            fi
        fi
    done
    return 1
}

dir_size=$(get_cur_dir_size)
echo "the size of  dir $cur_dir :  $dir_size KB"
size=$(get_volume_size_by_dir_size $dir_size) 
echo "the volume size we create is $size GB" 
create_volume $size
echo " create_value return value is $?"

attach_volume $my_volume_id $my_instance_id
echo $device_name

sleep 5
echo 'try to mkfs'
echo "$rsh_remote_host sudo mkfs -t ext4 $device_name"
$rsh_remote_host sudo mkfs -t ext4 $device_name
echo "mkfs return value $?"


echo "check if /mnt/backup_disk exists ?"
$rsh_remote_host sudo  ls /mnt/backup_disk
if [ $? -ne 0 ]
then
    echo 'creating backup folder /mnt/backup_disk'
    $rsh_remote_host sudo  mkdir -p /mnt/backup_disk
    echo "create folder return value $?"
fi

echo "mounting device  $device_name to /mnt/backup_disk"
$rsh_remote_host sudo mount $device_name /mnt/backup_disk
echo "mount return value $?"



echo "begin to backup: "
tar cvf - $cur_dir | $rsh_remote_host sudo dd of=/mnt/backup_disk/0
echo " backup return value $?"

$rsh_remote_host sudo ls /mnt/backup_disk/
sleep 5

echo "umount $device_name"
$rsh_remote_host sudo umount $device_name
echo "umount return $?"

echo "detaching volume..."
aws ec2 detach-volume --volume-id $my_volume_id
echo "detach returned $?"

echo "backup successful!!!!"
