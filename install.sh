#!/bin/bash

#variables used
selection=0
needed_rpm=null_rpm_link
needed_deps="tar curl"
needed_rpm_name=null_rpm_name
needed_package_name=null_package_name
stage=release
interactive=1
skip_install=0
test_files=""
source_type=""
insecure=""
name=collectd-install
debian_distribution_name=""
sfx_ingest_url="https://ingest.signalfx.com"
input_collectd=""

#rpm file variables
centos_rpm="SignalFx-collectd-RPMs-centos-${stage}-latest.noarch.rpm"
aws_linux_rpm="SignalFx-collectd-RPMs-AWS_EC2_Linux-${stage}-latest.noarch.rpm"

#download location variables
centos="https://dl.signalfx.com/rpms/SignalFx-rpms/${stage}/${centos_rpm}"
aws_linux="https://dl.signalfx.com/rpms/SignalFx-rpms/${stage}/${aws_linux_rpm}"

#plugin rpm file variables
centos_plugin_rpm="SignalFx-collectd_plugin-RPMs-centos-${stage}-latest.noarch.rpm"
aws_linux_plugin_rpm="SignalFx-collectd_plugin-RPMs-AWS_EC2_Linux-${stage}-latest.noarch.rpm"

#plugin download location variables
centos_plugin="https://dl.signalfx.com/rpms/SignalFx-rpms/${stage}/${centos_plugin_rpm}"
aws_linux_plugin="https://dl.signalfx.com/rpms/SignalFx-rpms/${stage}/${aws_linux_plugin_rpm}"

signalfx_public_key_id="185894C15AE495F6"

#ppa locations for wheezy and jessie
signalfx_public_key_id="185894C15AE495F6"
wheezy_ppa="https://dl.signalfx.com/debs/collectd/wheezy/${stage}"
jessie_ppa="https://dl.signalfx.com/debs/collectd/jessie/${stage}"

usage() {
    echo "Usage: $name [ <api_token> ] [ --beta | --test ] [ -H <hostname> ] [ -U <Ingest URL>] [ -h ] [ --insecure ] [ -y ] [ --config-only ] [ -C /path/to/collectd ]"
    echo " -y makes the operation non-interactive. api_token is required and defaults to dns if no hostname is set"
    echo " -H <hostname> will set the collectd hostname to <hostname> instead of deferring to dns."
    echo " -U <Ingest URL> will be used as the ingest url. Defaults to ${sfx_ingest_url}"
    echo " -C /path/to/collectd to use that collectd, this will still install the plugin if it is not already installed."
    echo " --beta will use the beta repos instead of release."
    echo " --test will use the test repos instead of release."
    echo " --configure-only will use the installed collectd instead of attempting to install and will not install anything new."
    echo " --insecure will use the insecure -k with any curl fetches."
    echo " -h this page."
    exit "$1"
}

#confirm user input (yes or no)
confirm ()
{
    [ $interactive -eq 0 ] && return
    read -r -p "Is this correct? [y/N] " response < /dev/tty
    if [[ $response =~ ^([yY][eE][sS]|[yY])$ ]]
        then
    return
    else
        exit 0
    fi
}

parse_args(){
    while [ $# -gt 0 ]; do
        case $1 in
           -y)
              [ -z "$source_type" ] && source_type="dns"
              export interactive=0
              shift 1 ;;
           --beta)
              export stage=beta
              shift 1;;
           --test)
              export stage=test
              shift 1;;
           --test-files)
              export test_files="-test"
              shift 1;;
           --insecure)
              export insecure="-k"
              shift 1 ;;
           --configure-only)
              export skip_install=1
              shift 1 ;;
           -H)
              [ -z "$2" ] && echo "Argument required for hostname parameter." && usage -1
              export source_type="input"
              export hostname="$2"
              shift 2 ;;
           -C)
	      input_collectd="$2"
	      shift 2 ;;
           -U)
              [ -z "$2" ] && echo "Argument required for Ingest URL parameter." && usage -1
              export sfx_ingest_url="$2"; shift 2 ;;
           -h)
               usage 0; ;;
           \?) echo "Invalid option: -$1" >&2;
               exit 2;
               ;;
           *) break ;;
       esac
    done
    if [ -n "$insecure" ]; then
        echo "You have entered insecure mode; all curl commands will be executed with the -k 'insecure' parameter."
        confirm
    fi
}

show_usage_on_help() {
    if [ "$1" = "-h" ]; then
        usage 0
    fi

    while [ $# -gt 0 ]; do
        case $1 in
           -h)
              usage 0
              shift 1 ;;
           \?) shift 1;
               ;;
           *) break ;;
       esac
    done
}

parse_args_wrapper() {
    DLFILE=$(mktemp -d -t sfx-download-XXXXXX)
    export BASE_DIR="$DLFILE"

    show_usage_on_help "$@"

    if [ "$#" -gt 0 ]; then

        if [ "$(echo "$1" | cut -c1)" != "-" ]; then
            export raw_api_token=$1
            shift
        fi
    fi

    if [ "$#" -gt 0 ]; then
        parse_args "$@"
    fi

    if [ $interactive -eq 0 ] && [ -z "$raw_api_token" ]; then
        echo "Non-interactive requires the api token"
        usage -1
    fi

    if [ -n "$raw_api_token" ]; then
        api_output=$(curl $insecure -d '[]' -H "X-Sf-Token: $raw_api_token" -H "Content-Type:application/json" -X POST "$sfx_ingest_url"/v2/event 2>/dev/null)
        if [ ! "$api_output" = "\"OK\"" ]; then
            echo "There was a problem with the api token '$raw_api_token' passed in and we were unable to communicate with SignalFx: $api_output"
            echo "Please check your auth token is valid or check your networking."
            exit 1
        else
            echo "Round trip to SignalFx was successful; the install will continue with the api token provided."
        fi
    fi

    if [ -n "$input_collectd" ]; then
        if [ ! -f "$input_collectd" ]; then
            echo "We were unable to find a valid collectd at provided location of '$input_collectd'."
            usage 2
        fi
        export COLLECTD="$input_collectd"
        find_collectd_ver
    fi

    #determine if the script is being run by root or not
    user=$(whoami)
    if [ "$user" == "root" ]; then
        sudo=""
    else
        sudo="sudo"
    fi
    export sudo
}


determine_os() {
    #determine hostOS for newer versions of Linux
    hostOS=$(cat /etc/*-release | grep PRETTY_NAME | grep -o '".*"' | sed 's/"//g' | sed -e 's/([^()]*)//g' | sed -e 's/[[:space:]]*$//')
    if [ ! -f /etc/redhat-release ]
        then
        hostOS_2=null_os
    else
        #older versions of RPM based Linux that don't have version in PRETTY_NAME format
        hostOS_2=$(head -c 16 /etc/redhat-release)
    fi
}

#Function to determine the OS to install for from end user input
assign_needed_os() {
    case $selection in
        #REHL/Centos 7.x
        1)
            hostOS="CentOS Linux 7"
        ;;
        #REHL/Centos 6.x
        2)
            hostOS="CentOS Linux 6"
        ;;
        #Amazon Linux
        3)
            hostOS="Amazon Linux (all versions 2014.09 and newer)"
        ;;
        #Ubuntu 15.04
        4)
            hostOS="Ubuntu 15.04"
        ;;
        #Ubuntu 14.04
        5)
            hostOS="Ubuntu 14.04.1 LTS"
        ;;
        #Ubuntu 12.04
        6)
            hostOS="Ubuntu 12.04"
        ;;
        #Debian GNU/Linux 7 (wheezy)
        7)
            hostOS="Debian GNU/Linux 7"
        ;;
        #Debian GNU/Linux 8 (jessie)
        8)
            hostOS="Debian GNU/Linux 8"
        ;;
        *)
        printf "error occurred. Exiting. Please contact support@signalfx.com\n" && exit 0
        ;;
    esac
}

#Validate the users input
validate_os_input() {
if [[ "$selection" =~ ^[0-9]+$ ]] && [[ "$selection" -ge 1 && "$selection" -le 10 ]]
    then
        assign_needed_os
elif [ "$selection" == 11 ];
    then
        printf "\nWe currently do not support any other Linux distribution with our collectd packages.
Please visit https://support.signalfx.com/hc/en-us/articles/201094025-Use-collectd for detailed
instructions on how to install collectd for various Linux distributions or contact support@signalfx.com\n" && exit 0
elif [ "$selection" == 0 ];
    then
        printf "\nGood Bye!" && exit 0
else
    printf "\nInvalid user input please make a Distribution selection of 1 through 8.
Enter your Selection: "
    read -r selection < /dev/tty
    validate_os_input
fi
}

#Get end user input for OS to install for
get_os_input() {
	#Ask end user for what OS to install for
	printf "\nWe were unable to automatically determine the version of Linux you are on!
Please enter the number of the OS you wish to install for:
1. RHEL/Centos 7
2. RHEL/Centos 6.x
3. Amazon Linux (all versions 2014.09 and newer)
4. Ubuntu 15.04
5. Ubuntu 14.04
6. Ubuntu 12.04
7. Debian GNU/Linux 7
8. Debian GNU/Linux 8
9. Other
0. Exit
Enter your Selection: "
	read -r selection < /dev/tty

    validate_os_input

}

#RPM Based Linux Functions
#Install function for RPM collectd
install_rpm_collectd_procedure() {
    # if someone supplied collectd don't do anything
    if [ -n "$input_collectd" ]; then
        echo "Using collectd at '$input_collectd' instead of installing it"
        return
    fi
    #install deps
    printf "Installing Dependencies\n"
    $sudo yum -y install $needed_deps

    #download signalfx rpm for collectd
    printf "Downloading SignalFx RPM %s\n" "$needed_rpm"
    curl -sSL $insecure $needed_rpm -o "$needed_rpm_name"

    #install signalfx rpm for collectd
    printf "Installing SignalFx RPM\n"
    $sudo yum -y install $needed_rpm_name
    $sudo rm -f $needed_rpm_name
    type setsebool > /dev/null 2>&1 && $sudo setsebool -P collectd_tcp_network_connect on

    #install collectd from signalfx rpm
    printf "Installing collectd\n"
    $sudo yum -y install collectd

    #install base plugins signalfx deems necessary
    printf "Installing base-plugins\n"
    $sudo yum -y install collectd-disk collectd-write_http
}

#Debian Based Linux Functions
#Install function for debian based systems
#install function for debian collectd
install_debian_collectd_procedure() {
    # if someone supplied collectd don't do anything
    if [ -n "$input_collectd" ]; then
        echo "Using collectd at '$input_collectd' instead of installing it"
        return
    fi
    #update apt-get
    printf "Updating apt-get\n"
    $sudo apt-get -y update
    if [ "$stage" = "test" ]; then
        needed_deps="$needed_deps apt-transport-https"
    fi

    #Installing dependent packages to later add signalfx repo
    printf "Installing source package to get SignalFx collectd package\n"
    $sudo apt-get -y install $needed_deps "$needed_package_name"

    if [ "$stage" = "test" ]; then
        printf "Getting SignalFx collectd package from test repo hosted at SignalFx\n"
        echo "deb [trusted=yes] https://dl.signalfx.com/debs/collectd/${debian_distribution_name}/${stage} /" | $sudo tee /etc/apt/sources.list.d/signalfx_collectd-${stage}-${debian_distribution_name}.list > /dev/null
    else
        #Adding signalfx repo
        printf "Getting SignalFx collectd package\n"
        if [ "$debian_distribution_name" == "wheezy" ] || [ "$debian_distribution_name" == "jessie" ]; then
            $sudo apt-key adv --keyserver keyserver.ubuntu.com --recv-keys $signalfx_public_key_id
            echo "deb ${repo_link} /" | $sudo tee /etc/apt/sources.list.d/signalfx_collectd.list > /dev/null
        else
            $sudo add-apt-repository -y ppa:signalfx/collectd-${stage}
        fi
    fi

    #Updating apt-get to reference the signalfx repo to install collectd
    printf "Updating apt-get to reference new SignalFx package\n"
    $sudo apt-get -y update

    #Installing signalfx collectd package and plugins
    printf "Installing collectd and additional plugins\n"
    $sudo apt-get -y install collectd collectd-core

    #Configuring collectd with basic configuration
}

#take "hostOS" and match it up to OS and assign tasks
perform_install_for_os() {
    case $hostOS in
        "CentOS Linux 7")
            needed_rpm=$centos
            needed_rpm_name=$centos_rpm
            needed_plugin_rpm=$centos_plugin
            needed_plugin_rpm_name=$centos_plugin_rpm
            printf "Install will proceed for %s\n" "$hostOS"
            confirm
            install_rpm_collectd_procedure
            install_rpm_plugin_procedure
        ;;
        "CentOS Linux 6")
            needed_rpm=$centos
            needed_rpm_name=$centos_rpm
            needed_plugin_rpm=$centos_plugin
            needed_plugin_rpm_name=$centos_plugin_rpm
            printf "Install will proceed for %s\n" "$hostOS"
            confirm
            install_rpm_collectd_procedure
            install_rpm_plugin_procedure
        ;;
        "Amazon Linux AMI"*)
            needed_rpm=$aws_linux
            needed_rpm_name=$aws_linux_rpm
            needed_plugin_rpm=$aws_linux_plugin
            needed_plugin_rpm_name=$aws_linux_plugin_rpm
            printf "Install will proceed for %s\n" "$hostOS"
            confirm
            install_rpm_collectd_procedure
            install_rpm_plugin_procedure
        ;;
        "Ubuntu 15.04"*)
            needed_package_name=software-properties-common
            printf "Install will proceed for %s\n" "$hostOS"
            debian_distribution_name="vivid"
            confirm
            install_debian_collectd_procedure
            install_debian_collectd_plugin_procedure
        ;;
        "Ubuntu 14.04"*)
            needed_package_name=software-properties-common
            printf "Install will proceed for %s\n" "$hostOS"
            debian_distribution_name="trusty"
            confirm
            install_debian_collectd_procedure
            install_debian_collectd_plugin_procedure
        ;;
        "Ubuntu 12.04"* | "Ubuntu precise"*)
            needed_package_name=python-software-properties
            printf "Install will proceed for %s\n" "$hostOS"
            debian_distribution_name="precise"
            confirm
            install_debian_collectd_procedure
            install_debian_collectd_plugin_procedure
        ;;
        "Debian GNU/Linux 7")
            needed_package_name="apt-transport-https"
            printf "Install will proceed for %s\n" "$hostOS"
            repo_link=$wheezy_ppa
            debian_distribution_name="wheezy"
            confirm
            install_debian_collectd_procedure
            install_debian_collectd_plugin_procedure
        ;;
        "Debian GNU/Linux 8")
            needed_package_name="apt-transport-https"
            printf "Install will proceed for %s\n" "$hostOS"
            repo_link=$jessie_ppa
            debian_distribution_name="jessie"
            confirm
            install_debian_collectd_procedure
            install_debian_collectd_plugin_procedure
        ;;
        *)
        case $hostOS_2 in
            "CentOS release 6")
                needed_rpm=$centos
                needed_rpm_name=$centos_rpm
                needed_plugin_rpm=$centos_plugin
                needed_plugin_rpm_name=$centos_plugin_rpm
                printf "Install will proceed for %s\n" "$hostOS_2"
                confirm
                install_rpm_collectd_procedure
                install_rpm_plugin_procedure
            ;;
            "Red Hat Enterpri")
                needed_rpm=$centos
                needed_rpm_name=$centos_rpm
                needed_plugin_rpm=$centos_plugin
                needed_plugin_rpm_name=$centos_plugin_rpm
                printf "Install will proceed for %s\n" "$hostOS"
                install_rpm_collectd_procedure
                install_rpm_plugin_procedure
            ;;
            *)
                get_os_input
                perform_install_for_os
            ;;
        esac
        ;;
    esac
    if [ -z "$FOUND" ]; then
        printf "Unsupported OS, will not attempt to install plugin\n"
        NO_PLUGIN=1
    fi
}

vercomp () {
    if [[ $1 == "$2" ]]
    then
        echo 0
        return
    fi
    local IFS=.
    local i ver1=($1) ver2=($2)
    # fill empty fields in ver1 with zeros
    for ((i=${#ver1[@]}; i<${#ver2[@]}; i++))
    do
        ver1[i]=0
    done
    for ((i=0; i<${#ver1[@]}; i++))
    do
        if [[ -z ${ver2[i]} ]]
        then
            # fill empty fields in ver2 with zeros
            ver2[i]=0
        fi
        if ((10#${ver1[i]} > 10#${ver2[i]}))
        then
            echo 1
            return
        fi
        if ((10#${ver1[i]} < 10#${ver2[i]}))
        then
            echo 2
            return
        fi
    done
    echo 0
}

check_for_err() {
    if [ $? != 0 ]; then
        printf "FAILED\n"
        exit 1
    else
        echo "$@"
    fi
}

find_installed_collectd(){
   if [ -z "$COLLECTD" ]; then
	   for p in /opt/signalfx-collectd/sbin/collectd /usr/sbin/collectd "/usr/local/sbin/collectd"; do
	       if [ -x $p ]; then
		   export COLLECTD=${p}
		   find_collectd_ver
		   break;
	       fi
	   done
   fi
}

find_collectd_ver() {
    COLLECTD_VER=$(${COLLECTD} -h | sed -n 's/^collectd \([0-9\.]*\).*/\1/p')
    if [ -z "$COLLECTD_VER" ]; then
        echo "Failed to figure out CollectD version using collectd at '$COLLECTD'.";
        usage 2
    fi
}

#RPM Based Linux Functions
#Install function for RPM collectd
install_rpm_plugin_procedure() {
    if [ -f /opt/signalfx-collectd-plugin/signalfx_metadata.py ]; then
        printf "SignalFx collectd plugin already installed\n"
        FOUND=1
        return
    fi
    #download signalfx plugin rpm for collectd
    printf "Downloading SignalFx plugin RPM\n"
    curl -sSL $insecure $needed_plugin_rpm -o $needed_plugin_rpm_name

    #install signalfx rpm for collectd
    printf "Installing SignalFx plugin RPM\n"
    $sudo yum -y install $needed_plugin_rpm_name
    $sudo rm -f $needed_plugin_rpm_name

    #install collectd from signalfx plugin rpm
    printf "Installing signalfx-collectd-plugin\n"
    $sudo yum -y install signalfx-collectd-plugin
    FOUND=1
}

#Debian Based Linux Functions
#Install function for debian based systems
install_debian_collectd_plugin_procedure() {
    if [ -f /opt/signalfx-collectd-plugin/signalfx_metadata.py ]; then
        printf "SignalFx collectd plugin already installed\n"
        FOUND=1
        return
    fi
    #Installing dependent packages to later add signalfx plugin repo
    printf "Installing source package to get SignalFx collectd plugin package\n"
    $sudo apt-get -y install $needed_package_name

    repo_link="https://dl.signalfx.com/debs/signalfx-collectd-plugin/${debian_distribution_name}/${stage}"
    if [ "$stage" = "test" ]; then
        printf "Getting SignalFx collectd package from test repo hosted at SignalFx\n"
        echo "deb [trusted=yes] ${repo_link} /" | $sudo tee /etc/apt/sources.list.d/signalfx_collectd_plugin-${stage}-${debian_distribution_name}.list > /dev/null
    else
        #Adding signalfx repo
        printf "Getting SignalFx collectd package\n"
        if [ "$debian_distribution_name" == "wheezy" ] || [ "$debian_distribution_name" == "jessie" ]; then
            $sudo apt-key adv --keyserver keyserver.ubuntu.com --recv-keys $signalfx_public_key_id
            echo "deb ${repo_link} /" | $sudo tee /etc/apt/sources.list.d/signalfx_collectd_plugin-${stage}-${debian_distribution_name}.list > /dev/null
        else
            $sudo add-apt-repository -y ppa:signalfx/collectd-plugin-${stage}
        fi
    fi


    #Updating apt-get to reference the signalfx repo to install plugin
    printf "Updating apt-get to reference new SignalFx plugin package\n"
    $sudo apt-get -y update

    #Installing signalfx collectd package and plugins
    printf "Installing collectd and additional plugins\n"
    $sudo apt-get -y install signalfx-collectd-plugin
    FOUND=1
}

sfx_ingest_url="https://ingest.signalfx.com"
insecure=""

get_logfile() {
    LOGTO="\"/var/log/signalfx-collectd.log\""
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        if [ "$NAME" == "CentOS Linux" -a "$VERSION_ID" == "7" ]; then
            LOGTO="stdout";
        fi
    fi
}

get_collectd_config() {
    curl -sSL $insecure https://dl.signalfx.com/install-files${test_files}.tgz  | tar -C "$BASE_DIR" -xzf -

    printf "Getting config file for collectd ..."
    find_installed_collectd
    COLLECTD_CONFIG=$(${COLLECTD} -h 2>/dev/null | grep 'Config file' | awk '{ print $3; }')

    if [ -z "$COLLECTD_CONFIG" ]; then
        echo "Failed"
        exit 2;
    else
        echo "Success";
    fi
    COLLECTD_ETC=$(dirname "${COLLECTD_CONFIG}")
    USE_SERVICE_COLLECTD=0
    if [ "$COLLECTD_ETC" == "/etc" ]; then
	USE_SERVICE_COLLECTD=1
        COLLECTD_ETC="/etc/collectd.d"
        printf "Making /etc/collectd.d ..."
        mkdir -p ${COLLECTD_ETC};
        check_for_err "Success";
    elif [ "$COLLECTD_ETC" == "/etc/collectd" ]; then
        USE_SERVICE_COLLECTD=1
    fi

	 COLLECTD_MANAGED_CONFIG_DIR=${COLLECTD_ETC}/managed_config
	 COLLECTD_FILTERING_CONFIG_DIR=${COLLECTD_ETC}/filtering_config
    printf "Getting TypesDB default value ..."
    if [ -x /usr/bin/strings ]; then
        TYPESDB=$(strings "${COLLECTD}" | grep /types.db)
    else
        TYPESDB=$(grep -oP -a "/[-_/[:alpha:]0-9]+/types.db\x00" "${COLLECTD}")
    fi
    if [ -z "$TYPESDB" ]; then
        echo "FAILED"
        exit 2;
    else
        echo "Success";
    fi
}

get_source_config() {
    if [ -z "$source_type" ]; then
        echo "There are two ways to configure the source name to be used by collectd"
        echo "when reporting metrics:"
        echo "dns - Use the name of the host by resolving it in dns"
        echo "input - You can enter a hostname to use as the source name"
        echo
        read -r -p "How would you like to configure your Hostname? (dns  or input): " source_type < /dev/tty

        while [ "$source_type" != "dns" ] && [ "$source_type" != "input" ]; do
            read -r -p "Invalid answer. How would you like to configure your Hostname? (dns or input): " source_type < /dev/tty
        done
    fi

    case $source_type in
    "input")
        if [ -z "$hostname" ]; then
            read -r -p "Input hostname value: " hostname < /dev/tty
            while [ -z "$hostname" ]; do
              read -r -p "Invalid input. Input hostname value: " hostname < /dev/tty
            done
        fi
        SOURCE_NAME_INFO="Hostname \"${hostname}\""
        ;;
    "dns")
        SOURCE_NAME_INFO="FQDNLookup   true"
        ;;
    *)
        echo "Invalid SOURCE_TYPE value ${source_type}";
        exit 2;
    esac

}

install_config(){
    printf "Installing %s ..." "$2"
    cp "${BASE_DIR}/$1" "${COLLECTD_MANAGED_CONFIG_DIR}"
    check_for_err "Success"
}

install_filters() {
    printf "Installing filtering config ..."
    cp "${BASE_DIR}/filtering.conf" "${COLLECTD_FILTERING_CONFIG_DIR}/"
    check_for_err  "Success"
}

check_for_aws() {
    [ -n "$AWS_DONE" ] && return
    printf "Checking to see if this box is in AWS: "
    AWS_UNIQUE_ID=$("${BASE_DIR}/get_aws_unique_id") || true
    if [ -n "$AWS_UNIQUE_ID" ]; then
        printf "Using AWSUniqueId: %s\n" "${AWS_UNIQUE_ID}"
        EXTRA_DIMS="?sfxdim_AWSUniqueId=${AWS_UNIQUE_ID}"
    else
        printf "Not IN AWS\n"
    fi
    AWS_DONE=1
}

install_plugin_common() {
    if [ -z "$raw_api_token" ]; then
       if [ -z "${SFX_USER}" ]; then
           read -r -p "Input SignalFx user name: " SFX_USER < /dev/tty
           while [ -z "${SFX_USER}" ]; do
               read -r -p "Invalid input. Input SignalFx user name: " SFX_USER < /dev/tty
           done
       fi
       raw_api_token=$(python "${BASE_DIR}/get_all_auth_tokens.py" --print_token_only --error_on_multiple "${SFX_API}" "${SFX_ORG}" "${SFX_USER}")
       if [ -z "$raw_api_token" ]; then
          echo "Failed to get SignalFx API token";
          exit "2";
       fi
    fi
    check_for_aws
}

install_signalfx_plugin() {
    if [ -n "$NO_PLUGIN" ]; then
        return
    fi
    install_plugin_common

    printf "Fixing SignalFX plugin configuration ..."
    sed -e "s#%%%API_TOKEN%%%#${raw_api_token}#g" \
        -e "s#URL.*#URL \"${sfx_ingest_url}/v1/collectd${EXTRA_DIMS}\"#g" \
        "${BASE_DIR}/10-signalfx.conf" > "${COLLECTD_MANAGED_CONFIG_DIR}/10-signalfx.conf"
    check_for_err "Success";
}

install_write_http_plugin(){
    install_plugin_common

    printf "Fixing write_http plugin configuration ..."
    sed -e "s#%%%API_TOKEN%%%#${raw_api_token}#g" \
        -e "s#%%%INGEST_HOST%%%#${sfx_ingest_url}#g" \
	-e "s#%%%EXTRA_DIMS%%%#${EXTRA_DIMS}#g" \
        "${BASE_DIR}/10-write_http-plugin.conf" > "${COLLECTD_MANAGED_CONFIG_DIR}/10-write_http-plugin.conf"
    check_for_err "Success";
}

copy_configs(){
    okay_ver=$(vercomp "$COLLECTD_VER" 5.2)
    if [ "$okay_ver" !=  2 ]; then
        install_config 10-aggregation-cpu.conf "CPU Aggregation Plugin"
    fi
    install_write_http_plugin
    install_filters
}

verify_configs(){
    echo "Verifying config"
    ${COLLECTD} -t
    echo "All good"
}

check_with_user_and_stop_other_collectd_instances(){
    count_running_collectd_instances=$(pgrep -x collectd | wc -l)
    if [ "$count_running_collectd_instances" -ne 0 ]; then
        PROCEED_STATUS=0
        printf "Currently, %s more instances of collectd are running on this machine\n" "$count_running_collectd_instances"
        printf "Do you want to\n"
        printf "1. Stop here and check\n"
        printf "2. Stop all running instances of collectd and start a new one\n"
        printf "3. Start this along with others\n"
        while [[ ! ( $PROCEED_STATUS -eq 1 || $PROCEED_STATUS -eq 2 || $PROCEED_STATUS -eq 3 ) ]]; do
            read -r -p "Choose an option(1/2/3): " PROCEED_STATUS < /dev/tty
        done
        case $PROCEED_STATUS in
            1)
                echo "Check and come back. Exiting for now ..."
                exit 0;
                ;;
            2)
                echo "Stopping all running collectd instances ..."
                pkill -x collectdmon > /dev/null 2>&1
                pkill -x collectd > /dev/null 2>&1 # centos does not have collectdmon
                ;;
        esac
    fi
}

configure_collectd() {
    get_collectd_config
    get_source_config
    get_logfile
    okay_ver=$(vercomp "$COLLECTD_VER" 5.4.0)
    if [ "$okay_ver" != 2 ]; then
        WRITE_QUEUE_CONFIG="WriteQueueLimitHigh 500000\\nWriteQueueLimitLow  400000"
    fi
    okay_ver=$(vercomp "$COLLECTD_VER" 5.5.0)
    if [ "$okay_ver" != 2 ]; then
        WRITE_QUEUE_CONFIG="$WRITE_QUEUE_CONFIG\\nCollectInternalStats true"
    fi

    printf "Making managed config dir %s ..." "${COLLECTD_MANAGED_CONFIG_DIR}"
    mkdir -p "${COLLECTD_MANAGED_CONFIG_DIR}"
    check_for_err "Success";

    printf "Making managed filtering config dir %s ..." "${COLLECTD_FILTERING_CONFIG_DIR}"
    mkdir -p "${COLLECTD_FILTERING_CONFIG_DIR}"
    check_for_err "Success";

    if [ -e "${COLLECTD_CONFIG}" ]; then
        printf "Backing up %s: " "${COLLECTD_CONFIG}";
        _bkupname=${COLLECTD_CONFIG}.$(date +"%Y-%m-%d-%T");
        mv "${COLLECTD_CONFIG}" "${_bkupname}"
        check_for_err "Success(${_bkupname})";
    fi
    printf "Installing signalfx collectd configuration to %s ... " "${COLLECTD_CONFIG}"
    sed -e "s#%%%TYPESDB%%%#${TYPESDB}#" \
        -e "s#%%%SOURCENAMEINFO%%%#${SOURCE_NAME_INFO}#" \
        -e "s#%%%WRITEQUEUECONFIG%%%#${WRITE_QUEUE_CONFIG}#" \
        -e "s#%%%COLLECTDMANAGEDCONFIG%%%#${COLLECTD_MANAGED_CONFIG_DIR}#" \
        -e "s#%%%COLLECTDFILTERINGCONFIG%%%#${COLLECTD_FILTERING_CONFIG_DIR}#" \
        -e "s#%%%LOGTO%%%#${LOGTO}#" \
        "${BASE_DIR}/collectd.conf.tmpl" > "${COLLECTD_CONFIG}"
    check_for_err "Success"

    # Install Plugin
    install_signalfx_plugin

    # Install managed_configs
    copy_configs
    verify_configs

    # Stop running Collectd
    echo "Stopping collectd"
    if [ ${USE_SERVICE_COLLECTD} -eq 1 ]; then
        service collectd stop
    else
        pkill -nx collectd # stops the newest (most recently started) collectd similar to 'service collectd stop'
    fi

    check_with_user_and_stop_other_collectd_instances

    echo "Starting collectd"
    if [ ${USE_SERVICE_COLLECTD} -eq 1 ]; then
        service collectd start
    else
        ${COLLECTD}
    fi
}


#Determine the OS and install/configure collectd to send metrics to SignalFx
parse_args_wrapper "$@"
determine_os
[ $skip_install -eq 0 ] && perform_install_for_os
configure_collectd
rm -rf "$BASE_DIR"
