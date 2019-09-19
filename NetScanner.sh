#!/bin/bash

# GLOBAL DEFINITIONS
filename=$1
logfile=$2
vmfile=$3
key="/root/.ssh/script_rsa"
netseg=("172.16.0" "172.16.1" "172.16.10" "192.168.0")
max=(254 1 254 5)
commands=(
	"(hostname; hostname -f) | sed '/^localhost/s/.*/None (localhost)/' | tail -1" # Hostname
	"(cat /sys/class/net/*/address) | grep -v '00:00:00:00:00:00' | head -1" # MAC Address
	"(df -h --total) | tail -1 | awk '{print \$3\"/\"\$2}'" # Storage
	"case \"\$((dmesg;systemd-detect-virt;hostnamectl;virt-what;facter virtual) 2> /dev/null )\" in *PowerEdge* ) echo Physical;; *openvz* ) echo OpenVZ;; *KVM* ) echo KVM;; *vmware* ) echo VMWare;; esac" # Virtualization
	"dmidecode | grep 'Product Name' | cut -f2 -d: | tr -d ' ' | head -1" # Serial #
	"dmidecode | grep 'Serial Number' | cut -f2 -d: | tr -d ' ' | head -1" # Product Name
	"grep -h 'PRETTY_NAME\|CentOS' /etc/*-release 2>/dev/null | head -1 | cut -d'\"' -f2" # OS
)

servList=(
	"Master (172.16.0.110)"
	"Compute1 (172.16.10.111)"
	"Compute2 (172.16.10.112)"
	"Compute5 (172.16.10.115)"
	"Compute6 (172.16.0.116)"
	"Compute8 (172.16.0.118)"
	"Compute9 (172.16.0.119)"
	"ESXI (172.16.10.51)"
)

argParse() {
if [ -z "$filename" ]
then
	filename="netinfo.csv"
else
        if ! echo $filename | grep -oq "\." # Check if there's a "." in the argument (meaning the user provided a file type)
        then
                filename="$filename.csv" # If not type is provided, use .csv
        fi
fi

if [ -z "$logfile" ]
then
        logfile="infolog.txt"
else
        if ! echo $logfile | grep -oq "\." # Check if there's a "." in the argument (meaning the user provided a file type)
        then
                logfile="$logfile.txt" # If not type is provided, use .txt
        fi
fi

if [ -z "$vmfile" ]
then
        vmfile="VM.csv"
else
        if ! echo $vmfile | grep -oq "\." # Check if there's a "." in the argument (meaning the user provided a file type)
        then
                vmfile="$vmfile.csv" # If not type is provided, use .csv
        fi
fi
touch $filename $logfile $vmfile
}

checkFile() {
if [ ! -f $filename ]
then
        echo "$filename not found, building..."
        touch $filename
fi
if [ ! -f $logfile ]
then
        echo "$logfile not found, building..."
        touch $logfile
fi
if [ ! -f $vmfile ]
then
        echo "$vmfile not found, building..."
        touch $vmfile
fi

}

SSH() {
	ssh -q -i "$key" -o ConnectTimeout=5 -o StrictHostKeyChecking=no -o BatchMode=yes root@$address "$1" 2>/dev/null
}

checkInternet() {
address="8.8.8.8"
getLine
}

getLine() {
echo "Gathering info for $address..."
line=()
canSSH=false
line[0]="$address"
if ( ping -c 2 $address &> /dev/null )
then
	line[1]="UP"
else
	line[1]="DOWN"
fi

if  [[ "$address" == "172.16.0.*" ]] && (( "$hostseg" >= "150" ))
then
	line[2]="DHCP"
else
	line[2]="Static"
fi

if [ "${line[0]}" != "8.8.8.8" ] && [ "${line[1]}" == "UP" ] && [ "$(SSH "echo Success 2>&1")" &> /dev/null = "Success" ]
then
	canSSH=true
fi

for (( i=0; i < ${#commands[@]}; i++ ))
do
	
	if [ "$canSSH" = true ]
	then
		line[${#line[@]}]="$(SSH "${commands[i]}")"
	else
		line[${#line[@]}]=""
	fi
done

line[${#line[@]}]="$(grep "\<${line[0]}\>\|\<${line[4]}\>" $vmfile | awk '{print $1}' | tr -d '"' | cut -f1 -d ' ')" # Find VM
fixLine $filename
}

getOldLine() {
oldline=()
for ((i=0; i < ${#line[@]}; i++)) 
do
	oldline[i]="$(grep "\<$address\>" $1 | awk -F'"' -v col=$(((i+1)*2)) '{print $col}')"
done
}

fixLine() {
getOldLine $1

if [ ! -z "${line[3]}" ] && ! (grep "(DNS)" $logfile | grep -q "\<$address\>") && [ "${line[2]" != "DHCP" ] && ( [ "$(dig +short ${line[3]})" != "$address" ] || [ "$(dig +short -x $address | sed 's/.$//')" != "${line[3]}" ] )
then
        if [ -z "$(dig +short -x $address)" ] # If true, no entry found
        then
                DNSLine="$(date +%b-%-d%t%H:%M) (DNS):\tNo DNS entry for $address; Real: $address/${line[3]}"
        else
                DNSLine="$(date +%b-%-d%t%H:%M) (DNS):\tDNS mismatch for $address Real: $address/${line[3]} Given: $(dig +short ${line[3]})/$(dig +short -x $address | sed 's/.$//')"
        fi
        echo -e "$DNSLine" >> $logfile
fi

for ((i=0; i < ${#line[@]}; i++ ))
do
newVal="${line[i]}"
oldVal="${oldline[i]}"
if [ -z "$newVal" ]
then
	line[i]="\"$oldVal\"\t"
else
	if [ "$newVal" != "$oldVal" ] && [ ! -z "$oldVal" ]
	then
        	echo -e "$(date +%b-%-d%t%H:%M) ($i):\t$address from $oldVal to $newVal" >> $logfile # Log any changes
	fi
	line[i]="\"$newVal\"\t"
fi
done
writeLine $1
}

writeLine() {
linenum="$(grep -n "\<$address\>" $1 | cut -f1 -d:)"
write="${line[*]}"
echo -e "Line: $write"
if [ -z "$linenum" ]
then
	echo -e "$write" >> $1
else
	`sed -i "${linenum}s@.*@${write}@" $1`
fi
}

ipStatus() {
checkFile
for (( loopnum=0; loopnum < ${#netseg[@]}; loopnum++ ))
do
	for (( hostseg=1; hostseg <= ${max[loopnum]}; hostseg++ ))
	do
		if [ $(( $hostseg % 10 )) == 0 ] 
		then
			checkInternet	
		fi
		address="${netseg[loopnum]}.$hostseg"
		getLine
	done

done
}

whatsWhere() {
checkFile
val="${#servList[@]}"
for (( num=0; num < $val; num++ ))
do	
	vmCMD=() # Quantity, Name, Number, IP
	line=()
	kvm=false
	line[0]="\"${servList[$num]}\"\t"
	address="$(echo ${line[0]} | awk -vRS=')' -vFS='(' '{print $2}')"
	line[1]="\"$address\"\t"
	if SSH "vzlist" &> /dev/null #OpenVZ
	then
		vmCMD=(
			"SSH \"vzlist -H | wc -l\""
			"SSH \"vzlist -H -o hostname\" | head -\$i | tail -1"
			""
			"SSH \"vzlist -H -o ip\" | head -\$i | tail -1"
		)
	else if SSH "virsh list" &> /dev/null # KVM
	then
		vmCMD=(
			"SSH \"virsh list --all | grep '[0-9]\|- ' | wc -l\""
			"SSH \"virsh list --all\" | grep '[0-9]\|- ' | awk '{print \$2}' | head -\$i | tail -1"
			"SSH \"virsh domiflist \$name\" | grep -v 'MAC\|---' | awk '{print \$5}'"
			"grep \"\<$number\>\" $filename | awk '{print $1}' | tr -d '\"'"
		)
		kvm=true
	else if SSH "esxcli --help" &> /dev/null #ESXI
	then
		vmCMD=(
			"SSH \"vim-cmd vmsvc/getallvms\" | grep '^[0-9]' | wc -l"
			"SSH \"vim-cmd vmsvc/getallvms\" | grep '^[0-9]' | awk '{print \$2}' | head -\$i | tail -1"
			"SSH \"vim-cmd vmsvc/getallvms\" | grep -o '^[0-9]' | head -\$i | tail -1"
			"SSH \"vim-cmd vmsvc/get.guest \"\$number\"\" | grep -oE \"172.16.[0-9]{1,3}.[0-9]{1,3}\" | head -1"
		)
	fi
	fi
	fi
getVM
done	
}

getVM() {
val="$(eval ${vmCMD[0]})"
for (( i=1; i<=$val; i++ ))
do
	addr=""
	name="$(eval ${vmCMD[1]})"
	number="$(eval ${vmCMD[2]})"
	if [ "$kvm" = true ]
	then
		addr="$number"
	else
		addr="$(eval ${vmCMD[3]})"
	fi
	line[${#line[@]}]="\"$name\"\t"
	line[${#line[@]}]="\"$addr\"\t"
done
writeLine $vmfile
}


# Entry Point
argParse
while true
do
		checkInternet	
		ipStatus
		whatsWhere
		while [ "$(date +%M)" != "40" ]
		do
			checkInternet
			sleep 45
		done
done
