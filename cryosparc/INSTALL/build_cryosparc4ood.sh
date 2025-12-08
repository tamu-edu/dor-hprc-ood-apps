#!/bin/bash
# script provided by Michael Dickens cmdickens@tamu.edu - TAMU HPRC - https://hprc.tamu.edu

function help {
    echo
    echo "------------------------------------------------------------------------"
    echo "   Builds a definition file and creates a Singularity image"
    echo "------------------------------------------------------------------------"
    echo
    echo "Synopsys:"
    echo "    This script will generate a Singulairty definition file and an install script (cryosparc4ood.def)"
    echo "    and an install script (src/install_cryosparc4ood_v4.7.1.sh) which are used in the Singularity image build process"
    echo
    echo "Usage: $(basename $0) -l license_id"
    echo
    echo "    Required:"
    echo "           -l license                     cryosparc license id"
    echo
    echo "    Example command: (on a GPU node)"
    echo "      A GPU and the singularity command are required for the install. If you do not have these on a login node, use a compute node"
    echo
    echo "          ./build_cryosparc4ood.sh -l \$LICENSE_ID"
    echo
    echo "    Files:"
    echo "        Need a directory named src with the master and worker files (not symlinks) for use with singularity -B"
    echo
    echo "        ├── build_cryosparc4ood.sh"
    echo "        └── src"
    echo "            ├── cryosparc_master.tar.gz"
    echo "            └── cryosparc_worker.tar.gz"
    echo
    echo "    Download Files:"
    echo "        curl -L https://get.cryosparc.com/download/master-latest/\$LICENSE_ID -o cryosparc_master.tar.gz"
    echo "        curl -L https://get.cryosparc.com/download/worker-latest/\$LICENSE_ID -o cryosparc_worker.tar.gz"
    echo
}

while getopts ":hl:" opt; do
  case $opt in
    l)
      license_id=$OPTARG
      ;;
    h)
      help
      exit
      ;;
    *)
      help
      exit
      ;;
  esac
done

TZ=$(timedatectl show --va -p Timezone)
echo
echo "using Time zone:  [$TZ] if this is blank or incorrect, update script accordingly"
echo

#shift the command line options so that all the option will be processed. Otherwise, only the first one is processed.
shift $((OPTIND-1))

if [[ ! -v license_id ]]; then
    printf "\n====> Required option: -l license_id\n\n"
    help
    exit 1
fi

# get length of license_id should be 35 characters
license_length=${#license_id}
if [[ $license_length != 36 ]]; then
    printf "\n====> Check license_id format\n\n"
    exit 1
fi

# check if src/cryosparc_master.tar.gz file exists
if [[ ! -f src/cryosparc_master.tar.gz || ! -f src/cryosparc_worker.tar.gz ]]; then
    echo "=== file(s) not found: src/cryosparc_master.tar.gz src/cryosparc_worker.tar.gz"
    exit 1
fi

cryosparc_version=$(tar -Oxf src/cryosparc_master.tar.gz cryosparc_master/version)

cat > src/install_cryosparc4ood_${cryosparc_version}.sh <<EOF
# $cryosparc_version

export USER=admin
export CRYOSPARC_FORCE_USER=true
export CRYOSPARC_FORCE_HOSTNAME=true

echo "extracting install packages"
tar xzf /mnt/cryosparc_master.tar.gz -C /
tar xzf /mnt/cryosparc_worker.tar.gz -C /
echo "DONE: extracting install packages"

# comment out the ping localhost line
sed -i '/ping -c/ { N; N; N; s/^/#/; s/\n/&#/g }' /cryosparc_master/install.sh

cd /cryosparc_master && ./install.sh --standalone --yes \
              --hostname localhost \
              --license $license_id \
              --worker_path /cryosparc_worker \
              --port 39000 \
              --nossd \
              --initial_email "admin@cryo.edu" \
              --initial_password "admin" \
              --initial_username "admin" \
              --initial_firstname "admin" \
              --initial_lastname "admin"

# add a new user (optional)
# cryosparcm createuser --email "user@organization" --password "init-password" --username "myuser" --firstname "John" --lastname "Doe"
sleep 60

/cryosparc_master/bin/cryosparcm patch --yes
/cryosparc_master/bin/cryosparcm stop

# create a script to remove previous compute node host
cat > /cryosparc_master/bin/remove_hosts.sh <<EOTF
#!/usr/bin/env bash

/cryosparc_master/bin/cryosparcm cli 'get_scheduler_targets()'  | /usr/bin/python3 -c "import sys, ast, json; print( json.dumps(ast.literal_eval(sys.stdin.readline())) )" | /usr/bin/jq '.[].name' | sed 's:"::g' | xargs -I \{\} /cryosparc_master/bin/cryosparcm cli 'remove_scheduler_target_node("'{}'")'

EOTF
chmod +x /cryosparc_master/bin/remove_hosts.sh

# edit config.sh
sed -i 's,export CRYOSPARC_LICENSE_ID=.\+,export CRYOSPARC_LICENSE_ID=\$(cat /cryosparc_license/license_id),' /cryosparc_master/config.sh
sed -i 's,export CRYOSPARC_LICENSE_ID=.\+,export CRYOSPARC_LICENSE_ID=\$(cat /cryosparc_license/license_id),' /cryosparc_worker/config.sh
sed -i 's,export CRYOSPARC_BASE_PORT=.\+,,' /cryosparc_master/config.sh
sed -i 's,export CRYOSPARC_MASTER_HOSTNAME=.\+,,' /cryosparc_master/config.sh
sed -i 's,source config.sh,source /cryosparc_master/config.sh,' /cryosparc_master/bin/cryosparcm

echo "export CRYOSPARC_HOSTNAME_CHECK=localhost" >> /cryosparc_worker/config.sh
echo "export CRYOSPARC_MASTER_HOSTNAME=localhost" >> /cryosparc_worker/config.sh
echo "export CRYOSPARC_FORCE_USER=true" >> /cryosparc_worker/config.sh
echo "export CRYOSPARC_FORCE_HOSTNAME=true" >> /cryosparc_worker/config.sh

echo "export CRYOSPARC_HOSTNAME_CHECK=localhost" >> /cryosparc_master/config.sh
echo "export CRYOSPARC_MASTER_HOSTNAME=localhost" >> /cryosparc_master/config.sh
echo "export CRYOSPARC_FORCE_USER=true" >> /cryosparc_master/config.sh
echo "export CRYOSPARC_FORCE_HOSTNAME=true" >> /cryosparc_master/config.sh
echo "export no_proxy=localhost,127.0.0.0/8" >> /cryosparc_master/config.sh

mv /cryosparc_master/config.sh /cryosparc_master/run/
ln -s /cryosparc_master/run/config.sh /cryosparc_master/config.sh

tar czf /cryosparc_master_run_init_files-${cryosparc_version}.tar.gz /cryosparc_master/run && rm -rf /cryosparc_master/run/
EOF

cat > cryosparc4ood.def <<EOF
BootStrap: docker
From: nvidia/cuda:11.8.0-devel-ubuntu22.04

%environment
  export no_proxy=localhost,127.0.0.0/8
  export PATH=/cryosparc_master/bin:\$PATH
  export PATH=/cryosparc_worker/bin:\$PATH

%post
  apt-get update
  apt-get upgrade -y
  ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone
  apt-get install -y --no-install-recommends tzdata locales language-pack-en gnupg2 openssh-server openssh-client ssh-askpass lbzip2 zip
  apt-get install -y software-properties-common wget curl less jq iputils-ping

  #apt-get install -y nvidia-driver-545 nvidia-dkms-545
  #apt-get install -y nvidia-driver-550 nvidia-dkms-550
  apt-get install -y nvidia-driver-560 nvidia-dkms-560

  # verify the version of gcc
  gcc --version

  # verify the installation
  nvcc -V
  nvcc --list-gpu-code

  # install topaz-em in /usr/local/bin/topaz
  apt-get install -y python3 python3-pip
  pip3 install  topaz-em

  bash /mnt/install_cryosparc4ood_${cryosparc_version}.sh

  which topaz
  topaz --version
EOF

SINGULARITY_CACHEDIR=$TMPDIR SREGISTRY_DATABASE=$TMPDIR SINGULARITYENV_license_id=$license_id SINGULARITYENV_cryosparc_version=$cryosparc_version SINGULARITYENV_no_proxy="localhost,127.0.0.0/8" singularity build --nv --fakeroot -B $PWD/src/:/mnt cryosparc-${cryosparc_version}.sif  cryosparc4ood.def
